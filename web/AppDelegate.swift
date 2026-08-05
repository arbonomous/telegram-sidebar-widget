import Cocoa
import WebKit
import UserNotifications

// Panel subclass so a .nonactivatingPanel can still become key — this is what
// lets WKWebView receive keyboard input (typing in the message box) without the
// app stealing activation from the app the user is actually working in.
final class SidebarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate,
                          WKScriptMessageHandler, WKNavigationDelegate {

    static let shared = AppDelegate()

    private var panel: SidebarPanel!
    private var webView: WKWebView!
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var isExpanded = false

    // Hover state (permission-free polling — no Accessibility needed)
    private var hoverTimer: Timer?
    private var collapseGrace: Timer?

    // MARK: lifecycle
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // UNUserNotificationCenter requires a real .app bundle. When launched as
        // a bare executable (e.g. ./TelegramSidebarWeb during dev/testing) the
        // process has no bundle proxy and current() throws — which would crash
        // the app at launch before the panel ever appears. Guard it so the
        // widget still runs (panel + webview); it just skips native alerts.
        if Bundle.main.bundleURL.pathExtension.lowercased() == "app" {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
            UNUserNotificationCenter.current().delegate = self
        }

        setupStatusItem()
        setupPanel()
        setupWebView()
        loadTelegram()
        startHoverPolling()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hoverTimer?.invalidate()
        collapseGrace?.invalidate()
    }

    // MARK: status bar
    private func setupStatusItem() {
        if let btn = statusItem.button {
            btn.title = "✈"
            btn.toolTip = "Telegram Sidebar"
            btn.target = self
            btn.action = #selector(togglePanel)
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Expand / Collapse", action: #selector(togglePanel), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Reload", action: #selector(reload), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func togglePanel() { setExpanded(!isExpanded) }
    @objc private func reload() { webView.reload() }
    @objc private func quit() { NSApplication.shared.terminate(nil) }

    // MARK: panel
    private func setupPanel() {
        let mainDisplay = CGMainDisplayID()
        let mainBounds = CGDisplayBounds(mainDisplay)
        let screenMaxX = CGFloat(mainBounds.maxX)
        let visMinY = CGFloat(mainBounds.minY)
        let visH = CGFloat(mainBounds.height)

        panel = SidebarPanel(contentRect: NSRect(x: screenMaxX - 40, y: visMinY, width: 40, height: visH),
                             styleMask: [.nonactivatingPanel, .borderless],
                             backing: .buffered,
                             defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Visible collapsed strip: a solid, slightly translucent dark bar with a
        // right-edge hairline border. Without this the 40px panel paints nothing
        // (clear bg + transparent webview) and the collapsed widget is invisible —
        // it looks broken even though it's on-screen and working.
        panel.backgroundColor = NSColor(srgbRed: 0.10, green: 0.11, blue: 0.13, alpha: 0.92)
        panel.isOpaque = true
        panel.hasShadow = true
        panel.acceptsMouseMovedEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.title = "Telegram"

        // Draw a visible airplane glyph + hairline border on the collapsed strip so
        // the widget is discoverable when not expanded.
        if let cview = panel.contentView {
            // Force the content view itself opaque-dark. NSWindow ignores
            // panel.backgroundColor when the .titled styleMask draws a themed
            // frame, so the only reliable way to make the collapsed strip visible
            // is a layer-backed content view with a solid background color.
            cview.wantsLayer = true
            cview.layer?.isOpaque = true
            cview.layer?.backgroundColor = NSColor(srgbRed: 0.10, green: 0.11, blue: 0.13, alpha: 1.0).cgColor

            let glyph = NSTextField(labelWithString: "✈")
            glyph.font = NSFont.systemFont(ofSize: 18)
            glyph.textColor = .white
            glyph.alignment = .center
            glyph.drawsBackground = false
            glyph.isBezeled = false
            glyph.isEditable = false
            glyph.frame = NSRect(x: 0, y: visH - 40, width: 40, height: 28)
            cview.addSubview(glyph)

            let border = NSView()
            border.wantsLayer = true
            border.layer?.backgroundColor = NSColor(srgbRed: 0.55, green: 0.58, blue: 0.62, alpha: 0.7).cgColor
            border.frame = NSRect(x: 0, y: 0, width: 1, height: visH)
            cview.addSubview(border)
        }

        // The hover loop already expands the panel, so a click gesture here is
        // redundant AND harmful: it sits on contentView and competes with the
        // WebView for mouse events, which is why clicks inside Telegram did
        // nothing. Clicks now fall through to the WebView directly.
        panel.orderFrontRegardless()
        try? "setupPanel frame=\(panel.frame)\n".write(toFile: "/tmp/tg_panel.log", atomically: true, encoding: .utf8)
    }

    // MARK: web view
    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(source: Self.bridgeJS, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        controller.addUserScript(WKUserScript(source: Self.scrollFixJS, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        controller.add(self, name: "tgBridge")
        config.userContentController = controller

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        // Managed explicitly during expand/collapse; autoresizing disabled so the
        // UI never squishes mid-animation (no "breakage on collapse").
        webView.autoresizingMask = []
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.masksToBounds = true
        panel.contentView?.addSubview(webView)

        // Telegram Web's "All Chats" list is a virtualized infinite-scroll
        // container that can refuse to scroll inside an embedded WKWebView when
        // the internal scroll view's elasticity/indicators aren't configured.
        // Force vertical scrolling on so the list actually moves.
        if let scrollView = (webView.subviews.compactMap { $0 as? NSScrollView }).first {
            scrollView.verticalScrollElasticity = .allowed
            scrollView.horizontalScrollElasticity = .none
            scrollView.hasVerticalScroller = true
            scrollView.scrollerStyle = .overlay
        }

        // Activate the app (and focus the WebView) on a real interaction inside the
        // panel — click OR scroll. Without this, the accessory app stays inactive
        // and the WebView never becomes first responder, so clicks/keystrokes are
        // swallowed and scroll doesn't reach Telegram. Hover alone does not activate
        // (that would steal focus on every edge brush); only a real click/scroll does.
        var lastScrollLog = Date.distantPast
        let activateInside: (NSEvent) -> NSEvent? = { [weak self] event in
            guard let self = self, self.isExpanded,
                  let win = self.webView.window,
                  self.panel.frame.contains(win.convertPoint(toScreen: event.locationInWindow)) else { return event }
            NSApp.activate(ignoringOtherApps: true)
            win.makeFirstResponder(self.webView)
            return event
        }
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .scrollWheel], handler: activateInside)
    }

    private func loadTelegram() {
        webView.load(URLRequest(url: URL(string: "https://web.telegram.org")!))
    }

    // MARK: expand/collapse
    fileprivate func setExpanded(_ expanded: Bool) {
        guard expanded != isExpanded else { return }
        isExpanded = expanded

        let mainDisplay = CGMainDisplayID()
        let mainBounds = CGDisplayBounds(mainDisplay)
        let screenMaxX = CGFloat(mainBounds.maxX)
        let visMinY = CGFloat(mainBounds.minY)
        let visH = CGFloat(mainBounds.height)
        let w: CGFloat = expanded ? 380 : 40
        let r = NSRect(x: screenMaxX - w, y: visMinY, width: w, height: visH)

        // Keep the webView at full internal width so it slides in/out (clipped by
        // the panel's contentView) instead of being squished. Crucially, do NOT
        // hide it at the start of a collapse — keep the Telegram content visible
        // while the panel slides away and only hide it once fully collapsed, so the
        // airplane glyph shows on the 40px strip. Hiding up front made the collapse
        // read as an abrupt one-frame snap.
        webView.frame = NSRect(x: 0, y: 0, width: 380, height: visH)
        if expanded {
            webView.isHidden = false
            webView.alphaValue = 0   // fade in as it slides open
        } else {
            webView.alphaValue = 1   // fade out as it slides away
        }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.32
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(r, display: true)
            // Fade the content in the same arc so expand and collapse feel consistent.
            webView.animator().alphaValue = expanded ? 1 : 0
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            if expanded {
                self.panel.makeKey()
                self.webView.window?.makeFirstResponder(self.webView)
            } else {
                // Fully collapsed: hide and reset opacity so the next expand fades in.
                self.webView.isHidden = true
                self.webView.alphaValue = 1
            }
        })

        try? "setExpanded expanded=\(expanded) frame=\(panel.frame)\n".write(toFile: "/tmp/tg_panel.log", atomically: true, encoding: .utf8)
    }

    // MARK: hover polling (no Accessibility permission required)
    private func startHoverPolling() {
        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.pollHover()
        }
        try? "[hover] polling started\n".write(toFile: "/tmp/tg_panel.log", atomically: true, encoding: .utf8)
    }

    private func pollHover() {
        let mouse = NSEvent.mouseLocation
        let mainDisplay = CGMainDisplayID()
        let mainBounds = CGDisplayBounds(mainDisplay)
        let screenMaxX = CGFloat(mainBounds.maxX)
        let panelFrame = panel.frame

        let insidePanel = mouse.x >= panelFrame.minX && mouse.x <= panelFrame.maxX &&
                          mouse.y >= panelFrame.minY && mouse.y <= panelFrame.maxY
        let nearRightEdge = mouse.x >= (screenMaxX - 70)

        if insidePanel || nearRightEdge {
            // Mouse is on/near the panel → keep it open (cancel any pending collapse).
            collapseGrace?.invalidate()
            collapseGrace = nil
            if !isExpanded { setExpanded(true) }
        } else if isExpanded {
            // Mouse is well away → start/keep a short grace timer before collapsing.
            if collapseGrace == nil {
                collapseGrace = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
                    self?.collapseGrace = nil
                    // Re-check: only collapse if still away.
                    let m = NSEvent.mouseLocation
                    let pf = self?.panel.frame ?? .zero
                    let isInside = m.x >= pf.minX && m.x <= pf.maxX && m.y >= pf.minY && m.y <= pf.maxY
                    let near = m.x >= (screenMaxX - 70)
                    if isInside || near { return }
                    self?.setExpanded(false)
                }
            }
        }
    }

    // MARK: WKNavigationDelegate
    func webView(_ webView: WKWebView, didFinish nav: WKNavigation!) {
        webView.evaluateJavaScript(Self.titleJS, completionHandler: nil)
    }

    func webView(_ webView: WKWebView, didFail nav: WKNavigation!, withError error: Error) {
        try? "[fail] code=\((error as NSError).code) \(error.localizedDescription)\n".write(toFile: "/tmp/tg_web_console.log", atomically: true, encoding: .utf8)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation nav: WKNavigation!, withError error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        try? "[prov-fail] code=\((error as NSError).code) \(error.localizedDescription)\n".write(toFile: "/tmp/tg_web_console.log", atomically: true, encoding: .utf8)
    }

    private static let titleJS = """
    (function () {
      try {
        var handler = window.webkit.messageHandlers.tgBridge;
        if (!handler) return;
        handler.postMessage({ type: 'title', title: document.title || '' });
      } catch (e) {}
    })();
    """

    // MARK: WKScriptMessageHandler
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        switch body["type"] as? String {
        case "title":
            if let t = body["title"] as? String { updateBadge(from: t) }
        case "notification":
            let title = body["title"] as? String ?? "Telegram"
            let bodyText = body["body"] as? String ?? ""
            postNativeNotification(title: title, body: bodyText)
        default:
            break
        }
    }

    private func updateBadge(from title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        var count = 0
        if let range = trimmed.range(of: #"^\((\d+)\)"#, options: .regularExpression),
           let n = Int(trimmed[range].dropFirst().dropLast()) { count = n }
        statusItem.button?.title = count > 0 ? "✈(\(count > 99 ? "99+" : "\(count)"))" : "✈"
    }

    private func postNativeNotification(title: String, body: String) {
        guard Bundle.main.bundleURL.pathExtension.lowercased() == "app" else { return }
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    // JS bridge
    private static let bridgeJS = """
    (function () {
      try {
        var handler = window.webkit.messageHandlers.tgBridge;
        if (!handler) return;
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
    })();
    """

    // Force Telegram Web's chat-list scroller to use NATIVE scrolling. Telegram
    // renders the "All Chats" list in a div (class "...scrollable-y chatlist-parts
    // folders-scrollable") set to overflow:hidden and drives scrolling with its own
    // JS virtualized scroller, which doesn't move inside an embedded WKWebView — so
    // the list is frozen. Overriding it to overflow-y:auto with !important restores
    // native wheel/trackpad scrolling. Re-runs on a timer + MutationObserver because
    // Telegram rebuilds the list on navigation/tab switches.
    private static let scrollFixJS = """
    (function () {
      try {
        function fix() {
          var all = document.querySelectorAll('div.scrollable-y, div.chatlist-parts, div.folders-scrollable');
          all.forEach(function (el) {
            el.style.setProperty('overflow-y', 'auto', 'important');
            el.style.setProperty('-webkit-overflow-scrolling', 'touch', 'important');
            el.style.setProperty('overscroll-behavior', 'auto', 'important');
          });
        }
        fix();
        setInterval(fix, 1000);
        if (window.MutationObserver) {
          var obs = new MutationObserver(function () { fix(); });
          obs.observe(document.body, { childList: true, subtree: true });
        }
      } catch (e) {}
    })();
    """
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completion: @escaping (UNNotificationPresentationOptions) -> Void) {
        completion([.banner, .sound])
    }
}
