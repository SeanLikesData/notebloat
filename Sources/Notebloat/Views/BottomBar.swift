import SwiftUI
import AppKit

/// The bottom bar: the live character/word counter and the "•••" menu.
struct BottomBar: View {
    @EnvironmentObject private var store: TabStore
    @AppStorage(SettingsKey.fontSize) private var fontRaw = FontSize.medium.rawValue
    @AppStorage(SettingsKey.popoverSize) private var popoverRaw = PopoverSize.medium.rawValue
    @AppStorage(SettingsKey.pinned) private var pinned = false

    let onSettings: () -> Void
    let onRenameActive: () -> Void
    let onDeleteActive: () -> Void

    private var stats: String {
        TextStats.summary(for: store.activeTab?.content ?? "")
    }

    var body: some View {
        HStack {
            Spacer()
            Text(stats)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7).fill(NotebloatStyle.editorBackground))
            Spacer()

            menu
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: - The ••• menu

    private var menu: some View {
        Menu {
            Toggle(isOn: $pinned) {
                Label("Pinned", systemImage: "pin.fill")
            }

            Menu {
                Button(action: onRenameActive) {
                    Label("Rename…", systemImage: "pencil")
                }
                .keyboardShortcut("r", modifiers: .command)

                Button(role: .destructive, action: onDeleteActive) {
                    Label("Delete…", systemImage: "trash")
                }
                Divider()
                ForEach(store.tabs) { tab in
                    Button {
                        store.select(tab.id)
                    } label: {
                        if tab.id == store.activeID {
                            Label(tab.name, systemImage: "checkmark")
                        } else {
                            Text(tab.name)
                        }
                    }
                }
            } label: {
                Label("Active tab", systemImage: "square.and.pencil")
            }

            Menu {
                Picker("Font size", selection: $fontRaw) {
                    ForEach(FontSize.allCases) { Text($0.label).tag($0.rawValue) }
                }
            } label: {
                Label("Font size", systemImage: "textformat.size")
            }

            Menu {
                Picker("Popover size", selection: $popoverRaw) {
                    ForEach(PopoverSize.allCases) { Text($0.label).tag($0.rawValue) }
                }
            } label: {
                Label("Popover size", systemImage: "arrow.up.left.and.arrow.down.right")
            }

            Divider()
            Button(action: onSettings) {
                Label("Settings…", systemImage: "gearshape")
            }
            .keyboardShortcut(",", modifiers: .command)
            Divider()
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Exit", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 22)
                .background(RoundedRectangle(cornerRadius: 6).fill(NotebloatStyle.controlBackground))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

}
