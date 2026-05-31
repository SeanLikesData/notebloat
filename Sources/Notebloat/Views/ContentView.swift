import SwiftUI
import AppKit

/// Root of the menu bar popover. Stacks the tab bar, the editor, and the
/// bottom bar, and shows the new-tab / rename / settings panels on top.
struct ContentView: View {
    @EnvironmentObject private var store: TabStore
    @AppStorage(SettingsKey.theme) private var themeRaw = AppTheme.system.rawValue
    @AppStorage(SettingsKey.fontSize) private var fontRaw = FontSize.medium.rawValue
    @AppStorage(SettingsKey.popoverSize) private var popoverRaw = PopoverSize.medium.rawValue

    @State private var showingNewTab = false
    @State private var showingSettings = false
    @State private var renamingTab: TabItem?
    @State private var deletingTab: TabItem?

    private var popoverSize: CGSize {
        (PopoverSize(rawValue: popoverRaw) ?? .medium).dimensions
    }

    private var editorFont: Font {
        .system(size: (FontSize(rawValue: fontRaw) ?? .medium).pointSize)
    }

    private var colorScheme: ColorScheme? {
        (AppTheme(rawValue: themeRaw) ?? .system).colorScheme
    }

    var body: some View {
        ZStack {
            NotebloatStyle.panelBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                TabBarView(onNewTab: { showingNewTab = true })
                Divider().opacity(0.4)
                EditorPane(font: editorFont)
                Divider().opacity(0.4)
                BottomBar(
                    onNewTab: { showingNewTab = true },
                    onSettings: { showingSettings = true },
                    onRenameActive: { renamingTab = store.activeTab },
                    onDeleteActive: { deletingTab = store.activeTab }
                )
            }

            if let persistenceError = store.persistenceError {
                VStack {
                    Text(persistenceError)
                        .font(.system(size: 11))
                        .foregroundStyle(.primary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.18)))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red.opacity(0.3)))
                        .padding(10)
                    Spacer()
                }
            }

            if showingNewTab {
                NameDialog(
                    title: "New Tab",
                    initialText: "",
                    confirmLabel: "Create",
                    onCancel: { showingNewTab = false },
                    onConfirm: { name in
                        store.addTab(named: name)
                        showingNewTab = false
                    }
                )
            }

            if let tab = renamingTab {
                NameDialog(
                    title: "Rename Tab",
                    initialText: tab.name,
                    confirmLabel: "Save",
                    onCancel: { renamingTab = nil },
                    onConfirm: { name in
                        store.rename(tab.id, to: name)
                        renamingTab = nil
                    }
                )
            }

            if let tab = deletingTab {
                DeleteTabDialog(
                    tabName: tab.name,
                    onCancel: { deletingTab = nil },
                    onDelete: {
                        store.delete(tab.id)
                        deletingTab = nil
                    }
                )
            }

            if showingSettings {
                SettingsSheet(onClose: { showingSettings = false })
            }
        }
        .preferredColorScheme(colorScheme)
        .frame(width: popoverSize.width, height: popoverSize.height)
    }
}

enum NotebloatStyle {
    static let panelBackground = Color(nsColor: .windowBackgroundColor).opacity(0.92)
    static let controlBackground = Color.primary.opacity(0.12)
    static let activeControlBackground = Color.primary.opacity(0.20)
    static let editorBackground = Color.primary.opacity(0.06)
}
