import SwiftUI
import AppKit
import os

// The app uses AppKit for the menu bar item and the popover window lifecycle.
// The content is still SwiftUI. A custom borderless panel is used instead of
// NSPopover because NSPopover can visibly re-anchor itself after its first
// SwiftUI layout pass, which looks like the popover shifts down a few pixels.

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
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let menuBarGap: CGFloat = 1
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let store = TabStore()
    private let logger = Logger(subsystem: "com.notebloat.app", category: "popover")

    private var panel: NotebloatPanel?
    private var monitor: Any?
    private var defaultsObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let button = statusItem.button {
            button.image = StatusIcon.notebloat
            button.action = #selector(togglePopover)
            button.target = self
        }

        installMainMenu()
        createPanel()

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.applyPinnedBehavior()
                if self?.panel?.isVisible == true {
                    self?.positionPanel()
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

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "Quit Notebloat",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Paste and Match Style", action: #selector(NSTextView.pasteAsPlainText(_:)), keyEquivalent: "V")
        editMenu.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    private func createPanel() {
        let size = windowSize()
        let panel = NotebloatPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = NSHostingController(
            rootView: ContentView()
                .environmentObject(store)
        )
        self.panel = panel
        applyPinnedBehavior()
    }

    /// Reads the saved popover-size preference (the "Popover size" submenu)
    /// and returns its pixel dimensions, defaulting to medium.
    private func currentPopoverSize() -> NSSize {
        let raw = UserDefaults.standard.string(forKey: SettingsKey.popoverSize)
        let size = (raw.flatMap(PopoverSize.init(rawValue:)) ?? .medium).dimensions
        return NSSize(width: size.width, height: size.height)
    }

    private func windowSize() -> NSSize {
        let contentSize = currentPopoverSize()
        return contentSize
    }

    private var isPinned: Bool {
        UserDefaults.standard.bool(forKey: SettingsKey.pinned)
    }

    @objc private func togglePopover() {
        if panel?.isVisible == true {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let panel else { return }
        NSApp.activate(ignoringOtherApps: true)
        applyPinnedBehavior()
        positionPanel()
        panel.orderFrontRegardless()
        panel.makeKey()
        updateGlobalMonitor()
    }

    private func closePopover() {
        panel?.orderOut(nil)
        removeGlobalMonitor()
        logger.debug("Popover closed")
    }

    private func positionPanel() {
        guard let panel, let button = statusItem.button, let buttonWindow = button.window else { return }

        let size = windowSize()
        let buttonFrameInWindow = button.convert(button.bounds, to: nil)
        let buttonFrameOnScreen = buttonWindow.convertToScreen(buttonFrameInWindow)
        var origin = NSPoint(
            x: buttonFrameOnScreen.midX - (size.width / 2),
            y: buttonFrameOnScreen.minY - size.height - menuBarGap
        )

        if let screen = buttonWindow.screen ?? NSScreen.main {
            let visibleFrame = screen.visibleFrame
            origin.x = max(visibleFrame.minX + 8, min(origin.x, visibleFrame.maxX - size.width - 8))
            origin.y = max(visibleFrame.minY + 8, min(origin.y, visibleFrame.maxY - size.height - 8))
        }

        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func applyPinnedBehavior() {
        panel?.level = isPinned ? .floating : .normal
        updateGlobalMonitor()
    }

    private func updateGlobalMonitor() {
        removeGlobalMonitor()
        guard panel?.isVisible == true, !isPinned else { return }

        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isPinned else { return }
                self.closePopover()
            }
        }
    }

    private func removeGlobalMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

final class NotebloatPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

