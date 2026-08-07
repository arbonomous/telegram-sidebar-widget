import Cocoa
import WebKit
import UserNotifications

// Lets a .nonactivatingPanel become key, so the WKWebView receives keyboard input
// (typing in the message box) without stealing activation from the app you're using.
final class SidebarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate,
                          WKScriptMessageHandler, WKNavigationDelegate {

    static let shared = AppDelegate()

    // Deterministic WebView data store (UUID-based). Using a fixed identifier —
    // instead of the default per-bundle-id store — keeps the Telegram login
    // session intact across app renames and reinstalls. See migrateLegacySessionIfNeeded().
    private static let sessionStoreID = UUID(uuidString: "6F3A2B9C-1D4E-4F8A-9B7C-2E5D8A1C0F33")!

    // Single-instance guard. Keyed to a fixed product lock path (not the bundle
    // name) so it holds across renames/rebuilds — only one interactive SidePiece
    // may dock to the edge at a time. Diagnostic modes (--selftest/--capture) are
    // exempt so the test harness can run in parallel. The lock fd is kept open
    // for the process lifetime (never closed) so the advisory lock holds.
    private struct SingleInstanceLock {
        static let lockPath = NSHomeDirectory() + "/Library/Application Support/SidePiece/.running"
        static var lockFD: Int32 = -1
        static func isAlreadyRunning() -> Bool {
            let fd = open(lockPath, O_RDONLY)
            guard fd != -1 else { return false }
            defer { close(fd) }
            var lock = flock(l_start: 0, l_len: 0, l_pid: 0, l_type: Int16(F_WRLCK), l_whence: 0)
            return fcntl(fd, F_GETLK, &lock) != -1 && lock.l_type != Int16(F_UNLCK)
        }
        static func acquire() {
            try? FileManager.default.createDirectory(atPath: (lockPath as NSString).deletingLastPathComponent,
                                                     withIntermediateDirectories: true)
            lockFD = open(lockPath, O_WRONLY | O_CREAT, 0o644)
            if lockFD != -1 {
                var lock = flock(l_start: 0, l_len: 0, l_pid: 0, l_type: Int16(F_WRLCK), l_whence: 0)
                _ = fcntl(lockFD, F_SETLK, &lock)   // held until process exit (fd stays open)
            }
        }
    }

    private var panel: SidebarPanel!
    private var webView: WKWebView!
    private var railView: NSView!
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var isExpanded = false
    private var hoverTimer: Timer?
    private var collapseGrace: Timer?
    private var closeButton: NSButton!
    private var dismissedUntilLeave = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Single-instance guard: only one interactive SidePiece may run and dock
        // to the edge. Diagnostic modes (--selftest) are exempt so the test
        // harness can run alongside the real app and across rebuilds.
        let isDiagnostics = CommandLine.arguments.contains("--selftest")
        if !isDiagnostics && SingleInstanceLock.isAlreadyRunning() {
            NSApplication.shared.terminate(nil)
            return
        }
        if !isDiagnostics { SingleInstanceLock.acquire() }
        NSApp.setActivationPolicy(.accessory)
        if Self.canUseNotifications {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
                UNUserNotificationCenter.current().delegate = self
            }
        }
        setupStatusItem()
        setupPanel()
        setupWebView()
        webView.load(URLRequest(url: URL(string: "https://web.telegram.org/k")!))
        // --selftest: after load settles, render the WebView and prove it isn't
        // blank, then quit. Otherwise, start hover polling.
        if CommandLine.arguments.contains("--selftest") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.runSelfTest() }
        } else {
            startHoverPolling()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hoverTimer?.invalidate()
        collapseGrace?.invalidate()
    }

    // MARK: status bar
    private func setupStatusItem() {
        if let btn = statusItem.button {
            btn.title = "✈"
            btn.toolTip = "SidePiece"
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
    @objc private func collapseAndDismiss() {
        setExpanded(false)
        dismissedUntilLeave = true
    }

    // MARK: panel + collapsed rail
    private func setupPanel() {
        let mainBounds = CGDisplayBounds(CGMainDisplayID())
        let visH = CGFloat(mainBounds.height)
        let screenMaxX = CGFloat(mainBounds.maxX)
        let visMinY = CGFloat(mainBounds.minY)

        panel = SidebarPanel(contentRect: NSRect(x: screenMaxX - 40, y: visMinY, width: 40, height: visH),
                             styleMask: [.nonactivatingPanel, .borderless],
                             backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .white
        panel.isOpaque = true
        panel.hasShadow = true
        panel.acceptsMouseMovedEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.title = "Telegram"
        panel.orderFrontRegardless()

        // 40px collapsed rail: brand blue with the official Telegram logo at top.
        let brandBlue = NSColor(srgbRed: 0.2, green: 0.565, blue: 0.925, alpha: 1.0)
        railView = NSView()
        railView.wantsLayer = true
        railView.layer?.isOpaque = true
        railView.layer?.backgroundColor = brandBlue.cgColor
        railView.frame = NSRect(x: 0, y: 0, width: 40, height: visH)
        panel.contentView?.addSubview(railView)
        setupRailChrome()

        // One-shot diagnostic (not a poll loop): confirm the panel is on-screen.
        try? "panel docked at x=\(Int(panel.frame.minX)) width=\(Int(panel.frame.width)) hidden=\(panel.isVisible ? "visible" : "hidden")\n"
            .write(toFile: "/tmp/tg_panel.log", atomically: true, encoding: .utf8)
    }

    private func setupRailChrome() {
        guard let rv = railView else { return }
        let fm = FileManager.default
        var url: URL?
        if let ex = Bundle.main.executableURL {
            let cand = ex.deletingLastPathComponent().appendingPathComponent("Logo.png")
            if fm.fileExists(atPath: cand.path) { url = cand }
        }
        guard let u = url, let img = NSImage(contentsOf: u) else { return }
        let logo = NSImageView(frame: NSRect(x: 4, y: rv.bounds.height - 36, width: 32, height: 32))
        logo.image = img
        logo.imageScaling = .scaleProportionallyUpOrDown
        rv.addSubview(logo)
    }

    // MARK: web view
    private func setupWebView() {
        let visH = CGFloat(CGDisplayBounds(CGMainDisplayID()).height)
        migrateLegacySessionIfNeeded()
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: Self.sessionStoreID)
        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(source: Self.bridgeJS, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        controller.addUserScript(WKUserScript(source: Self.scrollFixJS, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        controller.add(self, name: "tgBridge")
        config.userContentController = controller

        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 380, height: visH), configuration: config)
        webView.navigationDelegate = self
        webView.setValue(true, forKey: "drawsBackground")
        webView.wantsLayer = true
        webView.layer?.isOpaque = true
        webView.autoresizingMask = []
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.masksToBounds = true
        panel.contentView?.addSubview(webView)

        // Close (✕) button pinned top-right of the expanded panel. Gives the user
        // a real "close" target instead of fighting the hover-expand. Clicking it
        // collapses AND sets dismissedUntilLeave, so it won't spring back open
        // while the cursor is still in the edge zone (the "I clicked X but it
        // re-expands" trap). The lock releases once the cursor leaves the edge.
        let cb = NSButton(frame: NSRect(x: 380 - 30, y: visH - 30, width: 24, height: 24))
        cb.title = "✕"
        cb.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        cb.isBordered = false
        cb.wantsLayer = true
        cb.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.30).cgColor
        cb.layer?.cornerRadius = 6
        cb.contentTintColor = .white
        cb.target = self
        cb.action = #selector(collapseAndDismiss)
        cb.toolTip = "Close (collapse panel)"
        cb.isHidden = true
        panel.contentView?.addSubview(cb)
        closeButton = cb

        // Telegram Web's "All Chats" list is a virtualized scroller that can refuse
        // to scroll inside an embedded WKWebView; force vertical scrolling on.
        if let scrollView = (webView.subviews.compactMap { $0 as? NSScrollView }).first {
            scrollView.verticalScrollElasticity = .allowed
            scrollView.horizontalScrollElasticity = .none
            scrollView.hasVerticalScroller = true
            scrollView.scrollerStyle = .overlay
        }

        // Activate the app (focus the WebView) on a real click/scroll inside the
        // panel — not on hover, which would steal focus on every edge brush.
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

    // One-time migration: the session used to live in the per-bundle-id WebKit
    // store, which moved when the app was renamed (TelegramSidebarWeb ->
    // SidePiece) and got orphaned — forcing a re-login every rebuild/rename.
    // Move that data into the deterministic store (sessionStoreID) so the login
    // survives renames/reinstalls. Idempotent: only runs when needed.
    private func migrateLegacySessionIfNeeded() {
        let fm = FileManager.default
        let webkitDir = NSHomeDirectory() + "/Library/WebKit"
        let candidates = ["TelegramSidebarWeb", "com.user.telegram-sidebar-web"]
        let destRoot = webkitDir + "/\(Self.sessionStoreID.uuidString)"
        let destData = destRoot + "/WebsiteData"
        // The deterministic store dir doesn't exist yet (it's created lazily when
        // the WKWebView is instantiated below), so we can move the whole folder.
        guard !fm.fileExists(atPath: destData) else { return }
        for name in candidates where name != Self.sessionStoreID.uuidString {
            let src = webkitDir + "/" + name + "/WebsiteData"
            guard fm.fileExists(atPath: src) else { continue }
            try? fm.createDirectory(atPath: destRoot, withIntermediateDirectories: true)
            try? fm.moveItem(atPath: src, toPath: destData)
            // Drop the now-empty orphaned store dir.
            try? fm.removeItem(atPath: webkitDir + "/" + name)
            break
        }
    }

    // MARK: expand / collapse
    fileprivate func setExpanded(_ expanded: Bool) {
        guard expanded != isExpanded else { return }
        isExpanded = expanded

        let mainBounds = CGDisplayBounds(CGMainDisplayID())
        let visH = CGFloat(mainBounds.height)
        let visMinY = CGFloat(mainBounds.minY)
        let screenMaxX = CGFloat(mainBounds.maxX)
        let w: CGFloat = expanded ? 380 : 40
        let r = NSRect(x: screenMaxX - w, y: visMinY, width: w, height: visH)

        webView.frame = NSRect(x: 0, y: 0, width: 380, height: visH)
        railView.isHidden = expanded
        closeButton?.isHidden = !expanded
        if expanded { webView.isHidden = false }   // always reveal on expand (collapse hides it)
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
            } else {
                self.webView.isHidden = true
                self.webView.alphaValue = 1
                self.railView.isHidden = false
            }
        })
    }

    // MARK: hover polling (no Accessibility permission required)
    private func startHoverPolling() {
        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.pollHover()
        }
    }

    private func pollHover() {
        let mouse = NSEvent.mouseLocation
        let mainBounds = CGDisplayBounds(CGMainDisplayID())
        let screenMaxX = CGFloat(mainBounds.maxX)
        let pf = panel.frame
        // Expand ONLY when the cursor is actually over our own panel — the 40px
        // collapsed rail, or the (already) expanded panel. No preemptive buffer to
        // the left: that buffer used to spring the panel open when the user moved
        // toward another window's close button near the right edge, blocking it.
        let inside = mouse.x >= pf.minX && mouse.x <= pf.maxX && mouse.y >= pf.minY && mouse.y <= pf.maxY
        let inActiveZone = inside

        // Once the cursor fully leaves our panel, release the dismiss lock so normal
        // hover-to-expand resumes on the next approach to the rail.
        if !inActiveZone { dismissedUntilLeave = false }

        if inActiveZone && !dismissedUntilLeave {
            collapseGrace?.invalidate()
            collapseGrace = nil
            if !isExpanded { setExpanded(true) }
        } else if isExpanded && !inside {
            if collapseGrace == nil {
                collapseGrace = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
                    self?.collapseGrace = nil
                    let m = NSEvent.mouseLocation
                    let f = self?.panel.frame ?? .zero
                    let stillInside = m.x >= f.minX && m.x <= f.maxX && m.y >= f.minY && m.y <= f.maxY
                    if !stillInside { self?.setExpanded(false) }
                }
            }
        }
    }

    // MARK: navigation
    func webView(_ webView: WKWebView, didFinish nav: WKNavigation!) {
        // Re-inject the bridge (large user-script can be silently skipped at docEnd),
        // which pins the light theme and forwards notifications + unread count.
        webView.evaluateJavaScript(Self.bridgeJS, completionHandler: nil)
    }

    // --selftest: force-expand, capture the rendered panel, and report whether it
    // actually rendered Telegram (not a blank/white panel). Writes
    // /tmp/tg_selftest.json and terminates. Triggered from launch (not didFinish)
    // so it doesn't depend on the navigation callback firing.
    private var selfTestDone = false
    private func runSelfTest() {
        setExpanded(true)
        // Poll the rendered pixels for up to ~30s. Telegram Web can take a while
        // to mount on a cold load, so we retry instead of failing on the first
        // (possibly still-blank) frame. Only report blank if it stays blank.
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
            if !blank || attempts >= 14 {
                self.reportSelfTest(blank: blank, colors: colors,
                                     reason: blank ? "blank/white render" : "rendered \(colors) color buckets")
            } else {
                attempts += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { poll() }
            }
        }
        // Watchdog: never hang — if polling never settles, report failure.
        Timer.scheduledTimer(withTimeInterval: 35, repeats: false) { [weak self] _ in
            self?.reportSelfTest(blank: true, colors: 0, reason: "watchdog timeout")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { poll() }
    }

    private func reportSelfTest(blank: Bool, colors: Int, reason: String) {
        guard !selfTestDone else { return }
        selfTestDone = true
        let json = "{\"ok\":\(!blank),\"reason\":\"\(reason)\",\"colors\":\(colors)}\n"
        try? json.write(toFile: "/tmp/tg_selftest.json", atomically: true, encoding: .utf8)
        NSApplication.shared.terminate(nil)
    }

    // Sample the bitmap; a blank/white panel yields ~1 color bucket, Telegram many.
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

    // MARK: script messages
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }
        switch type {
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
        if let range = trimmed.range(of: #"^\(\d+\)"#, options: .regularExpression),
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

    private static var canUseNotifications: Bool {
        let b = Bundle.main
        return b.bundleURL.pathExtension.lowercased() == "app" && b.bundleIdentifier != nil
    }

    // MARK: injected JS
    // Pins Telegram's LIGHT palette (the chat list is forced white; the open
    // conversation keeps your synced wallpaper) and patches window.Notification so
    // incoming messages surface as native macOS notifications + unread badge.
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
          var css = [
            'html { color-scheme: light !important; }',
            '#column-left, .column-left, .chatlist-parts, .folders-scrollable { background-color: #ffffff !important; }',
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
          }
          apply();
          setInterval(apply, 2000);
          if (window.MutationObserver) {
            new MutationObserver(apply).observe(document.body, { childList: true, subtree: true });
          }
        } catch (e) {}
      }
      start();
    })();
    """

    // Forces Telegram's "All Chats" scroller to use native scrolling (its JS
    // virtualized scroller is frozen inside an embedded WKWebView).
    private static let scrollFixJS = """
    (function () {
      try {
        function fix() {
          document.querySelectorAll('div.scrollable-y, div.chatlist-parts, div.folders-scrollable')
            .forEach(function (el) {
              el.style.setProperty('overflow-y', 'auto', 'important');
              el.style.setProperty('-webkit-overflow-scrolling', 'touch', 'important');
              el.style.setProperty('overscroll-behavior', 'auto', 'important');
            });
        }
        fix();
        setInterval(fix, 1000);
        if (window.MutationObserver) {
          new MutationObserver(function () { fix(); }).observe(document.body, { childList: true, subtree: true });
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
