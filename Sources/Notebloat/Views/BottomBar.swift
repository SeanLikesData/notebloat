import SwiftUI

/// The bottom bar: the live character/word counter and Settings button.
struct BottomBar: View {
    @EnvironmentObject private var store: TabStore

    let onSettings: () -> Void

    private var stats: String {
        TextStats.summary(for: store.activeTab?.content ?? "")
    }

    private var saveStatusColor: Color {
        if case .failed = store.saveState { return .red }
        return .secondary
    }

    var body: some View {
        HStack {
            Spacer()
            Text("\(stats) • \(store.saveState.label)")
                .font(.system(size: 11))
                .foregroundStyle(saveStatusColor)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .glassPill(cornerRadius: 8)
            Spacer()

            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 22)
                    .glassPill(cornerRadius: 8)
            }
            .buttonStyle(.plain)
            .help("Settings")
            .keyboardShortcut(",", modifiers: .command)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}
