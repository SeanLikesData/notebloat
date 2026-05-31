import SwiftUI
import ServiceManagement
import AppKit
import UniformTypeIdentifiers
import os

/// The Settings panel. A centered card over a dimmed background with theme,
/// font size, popover size, launch-at-login, import, and export controls.
struct SettingsSheet: View {
    @EnvironmentObject private var store: TabStore
    @AppStorage(SettingsKey.theme) private var themeRaw = AppTheme.system.rawValue
    @AppStorage(SettingsKey.fontSize) private var fontRaw = FontSize.medium.rawValue
    @AppStorage(SettingsKey.popoverSize) private var popoverRaw = PopoverSize.medium.rawValue
    @AppStorage(SettingsKey.launchAtLogin) private var launchAtLogin = false

    let onClose: () -> Void

    @State private var settingsMessage: String?
    private let logger = Logger(subsystem: "com.notebloat.app", category: "settings")

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(alignment: .leading, spacing: 0) {
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
                .padding(.bottom, 14)

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
                HStack(spacing: 10) {
                    Button("Export Notes…", action: exportNotes)
                    Button("Import Notes…", action: importNotes)
                }
                .padding(.vertical, 8)

                if let settingsMessage {
                    Text(settingsMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                }
            }
            .font(.system(size: 13))
            .padding(18)
            .frame(width: 320)
            .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.1)))
            .onAppear {
                launchAtLogin = (SMAppService.mainApp.status == .enabled)
            }
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

    private func exportNotes() {
        let panel = NSSavePanel()
        panel.title = "Export Notebloat Notes"
        panel.nameFieldStringValue = "Notebloat-tabs.json"
        panel.allowedContentTypes = [.json]

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportNotes(to: url)
            settingsMessage = "Notes exported to \(url.lastPathComponent)."
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
