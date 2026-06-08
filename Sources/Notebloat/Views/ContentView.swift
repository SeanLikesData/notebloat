import SwiftUI
import AppKit

/// Root of the menu bar popover. Stacks the tab bar, the editor, and the
/// bottom bar, and shows the new-tab / rename / settings panels on top.
struct ContentView: View {
    @EnvironmentObject private var store: TabStore
    @AppStorage(SettingsKey.theme) private var themeRaw = AppTheme.system.rawValue
    @AppStorage(SettingsKey.popoverSize) private var popoverRaw = PopoverSize.medium.rawValue

    @State private var showingNewTab = false
    @State private var showingSettings = false
    @State private var renamingTab: TabItem?
    @State private var deletingTab: TabItem?

    private var popoverSize: CGSize {
        (PopoverSize(rawValue: popoverRaw) ?? .medium).dimensions
    }

    private var colorScheme: ColorScheme? {
        (AppTheme(rawValue: themeRaw) ?? .system).colorScheme
    }

    var body: some View {
        ZStack {
            NotebloatStyle.panelMaterial

            VStack(spacing: 0) {
                TabBarView(
                    onNewTab: { showingNewTab = true },
                    onRename: { renamingTab = $0 },
                    onDelete: { deletingTab = $0 }
                )
                NotebloatStyle.divider
                EditorPane()
                NotebloatStyle.divider
                BottomBar(
                    onSettings: { showingSettings = true }
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
        .clipShape(RoundedRectangle(cornerRadius: NotebloatStyle.panelCornerRadius, style: .continuous))
        .overlay(NotebloatStyle.panelBorder)
    }
}

struct GlassPillModifier: ViewModifier {
    @State private var hovering = false
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(hovering ? NotebloatStyle.controlHoverBackground : NotebloatStyle.controlBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(hovering ? NotebloatStyle.activeControlStroke : NotebloatStyle.controlStroke, lineWidth: 1)
            )
            .onHover { hovering = $0 }
    }
}

extension View {
    func glassPill(cornerRadius: CGFloat) -> some View {
        modifier(GlassPillModifier(cornerRadius: cornerRadius))
    }
}

enum NotebloatStyle {
    static let panelCornerRadius: CGFloat = 18

    static var panelMaterial: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow, state: .active)
            LinearGradient(
                colors: [
                    Color.white.opacity(0.10),
                    Color.black.opacity(0.18),
                    Color.black.opacity(0.32)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color.white.opacity(0.10), Color.clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 260
            )
        }
    }

    static var panelBorder: some View {
        RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.32),
                        Color.white.opacity(0.12),
                        Color.black.opacity(0.22)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }

    static var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.10))
            .frame(height: 1)
            .overlay(Rectangle().fill(Color.black.opacity(0.12)).offset(y: 1))
    }

    static let controlBackground = Color.white.opacity(0.10)
    static let controlHoverBackground = Color.white.opacity(0.16)
    static let activeControlBackground = Color.white.opacity(0.22)
    static let editorBackground = Color.black.opacity(0.14)
    static let controlStroke = Color.white.opacity(0.14)
    static let activeControlStroke = Color.white.opacity(0.28)
}
