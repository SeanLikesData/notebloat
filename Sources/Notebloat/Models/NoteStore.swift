import SwiftUI
import AppKit
import os

/// Holds every tab and the current selection, and persists them to a JSON
/// file in Application Support. The single source of truth for note data.
@MainActor
final class TabStore: ObservableObject {
    enum SaveState: Equatable {
        case saved(Date)
        case saving
        case failed(String)

        var label: String {
            switch self {
            case .saved: "Saved"
            case .saving: "Saving…"
            case .failed: "Save failed"
            }
        }
    }

    @Published var tabs: [TabItem] = []
    @Published var activeID: UUID?
    @Published var persistenceError: String?
    @Published var saveState: SaveState = .saved(Date())

    let directoryURL: URL
    private let fileURL: URL
    private let logger = Logger(subsystem: "com.notebloat.app", category: "persistence")
    private var saveTask: Task<Void, Never>?

    private struct Persisted: Codable {
        var version: Int = 1
        var tabs: [TabItem]
        var activeID: UUID?
    }

    private enum ImportError: LocalizedError {
        case unsupportedVersion(Int)
        case fileTooLarge(Int64)

        var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let version):
                "This export uses unsupported data version \(version)."
            case .fileTooLarge(let byteCount):
                "This export is too large to import safely: \(byteCount) bytes."
            }
        }
    }

    private static let currentPersistenceVersion = 1
    private static let maximumImportByteCount: Int64 = 10 * 1024 * 1024

    convenience init() {
        let fileManager = FileManager.default
        let directory: URL

        do {
            let base = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            directory = base.appendingPathComponent("Notebloat", isDirectory: true)
        } catch {
            let fallback = fileManager.temporaryDirectory.appendingPathComponent("Notebloat", isDirectory: true)
            self.init(
                directoryURL: fallback,
                startupError: "Application Support could not be opened. Notes are using temporary storage for this launch. \(error.localizedDescription)"
            )
            return
        }

        self.init(directoryURL: directory)
    }

    init(directoryURL: URL, startupError: String? = nil) {
        self.directoryURL = directoryURL
        self.fileURL = directoryURL.appendingPathComponent("tabs.json")

        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            persistenceError = "The notes folder could not be created. \(error.localizedDescription)"
            saveState = .failed(error.localizedDescription)
        }

        if let startupError {
            persistenceError = startupError
            saveState = .failed(startupError)
        }

        load()
        let loadWarning = persistenceError

        // First launch: seed the two tabs shown in the design.
        if tabs.isEmpty {
            let personal = TabItem(name: "Personal")
            let work = TabItem(name: "Work")
            tabs = [personal, work]
            activeID = personal.id
            saveNow()
        }
        if activeID == nil || !tabs.contains(where: { $0.id == activeID }) {
            activeID = tabs.first?.id
            saveNow()
        }
        if let loadWarning {
            persistenceError = loadWarning
            saveState = .failed(loadWarning)
        }
    }

    deinit {
        saveTask?.cancel()
    }

    // MARK: - Derived

    var activeTab: TabItem? {
        guard let activeID else { return nil }
        return tabs.first { $0.id == activeID }
    }

    /// Two-way binding into a tab's text so the editor writes straight back
    /// into the store. Disk writes are debounced so typing does not write the
    /// full JSON file on every keystroke.
    func contentBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { [weak self] in
                self?.tabs.first(where: { $0.id == id })?.content ?? ""
            },
            set: { [weak self] newValue in
                guard let self,
                      let index = self.tabs.firstIndex(where: { $0.id == id })
                else { return }
                self.tabs[index].content = newValue
                self.scheduleSave()
            }
        )
    }

    // MARK: - Mutations

    func select(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeID = id
        saveNow()
    }

    @discardableResult
    func addTab(named name: String) -> TabItem {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = trimmed.isEmpty ? "Untitled" : trimmed
        let tab = TabItem(name: uniqueName(for: baseName))
        tabs.append(tab)
        activeID = tab.id
        saveNow()
        return tab
    }

    func rename(_ id: UUID, to name: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        tabs[index].name = uniqueName(for: trimmed, excluding: id)
        saveNow()
    }

    func delete(_ id: UUID) {
        tabs.removeAll { $0.id == id }
        if activeID == id {
            activeID = tabs.first?.id
        }
        // Never leave the user with zero tabs.
        if tabs.isEmpty {
            let fresh = TabItem(name: "Notes")
            tabs = [fresh]
            activeID = fresh.id
        }
        saveNow()
    }

    func moveTab(_ draggedID: UUID, before targetID: UUID) {
        guard draggedID != targetID,
              let sourceIndex = tabs.firstIndex(where: { $0.id == draggedID }),
              let targetIndex = tabs.firstIndex(where: { $0.id == targetID })
        else { return }

        let draggedTab = tabs.remove(at: sourceIndex)
        let adjustedTargetIndex = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        let insertionIndex = max(0, min(adjustedTargetIndex, tabs.count))
        tabs.insert(draggedTab, at: insertionIndex)
        saveNow()
    }

    func flushPendingSave() {
        saveTask?.cancel()
        saveTask = nil
        saveNow()
    }

    func exportNotes(to destinationURL: URL) throws {
        flushPendingSave()
        try FileManager.default.copyItemReplacingExisting(from: fileURL, to: destinationURL)
    }

    func exportMarkdown(to destinationURL: URL) throws {
        let sections = tabs.map { tab in
            let content = tab.content.trimmingCharacters(in: .newlines)
            return content.isEmpty ? "## \(tab.name)" : "## \(tab.name)\n\n\(content)"
        }
        let markdown = "# Notebloat Notes\n\n" + sections.joined(separator: "\n\n---\n\n") + "\n"
        try markdown.write(to: destinationURL, atomically: true, encoding: .utf8)
    }

    func importNotes(from sourceURL: URL) throws {
        let byteCount = try sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        if byteCount > Self.maximumImportByteCount {
            throw ImportError.fileTooLarge(Int64(byteCount))
        }

        let data = try Data(contentsOf: sourceURL)
        let decoded = try JSONDecoder().decode(Persisted.self, from: data)
        guard decoded.version <= Self.currentPersistenceVersion else {
            throw ImportError.unsupportedVersion(decoded.version)
        }

        let normalized = normalizeImportedTabs(decoded.tabs)
        tabs = normalized.isEmpty ? [TabItem(name: "Notes")] : normalized
        activeID = decoded.activeID
        if activeID == nil || !tabs.contains(where: { $0.id == activeID }) {
            activeID = tabs.first?.id
        }
        saveNow()
    }

    func revealNotesInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode(Persisted.self, from: data)
            tabs = decoded.tabs
            activeID = decoded.activeID
            persistenceError = nil
        } catch {
            logger.error("Failed to load tabs: \(error.localizedDescription, privacy: .public)")
            recoverCorruptFile(error: error)
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveState = .saving
        saveTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(400))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    private func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        saveState = .saving

        do {
            try createDailyBackupIfNeeded()
            try pruneOldBackups(keeping: 30)
            let snapshot = Persisted(tabs: tabs, activeID: activeID)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: [.atomic])
            persistenceError = nil
            saveState = .saved(Date())
        } catch {
            logger.error("Failed to save tabs: \(error.localizedDescription, privacy: .public)")
            let message = "Notes could not be saved. \(error.localizedDescription)"
            persistenceError = message
            saveState = .failed(message)
        }
    }

    private func recoverCorruptFile(error: Error) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let recoveredURL = fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("tabs.corrupt-\(formatter.string(from: Date())).json")

        do {
            try FileManager.default.moveItem(at: fileURL, to: recoveredURL)
            persistenceError = "The notes file could not be read. It was moved to \(recoveredURL.lastPathComponent)."
        } catch {
            persistenceError = "The notes file could not be read, and recovery failed. \(error.localizedDescription)"
        }
        if let persistenceError {
            saveState = .failed(persistenceError)
        }
    }

    private func createDailyBackupIfNeeded() throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else { return }

        let backupDirectory = fileURL.deletingLastPathComponent().appendingPathComponent("Backups", isDirectory: true)
        try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let backupURL = backupDirectory.appendingPathComponent("tabs-\(formatter.string(from: Date())).json")
        guard !fileManager.fileExists(atPath: backupURL.path) else { return }

        try fileManager.copyItem(at: fileURL, to: backupURL)
    }

    private func pruneOldBackups(keeping maximumBackupCount: Int) throws {
        let fileManager = FileManager.default
        let backupDirectory = fileURL.deletingLastPathComponent().appendingPathComponent("Backups", isDirectory: true)
        guard fileManager.fileExists(atPath: backupDirectory.path) else { return }

        let backupFiles = try fileManager.contentsOfDirectory(
            at: backupDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
            .filter { $0.lastPathComponent.hasPrefix("tabs-") && $0.pathExtension == "json" }
            .sorted { left, right in
                let leftDate = (try? left.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rightDate = (try? right.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return leftDate > rightDate
            }

        for oldBackup in backupFiles.dropFirst(maximumBackupCount) {
            try fileManager.removeItem(at: oldBackup)
        }
    }

    private func normalizeImportedTabs(_ importedTabs: [TabItem]) -> [TabItem] {
        var usedIDs = Set<UUID>()
        var usedNames = Set<String>()

        return importedTabs.map { tab in
            let id: UUID
            if usedIDs.contains(tab.id) {
                id = UUID()
            } else {
                id = tab.id
            }
            usedIDs.insert(id)

            let trimmedName = tab.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let baseName = trimmedName.isEmpty ? "Untitled" : trimmedName
            let name = uniqueName(for: baseName, existingNames: usedNames)
            usedNames.insert(name)

            return TabItem(id: id, name: name, content: tab.content)
        }
    }

    private func uniqueName(for proposedName: String, excluding excludedID: UUID? = nil) -> String {
        let existingNames = Set(
            tabs
                .filter { $0.id != excludedID }
                .map(\.name)
        )
        return uniqueName(for: proposedName, existingNames: existingNames)
    }

    private func uniqueName(for proposedName: String, existingNames: Set<String>) -> String {
        guard existingNames.contains(proposedName) else { return proposedName }

        var suffix = 2
        while existingNames.contains("\(proposedName) \(suffix)") {
            suffix += 1
        }
        return "\(proposedName) \(suffix)"
    }
}

private extension FileManager {
    func copyItemReplacingExisting(from sourceURL: URL, to destinationURL: URL) throws {
        let source = sourceURL.standardizedFileURL
        let destination = destinationURL.standardizedFileURL
        if fileExists(atPath: destination.path), contentsEqual(atPath: source.path, andPath: destination.path) {
            return
        }

        let temporaryURL = destination
            .deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).tmp-\(UUID().uuidString)")
        defer { try? removeItem(at: temporaryURL) }

        try copyItem(at: source, to: temporaryURL)
        if fileExists(atPath: destination.path) {
            try removeItem(at: destination)
        }
        try moveItem(at: temporaryURL, to: destination)
    }
}
