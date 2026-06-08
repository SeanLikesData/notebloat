import SwiftUI
import ServiceManagement
import AppKit
import UniformTypeIdentifiers
import os

/// The Settings panel. A centered card over a dimmed background with grouped
/// appearance, behavior, and local data controls.
struct SettingsSheet: View {
    @EnvironmentObject private var store: TabStore
    @AppStorage(SettingsKey.theme) private var themeRaw = AppTheme.system.rawValue
    @AppStorage(SettingsKey.fontSize) private var fontRaw = FontSize.medium.rawValue
    @AppStorage(SettingsKey.popoverSize) private var popoverRaw = PopoverSize.medium.rawValue
    @AppStorage(SettingsKey.launchAtLogin) private var launchAtLogin = false
    @AppStorage(SettingsKey.markdownRendering) private var markdownRendering = false
    @AppStorage(SettingsKey.pinned) private var pinned = false

    let onClose: () -> Void

    @State private var settingsMessage: String?
    private let logger = Logger(subsystem: "com.notebloat.app", category: "settings")

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Settings").font(.headline)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 15))
                    }
                    .buttonStyle(.plain)
                }

                section("Appearance") {
                    row("Theme", icon: "paintpalette") {
                        Picker("", selection: $themeRaw) {
                            ForEach(AppTheme.allCases) { Text($0.label).tag($0.rawValue) }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                    }
                    divider
                    row("Font size", icon: "textformat.size") {
                        Picker("", selection: $fontRaw) {
                            ForEach(FontSize.allCases) { Text($0.label).tag($0.rawValue) }
                        }
                        .labelsHidden()
                        .frame(width: 110)
                    }
                    divider
                    row("Popover size", icon: "uiwindow.split.2x1") {
                        Picker("", selection: $popoverRaw) {
                            ForEach(PopoverSize.allCases) { Text($0.label).tag($0.rawValue) }
                        }
                        .labelsHidden()
                        .frame(width: 110)
                    }
                }

                section("Behavior") {
                    row("Pinned", subtitle: "Keep the popover open while using other apps.", icon: "pin") {
                        Toggle("", isOn: $pinned)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    divider
                    row("Launch at login", icon: "macwindow") {
                        Toggle("", isOn: $launchAtLogin)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .onChange(of: launchAtLogin) { _, newValue in
                                applyLaunchAtLogin(newValue)
                            }
                    }
                    divider
                    row("Render Markdown", subtitle: "Show formatting outside the selected line.", icon: "text.quote") {
                        Toggle("", isOn: $markdownRendering)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                }

                section("Data") {
                    row("Reveal Notes in Finder", icon: "folder") {
                        Button("Reveal", action: store.revealNotesInFinder)
                            .buttonStyle(.plain)
                            .foregroundStyle(.blue)
                    }
                    divider
                    row("Export as Markdown", icon: "doc.text") {
                        Button("Export…") { exportNotes(as: .markdown) }
                            .buttonStyle(.plain)
                            .foregroundStyle(.blue)
                    }
                    divider
                    row("Export as JSON", icon: "curlybraces") {
                        Button("Export…") { exportNotes(as: .json) }
                            .buttonStyle(.plain)
                            .foregroundStyle(.blue)
                    }
                    divider
                    row("Import JSON", subtitle: "Restore notes from a previous export.", icon: "arrow.down.doc") {
                        Button("Import…", action: importNotes)
                            .buttonStyle(.plain)
                            .foregroundStyle(.blue)
                    }
                }

                if let settingsMessage {
                    Text(settingsMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.system(size: 13))
            .padding(20)
            .frame(width: 380)
            .background(RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.primary.opacity(0.15), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 10)
            .onAppear {
                launchAtLogin = (SMAppService.mainApp.status == .enabled)
            }
        }
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 6)
            
            VStack(spacing: 0) {
                content()
            }
            .padding(.vertical, 2)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        }
    }

    private func row<Control: View>(
        _ title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            control()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
    }

    private var divider: some View {
        Divider()
            .padding(.leading, 46)
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            settingsMessage = nil
        } catch {
            logger.error("Launch-at-login change failed: \(error.localizedDescription, privacy: .public)")
            // If the system rejects the change (common for an unsigned local
            // build), snap the toggle back to the real state.
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
            settingsMessage = "Launch at login could not be changed for this build."
        }
    }

    private enum ExportFormat {
        case json
        case markdown

        var fileName: String {
            switch self {
            case .json: "Notebloat-tabs.json"
            case .markdown: "Notebloat-notes.md"
            }
        }

        var contentType: UTType {
            switch self {
            case .json: .json
            case .markdown: UTType(filenameExtension: "md") ?? .plainText
            }
        }

        var label: String {
            switch self {
            case .json: "JSON"
            case .markdown: "Markdown"
            }
        }
    }

    private func exportNotes(as format: ExportFormat) {
        let panel = NSSavePanel()
        panel.title = "Export Notebloat Notes"
        panel.nameFieldStringValue = format.fileName
        panel.allowedContentTypes = [format.contentType]

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            switch format {
            case .json:
                try store.exportNotes(to: url)
            case .markdown:
                try store.exportMarkdown(to: url)
            }
            settingsMessage = "\(format.label) exported to \(url.lastPathComponent)."
        } catch {
            logger.error("Export failed: \(error.localizedDescription, privacy: .public)")
            settingsMessage = "Export failed. \(error.localizedDescription)"
        }
    }

    private func importNotes() {
        let panel = NSOpenPanel()
        panel.title = "Import Notebloat Notes"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.importNotes(from: url)
            settingsMessage = "Notes imported from \(url.lastPathComponent)."
        } catch {
            logger.error("Import failed: \(error.localizedDescription, privacy: .public)")
            settingsMessage = "Import failed. Choose a Notebloat JSON export."
        }
    }
}
