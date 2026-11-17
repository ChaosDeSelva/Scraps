import AppKit
import SwiftUI
import Carbon

@main struct ScrapsMain {
    @MainActor static func main() {
        umask(0o077)
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSPopoverDelegate {
    private var store: ScrapStore!
    private var statusItem: NSStatusItem!
    private var popover = NSPopover()
    private var libraryWindow: NSWindow?
    private var hotKey: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = NSAppearance(named: .aqua)
        if Bundle.main.bundleIdentifier == "local.scraps.qa" {
            let url = ScrapStore.defaultURL.deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Scraps-QA").appendingPathComponent("Scraps.sqlite")
            store = ScrapStore(url: url)
        } else { store = ScrapStore() }
        configureMenu()
        configureStatusItem()
        configurePopover()
        configureShortcut()
        showLibrary()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showLibrary()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "tray.and.arrow.down", accessibilityDescription: "Scraps")
        image?.isTemplate = true
        button.image = image
        button.toolTip = "Scraps — Quick capture (⌃⌥Space)"
        button.setAccessibilityLabel("Scraps quick capture")
        button.target = self
        button.action = #selector(statusClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            addItem("Quick capture", action: #selector(toggleCapture), to: menu)
            addItem("Open library", action: #selector(showLibrary), to: menu)
            menu.addItem(.separator())
            addItem("Quit Scraps", action: #selector(quit), to: menu)
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else { toggleCapture() }
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 470, height: 620)
        popover.contentViewController = NSHostingController(rootView: CaptureView(store: store,
            openLibrary: { [weak self] in self?.showLibrary() },
            didSave: { [weak self] in
                self?.popover.performClose(nil)
                self?.showSavedIndicator()
            }))
    }

    @objc func toggleCapture() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func showSavedIndicator() {
        statusItem.button?.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Saved to Scraps")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            let image = NSImage(systemSymbolName: "tray.and.arrow.down", accessibilityDescription: "Scraps")
            image?.isTemplate = true
            self?.statusItem.button?.image = image
        }
    }

    @objc func showLibrary() {
        popover.performClose(nil)
        if libraryWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Scraps"
            window.minSize = NSSize(width: 1040, height: 710)
            window.backgroundColor = NSColor(Palette.canvas)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentViewController = NSHostingController(rootView: LibraryView(store: store, capture: { [weak self] in self?.toggleCapture() }))
            window.setFrameAutosaveName("ScrapsLibrary")
            window.center()
            libraryWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        libraryWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func focusSearch() {
        showLibrary()
        NotificationCenter.default.post(name: .scrapsFocusSearch, object: nil)
    }

    @objc private func revealData() {
        NSWorkspace.shared.activateFileViewerSelecting([store.databaseURL])
    }

    @objc private func quit() { NSApp.terminate(nil) }

    private func configureMenu() {
        let menu = NSMenu()
        let appMenu = NSMenu()
        let appRoot = NSMenuItem()
        appRoot.submenu = appMenu
        menu.addItem(appRoot)
        addItem("About Scraps", action: #selector(about), to: appMenu)
        appMenu.addItem(.separator())
        addItem("Quit Scraps", action: #selector(quit), key: "q", to: appMenu)

        let file = NSMenu(title: "File")
        let fileRoot = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        fileRoot.submenu = file
        menu.addItem(fileRoot)
        addItem("Quick capture", action: #selector(toggleCapture), key: "n", to: file)
        addItem("Open library", action: #selector(showLibrary), key: "1", to: file)
        addItem("Show local data folder", action: #selector(revealData), to: file)
        let close = NSMenuItem(title: "Close window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        file.addItem(close)

        let edit = NSMenu(title: "Edit")
        let editRoot = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editRoot.submenu = edit
        menu.addItem(editRoot)
        edit.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(redo)
        edit.addItem(.separator())
        edit.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        edit.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        edit.addItem(.separator())
        addItem("Search library", action: #selector(focusSearch), key: "f", to: edit)

        let windowMenu = NSMenu(title: "Window")
        let windowRoot = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        windowRoot.submenu = windowMenu
        menu.addItem(windowRoot)
        windowMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""))
        NSApp.mainMenu = menu
        NSApp.windowsMenu = windowMenu
    }

    private func addItem(_ title: String, action: Selector, key: String = "", to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    @objc private func about() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Scraps", .applicationVersion: "0.1.0",
            .credits: NSAttributedString(string: "A local home for snippets, notes, and the context worth keeping.\n" + (store.shortcutAvailable ? "Quick capture: Control–Option–Space (registered)" : "The global shortcut is unavailable. Click the menu-bar icon to capture."))
        ])
    }

    private func configureShortcut() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let result = InstallEventHandler(GetApplicationEventTarget(), { _, _, data in
            guard let data else { return OSStatus(eventNotHandledErr) }
            // Carbon dispatches application hotkeys on the main event loop.
            MainActor.assumeIsolated {
                Unmanaged<AppDelegate>.fromOpaque(data).takeUnretainedValue().toggleCapture()
            }
            return noErr
        }, 1, &type, pointer, &hotKeyHandler)
        guard result == noErr else { store.shortcutAvailable = false; return }
        let id = EventHotKeyID(signature: OSType(0x53435250), id: 1)
        let registered = RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey), id,
                                             GetApplicationEventTarget(), 0, &hotKey)
        store.shortcutAvailable = registered == noErr
        if registered != noErr { statusItem.button?.toolTip = "Scraps — click to capture (shortcut unavailable)" }
    }
}
