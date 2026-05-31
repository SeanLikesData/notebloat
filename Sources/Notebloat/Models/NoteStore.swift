import SwiftUI
import os

/// Holds every tab and the current selection, and persists them to a JSON
/// file in Application Support. The single source of truth for note data.
@MainActor
final class TabStore: ObservableObject {
    @Published var tabs: [TabItem] = []
    @Published var activeID: UUID?
    @Published var persistenceError: String?

    private let fileURL: URL
    private let logger = Logger(subsystem: "com.notebloat.app", category: "persistence")
    private var saveTask: Task<Void, Never>?

    private struct Persisted: Codable {
        var version: Int = 1
        var tabs: [TabItem]
        var activeID: UUID?
    }

    convenience init() {
        let fileManager = FileManager.default
        let base = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = (base ?? fileManager.temporaryDirectory)
            .appendingPathComponent("Notebloat", isDirectory: true)
        self.init(directoryURL: directory)
    }

    init(directoryURL: URL) {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        self.fileURL = directoryURL.appendingPathComponent("tabs.json")

        load()

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

    func flushPendingSave() {
        saveTask?.cancel()
        saveTask = nil
        saveNow()
    }

    func exportNotes(to destinationURL: URL) throws {
        flushPendingSave()
        try FileManager.default.copyItemReplacingExisting(from: fileURL, to: destinationURL)
    }

    func importNotes(from sourceURL: URL) throws {
        let data = try Data(contentsOf: sourceURL)
        let decoded = try JSONDecoder().decode(Persisted.self, from: data)
        tabs = decoded.tabs.isEmpty ? [TabItem(name: "Notes")] : decoded.tabs
        activeID = decoded.activeID
        if activeID == nil || !tabs.contains(where: { $0.id == activeID }) {
            activeID = tabs.first?.id
        }
        saveNow()
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

        do {
            try createDailyBackupIfNeeded()
            let snapshot = Persisted(tabs: tabs, activeID: activeID)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: [.atomic])
            persistenceError = nil
        } catch {
            logger.error("Failed to save tabs: \(error.localizedDescription, privacy: .public)")
            persistenceError = "Notes could not be saved. \(error.localizedDescription)"
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

    private func uniqueName(for proposedName: String, excluding excludedID: UUID? = nil) -> String {
        let existingNames = Set(
            tabs
                .filter { $0.id != excludedID }
                .map(\.name)
        )
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
        if fileExists(atPath: destinationURL.path) {
            try removeItem(at: destinationURL)
        }
        try copyItem(at: sourceURL, to: destinationURL)
    }
}
