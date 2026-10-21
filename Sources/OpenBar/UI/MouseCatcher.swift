import AppKit
import SwiftUI

/// Transparent overlay that reports clicks, hover and scrolls with the view's screen rect,
/// since SwiftUI has no right/middle-click or anchor-in-screen-space APIs.
struct MouseCatcher: NSViewRepresentable {
    var onLeft: ((NSRect) -> Void)?
    var onRight: ((NSRect) -> Void)?
    var onMiddle: (() -> Void)?
    var onHover: ((Bool, NSRect) -> Void)?
    var onScroll: ((CGFloat) -> Void)?
    /// File dragged out when the user drags this view.
    var dragPath: String?

    func makeNSView(context: Context) -> CatcherView { CatcherView() }

    func updateNSView(_ view: CatcherView, context: Context) { view.config = self }

    final class CatcherView: NSView, NSDraggingSource {
        var config: MouseCatcher?
        private var tracking: NSTrackingArea?
        private var downInside = false
        private var downPoint: NSPoint?

        var screenRect: NSRect {
            guard let window else { return .zero }
            return window.convertToScreen(convert(bounds, to: nil))
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tracking { removeTrackingArea(tracking) }
            let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                      owner: self, userInfo: nil)
            addTrackingArea(area)
            tracking = area
        }

        override func mouseEntered(with event: NSEvent) { config?.onHover?(true, screenRect) }
        override func mouseExited(with event: NSEvent) { config?.onHover?(false, screenRect) }

        override func mouseDown(with event: NSEvent) {
            downInside = true
            downPoint = event.locationInWindow
        }

        override func mouseDragged(with event: NSEvent) {
            guard downInside, let path = config?.dragPath, let start = downPoint,
                  hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > 5 else { return }
            downInside = false
            config?.onHover?(false, screenRect)
            let item = NSDraggingItem(pasteboardWriter: URL(fileURLWithPath: path) as NSURL)
            let icon = IconCache.icon(path)
            let side = min(bounds.width, bounds.height)
            item.setDraggingFrame(NSRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2,
                                         width: side, height: side), contents: icon)
            beginDraggingSession(with: [item], event: event, source: self)
        }

        func draggingSession(_ session: NSDraggingSession,
                             sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            context == .withinApplication ? .move : .copy
        }

        override func mouseUp(with event: NSEvent) {
            defer { downInside = false }
            guard downInside, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
            if event.modifierFlags.contains(.control) {
                config?.onRight?(screenRect)
            } else {
                config?.onLeft?(screenRect)
            }
        }

        override func rightMouseDown(with event: NSEvent) { config?.onRight?(screenRect) }

        override func otherMouseUp(with event: NSEvent) {
            if event.buttonNumber == 2 { config?.onMiddle?() }
        }

        override func scrollWheel(with event: NSEvent) {
            guard let onScroll = config?.onScroll else { return super.scrollWheel(with: event) }
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 40 : event.scrollingDeltaY
            onScroll(event.isDirectionInvertedFromDevice ? -delta : delta)
        }
    }
}
