import Foundation

@main
enum NotebloatModelTests {
    static func main() async throws {
        try await testFirstLaunchCreatesDefaultTabs()
        try await testAddSelectRenameDeleteAndPersistence()
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
