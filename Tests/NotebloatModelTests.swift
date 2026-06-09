import Foundation
import AppKit

@main
enum NotebloatModelTests {
    static func main() async throws {
        try await testFirstLaunchCreatesDefaultTabs()
        try await testAddSelectRenameDeleteAndPersistence()
        try await testMoveTab()
        try await testImportExport()
        try await testExportToNotesFileIsSafe()
        try await testImportNormalizesUnsafeTabs()
        try await testImportRejectsFutureVersion()
        try await testMarkdownExport()
        try await testCorruptFileRecovery()
        try await testBackupRetention()
        try await testTextStats()
        try await testMarkdownStyling()
        try await testMarkdownLists()
        try await testLargeMarkdownStylingCompletes()
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
            expect(store.tabs.map(\.name) == ["Work", "Personal", "Docs"], "dragging right moves a tab before the target")

            store.moveTab(third, before: second)
            expect(store.tabs.map(\.name) == ["Docs", "Work", "Personal"], "dragging left moves a tab before the target")
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

    private static func testExportToNotesFileIsSafe() async throws {
        let directory = try freshTemporaryDirectory(named: "same-file-export")
        let store = await MainActor.run { TabStore(directoryURL: directory) }
        let notesURL = directory.appendingPathComponent("tabs.json")
        let before = try String(contentsOf: notesURL, encoding: .utf8)

        try await MainActor.run {
            try store.exportNotes(to: notesURL)
        }

        let after = try String(contentsOf: notesURL, encoding: .utf8)
        expect(after == before, "exporting to the notes file does not delete notes")
    }

    private static func testImportNormalizesUnsafeTabs() async throws {
        let directory = try freshTemporaryDirectory(named: "import-normalization")
        let sourceURL = directory.appendingPathComponent("unsafe.json")
        let duplicateID = UUID()
        let json = """
        {
          "version": 1,
          "activeID": "\(duplicateID.uuidString)",
          "tabs": [
            { "id": "\(duplicateID.uuidString)", "name": "", "content": "first" },
            { "id": "\(duplicateID.uuidString)", "name": "Untitled", "content": "second" },
            { "id": "\(UUID().uuidString)", "name": "Untitled", "content": "third" }
          ]
        }
        """
        try json.write(to: sourceURL, atomically: true, encoding: .utf8)

        let store = await MainActor.run { TabStore(directoryURL: directory) }
        try await MainActor.run {
            try store.importNotes(from: sourceURL)
            expect(store.tabs.map(\.name) == ["Untitled", "Untitled 2", "Untitled 3"], "import normalizes blank and duplicate tab names")
            expect(Set(store.tabs.map(\.id)).count == store.tabs.count, "import regenerates duplicate tab identifiers")
            expect(store.activeID == duplicateID, "import preserves a valid active tab identifier")
        }
    }

    private static func testImportRejectsFutureVersion() async throws {
        let directory = try freshTemporaryDirectory(named: "future-import")
        let sourceURL = directory.appendingPathComponent("future.json")
        let json = """
        {
          "version": 999,
          "activeID": null,
          "tabs": []
        }
        """
        try json.write(to: sourceURL, atomically: true, encoding: .utf8)

        let store = await MainActor.run { TabStore(directoryURL: directory) }
        do {
            try await MainActor.run {
                try store.importNotes(from: sourceURL)
            }
            expect(false, "future import versions are rejected")
        } catch {
            expect(error.localizedDescription.contains("unsupported"), "future import version has a clear error")
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

    private static func testMarkdownStyling() async throws {
        let source = "# Heading\n**Bold** text\n_Raw_ line"
        let storage = NSTextStorage(string: source)
        let baseFont = NSFont.systemFont(ofSize: 14)
        let activeLine = (source as NSString).lineRange(
            for: NSRange(location: (source as NSString).range(of: "_Raw_").location, length: 0)
        )

        MarkdownStyler.apply(
            to: storage,
            baseFont: baseFont,
            activeLineRanges: [activeLine],
            enabled: true
        )

        let headingMarkerFont = storage.attribute(
            .font,
            at: 0,
            effectiveRange: nil
        ) as? NSFont
        let headingFont = storage.attribute(
            .font,
            at: 2,
            effectiveRange: nil
        ) as? NSFont
        let boldFont = storage.attribute(
            .font,
            at: (source as NSString).range(of: "Bold").location,
            effectiveRange: nil
        ) as? NSFont
        let activeMarkerFont = storage.attribute(
            .font,
            at: activeLine.location,
            effectiveRange: nil
        ) as? NSFont

        expect(headingMarkerFont?.pointSize == 0.1, "inactive Markdown markers are hidden")
        expect(
            headingFont.map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } == true,
            "inactive Markdown headings are styled"
        )
        let headingColor = storage.attribute(
            .foregroundColor,
            at: 2,
            effectiveRange: nil
        ) as? NSColor
        expect(
            colorsMatch(headingColor, red: 0x7E, green: 0xB8, blue: 0xDA),
            "inactive Markdown headings use their level color"
        )
        expect(
            boldFont.map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } == true,
            "inactive Markdown emphasis uses rendered typography"
        )
        expect(activeMarkerFont?.pointSize == baseFont.pointSize, "active line shows raw Markdown")
        expect(storage.string == source, "Markdown styling preserves the plain-text source")
    }

    private static func testMarkdownLists() async throws {
        let source = "- List item\n- [ ] Todo\n- [x] Done\nRaw"
        let storage = NSTextStorage(string: source)
        let baseFont = NSFont.systemFont(ofSize: 14)
        let activeLine = (source as NSString).lineRange(
            for: NSRange(location: (source as NSString).range(of: "Raw").location, length: 0)
        )

        MarkdownStyler.apply(
            to: storage,
            baseFont: baseFont,
            activeLineRanges: [activeLine],
            enabled: true
        )

        let listMarker = storage.attribute(
            .notebloatListMarker,
            at: (source as NSString).range(of: "- List").location,
            effectiveRange: nil
        ) as? String
        let uncheckedMarker = storage.attribute(
            .notebloatListMarker,
            at: (source as NSString).range(of: "- [ ]").location,
            effectiveRange: nil
        ) as? String
        let checkedMarker = storage.attribute(
            .notebloatListMarker,
            at: (source as NSString).range(of: "- [x]").location,
            effectiveRange: nil
        ) as? String
        let sourceMarkerColor = storage.attribute(
            .foregroundColor,
            at: (source as NSString).range(of: "- List").location,
            effectiveRange: nil
        ) as? NSColor

        expect(listMarker == "•", "unordered Markdown lists render a bullet")
        expect(uncheckedMarker == "☐", "unchecked Markdown tasks render a checkbox")
        expect(checkedMarker == "☑", "checked Markdown tasks render a checked checkbox")
        expect(sourceMarkerColor?.alphaComponent == 0, "rendered lists hide the source marker")
        expect(storage.string == source, "list rendering preserves the plain-text source")
    }

    private static func testLargeMarkdownStylingCompletes() async throws {
        let line = "# Heading **bold** _italic_ [link](https://example.com) - [x] task\n"
        let source = String(repeating: line, count: 2_000)
        let storage = NSTextStorage(string: source)
        let baseFont = NSFont.systemFont(ofSize: 14)
        let start = Date()

        MarkdownStyler.apply(
            to: storage,
            baseFont: baseFont,
            activeLineRanges: [],
            enabled: true
        )

        expect(storage.string == source, "large Markdown styling preserves text")
        expect(Date().timeIntervalSince(start) < 5, "large Markdown styling completes in a reasonable time")
    }

    private static func colorsMatch(
        _ color: NSColor?,
        red: Int,
        green: Int,
        blue: Int
    ) -> Bool {
        guard let color = color?.usingColorSpace(.sRGB) else { return false }
        let tolerance = 0.001
        return abs(color.redComponent - CGFloat(red) / 255) < tolerance
            && abs(color.greenComponent - CGFloat(green) / 255) < tolerance
            && abs(color.blueComponent - CGFloat(blue) / 255) < tolerance
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
