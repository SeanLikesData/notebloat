import SwiftUI
import UniformTypeIdentifiers

/// The tab strip across the top. Tabs scroll horizontally. The trailing plus
/// creates a new tab because tab creation belongs next to the tabs.
struct TabBarView: View {
    @EnvironmentObject private var store: TabStore
    let onNewTab: () -> Void
    let onRename: (TabItem) -> Void
    let onDelete: (TabItem) -> Void

    @State private var draggedTabID: UUID?

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

            Button(action: onNewTab) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 22)
                    .background(RoundedRectangle(cornerRadius: 8).fill(NotebloatStyle.controlBackground))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(NotebloatStyle.controlStroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("New tab")
            .keyboardShortcut("n", modifiers: .command)
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
                    RoundedRectangle(cornerRadius: 9)
                        .fill(isActive ? NotebloatStyle.activeControlBackground : NotebloatStyle.controlBackground.opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(isActive ? NotebloatStyle.activeControlStroke : NotebloatStyle.controlStroke, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .opacity(draggedTabID == tab.id ? 0.45 : 1)
        .help("\(tab.name). Double-click to rename. Drag to reorder.")
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                onRename(tab)
            }
        )
        .contextMenu {
            Button("Rename…") { onRename(tab) }
            Button("Duplicate") { duplicate(tab) }
            Button(role: .destructive) { onDelete(tab) } label: { Text("Delete…") }
        }
        .onDrag {
            draggedTabID = tab.id
            return NSItemProvider(object: tab.id.uuidString as NSString)
        }
        .onDrop(
            of: [UTType.text.identifier],
            delegate: TabDropDelegate(
                targetTab: tab,
                draggedTabID: $draggedTabID,
                store: store
            )
        )
    }

    private func duplicate(_ tab: TabItem) {
        let duplicate = store.addTab(named: tab.name)
        if let index = store.tabs.firstIndex(where: { $0.id == duplicate.id }) {
            store.tabs[index].content = tab.content
            store.flushPendingSave()
        }
    }
}

private struct TabDropDelegate: DropDelegate {
    let targetTab: TabItem
    @Binding var draggedTabID: UUID?
    let store: TabStore

    func dropEntered(info: DropInfo) {
        guard let draggedTabID else { return }
        store.moveTab(draggedTabID, before: targetTab.id)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedTabID = nil
        return true
    }

    func dropExited(info: DropInfo) {
        if !info.hasItemsConforming(to: [UTType.text.identifier]) {
            draggedTabID = nil
        }
    }
}
