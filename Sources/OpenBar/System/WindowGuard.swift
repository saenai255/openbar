import AppKit
import ApplicationServices

/// Keeps windows from sliding under the bar,
/// since macOS has no API for reserving screen space.
final class WindowGuard {
    static let shared = WindowGuard()

    /// Bar rects in AX (top-left origin) coordinates paired with their screen frames.
    private var reservations: [(bar: CGRect, screen: CGRect, edge: BarPosition)] = []
    private var observers: [pid_t: AXObserver] = [:]
    private var pending: [CFHashCode: DispatchWorkItem] = [:]
    private var wanted = false
    private var trustTimer: Timer?
    private var enabled: Bool { wanted && AX.isTrusted }

    private init() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.syncObservers() }
        }
        nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.removeObserver(app.processIdentifier)
        }
    }

    func update(bars: [(frame: NSRect, screen: NSScreen)], edge: BarPosition, enabled: Bool) {
        wanted = enabled
        reservations = bars.map { ($0.frame.flippedToScreenSpace, $0.screen.frame.flippedToScreenSpace, edge) }
        trustTimer?.invalidate()
        trustTimer = nil
        if self.enabled {
            syncObservers()
            sweep()
        } else {
            for pid in observers.keys { removeObserver(pid) }
            if wanted { waitForTrust() }
        }
    }

    /// Accessibility is usually granted after launch; start guarding once it is.
    private func waitForTrust() {
        trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard let self, AX.isTrusted else { return }
            timer.invalidate()
            self.trustTimer = nil
            self.syncObservers()
            self.sweep()
        }
    }

    private func syncObservers() {
        guard enabled else { return }
        let me = ProcessInfo.processInfo.processIdentifier
        for app in NSWorkspace.shared.runningApplications
            where app.activationPolicy == .regular && app.processIdentifier != me && observers[app.processIdentifier] == nil {
            addObserver(app.processIdentifier)
        }
    }

    private func addObserver(_ pid: pid_t) {
        let callback: AXObserverCallback = { _, element, _, _ in
            WindowGuard.shared.schedule(element)
        }
        var observer: AXObserver?
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }
        let app = AX.application(pid)
        AXObserverAddNotification(observer, app, kAXWindowCreatedNotification as CFString, nil)
        AXObserverAddNotification(observer, app, kAXWindowResizedNotification as CFString, nil)
        AXObserverAddNotification(observer, app, kAXWindowMovedNotification as CFString, nil)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        observers[pid] = observer
    }

    private func removeObserver(_ pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }

    private func sweep() {
        for pid in observers.keys {
            for window in WindowList.windows(of: pid) where !window.isMinimized { adjust(window.element) }
        }
    }

    /// Debounced and deferred until mouse-up so drags and live resizes are not fought.
    private func schedule(_ element: AXUIElement) {
        let key = CFHash(element)
        pending[key]?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pending[key] = nil
            if NSEvent.pressedMouseButtons != 0 { return self.schedule(element) }
            self.adjust(element)
        }
        pending[key] = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: task)
    }

    private func adjust(_ element: AXUIElement) {
        guard enabled else { return }
        let subrole: String? = AX.attribute(element, kAXSubroleAttribute)
        guard subrole == kAXStandardWindowSubrole,
              (AX.attribute(element, "AXFullScreen") as Bool?) != true,
              let frame = AX.frame(element) else { return }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        guard let r = reservations.first(where: { $0.screen.contains(center) }), frame.intersects(r.bar) else { return }

        let menuBar = (NSScreen.screens.first { $0.frame.flippedToScreenSpace == r.screen })
            .map { $0.frame.maxY - $0.visibleFrame.maxY } ?? 0
        var usable = r.screen
        usable.origin.y += menuBar
        usable.size.height -= menuBar

        var f = frame
        switch r.edge {
        case .bottom:
            usable.size.height = r.bar.minY - usable.minY
            f.size.height = min(f.height, usable.height)
            f.origin.y = max(usable.minY, min(f.minY, usable.maxY - f.height))
        case .top:
            usable.size.height = usable.maxY - r.bar.maxY
            usable.origin.y = r.bar.maxY
            f.origin.y = max(f.minY, usable.minY)
            f.size.height = min(f.height, usable.maxY - f.minY)
        case .left:
            usable.size.width = usable.maxX - r.bar.maxX
            usable.origin.x = r.bar.maxX
            f.origin.x = max(f.minX, usable.minX)
            f.size.width = min(f.width, usable.maxX - f.minX)
        case .right:
            usable.size.width = r.bar.minX - usable.minX
            f.size.width = min(f.width, usable.width)
            f.origin.x = max(usable.minX, min(f.minX, usable.maxX - f.width))
        }
        guard abs(f.minX - frame.minX) > 0.5 || abs(f.minY - frame.minY) > 0.5
                || abs(f.width - frame.width) > 0.5 || abs(f.height - frame.height) > 0.5 else { return }
        AX.setFrame(element, f)
    }
}
