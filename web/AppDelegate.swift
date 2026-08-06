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
    private var railView: NSView!
    private var logoView: NSImageView?
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var isExpanded = false

    // Hover state (permission-free polling — no Accessibility needed)
    private var hoverTimer: Timer?
    private var collapseGrace: Timer?

    // MARK: lifecycle
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // UNUserNotificationCenter.current() aborts the process (uncatchable
        // assertion: "bundleProxyForCurrentProcess is nil") when the app is
        // launched in a context where the bundle proxy can't be resolved — e.g.
        // as a bare executable, OR a .app launched by a non-LaunchServices parent
        // (Hermes/terminal) leaving the process orphaned. The panel must appear
        // regardless, so we only touch notifications when the bundle identifier is
        // actually resolvable, and we defer the call out of the launch backtrace.
        if Self.canUseNotifications {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
                UNUserNotificationCenter.current().delegate = self
            }
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
        // Panel background is WHITE so it matches Telegram's light theme (the
        // reference screenshot shows a white/mint UI). This is only the fallback
        // shown for a frame during the expand animation or a reload gap — the
        // WebView paints Telegram's own light content on top. The brand-blue is
        // confined to a separate 40px `railView` that is hidden whenever the panel
        // is wide, so an expanded panel can never show blue.
        panel.backgroundColor = NSColor.white
        panel.isOpaque = true
        panel.hasShadow = true
        panel.acceptsMouseMovedEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.title = "Telegram"

        // A 40px-wide rail pinned to the LEFT edge of the panel. It is Telegram
        // brand blue (#3390EC) with a white Telegram paper-plane logo at the top.
        // It is removed from the view hierarchy the moment the panel expands, so an
        // expanded panel never shows the rail.
        let brandBlue = NSColor(srgbRed: 0.2, green: 0.565, blue: 0.925, alpha: 1.0) // #3390EC
        railView = NSView()
        railView.wantsLayer = true
        railView.layer?.isOpaque = true
        railView.layer?.backgroundColor = brandBlue.cgColor
        railView.frame = NSRect(x: 0, y: 0, width: 40, height: visH)
        panel.contentView?.addSubview(railView)

        // White Telegram logo at the top of the rail (clean, no doodle/avatar).
        setupRailChrome()

        // The hover loop already expands the panel, so a click gesture here is
        // redundant AND harmful: it sits on contentView and competes with the
        // WebView for mouse events, which is why clicks inside Telegram did
        // nothing. Clicks now fall through to the WebView directly.
        panel.orderFrontRegardless()
        try? "setupPanel frame=\(panel.frame)\n".write(toFile: "/tmp/tg_panel.log", atomically: true, encoding: .utf8)
    }

    // MARK: web view
    private func setupWebView() {
        let visH = CGFloat(CGDisplayBounds(CGMainDisplayID()).height)
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(source: Self.pingJS, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        controller.addUserScript(WKUserScript(source: Self.bridgeJS, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        controller.addUserScript(WKUserScript(source: Self.scrollFixJS, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        controller.add(self, name: "tgBridge")
        config.userContentController = controller

        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 380, height: visH), configuration: config)
        webView.navigationDelegate = self
        // Opaque backing: paint Telegram's own content (its dark CSS sets the
        // page background) instead of relying on a transparent WebView compositing
        // over the panel. In a borderless .nonactivatingPanel the transparent path
        // can silently fail to paint, leaving a dark-but-blank panel. Opaque always
        // shows content; the collapsed state still hides the WebView to reveal the
        // blue rail, so opacity here doesn't affect the collapsed look.
        webView.setValue(true, forKey: "drawsBackground")
        webView.wantsLayer = true
        webView.layer?.isOpaque = true
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
        // The blue rail is ONLY visible while collapsed. As soon as we expand,
        // remove it from the view entirely so no blue can show across a wide panel.
        railView.isHidden = expanded
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
            // Re-read the LIVE state: a rapid hover in/out can schedule a collapse
            // completion that fires AFTER the panel has re-expanded. If we're now
            // expanded, leave the WebView visible. Only hide it when truly collapsed.
            if self.isExpanded {
                self.panel.makeKey()
                self.webView.window?.makeFirstResponder(self.webView)
            } else {
                // Fully collapsed: hide and reset opacity so the next expand fades in.
                self.webView.isHidden = true
                self.webView.alphaValue = 1
                self.railView.isHidden = false
                // Rail is solid brand blue with a static logo — nothing to repaint.
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

        // Diagnostics: continuously log the WebView's REAL on-screen state so we
        // can tell whether "blue when expanded" is a visibility bug (alpha/hidden)
        // or a render bug (loaded but blank).
        var probeTick = 0
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let line = "STATE isExpanded=\(self.isExpanded) hidden=\(self.webView.isHidden) alpha=\(String(format: "%.2f", self.webView.alphaValue)) frame=\(self.webView.frame) inWindow=\(self.webView.window != nil) url=\(self.webView.url?.absoluteString ?? "")\n"
            try? line.write(toFile: "/tmp/tg_state.log", atomically: true, encoding: .utf8)
            probeTick += 1
            if probeTick % 5 == 0 {
                self.webView.evaluateJavaScript(Self.domProbeJS) { res, err in
                    let out = err != nil ? "[probe] error=\(err!.localizedDescription)" : "[probe] \(res ?? "nil")"
                    try? out.appendLine(to: "/tmp/tg_web_console.log")
                }
            }
        }
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
        try? "[load] didFinish url=\(webView.url?.absoluteString ?? "")\n".write(toFile: "/tmp/tg_web_console.log", atomically: true, encoding: .utf8)
        webView.evaluateJavaScript(Self.titleJS, completionHandler: nil)
        // Inject the theme/wallpaper/avatar bridge via evaluateJavaScript — the same
        // path titleJS uses and that works reliably (user-script injection was
        // silently refused by WKWebView for this large script).
        webView.evaluateJavaScript(Self.bridgeJS, completionHandler: nil)
        // On-demand DOM probe (native-controlled timing; avoids fragile user-script
        // intervals that die when Telegram's SPA navigates). Reports whether real
        // Telegram content is in the DOM.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            webView.evaluateJavaScript(Self.domProbeJS) { res, err in
                if let e = err {
                    try? "[probe] error=\(e.localizedDescription)\n".appendLine(to: "/tmp/tg_web_console.log")
                    return
                }
                let desc = "\(res ?? "nil")"
                try? "[probe] \(desc)\n".appendLine(to: "/tmp/tg_web_console.log")
            }
        }
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

    // On-demand DOM probe: returns a plain snapshot of whether Telegram's SPA
    // actually mounted content. Called via evaluateJavaScript from didFinish so
    // timing is native-controlled (user-script intervals die on SPA navigation).
    private static let domProbeJS = """
    (function () {
      try {
        var d = document;
        var b = d.body;
        return {
          ready: d.readyState,
          kids: b ? b.childElementCount : -1,
          len: (b && b.innerHTML || '').length,
          login: !!(d.querySelector('form.auth-form') || d.querySelector('.auth') || d.querySelector('.login-form')),
          chatList: !!(d.querySelector('.chatlist') || d.querySelector('.chatlist-parts') || d.querySelector('#column-left')),
          colCenter: !!(d.querySelector('#column-center') || d.querySelector('.column-center')),
          sH: b ? b.scrollHeight : 0,
          cH: b ? b.clientHeight : 0
        };
      } catch (e) { return { error: String(e) }; }
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
        case "domstate":
            break
        default:
            break
        }
    }

    private func setupRailChrome() {
        // Solid brand-blue rail with the official Telegram logo (blue disc + white
        // paper-plane) at the top. Static (no web dependency).
        guard let rv = railView else { return }
        rv.layer?.backgroundColor = NSColor(srgbRed: 0.2, green: 0.565, blue: 0.925, alpha: 1.0).cgColor

        // Load the official Logo.png from beside the executable (Bundle resource
        // lookup was unreliable here; an explicit file path next to the binary works).
        let fm = FileManager.default
        var url: URL?
        if let ex = Bundle.main.executableURL {
            let cand = ex.deletingLastPathComponent().appendingPathComponent("Logo.png")
            if fm.fileExists(atPath: cand.path) { url = cand }
        }
        guard let u = url, let img = NSImage(contentsOf: u) else { return }

        // Blue disc with white plane, centered at the top of the 40px rail.
        let logo = NSImageView(frame: NSRect(x: 4, y: rv.bounds.height - 36, width: 32, height: 32))
        logo.image = img
        logo.imageScaling = .scaleProportionallyUpOrDown
        logo.wantsLayer = true
        logo.layer?.opacity = 1
        rv.addSubview(logo)
        logoView = logo
    }

    private func updateBadge(from title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        var count = 0
        if let range = trimmed.range(of: #"^\((\d+)\)"#, options: .regularExpression),
           let n = Int(trimmed[range].dropFirst().dropLast()) { count = n }
        statusItem.button?.title = count > 0 ? "✈(\(count > 99 ? "99+" : "\(count)"))" : "✈"
    }

    private func postNativeNotification(title: String, body: String) {
        guard Self.canUseNotifications else { return }
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    // True only when the running process has a resolvable bundle proxy — i.e. a
    // real .app whose bundleIdentifier was successfully looked up. UNUserNotification
    // Center.current() aborts the process when this is false, so it's the single
    // gate for every notification-center call.
    private static var canUseNotifications: Bool {
        let b = Bundle.main
        return b.bundleURL.pathExtension.lowercased() == "app" && b.bundleIdentifier != nil
    }

    // JS bridge
    private static let pingJS = """
    (function () {
      try {
        var h = window.webkit.messageHandlers.tgBridge;
        (h || { postMessage: function(){} }).postMessage({ type: 'ping', ready: !!h });
      } catch (e) {}
    })();
    """

    private static let bridgeJS = """
    (function () {
      // web.telegram.org / WKWebView can briefly NOT have the bridge handler ready
      // at .atDocumentEnd, so a naive `if (!handler) return` kills the whole script
      // (which is why the wallpaper + avatar code never ran). Poll until it exists,
      // then run exactly once.
      function start() {
        var handler = window.webkit.messageHandlers.tgBridge;
        if (!handler) { setTimeout(start, 100); return; }
        try {
        handler.postMessage({ type: 'boot', ok: true });
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
        // Match the official Telegram LIGHT theme (as shown in the reference: white
        // header, light surfaces, #3390EC blue accents). The chat wallpaper (the
        // sage-green pattern in the reference) is synced from the user's account, so
        // we only need to pin the light palette + color-scheme. Without this pin,
        // web.telegram.org can fall back to the account's night theme and render
        // dark — which looked wrong against the rest of the (light) Telegram UI.
        (function () {
          try {
            var css = [
              '/* Keep Telegram in its LIGHT palette (prevents dark-theme fallback).',
              '   Do NOT override the chat background — the open conversation uses',
              '   your synced "Doodles" wallpaper (mint-green doodle pattern). Only',
              '   the chat LIST (All Chats) is forced white so it reads cleanly in',
              '   the thin panel. */',
              'html { color-scheme: light !important; }',
              '/* Chat LIST (All Chats) — solid white. */',
              '#column-left, .column-left,',
              '.chatlist-parts, .folders-scrollable { background-color: #ffffff !important; }',
              ':root {',
              '  --chatlist-background: #ffffff !important;',
              '  --primary-color: #3390ec !important;',
              '  --active-color: #3390ec !important;',
              '  --text-color: #000000 !important;',
              '  --secondary-text-color: #707991 !important;',
              '}'
            ].join(' ');
            function apply() {
              var id = 'tg-light-theme';
              var el = document.getElementById(id);
              if (!el) {
                el = document.createElement('style');
                el.id = id;
                (document.head || document.documentElement).appendChild(el);
              }
              el.textContent = css;
              // Light theme applied. The collapsed rail is a static brand-blue strip
              // with the Telegram logo (drawn in Swift), so nothing else to do here.
            }
            apply();   // apply immediately, then keep it applied
            setInterval(apply, 2000);
            if (window.MutationObserver) {
              // Observe <body> (NOT documentElement). apply() writes into <head>, so
              // watching body avoids an infinite mutation storm: our own style write
              // would otherwise retrigger the observer forever, pegging the
              // WebContent process and freezing the page (blank panel, no JS).
              new MutationObserver(apply).observe(document.body, { childList: true, subtree: true });
            }
          } catch (e) {
          }
        })();
      } catch (e) {}
      }
      start();
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

private extension String {
    func appendLine(to path: String) {
        if let fh = FileHandle(forWritingAtPath: path) {
            fh.seekToEndOfFile()
            fh.write(Data((self + "\n").utf8))
            fh.closeFile()
        } else {
            try? (self + "\n").write(toFile: path, atomically: true, encoding: .utf8)
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completion: @escaping (UNNotificationPresentationOptions) -> Void) {
        completion([.banner, .sound])
    }
}
