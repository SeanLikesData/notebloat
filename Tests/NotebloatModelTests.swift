import Foundation

@main
enum NotebloatModelTests {
    static func main() async throws {
        try await testFirstLaunchCreatesDefaultTabs()
        try await testAddSelectRenameDeleteAndPersistence()
        try await testMoveTab()
        try await testImportExport()
        try await testMarkdownExport()
        try await testCorruptFileRecovery()
        try await testBackupRetention()
        try await testTextStats()
        print("All Notebloat model tests passed.")
    }

    private static func testFirstLaunchCreatesDefaultTabs() async throws {
        let directory = try freshTemporaryDirectory(named: "first-launch")
        let store = await MainActor.run { TabStore(directoryURL: directory) }

        await MainActor.run {
            expect(store.tabs.map(\.name) == ["Personal", "Work"], "first launch creates default tabs")
            expect(store.activeTab?.name == "Personal", "first launch selects Personal")
        }
    }

    private static func testAddSelectRenameDeleteAndPersistence() async throws {
        let directory = try freshTemporaryDirectory(named: "mutations")
        let store = await MainActor.run { TabStore(directoryURL: directory) }

        let workID = await MainActor.run { store.tabs[1].id }
        await MainActor.run {
            store.select(workID)
            store.addTab(named: "Work")
            expect(store.activeTab?.name == "Work 2", "duplicate tab names are made unique")
            if let activeID = store.activeID {
                store.rename(activeID, to: "Docs")
            }
            expect(store.activeTab?.name == "Docs", "rename changes the active tab name")
            store.flushPendingSave()
        }

        let reloaded = await MainActor.run { TabStore(directoryURL: directory) }
        await MainActor.run {
            expect(reloaded.activeTab?.name == "Docs", "active tab selection persists")
            if let docsID = reloaded.activeID {
                reloaded.delete(docsID)
            }
            expect(!reloaded.tabs.isEmpty, "deleting a tab never leaves zero tabs")
        }
    }

    private static func testMoveTab() async throws {
        let directory = try freshTemporaryDirectory(named: "move-tab")
        let store = await MainActor.run { TabStore(directoryURL: directory) }

        await MainActor.run {
            let first = store.tabs[0].id
            let second = store.tabs[1].id
            store.addTab(named: "Docs")
            let third = store.tabs[2].id

            store.moveTab(first, before: third)
            expect(store.tabs.map(\.name) == ["Work", "Docs", "Personal"], "dragging right can move a tab to the end")

            store.moveTab(third, before: second)
            expect(store.tabs.map(\.name) == ["Docs", "Work", "Personal"], "dragging left can move a tab before the target")
        }
    }

    private static func testImportExport() async throws {
        let directory = try freshTemporaryDirectory(named: "import-export")
        let store = await MainActor.run { TabStore(directoryURL: directory) }
        let exportURL = directory.appendingPathComponent("export.json")

        try await MainActor.run {
            let tab = store.addTab(named: "Imported")
            if let index = store.tabs.firstIndex(where: { $0.id == tab.id }) {
                store.tabs[index].content = "hello import export"
            }
            store.flushPendingSave()
            try store.exportNotes(to: exportURL)
        }

        let importDirectory = try freshTemporaryDirectory(named: "import-target")
        let imported = await MainActor.run { TabStore(directoryURL: importDirectory) }
        try await MainActor.run {
            try imported.importNotes(from: exportURL)
            expect(imported.tabs.contains(where: { $0.name == "Imported" && $0.content == "hello import export" }), "import restores exported notes")
        }
    }

    private static func testMarkdownExport() async throws {
        let directory = try freshTemporaryDirectory(named: "markdown-export")
        let store = await MainActor.run { TabStore(directoryURL: directory) }
        let exportURL = directory.appendingPathComponent("notes.md")

        try await MainActor.run {
            store.tabs[0].content = "Weekend plans"
            store.tabs[1].content = ""
            store.addTab(named: "Ideas")
            if let activeID = store.activeID,
               let index = store.tabs.firstIndex(where: { $0.id == activeID }) {
                store.tabs[index].content = "Build something small."
            }
            try store.exportMarkdown(to: exportURL)
        }

        let markdown = try String(contentsOf: exportURL, encoding: .utf8)
        expect(
            markdown == """
            # Notebloat Notes

            ## Personal

            Weekend plans

            ---

            ## Work

            ---

            ## Ideas

            Build something small.

            """,
            "Markdown export includes every tab in order"
        )
    }

    private static func testCorruptFileRecovery() async throws {
        let directory = try freshTemporaryDirectory(named: "corrupt")
        try "not json".write(to: directory.appendingPathComponent("tabs.json"), atomically: true, encoding: .utf8)

        let store = await MainActor.run { TabStore(directoryURL: directory) }
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)

        await MainActor.run {
            expect(store.persistenceError != nil, "corrupt file creates an error message")
            expect(store.tabs.map(\.name) == ["Personal", "Work"], "corrupt file falls back to default tabs")
        }
        expect(files.contains(where: { $0.hasPrefix("tabs.corrupt-") }), "corrupt file is moved aside")
    }

    private static func testBackupRetention() async throws {
        let directory = try freshTemporaryDirectory(named: "backup-retention")
        let backupDirectory = directory.appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)

        for day in 1...35 {
            let backup = backupDirectory.appendingPathComponent(String(format: "tabs-2026-05-%02d.json", day))
            try "{}".write(to: backup, atomically: true, encoding: .utf8)
            let date = Date(timeIntervalSince1970: TimeInterval(day))
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: backup.path)
        }

        let store = await MainActor.run { TabStore(directoryURL: directory) }
        await MainActor.run { store.flushPendingSave() }

        let remaining = try FileManager.default.contentsOfDirectory(atPath: backupDirectory.path)
            .filter { $0.hasPrefix("tabs-") && $0.hasSuffix(".json") }
        expect(remaining.count <= 30, "backup retention keeps at most 30 backup files")
    }

    private static func testTextStats() async throws {
        expect(TextStats.summary(for: "") == "0 chars • 0 words", "empty text stats")
        expect(TextStats.summary(for: "hello world") == "11 chars • 2 words", "word count stats")
        expect(TextStats.summary(for: "a") == "1 char • 1 word", "singular labels")
    }

    private static func freshTemporaryDirectory(named name: String) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("NotebloatTests", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("Test failed: \(message)\n", stderr)
            Foundation.exit(1)
        }
    }
}
