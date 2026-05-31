import SwiftUI
import UniformTypeIdentifiers

/// The tab strip across the top. Tabs wrap onto additional rows when there are
/// too many to fit on one line. That keeps tab backlog visible instead of
/// hiding old tabs behind horizontal scrolling.
struct TabBarView: View {
    @EnvironmentObject private var store: TabStore
    let onNewTab: () -> Void
    let onRename: (TabItem) -> Void
    let onDelete: (TabItem) -> Void

    @State private var draggedTabID: UUID?

    var body: some View {
        FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(store.tabs) { tab in
                pill(for: tab)
            }

            Button(action: onNewTab) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 22)
                    .glassPill(cornerRadius: 8)
            }
            .buttonStyle(.plain)
            .help("New tab")
            .keyboardShortcut("n", modifiers: .command)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
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

private struct FlowLayout: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        let rows = rows(for: subviews, proposedWidth: proposal.width ?? 0)
        let width = proposal.width ?? rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + verticalSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        let rows = rows(for: subviews, proposedWidth: bounds.width)
        var y = bounds.minY

        for row in rows {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + horizontalSpacing
            }
            y += row.height + verticalSpacing
        }
    }

    private func rows(for subviews: Subviews, proposedWidth: CGFloat) -> [FlowRow] {
        let maxWidth = max(proposedWidth, 1)
        var rows: [FlowRow] = []
        var currentItems: [FlowItem] = []
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let nextWidth = currentItems.isEmpty ? size.width : currentWidth + horizontalSpacing + size.width

            if nextWidth > maxWidth, !currentItems.isEmpty {
                rows.append(FlowRow(items: currentItems, width: currentWidth, height: currentHeight))
                currentItems = [FlowItem(index: index, size: size)]
                currentWidth = size.width
                currentHeight = size.height
            } else {
                currentItems.append(FlowItem(index: index, size: size))
                currentWidth = nextWidth
                currentHeight = max(currentHeight, size.height)
            }
        }

        if !currentItems.isEmpty {
            rows.append(FlowRow(items: currentItems, width: currentWidth, height: currentHeight))
        }

        return rows
    }

    private struct FlowRow {
        var items: [FlowItem]
        var width: CGFloat
        var height: CGFloat
    }

    private struct FlowItem {
        var index: Int
        var size: CGSize
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

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
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
