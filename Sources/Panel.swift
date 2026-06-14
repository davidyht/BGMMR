import Cocoa

private final class CardView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
}

/// Draggable, resizable (zoomable) overlay card showing opponent MMRs.
final class MmrPanel: NSObject, NSWindowDelegate {
    static let shared = MmrPanel()

    private static let baseInset: CGFloat = 8
    private static let gold = NSColor(red: 1.0, green: 0.82, blue: 0.30, alpha: 1.0)
    private static let gray = NSColor(white: 0.72, alpha: 1.0)
    private static let minScale: CGFloat = 0.6
    private static let maxScale: CGFloat = 3.0

    private var panel: NSPanel?
    private let card = CardView()
    private let label = NSTextField()
    private let closeButton = NSButton()
    private var moveObserver: Any?
    private var lastSetFrame: NSRect = .zero
    private var applyingFrame = false
    private var dismissed = false
    private var lastEntries: [(name: String, rating: Int?)] = []
    private var lastTitle = "Opponents (MMR)"
    private var scale: CGFloat = 1.0

    private override init() {
        super.init()
        scale = max(MmrPanel.minScale, min(MmrPanel.maxScale, CGFloat(Settings.panelScale)))
    }

    // MARK: window

    private func ensureWindow() {
        if panel != nil { return }
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 220, height: 60),
                        styleMask: [.borderless, .resizable, .nonactivatingPanel], backing: .buffered, defer: true)
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) - 1)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.ignoresMouseEvents = false
        p.isMovableByWindowBackground = true
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.minSize = NSSize(width: 110, height: 36)
        p.delegate = self

        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.62).cgColor
        card.layer?.cornerRadius = 7
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor(white: 1.0, alpha: 0.12).cgColor

        label.isBezeled = false
        label.isEditable = false
        label.isSelectable = false
        label.drawsBackground = false
        label.maximumNumberOfLines = 0
        label.cell?.wraps = true

        closeButton.isBordered = false
        closeButton.imagePosition = .imageOnly
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")
        closeButton.contentTintColor = NSColor(white: 0.85, alpha: 0.9)
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.toolTip = "Close"
        (closeButton.cell as? NSButtonCell)?.highlightsBy = []

        card.addSubview(label)
        card.addSubview(closeButton)
        p.contentView?.addSubview(card)
        panel = p

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: p, queue: .main) { [weak self] _ in
            guard let self, let panel = self.panel, !self.applyingFrame else { return }
            if panel.frame == self.lastSetFrame { return }
            Settings.panelFrame = panel.frame
        }
    }

    @objc private func closeClicked() { dismissed = true; hide() }

    // MARK: content

    private func truncate(_ s: String, font: NSFont, maxWidth: CGFloat) -> String {
        let a: [NSAttributedString.Key: Any] = [.font: font]
        if (s as NSString).size(withAttributes: a).width <= maxWidth { return s }
        var t = s
        while t.count > 1 {
            t = String(t.dropLast())
            if ((t + "…") as NSString).size(withAttributes: a).width <= maxWidth { return t + "…" }
        }
        return t
    }

    private func makeContent(_ entries: [(name: String, rating: Int?)], title: String, scale: CGFloat) -> (NSAttributedString, CGFloat) {
        let titleFont = NSFont.boldSystemFont(ofSize: 12 * scale)
        let nameFont = NSFont.systemFont(ofSize: 12 * scale)
        let mmrFont = NSFont.monospacedDigitSystemFont(ofSize: 12 * scale, weight: .semibold)
        func w(_ s: String, _ f: NSFont) -> CGFloat { ceil((s as NSString).size(withAttributes: [.font: f]).width) }

        let nameCap: CGFloat = 150 * scale
        let names = entries.map { truncate($0.name, font: nameFont, maxWidth: nameCap) }
        let mmrs = entries.map { $0.rating.map { "\($0)" } ?? "<8000" }
        let maxName = names.map { w($0, nameFont) }.max() ?? 0
        let maxMmr = mmrs.map { w($0, mmrFont) }.max() ?? 0
        let tab = maxName + 16 * scale
        let contentWidth = max(tab + maxMmr, w(title, titleFont)) + 2

        let row = NSMutableParagraphStyle()
        row.tabStops = [NSTextTab(textAlignment: .left, location: tab)]
        row.defaultTabInterval = tab
        row.lineBreakMode = .byClipping
        row.paragraphSpacing = 1.5 * scale
        let titleStyle = NSMutableParagraphStyle(); titleStyle.paragraphSpacing = 4 * scale

        let res = NSMutableAttributedString()
        res.append(NSAttributedString(string: title + "\n", attributes: [.font: titleFont, .foregroundColor: MmrPanel.gold, .paragraphStyle: titleStyle]))
        for (i, e) in entries.enumerated() {
            let suffix = i == entries.count - 1 ? "" : "\n"
            let line = NSMutableAttributedString(string: names[i], attributes: [.font: nameFont, .foregroundColor: NSColor(white: 0.96, alpha: 1.0), .paragraphStyle: row])
            line.append(NSAttributedString(string: "\t" + mmrs[i] + suffix, attributes: [.font: mmrFont, .foregroundColor: e.rating != nil ? MmrPanel.gold : MmrPanel.gray, .paragraphStyle: row]))
            res.append(line)
        }
        return (res, contentWidth)
    }

    private func layout(inset: CGFloat, contentW: CGFloat, textH: CGFloat) {
        guard let cv = panel?.contentView else { return }
        card.frame = cv.bounds
        label.frame = NSRect(x: inset, y: inset, width: contentW, height: textH)
        let cb = max(12, 13 * scale)
        closeButton.frame = NSRect(x: card.bounds.width - cb - 4, y: card.bounds.height - cb - 4, width: cb, height: cb)
    }

    // MARK: public

    /// Preview shows the selected region's real top 8 players.
    func showPreview() {
        dismissed = false
        let region = Settings.region
        let render: () -> Void = { [weak self] in
            let top = RankService.shared.topPlayers(8)
            let title = "Top 8 · \(region.short)"
            if top.isEmpty {
                self?.update(entries: [("Loading leaderboard…", nil)], title: title)
            } else {
                self?.update(entries: top.map { (name: $0.name, rating: Optional($0.rating)) }, title: title)
            }
        }
        RankService.shared.prefetch(region: region, duos: false) { DispatchQueue.main.async { render() } }
        render()
    }

    func update(entries: [(name: String, rating: Int?)], title: String = "Opponents (MMR)") {
        guard !entries.isEmpty else { hide(); return }
        if dismissed { return }
        lastEntries = entries
        lastTitle = title
        ensureWindow()
        guard let panel = panel else { return }

        let inset = MmrPanel.baseInset * scale
        let (attr, contentW) = makeContent(entries, title: title, scale: scale)
        label.attributedStringValue = attr
        let textH = ceil(attr.boundingRect(with: NSSize(width: contentW + 2, height: .greatestFiniteMagnitude),
                                           options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
        let w = contentW + inset * 2
        let h = textH + inset * 2

        let leftX: CGFloat, topY: CGFloat
        if let saved = Settings.panelFrame {
            leftX = saved.minX; topY = saved.maxY
        } else if let scr = NSScreen.main {
            leftX = scr.visibleFrame.minX + 24; topY = scr.visibleFrame.maxY - 24
        } else { leftX = 40; topY = 800 }

        let frame = NSRect(x: leftX, y: topY - h, width: w, height: h)
        applyingFrame = true
        lastSetFrame = frame
        panel.setFrame(frame, display: true)
        applyingFrame = false
        layout(inset: inset, contentW: contentW, textH: textH)
        panel.orderFront(nil)
    }

    /// Menu zoom (reliable companion to corner-drag).
    func zoom(by delta: CGFloat) {
        setScale(scale + delta)
    }
    private func setScale(_ s: CGFloat) {
        scale = max(MmrPanel.minScale, min(MmrPanel.maxScale, s))
        Settings.panelScale = Double(scale)
        if panel?.isVisible == true { update(entries: lastEntries, title: lastTitle) }
    }

    func hide() { panel?.orderOut(nil) }

    /// Hide and clear the "user closed it" flag — called at match start/end so a new game shows it again.
    func resetState() { dismissed = false; hide() }

    // MARK: NSWindowDelegate (corner-drag zoom)

    func windowDidResize(_ notification: Notification) {
        guard !applyingFrame, let panel = panel, !lastEntries.isEmpty else { return }
        let (_, naturalContentW) = makeContent(lastEntries, title: lastTitle, scale: 1.0)
        let naturalW = naturalContentW + MmrPanel.baseInset * 2
        guard naturalW > 1 else { return }
        scale = max(MmrPanel.minScale, min(MmrPanel.maxScale, panel.frame.width / naturalW))
        // Re-render at the new scale, filling the window the user is dragging.
        let inset = MmrPanel.baseInset * scale
        let (attr, contentW) = makeContent(lastEntries, title: lastTitle, scale: scale)
        label.attributedStringValue = attr
        let textH = ceil(attr.boundingRect(with: NSSize(width: contentW + 2, height: .greatestFiniteMagnitude),
                                           options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
        layout(inset: inset, contentW: contentW, textH: textH)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        Settings.panelScale = Double(scale)
        if let f = panel?.frame { Settings.panelFrame = f }   // anchor to where the user left it
        update(entries: lastEntries, title: lastTitle)        // snap to fit content at this zoom
    }
}
