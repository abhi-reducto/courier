// App lifecycle, the menu bar item, the Dock, and the app's main menu.
import AppKit
import Combine
import SwiftUI
import UserNotifications

// Transparent view over the status button that accepts file drops. hitTest returns nil
// so clicks still reach the button and open the menu.
final class DropView: NSView {
    weak var target: AppDelegate?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        target?.setIcon("package-open")  // the box opens while a file hovers
        return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }
    override func draggingExited(_ sender: NSDraggingInfo?) { target?.setIcon("package") }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(sender.draggingPasteboard)
        guard let target, !urls.isEmpty else { return false }
        Uploads.shared.send(urls.map(\.path), to: target.settings.selected)
        return true
    }
}

func fileURLs(_ pb: NSPasteboard) -> [URL] {
    pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSToolbarDelegate, UNUserNotificationCenterDelegate {
    let settings = Settings.shared
    let uploads = Uploads.shared
    var item: NSStatusItem!
    let menu = NSMenu()
    var mainWindow: NSWindow?
    var subs: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ n: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        setIcon("package")
        menu.delegate = self
        item.menu = menu
        if let button = item.button {
            let drop = DropView(frame: button.bounds)
            drop.autoresizingMask = [.width, .height]
            drop.target = self
            drop.registerForDraggedTypes([.fileURL])
            button.addSubview(drop)
        }
        NSApp.mainMenu = mainMenu()
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        settings.refresh()
        if settings.selected.isEmpty, let d = settings.devices.first(where: \.online) { settings.selected = d.name }

        // Menu bar icon follows uploads: a progress ring, then a check or an X for a moment.
        uploads.$progress.receive(on: RunLoop.main).sink { [weak self] p in
            if let pct = p.values.min() { self?.setProgress(pct) }
        }.store(in: &subs)
        uploads.finished.receive(on: RunLoop.main).sink { [weak self] r in
            guard let self else { return }
            item.button?.toolTip = nil
            setIcon(r.ok ? "circle-check" : "circle-x")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if self.uploads.progress.isEmpty { self.setIcon("package") }
            }
            notify(r.message)
        }.store(in: &subs)

        settings.$showInDock.combineLatest(settings.$showInMenuBar).receive(on: RunLoop.main)
            .sink { [weak self] dock, bar in self?.applyVisibility(dock: dock, menuBar: bar) }
            .store(in: &subs)
        // Say where Drop went when it's added to or taken off the Dock or the menu bar.
        settings.$showInDock.dropFirst().removeDuplicates().sink { on in
            notify(on ? "Courier is in the Dock now." : "Courier is off the Dock. It's still in the menu bar.")
        }.store(in: &subs)
        settings.$showInMenuBar.dropFirst().removeDuplicates().sink { on in
            notify(on ? "Courier is in the menu bar now." : "Courier is off the menu bar. Open it from the Dock.")
        }.store(in: &subs)
        // With no menu bar icon, the window is the only way in.
        if !settings.showInMenuBar || CommandLine.arguments.contains("--window") { openMain() }
        if CommandLine.arguments.contains("--settings") { openSettings() }
    }

    func applyVisibility(dock: Bool, menuBar: Bool) {
        item.isVisible = menuBar
        let wasVisible = mainWindow?.isVisible == true
        NSApp.setActivationPolicy(dock ? .regular : .accessory)
        // Leaving the Dock deactivates the app, which hides its window. Bring it back.
        if dock || wasVisible {
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                if wasVisible { self.mainWindow?.makeKeyAndOrderFront(nil) }
            }
        }
    }

    // Show notifications even while a Drop window is in front.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner])
    }

    // Clicking the Dock icon.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { openMain() }
        return true
    }

    // MARK: Status item icon

    func setIcon(_ name: String) {
        let img = lucideImage(name) ?? NSImage(systemSymbolName: name, accessibilityDescription: "Courier")
        img?.isTemplate = true
        item.button?.image = img
    }

    // Upload icon with a ring that fills clockwise as the upload progresses.
    func setProgress(_ pct: Int) {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { r in
            // Same proportions as Lucide's circle icons: r=10, stroke 2 on a 24 grid.
            let c = NSPoint(x: r.midX, y: r.midY), radius: CGFloat = 7.5
            NSColor.black.withAlphaComponent(0.25).setStroke()
            let track = NSBezierPath(); track.appendArc(withCenter: c, radius: radius, startAngle: 0, endAngle: 360)
            track.lineWidth = 1.5; track.stroke()
            NSColor.black.setStroke()
            let arc = NSBezierPath()
            arc.appendArc(withCenter: c, radius: radius, startAngle: 90, endAngle: 90 - 360 * CGFloat(pct) / 100, clockwise: true)
            arc.lineWidth = 1.5; arc.lineCapStyle = .round; arc.stroke()
            lucideImage("arrow-up", size: 10)?.draw(in: NSRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10))
            return true
        }
        img.isTemplate = true
        item.button?.image = img
        item.button?.toolTip = "Uploading… \(pct)%"
    }

    // MARK: Status menu

    // Actions, then the devices with their folders in small gray type on the right, then the app.
    // No shortcut labels here: their column would push the folders out of line.
    func menuNeedsUpdate(_ menu: NSMenu) {
        settings.refresh()
        let selected = settings.selected
        menu.removeAllItems()
        menu.addItem(item("Select Files…", "file-plus", #selector(selectFiles)))
        menu.addItem(item("Send Clipboard", "clipboard-paste", #selector(sendClipboard)))
        menu.addItem(.separator())

        menu.addItem(NSMenuItem.sectionHeader(title: "Send to"))
        let shown = settings.devices.filter { !settings.hidden.contains($0.name) || $0.name == selected }
        let rows = shown.map { ($0.name, $0.online ? shortPath(settings.dir(for: $0.name)) : "offline") }
        let column = rightColumn(rows)
        for (d, row) in zip(shown, rows) {
            let mi = NSMenuItem(title: d.name, action: #selector(pick(_:)), keyEquivalent: "")
            mi.attributedTitle = twoColumn(row.0, row.1, column)
            mi.image = lucideImage(settings.icon(for: d.name), size: 16)
            mi.representedObject = d.name
            mi.state = d.name == selected ? .on : .off
            mi.isEnabled = d.online
            mi.target = self
            menu.addItem(mi)
        }
        menu.addItem(.separator())

        menu.addItem(item("Open Courier…", "package", #selector(openMain)))
        menu.addItem(item("Settings…", "settings", #selector(openSettings)))
        let quit = item("Quit Courier", "x", #selector(NSApp.terminate(_:)))
        quit.target = NSApp
        menu.addItem(quit)
    }

    func item(_ title: String, _ icon: String, _ action: Selector?) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: "")
        mi.image = lucideImage(icon, size: 16) ?? NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        mi.target = self
        return mi
    }

    // Long folders keep their start and end: ~/.cache/claude-images -> ~/.cache/…/claude-images.
    func shortPath(_ p: String) -> String {
        guard p.count > 24 else { return p }
        let parts = p.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count > 3 else { return String(p.prefix(10)) + "…" + String(p.suffix(12)) }
        return "\(parts[0])/\(parts[1])/…/\(parts.last!)"
    }

    static let detailFont = NSFont.systemFont(ofSize: 11.5)

    // Where the right-hand column ends: widest name, a gap, widest folder.
    func rightColumn(_ rows: [(String, String)]) -> CGFloat {
        let name = NSFont.menuFont(ofSize: 0)
        let w = { (t: String, f: NSFont) in (t as NSString).size(withAttributes: [.font: f]).width }
        return (rows.map { w($0.0, name) }.max() ?? 0) + 40 + (rows.map { w($0.1, Self.detailFont) }.max() ?? 0)
    }

    func twoColumn(_ left: String, _ right: String, _ column: CGFloat) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.tabStops = [NSTextTab(textAlignment: .right, location: column)]
        let s = NSMutableAttributedString(string: left, attributes: [.font: NSFont.menuFont(ofSize: 0), .paragraphStyle: para])
        s.append(NSAttributedString(string: "\t" + right, attributes: [
            .font: Self.detailFont, .paragraphStyle: para, .foregroundColor: NSColor.tertiaryLabelColor,
            .baselineOffset: 0.5]))
        return s
    }

    @objc func pick(_ sender: NSMenuItem) {
        if let name = sender.representedObject as? String { settings.selected = name }
    }

    @objc func selectFiles() { chooseFiles(for: settings.selected) }

    @objc func sendClipboard() { Uploads.shared.send(fileURLs(NSPasteboard.general).map(\.path), to: settings.selected) }

    // MARK: Windows

    @objc func openMain() {
        if mainWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            let host = NSHostingController(rootView: MainView())
            host.sizingOptions = []  // the window keeps its own size when switching to Settings
            w.contentViewController = host
            // A real toolbar: a taller title bar with the settings button as a standard toolbar item.
            let toolbar = NSToolbar(identifier: "DropToolbar")
            toolbar.delegate = self
            toolbar.displayMode = .iconOnly
            toolbar.allowsUserCustomization = false
            w.toolbar = toolbar
            w.toolbarStyle = .unified
            w.titlebarSeparatorStyle = .none
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isMovableByWindowBackground = true
            w.backgroundColor = Theme.nsBG
            w.setContentSize(NSSize(width: 480, height: 640))
            w.minSize = NSSize(width: 420, height: 480)
            w.isReleasedWhenClosed = false
            w.setFrameAutosaveName("DropWindow")
            if !w.setFrameUsingName("DropWindow") { w.center() }
            mainWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    static let settingsItem = NSToolbarItem.Identifier("settings")
    var settingsToolbarItem: NSToolbarItem?

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.settingsItem]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard id == Self.settingsItem else { return nil }
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = "Settings"
        item.toolTip = "Settings  ⌘,"
        item.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
        item.isBordered = true
        item.target = self
        item.action = #selector(toggleSettings)
        settingsToolbarItem = item
        UIState.shared.$showSettings.receive(on: RunLoop.main).sink { [weak item] on in
            item?.image = NSImage(systemSymbolName: on ? "xmark" : "gearshape", accessibilityDescription: on ? "Close Settings" : "Settings")
            item?.toolTip = on ? "Close Settings" : "Settings  ⌘,"
        }.store(in: &subs)
        return item
    }

    // ⌘, opens Settings, or closes it when it's already showing in a front window.
    @objc func toggleSettingsFromMenu() {
        if UIState.shared.showSettings && mainWindow?.isKeyWindow == true { toggleSettings() } else { openSettings() }
    }

    @objc func toggleSettings() {
        withAnimation(.easeOut(duration: 0.18)) { UIState.shared.showSettings.toggle() }
    }

    // Settings live inside the Drop window, behind the toolbar's gear.
    @objc func openSettings() {
        UIState.shared.showSettings = true
        openMain()
    }

    // App menu bar, used while a Drop window is in front. The Edit menu makes ⌘C/⌘V work in text fields.
    func mainMenu() -> NSMenu {
        let main = NSMenu()
        func add(_ title: String, _ items: [NSMenuItem]) {
            let m = NSMenu(title: title)
            items.forEach(m.addItem)
            let top = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            top.submenu = m
            main.addItem(top)
        }
        func mi(_ t: String, _ a: Selector?, _ k: String, target: AnyObject? = nil) -> NSMenuItem {
            let i = NSMenuItem(title: t, action: a, keyEquivalent: k)
            i.target = target
            return i
        }
        add("Courier", [
            mi("About Courier", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), ""),
            .separator(),
            mi("Settings…", #selector(toggleSettingsFromMenu), ",", target: self),
            .separator(),
            mi("Hide Courier", #selector(NSApplication.hide(_:)), "h"),
            .separator(),
            mi("Quit Courier", #selector(NSApplication.terminate(_:)), "q"),
        ])
        add("File", [
            mi("Open Courier Window", #selector(openMain), "n", target: self),
            mi("Close Window", #selector(NSWindow.performClose(_:)), "w"),
        ])
        add("Edit", [
            mi("Undo", Selector(("undo:")), "z"),
            mi("Redo", Selector(("redo:")), "Z"),
            .separator(),
            mi("Cut", #selector(NSText.cut(_:)), "x"),
            mi("Copy", #selector(NSText.copy(_:)), "c"),
            mi("Paste", #selector(NSText.paste(_:)), "v"),
            mi("Select All", #selector(NSText.selectAll(_:)), "a"),
        ])
        add("Window", [
            mi("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
        ])
        return main
    }
}

// Shared by the menu bar and the window.
func chooseFiles(for device: String) {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = true
    panel.prompt = "Send to \(device)"
    NSApp.activate(ignoringOtherApps: true)
    if panel.runModal() == .OK, !panel.urls.isEmpty { Uploads.shared.send(panel.urls.map(\.path), to: device) }
}

// Files copied in Finder are sent as files; otherwise rimg sends the clipboard image.
func sendClipboard(to device: String) {
    Uploads.shared.send(fileURLs(NSPasteboard.general).map(\.path), to: device)
}

// A macOS notification from Drop itself, so it carries Drop's icon.
func notify(_ text: String) {
    let content = UNMutableNotificationContent()
    content.title = "Courier"
    content.body = text
    UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
}
