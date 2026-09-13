import Cocoa
import WebKit
import UserNotifications

// MARK: - Panel
final class SidebarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - App Delegate & Coordinator
final class AppDelegate: NSObject, NSApplicationDelegate,
                          WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate, NSMenuDelegate {
    static let shared = AppDelegate()

    private static let storeID = UUID(uuidString: "6F3A2B9C-1D4E-4F8A-9B7C-2E5D8A1C0F33")!
    private static let telegramURL = URL(string: "https://web.telegram.org/k")!
    private static let wakeSentinel = "/tmp/sidepiece.wake"
    private static let lockFile = NSHomeDirectory() + "/Library/Application Support/SidePiece/.running"

    // UI
    private var panel: SidebarPanel!
    private var webView: WKWebView!
    private var railView: NSView!
    private var railBadge: NSTextField?
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    // State
    private var isExpanded = false
    private var panelHidden = false
    private var dismissedUntilLeave = false
    private var lastBadgeCount = 0
    private var hoverTimer: Timer?
    private var collapseGrace: Timer?

    // Menu references
    private var hideItem: NSMenuItem?
    private var toggleItem: NSMenuItem?
    private var launchItem: NSMenuItem?
    private var expandItem: NSMenuItem?
    private var compactItem: NSMenuItem?
    private var invisibleRailItem: NSMenuItem?
    private var heightTitleItem: NSMenuItem?
    private var sideMenu: NSMenu?
    private var widthMenu: NSMenu?
    private var heightMenu: NSMenu?

    // Preferences
    private let d = UserDefaults.standard
    enum DockSide: String { case left, right }
    private var dockSide: DockSide {
        get { DockSide(rawValue: d.string(forKey: "dockSide") ?? "right") ?? .right }
        set { d.set(newValue.rawValue, forKey: "dockSide") }
    }
    private var invisibleRail: Bool {
        get {
            if let val = d.object(forKey: "invisibleRail") as? Bool { return val }
            return false
        }
        set {
            d.set(newValue, forKey: "invisibleRail")
        }
    }

    private var telegramMenuIcon: NSImage? {
        let fm = FileManager.default
        let candidates: [URL?] = [
            Bundle.main.url(forResource: "Logo", withExtension: "png"),
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("Logo.png"),
            Bundle.main.resourceURL?.appendingPathComponent("Logo.png"),
            URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("Logo.png"),
            URL(fileURLWithPath: "/Applications/SidePiece.app/Contents/MacOS/Logo.png"),
            URL(fileURLWithPath: "/Applications/SidePiece.app/Contents/Resources/Logo.png")
        ]
        for case let url? in candidates where fm.fileExists(atPath: url.path) {
            if let original = NSImage(contentsOf: url) {
                let size = NSSize(width: 18, height: 18)
                let icon = NSImage(size: size)
                icon.lockFocus()
                original.draw(in: NSRect(origin: .zero, size: size),
                              from: NSRect(origin: .zero, size: original.size),
                              operation: .copy,
                              fraction: 1.0)
                icon.unlockFocus()
                icon.isTemplate = false
                return icon
            }
        }
        let fallback = NSImage(systemSymbolName: "paperplane.fill", accessibilityDescription: "SidePiece")
        fallback?.isTemplate = true
        return fallback
    }

    private var panelWidth: CGFloat {
        get { let w = CGFloat(d.double(forKey: "panelWidth")); return w > 0 ? w : 380 }
        set { d.set(Double(newValue), forKey: "panelWidth") }
    }
    private var effectiveWidth: CGFloat { max(280, min(520, panelWidth)) }
    private var launchAtLogin: Bool {
        get { d.bool(forKey: "launchAtLogin") }
        set { d.set(newValue, forKey: "launchAtLogin") }
    }
    private var expandOnNotify: Bool {
        get { d.bool(forKey: "expandOnNotification") }
        set { d.set(newValue, forKey: "expandOnNotification") }
    }
    private var compactMode: Bool {
        get { d.object(forKey: "compactMode") == nil ? true : d.bool(forKey: "compactMode") }
        set { d.set(newValue, forKey: "compactMode") }
    }
    private var compactHeight: CGFloat {
        get { let h = CGFloat(d.double(forKey: "compactHeight")); return h > 0 ? h : 500 }
        set { d.set(Double(newValue), forKey: "compactHeight") }
    }

    // MARK: - Geometry & Display Helpers
    private func activeScreenBounds() -> (maxX: CGFloat, minX: CGFloat, minY: CGFloat, height: CGFloat) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSPointInRect(mouse, $0.frame) } ?? NSScreen.main
        let frame = screen?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        return (frame.maxX, frame.minX, frame.minY, frame.height)
    }

    private func currentPanelHeight() -> CGFloat {
        compactMode ? min(compactHeight, activeScreenBounds().height) : activeScreenBounds().height
    }

    private func currentPanelFrame(expanded: Bool) -> NSRect {
        let (maxX, minX, minY, h) = activeScreenBounds()
        let w: CGFloat = expanded ? effectiveWidth : 40
        let panelH = currentPanelHeight()
        let y = compactMode ? minY + (h - panelH) / 2.0 : minY
        let x = (dockSide == .right) ? (maxX - w) : minX
        return NSRect(x: x, y: y, width: w, height: panelH)
    }

    private func updatePanelFrame(animated: Bool = true) {
        guard panel != nil else { return }
        let r = currentPanelFrame(expanded: isExpanded)
        webView?.frame = NSRect(x: 0, y: 0, width: effectiveWidth, height: r.height)
        railView?.frame = NSRect(x: 0, y: 0, width: 40, height: r.height)
        applyCornerRadius()

        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.24
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(r, display: true)
            })
        } else {
            panel.setFrame(r, display: true)
        }
    }

    private func applyCornerRadius() {
        guard let rv = railView else { return }
        let radius: CGFloat = 14
        let corners: CACornerMask = (dockSide == .right)
            ? [.layerMinXMinYCorner, .layerMinXMaxYCorner]
            : [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        rv.wantsLayer = true
        rv.layer?.cornerRadius = radius
        rv.layer?.maskedCorners = corners
        rv.layer?.masksToBounds = true

        webView?.wantsLayer = true
        webView?.layer?.cornerRadius = radius
        webView?.layer?.maskedCorners = corners
        webView?.layer?.masksToBounds = true
    }

    // MARK: - Lifecycle
    func applicationDidFinishLaunching(_ notification: Notification) {
        let isDiag = CommandLine.arguments.contains("--selftest")
        if !isDiag && isAlreadyRunning() {
            try? "".write(toFile: Self.wakeSentinel, atomically: true, encoding: .utf8)
            NSApplication.shared.terminate(nil)
            return
        }
        if !isDiag { acquireLock() }
        NSApp.setActivationPolicy(.regular)

        if Bundle.main.bundleURL.pathExtension.lowercased() == "app" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
                UNUserNotificationCenter.current().delegate = self
            }
        }

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.updatePanelFrame(animated: false)
        }

        setupStatusMenu()
        setupPanel()
        setupWebView()

        webView.isHidden = true
        railView.isHidden = invisibleRail
        webView.alphaValue = 1
        isExpanded = false
        webView.load(URLRequest(url: Self.telegramURL))

        if isDiag {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.runSelfTest() }
        } else {
            startHoverPolling()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        setExpanded(true)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        hoverTimer?.invalidate()
        collapseGrace?.invalidate()
    }

    // MARK: - UI Setup
    private func setupPanel() {
        let r = currentPanelFrame(expanded: false)
        panel = SidebarPanel(contentRect: r, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = invisibleRail ? .clear : NSColor(srgbRed: 0.10, green: 0.11, blue: 0.13, alpha: 1.0)
        panel.isOpaque = !invisibleRail
        panel.hasShadow = !invisibleRail
        panel.acceptsMouseMovedEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.title = "SidePiece"
        panel.orderFrontRegardless()

        let rv = NSView(frame: NSRect(x: 0, y: 0, width: 40, height: r.height))
        rv.wantsLayer = true
        rv.layer?.isOpaque = true
        rv.layer?.backgroundColor = NSColor(srgbRed: 0.20, green: 0.565, blue: 0.925, alpha: 1.0).cgColor
        rv.isHidden = invisibleRail
        panel.contentView?.addSubview(rv)
        railView = rv

        // Logo
        let fm = FileManager.default
        let logoURL = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("Logo.png")
            ?? URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("Logo.png")
        if let img = NSImage(contentsOf: logoURL) {
            let logo = NSImageView(frame: NSRect(x: 4, y: railView.bounds.height - 38, width: 32, height: 32))
            logo.autoresizingMask = [.minYMargin]
            logo.image = img
            logo.imageScaling = .scaleProportionallyUpOrDown
            railView.addSubview(logo)
        }

        // Unread Badge Pill
        let badge = NSTextField(labelWithString: "")
        badge.frame = NSRect(x: 5, y: railView.bounds.height - 62, width: 30, height: 18)
        badge.autoresizingMask = [.minYMargin]
        badge.alignment = .center
        badge.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        badge.textColor = .white
        badge.wantsLayer = true
        badge.layer?.backgroundColor = NSColor(srgbRed: 0.90, green: 0.22, blue: 0.21, alpha: 1.0).cgColor
        badge.layer?.cornerRadius = 9
        badge.layer?.masksToBounds = true
        badge.isHidden = true
        railView.addSubview(badge)
        railBadge = badge

        applyCornerRadius()
    }

    private func setupWebView() {
        let r = currentPanelFrame(expanded: false)
        migrateLegacySessionIfNeeded()

        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: Self.storeID)
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(source: Self.bridgeJS, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        controller.addUserScript(WKUserScript(source: Self.scrollFixJS, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        controller.add(self, name: "tgBridge")
        config.userContentController = controller

        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: effectiveWidth, height: r.height), configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.setValue(true, forKey: "drawsBackground")
        webView.wantsLayer = true
        webView.layer?.isOpaque = true
        webView.layer?.backgroundColor = NSColor(srgbRed: 0.10, green: 0.11, blue: 0.13, alpha: 1.0).cgColor
        panel.contentView?.addSubview(webView)

        if let scroll = (webView.subviews.compactMap { $0 as? NSScrollView }).first {
            scroll.verticalScrollElasticity = .allowed
            scroll.horizontalScrollElasticity = .none
            scroll.hasVerticalScroller = true
            scroll.scrollerStyle = .overlay
        }

        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .scrollWheel]) { [weak self] event in
            guard let self = self, self.isExpanded,
                  let win = self.webView.window,
                  self.panel.frame.contains(win.convertPoint(toScreen: event.locationInWindow)) else { return event }
            NSApp.activate(ignoringOtherApps: true)
            win.makeFirstResponder(self.webView)
            return event
        }
    }

    // MARK: - Expand / Collapse Animation
    func setExpanded(_ expanded: Bool) {
        guard expanded != isExpanded else { return }
        isExpanded = expanded

        let r = currentPanelFrame(expanded: expanded)
        webView.frame = NSRect(x: 0, y: 0, width: effectiveWidth, height: r.height)
        railView.frame = NSRect(x: 0, y: 0, width: 40, height: r.height)

        if expanded {
            panel.hasShadow = true
            panel.backgroundColor = NSColor(srgbRed: 0.10, green: 0.11, blue: 0.13, alpha: 1.0)
            panel.isOpaque = true
            railView.isHidden = true
            webView.isHidden = false
        } else {
            if !invisibleRail {
                railView.isHidden = false
            }
        }
        webView.alphaValue = expanded ? 0 : 1

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.32
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(r, display: true)
            webView.animator().alphaValue = expanded ? 1 : 0
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            if self.isExpanded {
                self.panel.makeKey()
                self.webView.window?.makeFirstResponder(self.webView)
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            } else {
                self.webView.isHidden = true
                self.webView.alphaValue = 1
                if self.invisibleRail {
                    self.railView.isHidden = true
                    self.panel.backgroundColor = .clear
                    self.panel.isOpaque = false
                    self.panel.hasShadow = false
                } else {
                    self.railView.isHidden = false
                    self.panel.backgroundColor = NSColor(srgbRed: 0.10, green: 0.11, blue: 0.13, alpha: 1.0)
                    self.panel.isOpaque = true
                    self.panel.hasShadow = true
                }
            }
            self.refreshMenuStates()
        })
    }

    // MARK: - Hover Polling
    private func startHoverPolling() {
        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.checkWake()
            self?.pollHover()
        }
    }

    private func pollHover() {
        guard !panelHidden else { return }
        let mouse = NSEvent.mouseLocation
        let pf = panel.frame
        let inside = NSPointInRect(mouse, pf)

        if !inside { dismissedUntilLeave = false }

        if inside && !dismissedUntilLeave {
            collapseGrace?.invalidate()
            collapseGrace = nil
            if !isExpanded { setExpanded(true) }
        } else if isExpanded && !inside {
            if collapseGrace == nil {
                collapseGrace = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
                    self?.collapseGrace = nil
                    guard let self = self else { return }
                    if !NSPointInRect(NSEvent.mouseLocation, self.panel.frame) {
                        self.setExpanded(false)
                    }
                }
            }
        }
    }

    private func checkWake() {
        guard (try? String(contentsOfFile: Self.wakeSentinel, encoding: .utf8)) != nil else { return }
        try? FileManager.default.removeItem(atPath: Self.wakeSentinel)
        DispatchQueue.main.async { [weak self] in
            self?.showPanel()
            self?.setExpanded(true)
        }
    }

    // MARK: - Status Menu Setup
    private func setupStatusMenu() {
        if let btn = statusItem.button {
            btn.toolTip = "SidePiece"
            btn.image = telegramMenuIcon
            btn.imagePosition = .imageLeft
            btn.title = ""
        }

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        func item(_ title: String, _ action: Selector? = nil, _ key: String = "", _ tag: Any? = nil) -> NSMenuItem {
            let m = NSMenuItem(title: title, action: action, keyEquivalent: key)
            m.target = self
            m.representedObject = tag
            return m
        }

        func submenu(_ title: String, items: [(String, Selector, Any?)]) -> (NSMenuItem, NSMenu) {
            let sub = NSMenu()
            sub.autoenablesItems = false
            sub.delegate = self
            for (t, a, tag) in items { sub.addItem(item(t, a, "", tag)) }
            let parent = item(title)
            parent.submenu = sub
            return (parent, sub)
        }

        hideItem = item("Hide SidePiece", #selector(toggleHide), "h")
        menu.addItem(hideItem!)

        let (dockParent, dockSub) = submenu("Dock Side", items: [("Right", #selector(dockRight), nil), ("Left", #selector(dockLeft), nil)])
        sideMenu = dockSub
        menu.addItem(dockParent)

        let (widthParent, widthSub) = submenu("Panel Width", items: [("Narrow", #selector(setPanelWidth(_:)), 300), ("Medium", #selector(setPanelWidth(_:)), 380), ("Wide", #selector(setPanelWidth(_:)), 460)])
        widthMenu = widthSub
        menu.addItem(widthParent)

        launchItem = item("Launch at Login", #selector(toggleLaunchAtLogin))
        menu.addItem(launchItem!)

        expandItem = item("Expand on Notification", #selector(toggleExpandOnNotification))
        menu.addItem(expandItem!)

        compactItem = item("Compact Sidebar", #selector(toggleCompactMode))
        menu.addItem(compactItem!)

        invisibleRailItem = item("Invisible Rail (Auto-Hide)", #selector(toggleInvisibleRail))
        menu.addItem(invisibleRailItem!)

        let (heightParent, heightSub) = submenu("Compact Height", items: [("Short", #selector(setCompactHeight(_:)), 400), ("Medium", #selector(setCompactHeight(_:)), 500), ("Tall", #selector(setCompactHeight(_:)), 650)])
        heightMenu = heightSub
        heightTitleItem = heightParent
        menu.addItem(heightParent)

        menu.addItem(item("Clear Telegram Session", #selector(clearSession)))
        menu.addItem(NSMenuItem.separator())

        toggleItem = item("Expand Panel", #selector(togglePanel), "e")
        menu.addItem(toggleItem!)
        menu.addItem(item("Reload", #selector(reload), "r"))
        menu.addItem(item("Quit", #selector(quit), "q"))

        statusItem.menu = menu
        refreshMenuStates()
    }

    func menuWillOpen(_ menu: NSMenu) { refreshMenuStates() }

    private func refreshMenuStates() {
        hideItem?.title = panelHidden ? "Show SidePiece" : "Hide SidePiece"
        toggleItem?.title = isExpanded ? "Collapse Panel" : "Expand Panel"
        launchItem?.state = launchAtLogin ? .on : .off
        expandItem?.state = expandOnNotify ? .on : .off
        compactItem?.state = compactMode ? .on : .off
        invisibleRailItem?.state = invisibleRail ? .on : .off
        heightTitleItem?.isEnabled = compactMode

        sideMenu?.items.forEach { $0.state = ($0.title == (dockSide == .right ? "Right" : "Left")) ? .on : .off }
        widthMenu?.items.forEach { $0.state = (Int(effectiveWidth) == ($0.representedObject as? Int ?? 0)) ? .on : .off }
        heightMenu?.items.forEach {
            $0.state = (Int(compactHeight) == ($0.representedObject as? Int ?? 0)) ? .on : .off
            $0.isEnabled = compactMode
        }
    }

    // MARK: - Actions
    @objc private func toggleInvisibleRail() {
        invisibleRail = !invisibleRail
        if !isExpanded {
            railView?.isHidden = invisibleRail
            panel.backgroundColor = invisibleRail ? .clear : NSColor(srgbRed: 0.10, green: 0.11, blue: 0.13, alpha: 1.0)
            panel.isOpaque = !invisibleRail
            panel.hasShadow = !invisibleRail
        }
        refreshMenuStates()
    }

    @objc private func toggleHide() { panelHidden ? showPanel() : hidePanel() }
    private func showPanel() {
        guard panelHidden else { return }
        panelHidden = false; setExpanded(false); panel.orderFrontRegardless(); refreshMenuStates()
    }
    private func hidePanel() {
        guard !panelHidden else { return }
        panelHidden = true; dismissedUntilLeave = false; panel.orderOut(nil); refreshMenuStates()
    }

    @objc private func togglePanel() {
        if panelHidden { showPanel(); setExpanded(true); return }
        setExpanded(!isExpanded)
    }
    @objc private func reload() { webView.reload() }
    @objc private func quit() { NSApplication.shared.terminate(nil) }

    @objc private func dockRight() { setDockSide(.right) }
    @objc private func dockLeft() { setDockSide(.left) }
    private func setDockSide(_ side: DockSide) {
        guard dockSide != side else { return }
        dockSide = side; refreshMenuStates()
        if !panelHidden { updatePanelFrame(animated: true) }
    }

    @objc private func setPanelWidth(_ sender: NSMenuItem) {
        guard let w = sender.representedObject as? Int else { return }
        panelWidth = CGFloat(w); refreshMenuStates()
        if !panelHidden && isExpanded { updatePanelFrame(animated: true) }
    }

    @objc private func toggleCompactMode() {
        compactMode = !compactMode; refreshMenuStates()
        if !panelHidden { updatePanelFrame(animated: true) }
    }

    @objc private func setCompactHeight(_ sender: NSMenuItem) {
        guard let h = sender.representedObject as? Int else { return }
        compactHeight = CGFloat(h); refreshMenuStates()
        if !panelHidden { updatePanelFrame(animated: true) }
    }

    @objc private func toggleExpandOnNotification() {
        expandOnNotify = !expandOnNotify; refreshMenuStates()
    }

    @objc private func toggleLaunchAtLogin() {
        let desired = !launchAtLogin
        let agentPlist = NSHomeDirectory() + "/Library/LaunchAgents/com.sidepiece.app.plist"
        if desired {
            let plist = """
            <?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict><key>Label</key><string>com.sidepiece.app</string><key>ProgramArguments</key><array><string>/Applications/SidePiece.app/Contents/MacOS/SidePiece</string></array><key>RunAtLoad</key><true/></dict></plist>
            """
            try? FileManager.default.createDirectory(atPath: (agentPlist as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            if let src = Bundle.main.url(forResource: "com.sidepiece.app", withExtension: "plist") {
                try? FileManager.default.removeItem(atPath: agentPlist)
                try? FileManager.default.copyItem(at: src, to: URL(fileURLWithPath: agentPlist))
            } else {
                try? plist.write(toFile: agentPlist, atomically: true, encoding: .utf8)
            }
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/launchctl"); p.arguments = ["load", agentPlist]; try? p.run()
        } else {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/launchctl"); p.arguments = ["unload", agentPlist]; try? p.run()
            try? FileManager.default.removeItem(atPath: agentPlist)
        }
        launchAtLogin = desired
        refreshMenuStates()
    }

    @objc private func clearSession() {
        let alert = NSAlert()
        alert.messageText = "Clear Telegram Session?"
        alert.informativeText = "This will log you out of Telegram Web. You will need to log in again."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear Session")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let store = WKWebsiteDataStore(forIdentifier: Self.storeID)
        store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: Date(timeIntervalSince1970: 0)) { [weak self] in
            guard let self = self else { return }
            self.webView.load(URLRequest(url: Self.telegramURL))
        }
    }

    // MARK: - Navigation & Link Interception
    func webView(_ webView: WKWebView, didFinish nav: WKNavigation!) {
        webView.evaluateJavaScript(Self.bridgeJS, completionHandler: nil)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.allow); return }
        let host = url.host?.lowercased() ?? ""
        if host.contains("telegram.org") || host.contains("t.me") || url.scheme == "about" || url.scheme == "blob" {
            decisionHandler(.allow)
            return
        }
        if navigationAction.navigationType == .linkActivated {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { NSWorkspace.shared.open(url) }
        return nil
    }

    // MARK: - WebKit Script Message Handling & Badges
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "title":
            guard let t = body["title"] as? String else { return }
            let trimmed = t.trimmingCharacters(in: .whitespaces)
            var count = 0
            if let range = trimmed.range(of: #"^\(\d+\)"#, options: .regularExpression),
               let n = Int(trimmed[range].dropFirst().dropLast()) { count = n }
            guard count != lastBadgeCount else { return }
            lastBadgeCount = count

            if let btn = statusItem.button {
                btn.image = telegramMenuIcon
                btn.imagePosition = .imageLeft
                btn.title = count > 0 ? (count > 99 ? " 99+" : " \(count)") : ""
            }
            if let rb = railBadge {
                if count > 0 { rb.stringValue = count > 99 ? "99+" : "\(count)"; rb.isHidden = false }
                else { rb.stringValue = ""; rb.isHidden = true }
            }
        case "notification":
            let title = body["title"] as? String ?? "Telegram"
            let text = body["body"] as? String ?? ""
            if expandOnNotify {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, !self.panelHidden, !self.isExpanded else { return }
                    self.setExpanded(true)
                }
            }
            if Bundle.main.bundleURL.pathExtension.lowercased() == "app" {
                let c = UNMutableNotificationContent()
                c.title = title; c.body = text; c.sound = .default
                UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
            }
        default: break
        }
    }

    // MARK: - Process Lock & Session Migration
    private func isAlreadyRunning() -> Bool {
        let fd = open(Self.lockFile, O_RDONLY)
        guard fd != -1 else { return false }
        defer { close(fd) }
        var lock = flock(l_start: 0, l_len: 0, l_pid: 0, l_type: Int16(F_WRLCK), l_whence: 0)
        return fcntl(fd, F_GETLK, &lock) != -1 && lock.l_type != Int16(F_UNLCK)
    }

    private func acquireLock() {
        try? FileManager.default.createDirectory(atPath: (Self.lockFile as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let fd = open(Self.lockFile, O_WRONLY | O_CREAT, 0o644)
        if fd != -1 {
            var lock = flock(l_start: 0, l_len: 0, l_pid: 0, l_type: Int16(F_WRLCK), l_whence: 0)
            _ = fcntl(fd, F_SETLK, &lock)
        }
    }

    private func migrateLegacySessionIfNeeded() {
        let fm = FileManager.default
        let webkitDir = NSHomeDirectory() + "/Library/WebKit"
        let dest = webkitDir + "/\(Self.storeID.uuidString)/WebsiteData"
        guard !fm.fileExists(atPath: dest) else { return }
        for name in ["TelegramSidebarWeb", "com.user.telegram-sidebar-web"] {
            let src = webkitDir + "/" + name + "/WebsiteData"
            if fm.fileExists(atPath: src) {
                try? fm.createDirectory(atPath: (dest as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
                try? fm.moveItem(atPath: src, toPath: dest)
                try? fm.removeItem(atPath: webkitDir + "/" + name)
                break
            }
        }
    }

    // MARK: - Self-Test Diagnostic Harness
    private var selfTestDone = false
    private func runSelfTest() {
        setExpanded(true)
        var attempts = 0
        func poll() {
            guard let cv = self.panel.contentView,
                  let rep = cv.bitmapImageRepForCachingDisplay(in: cv.bounds) else {
                self.reportSelfTest(blank: true, colors: 0, reason: "no contentView/bitmap"); return
            }
            cv.layoutSubtreeIfNeeded()
            cv.cacheDisplay(in: cv.bounds, to: rep)
            if let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: "/tmp/tg_selftest.png"))
            }
            let (blank, colors) = self.classifyRep(rep)
            if !blank || attempts >= 15 {
                self.reportSelfTest(blank: blank, colors: colors, reason: blank ? "blank/white render" : "rendered \(colors) color buckets")
            } else {
                attempts += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { poll() }
            }
        }
        Timer.scheduledTimer(withTimeInterval: 35, repeats: false) { [weak self] _ in
            self?.reportSelfTest(blank: true, colors: 0, reason: "watchdog timeout")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { poll() }
    }

    private func reportSelfTest(blank: Bool, colors: Int, reason: String) {
        guard !selfTestDone else { return }
        selfTestDone = true
        let okVal = !blank ? "true" : "false"
        let json = "{\"ok\":\(okVal),\"reason\":\"\(reason)\",\"colors\":\(colors)}" + String(UnicodeScalar(10))
        try? json.write(toFile: "/tmp/tg_selftest.json", atomically: true, encoding: .utf8)
        NSApplication.shared.terminate(nil)
    }

    private func classifyRep(_ rep: NSBitmapImageRep) -> (blank: Bool, colors: Int) {
        let w = rep.pixelsWide, h = rep.pixelsHigh
        let stepX = max(1, w / 60), stepY = max(1, h / 60)
        var seen = Set<Int>()
        for y in stride(from: 0, to: h, by: stepY) {
            for x in stride(from: 0, to: w, by: stepX) {
                if let c = rep.colorAt(x: x, y: y) {
                    let r = Int(c.redComponent * 255) >> 4
                    let g = Int(c.greenComponent * 255) >> 4
                    let b = Int(c.blueComponent * 255) >> 4
                    seen.insert((r << 8) | (g << 4) | b)
                }
            }
        }
        return (seen.count < 6, seen.count)
    }

    // MARK: - Injected JavaScript
    // Pure native bridge without CSS overrides — Telegram Web K native themes handle Day/Night flawlessly.
    private static let bridgeJS = """
    (function () {
      function start() {
        var handler = window.webkit.messageHandlers.tgBridge;
        if (!handler) { setTimeout(start, 100); return; }
        try {
          setInterval(function () {
            handler.postMessage({ type: 'title', title: document.title || '' });
          }, 2000);
          if (window.Notification) {
            var Real = window.Notification;
            function Patched(title, opts) {
              handler.postMessage({ type: 'notification', title: String(title || ''), body: String((opts && opts.body) || '') });
            }
            Patched.permission = Real.permission;
            Patched.requestPermission = function (cb) { try { return Real.requestPermission(cb); } catch (e) {} };
            Patched.prototype = Real.prototype;
            window.Notification = Patched;
          }
        } catch (e) {}
      }
      start();
    })();
    """

    private static let scrollFixJS = """
    (function () {
      try {
        function fix() {
          document.querySelectorAll('div.scrollable-y, div.chatlist-parts, div.folders-scrollable')
            .forEach(function (el) {
              if (el.style.overflowY !== 'auto') {
                el.style.setProperty('overflow-y', 'auto', 'important');
              }
            });
        }
        fix();
        setInterval(fix, 1000);
      } catch (e) {}
    })();
    """
}

// MARK: - Notifications Delegate
extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completion: @escaping (UNNotificationPresentationOptions) -> Void) {
        completion([.banner, .sound])
    }
}
