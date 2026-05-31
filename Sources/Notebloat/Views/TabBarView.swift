import SwiftUI

/// The tab strip across the top. Tabs scroll horizontally; the trailing
/// chevron opens a menu listing every tab with a checkmark on the active one,
/// plus a shortcut to create a new tab.
struct TabBarView: View {
    @EnvironmentObject private var store: TabStore
    let onNewTab: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(store.tabs) { tab in
                        pill(for: tab)
                    }
                }
                .padding(.leading, 10)
                .padding(.vertical, 8)
            }

            Spacer(minLength: 0)

            Menu {
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
                Divider()
                Button("New Tab…", action: onNewTab)
                    .keyboardShortcut("n", modifiers: .command)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 28, height: 22)
                    .background(RoundedRectangle(cornerRadius: 6).fill(NotebloatStyle.controlBackground))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.trailing, 10)
        }
    }

    private func pill(for tab: TabItem) -> some View {
        let isActive = tab.id == store.activeID
        return Button {
            store.select(tab.id)
        } label: {
            Text(tab.name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 120)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isActive ? NotebloatStyle.activeControlBackground : NotebloatStyle.controlBackground.opacity(0.5))
                )
        }
        .buttonStyle(.plain)
        .help(tab.name)
    }
}
