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
                    row("Theme") {
                        Picker("", selection: $themeRaw) {
                            ForEach(AppTheme.allCases) { Text($0.label).tag($0.rawValue) }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                    }
                    divider
                    row("Font size") {
                        Picker("", selection: $fontRaw) {
                            ForEach(FontSize.allCases) { Text($0.label).tag($0.rawValue) }
                        }
                        .labelsHidden()
                        .frame(width: 110)
                    }
                    divider
                    row("Popover size") {
                        Picker("", selection: $popoverRaw) {
                            ForEach(PopoverSize.allCases) { Text($0.label).tag($0.rawValue) }
                        }
                        .labelsHidden()
                        .frame(width: 110)
                    }
                }

                section("Behavior") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Pinned")
                            Text("Keep the popover open while using other apps.")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $pinned)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    .padding(.vertical, 8)
                    divider
                    HStack {
                        Text("Launch at login")
                        Spacer()
                        Toggle("", isOn: $launchAtLogin)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: launchAtLogin) { _, newValue in
                                applyLaunchAtLogin(newValue)
                            }
                    }
                    .padding(.vertical, 8)
                    divider
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Render Markdown")
                            Text("Show formatting outside the selected line.")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $markdownRendering)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    .padding(.vertical, 8)
                }

                section("Data") {
                    Text("Notes are stored locally on this Mac.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 6)

                    HStack(spacing: 8) {
                        Button("Reveal in Finder", action: store.revealNotesInFinder)
                        Button("Markdown…") { exportNotes(as: .markdown) }
                        Button("JSON…") { exportNotes(as: .json) }
                        Button("Import…", action: importNotes)
                    }
                    .buttonStyle(.borderless)
                }

                if let settingsMessage {
                    Text(settingsMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.system(size: 13))
            .padding(18)
            .frame(width: 340)
            .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.1)))
            .onAppear {
                launchAtLogin = (SMAppService.mainApp.status == .enabled)
            }
        }
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            content()
        }
    }

    private func row<Control: View>(
        _ title: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            control()
        }
        .padding(.vertical, 8)
    }

    private var divider: some View {
        Divider().opacity(0.4)
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
