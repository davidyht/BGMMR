import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "MMR"
        statusItem.button?.toolTip = "Battlegrounds Opponent MMR"
        let menu = NSMenu()
        menu.delegate = self                // rebuilt each time it opens, so status is live
        statusItem.menu = menu
        HearthstoneWatcher.shared.start()
    }

    // Rebuild on open so the status line + checkmarks are current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let header = NSMenuItem(title: "Battlegrounds Opponent MMR", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        let status = NSMenuItem(title: statusLine(), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        addItem(menu, "Enabled", #selector(toggleEnabled), state: Settings.enabled)

        let regionMenu = NSMenu()
        for r in Region.allCases {
            let it = NSMenuItem(title: r.label, action: #selector(setRegion(_:)), keyEquivalent: "")
            it.target = self; it.representedObject = r.rawValue
            it.state = (Settings.region == r) ? .on : .off
            regionMenu.addItem(it)
        }
        let regionItem = NSMenuItem(title: "Region", action: nil, keyEquivalent: "")
        regionItem.submenu = regionMenu
        menu.addItem(regionItem)

        addItem(menu, "Set your BattleTag… (\(Settings.ownName.isEmpty ? "none" : Settings.ownName))", #selector(setOwnName))
        let hsTitle = Settings.hearthstonePath.isEmpty
            ? "Set Hearthstone path… (auto-detect)"
            : "Hearthstone: \((Settings.hearthstonePath as NSString).lastPathComponent) — change…"
        addItem(menu, hsTitle, #selector(setHearthstonePath))
        if !Settings.hearthstonePath.isEmpty {
            addItem(menu, "Use auto-detect (clear path)", #selector(clearHearthstonePath))
        }
        addItem(menu, "Show panel preview", #selector(showPreview))
        addItem(menu, "Zoom In", #selector(zoomIn), key: "+")
        addItem(menu, "Zoom Out", #selector(zoomOut), key: "-")

        menu.addItem(.separator())
        addItem(menu, "Auto-start with Hearthstone", #selector(toggleAutoStart), state: AutoStart.isInstalled)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @discardableResult
    private func addItem(_ menu: NSMenu, _ title: String, _ action: Selector, key: String = "", state: Bool? = nil) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
        it.target = self
        if let s = state { it.state = s ? .on : .off }
        menu.addItem(it)
        return it
    }

    private func statusLine() -> String {
        switch HearthstoneWatcher.shared.state {
        case .disabled:   return "Disabled"
        case .noGame:     return "Hearthstone: not running"
        case .rosetta:    return "Hearthstone: under Rosetta — switch to Apple Silicon"
        case .connecting: return "Hearthstone: connecting…"
        case .connected:  return "Hearthstone: connected"
        }
    }

    // MARK: actions

    @objc private func toggleEnabled() {
        Settings.enabled.toggle()
        HearthstoneWatcher.shared.refresh()
    }

    @objc private func setRegion(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let r = Region(rawValue: raw) { Settings.region = r }
    }

    @objc private func showPreview() { MmrPanel.shared.showPreview() }
    @objc private func zoomIn() { MmrPanel.shared.zoom(by: 0.15) }
    @objc private func zoomOut() { MmrPanel.shared.zoom(by: -0.15) }

    @objc private func setOwnName() {
        let alert = NSAlert()
        alert.messageText = "Your BattleTag"
        alert.informativeText = "Enter your name (without #1234) so you're hidden from the opponent list. Leave blank to show everyone."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = Settings.ownName
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            Settings.ownName = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    @objc private func toggleAutoStart() {
        if AutoStart.isInstalled {
            AutoStart.remove()
        } else if let note = AutoStart.install() {
            showInfo(note)
        }
    }

    @objc private func setHearthstonePath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = ["app"]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Choose"
        panel.message = "Select Hearthstone.app (only needed if auto-detect fails)."
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            Settings.hearthstonePath = url.path
            AutoStart.refreshIfInstalled()
            HearthstoneWatcher.shared.refresh()
        }
    }

    @objc private func clearHearthstonePath() {
        Settings.hearthstonePath = ""
        AutoStart.refreshIfInstalled()
        HearthstoneWatcher.shared.refresh()
    }

    private func showInfo(_ text: String) {
        let a = NSAlert(); a.messageText = "BGMMR"; a.informativeText = text
        a.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}
