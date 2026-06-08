import SwiftUI

/// The centered card used to create or rename a tab: a single text field over
/// a dimmed background with Cancel and confirm actions.
struct NameDialog: View {
    let title: String
    let initialText: String
    let confirmLabel: String
    let onCancel: () -> Void
    let onConfirm: (String) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canConfirm: Bool {
        !trimmedText.isEmpty
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(spacing: 14) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))

                TextField("Tab name", text: $text)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.12)))
                    .focused($focused)
                    .onSubmit(confirm)

                if !canConfirm {
                    Text("Enter a tab name.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 10) {
                    Button(action: onCancel) {
                        Text("Cancel").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(DialogButtonStyle())
                    .keyboardShortcut(.cancelAction)

                    Button(action: confirm) {
                        Text(confirmLabel).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(DialogButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canConfirm)
                }
            }
            .padding(16)
            .frame(width: 240)
            .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.1)))
            .onAppear {
                text = initialText
                // Wait until SwiftUI has installed the text field in the
                // AppKit responder chain before taking focus from the editor.
                DispatchQueue.main.async {
                    focused = true
                }
            }
        }
    }

    private func confirm() {
        guard canConfirm else { return }
        onConfirm(trimmedText)
    }
}

/// The centered card used before destructive tab deletion.
struct DeleteTabDialog: View {
    let tabName: String
    let onCancel: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(spacing: 14) {
                Text("Delete Tab?")
                    .font(.system(size: 13, weight: .semibold))

                Text("Delete \"\(tabName)\" permanently? This cannot be undone.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 10) {
                    Button(action: onCancel) {
                        Text("Cancel").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(DialogButtonStyle())
                    .keyboardShortcut(.cancelAction)

                    Button(action: onDelete) {
                        Text("Delete").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(DialogButtonStyle(prominent: true, destructive: true))
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
            .frame(width: 260)
            .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.1)))
        }
    }
}

/// Flat translucent button used in the dialogs.
struct DialogButtonStyle: ButtonStyle {
    var prominent = false
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        let base = prominent ? 0.22 : 0.12
        let opacity = configuration.isPressed ? base + 0.1 : base
        return configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(destructive ? .red : .primary)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(opacity))
            )
    }
}
