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

        if !Settings.firstRunDone {
            if !runFirstRun() { NSApp.terminate(nil); return }
            Settings.firstRunDone = true
        }
        HearthstoneWatcher.shared.start()
    }

    /// First-launch: disclaimer + region pick. Returns false if the user declines.
    private func runFirstRun() -> Bool {
        NSApp.activate(ignoringOtherApps: true)

        let disc = NSAlert()
        disc.messageText = "Before you start"
        disc.informativeText = """
        BGMMR shows your opponents' Battlegrounds MMR by reading Hearthstone's memory (via code \
        injection). This is a gray area under Blizzard's Terms of Service and carries a real risk \
        of anti-cheat action on your account. It is not affiliated with or endorsed by Blizzard.

        Use at your own risk.
        """
        disc.alertStyle = .warning
        disc.addButton(withTitle: "I Understand — Continue")
        disc.addButton(withTitle: "Quit")
        if disc.runModal() != .alertFirstButtonReturn { return false }

        let pick = NSAlert()
        pick.messageText = "Select your region"
        pick.informativeText = "Pick the region you play Battlegrounds on (used to look up MMRs)."
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 220, height: 26))
        popup.addItems(withTitles: Region.allCases.map { $0.label })
        if let idx = Region.allCases.firstIndex(of: Settings.region) { popup.selectItem(at: idx) }
        pick.accessoryView = popup
        pick.addButton(withTitle: "Save")
        if pick.runModal() == .alertFirstButtonReturn {
            let r = Region.allCases[max(0, popup.indexOfSelectedItem)]
            Settings.region = r
        }
        return true
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
