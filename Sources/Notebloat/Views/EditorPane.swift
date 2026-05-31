import SwiftUI

/// The text area for the active tab. It focuses itself when the popover opens
/// and when the user switches tabs, so the application is ready for typing.
struct EditorPane: View {
    @EnvironmentObject private var store: TabStore
    @FocusState private var editorFocused: Bool
    let font: Font

    var body: some View {
        Group {
            if let active = store.activeTab {
                TextEditor(text: store.contentBinding(for: active.id))
                    .font(font)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(NotebloatStyle.editorBackground))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(NotebloatStyle.controlStroke, lineWidth: 1))
                    .padding(10)
                    .focused($editorFocused)
                    .onAppear { editorFocused = true }
                    .onChange(of: active.id) { _, _ in editorFocused = true }
            } else {
                Text("No tabs")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
