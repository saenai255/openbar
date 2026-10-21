import AppKit
import SwiftUI

final class BarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class BarController {
    let displayID: CGDirectDisplayID
    private var lastScreen: NSScreen
    /// Re-resolved by ID: NSScreen objects are replaced when displays are reconfigured.
    var screen: NSScreen {
        if let s = NSScreen.screens.first(where: { $0.displayID == displayID }) { lastScreen = s }
        return lastScreen
    }
    let panel: BarPanel
    private(set) var isHidden = false
    private var autoHideTimer: Timer?
    private var outsideSince: Date?
    private var suppressedForFullscreen = false

    private static var openMenus = 0
    private static let menuObservers: [NSObjectProtocol] = {
        let nc = NotificationCenter.default
        return [
            nc.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { _ in openMenus += 1 },
            nc.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { _ in
                openMenus = max(0, openMenus - 1)
            },
        ]
    }()

    private var prefs: Prefs { .shared }

    init(screen: NSScreen) {
        _ = Self.menuObservers
        displayID = screen.displayID
        lastScreen = screen
        panel = BarPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = NSHostingView(rootView: BarView(displayID: displayID))
        layout()
        panel.orderFrontRegardless()
    }

    func close() {
        autoHideTimer?.invalidate()
        panel.orderOut(nil)
        panel.close()
    }

    var menuBarHeight: CGFloat { screen.frame.maxY - screen.visibleFrame.maxY }

    /// Visible bar frame in Cocoa coordinates.
    var barFrame: NSRect {
        let f = screen.frame
        let t = prefs.size.thickness
        let w = t + 12
        switch prefs.position {
        case .bottom: return NSRect(x: f.minX, y: f.minY, width: f.width, height: t)
        case .top: return NSRect(x: f.minX, y: f.maxY - menuBarHeight - t, width: f.width, height: t)
        case .left: return NSRect(x: f.minX, y: f.minY, width: w, height: f.height - menuBarHeight)
        case .right: return NSRect(x: f.maxX - w, y: f.minY, width: w, height: f.height - menuBarHeight)
        }
    }

    private var hiddenFrame: NSRect {
        let r = barFrame
        let peek: CGFloat = 1
        switch prefs.position {
        case .bottom: return r.offsetBy(dx: 0, dy: -(r.height - peek))
        case .top: return r.offsetBy(dx: 0, dy: r.height + menuBarHeight)
        case .left: return r.offsetBy(dx: -(r.width - peek), dy: 0)
        case .right: return r.offsetBy(dx: r.width - peek, dy: 0)
        }
    }

    private var revealZone: NSRect {
        let r = barFrame
        switch prefs.position {
        case .bottom: return NSRect(x: r.minX, y: r.minY, width: r.width, height: 2)
        case .top: return NSRect(x: r.minX, y: r.maxY - 3, width: r.width, height: 3)
        case .left: return NSRect(x: r.minX, y: r.minY, width: 2, height: r.height)
        case .right: return NSRect(x: r.maxX - 2, y: r.minY, width: 2, height: r.height)
        }
    }

    func layout() {
        if prefs.autoHide {
            if autoHideTimer == nil {
                autoHideTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
            }
            setHidden(isHidden, animated: false)
        } else {
            autoHideTimer?.invalidate()
            autoHideTimer = nil
            isHidden = false
            panel.setFrame(barFrame, display: true)
        }
    }

    private func setHidden(_ hidden: Bool, animated: Bool) {
        isHidden = hidden
        let target = hidden ? hiddenFrame : barFrame
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                panel.animator().setFrame(target, display: true)
            }
        } else {
            panel.setFrame(target, display: true)
        }
    }

    private var isBusy: Bool {
        Self.openMenus > 0 || PreviewController.shared.isVisible
            || NSApp.windows.contains { $0.isVisible && String(describing: type(of: $0)).contains("Popover") }
    }

    private func tick() {
        let mouse = NSEvent.mouseLocation
        if isHidden {
            if revealZone.contains(mouse) && NSEvent.pressedMouseButtons == 0 {
                setHidden(false, animated: true)
            }
            return
        }
        if barFrame.insetBy(dx: -2, dy: -2).contains(mouse) || isBusy {
            outsideSince = nil
        } else if let since = outsideSince {
            if Date().timeIntervalSince(since) > 0.5 {
                outsideSince = nil
                setHidden(true, animated: true)
            }
        } else {
            outsideSince = Date()
        }
    }

    func updateFullscreenState() {
        let covers = WindowList.frontmostCoversScreen(screen)
        guard covers != suppressedForFullscreen else { return }
        suppressedForFullscreen = covers
        if covers { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }
}
