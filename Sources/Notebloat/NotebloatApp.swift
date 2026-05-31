import SwiftUI
import AppKit
import os

// The app is driven by an AppKit AppDelegate rather than a SwiftUI
// `MenuBarExtra` scene. `MenuBarExtra`'s window-style popover does not
// present reliably when the app is compiled with a bare `swiftc` build
// (no full Xcode) and launched as an LSUIElement accessory: the status
// icon appears but clicking it does nothing. Managing an NSStatusItem and
// NSPopover directly is the standard, dependable approach, and it still
// hosts the same SwiftUI views.

@main
enum Main {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let store = TabStore()
    private let logger = Logger(subsystem: "com.notebloat.app", category: "popover")
    private var monitor: Any?
    private var defaultsObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "note.text",
                accessibilityDescription: "Notebloat"
            )
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover.delegate = self
        applyPinnedBehavior()
        // No open/close animation: for a quick-notes tool opened and closed
        // constantly, an instant popover feels better than a smooth one.
        popover.animates = false
        popover.contentViewController = NSHostingController(
            rootView: ContentView().environmentObject(store)
        )
        // Give the popover a concrete size up front. Without this, the first
        // show happens before the SwiftUI content has laid out, so AppKit
        // anchors the popover using a zero size and then resizes it after it
        // appears. On a multi-display setup that initial mis-size makes the
        // popover land in the wrong place instead of directly below the icon.
        popover.contentSize = currentPopoverSize()

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.applyPinnedBehavior()
                if self?.popover.isShown == true {
                    self?.popover.contentSize = self?.currentPopoverSize() ?? .zero
                    self?.applyPinnedWindowLevel()
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.flushPendingSave()
        removeGlobalMonitor()
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
            self.defaultsObserver = nil
        }
    }

    /// Reads the saved popover-size preference (the "Popover size" submenu)
    /// and returns its pixel dimensions, defaulting to medium.
    private func currentPopoverSize() -> NSSize {
        let raw = UserDefaults.standard.string(forKey: SettingsKey.popoverSize)
        let size = (raw.flatMap(PopoverSize.init(rawValue:)) ?? .medium).dimensions
        return NSSize(width: size.width, height: size.height)
    }

    private var isPinned: Bool {
        UserDefaults.standard.bool(forKey: SettingsKey.pinned)
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        // Re-apply the size and pinned mode in case the user changed settings,
        // so the popover anchors correctly every time.
        popover.contentSize = currentPopoverSize()
        applyPinnedBehavior()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        applyPinnedWindowLevel()
        // Activate so the text field accepts keystrokes, but only after the
        // popover has been positioned by the show call above.
        NSApp.activate(ignoringOtherApps: true)

        updateGlobalMonitor()
    }

    private func applyPinnedBehavior() {
        popover.behavior = isPinned ? .applicationDefined : .transient
        updateGlobalMonitor()
    }

    private func applyPinnedWindowLevel() {
        guard let window = popover.contentViewController?.view.window else { return }
        window.level = isPinned ? .floating : .normal
    }

    private func updateGlobalMonitor() {
        removeGlobalMonitor()
        guard popover.isShown, !isPinned else { return }

        // Close the popover when the user clicks outside it. NSPopover's
        // transient behavior usually handles this, but a global monitor makes
        // it reliable for an accessory app.
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isPinned else { return }
                self.popover.performClose(nil)
            }
        }
    }

    private func removeGlobalMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    func popoverDidClose(_ notification: Notification) {
        logger.debug("Popover closed")
        removeGlobalMonitor()
    }
}
