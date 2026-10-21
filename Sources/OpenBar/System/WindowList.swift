import AppKit
import ApplicationServices

struct WindowEntry: Identifiable, Equatable {
    let element: AXUIElement
    let windowID: CGWindowID?
    let pid: pid_t
    let title: String
    let isMinimized: Bool
    let displayID: CGDirectDisplayID?

    var id: String { windowID.map { "w\($0)" } ?? "e\(CFHash(element))" }

    static func == (a: WindowEntry, b: WindowEntry) -> Bool {
        a.id == b.id && a.title == b.title && a.isMinimized == b.isMinimized && a.displayID == b.displayID
    }
}

struct DisplayRect {
    let id: CGDirectDisplayID
    /// Screen frame in AX (top-left origin) coordinates.
    let frame: CGRect

    @MainActor static var current: [DisplayRect] {
        NSScreen.screens.map { DisplayRect(id: $0.displayID, frame: $0.frame.flippedToScreenSpace) }
    }

    static func owner(of window: CGRect, in displays: [DisplayRect]) -> CGDirectDisplayID? {
        displays.max { a, b in
            let ia = a.frame.intersection(window), ib = b.frame.intersection(window)
            return (ia.isNull ? 0 : ia.width * ia.height) < (ib.isNull ? 0 : ib.width * ib.height)
        }
        .flatMap { $0.frame.intersects(window) ? $0.id : nil }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

enum WindowList {
    static func windows(of pid: pid_t, displays: [DisplayRect] = []) -> [WindowEntry] {
        let app = AX.application(pid)
        guard let list: [AXUIElement] = AX.attribute(app, kAXWindowsAttribute) else { return [] }
        return list.compactMap { el in
            let subrole: String? = AX.attribute(el, kAXSubroleAttribute)
            guard subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole else { return nil }
            let title: String = AX.attribute(el, kAXTitleAttribute) ?? ""
            let minimized: Bool = AX.attribute(el, kAXMinimizedAttribute) ?? false
            let display = displays.isEmpty ? nil : AX.frame(el).flatMap { DisplayRect.owner(of: $0, in: displays) }
            return WindowEntry(element: el, windowID: AX.windowID(el), pid: pid, title: title, isMinimized: minimized,
                               displayID: display)
        }
    }

    /// PIDs owning a normal-layer window on the current Space.
    static func pidsOnCurrentSpace() -> Set<pid_t> {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        var pids = Set<pid_t>()
        for w in info where (w[kCGWindowLayer as String] as? Int) == 0 {
            if let pid = w[kCGWindowOwnerPID as String] as? pid_t { pids.insert(pid) }
        }
        return pids
    }

    /// True when the frontmost app has a window covering the whole screen (fullscreen video, games, etc.).
    static func frontmostCoversScreen(_ screen: NSScreen) -> Bool {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        let target = screen.frame.flippedToScreenSpace
        for w in info where (w[kCGWindowOwnerPID as String] as? pid_t) == pid && (w[kCGWindowLayer as String] as? Int) == 0 {
            guard let dict = w[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict) else { continue }
            if abs(bounds.minX - target.minX) < 1, abs(bounds.minY - target.minY) < 1,
               abs(bounds.width - target.width) < 1, abs(bounds.height - target.height) < 1 {
                return true
            }
        }
        return false
    }

    static func focus(_ window: WindowEntry) {
        if let app = NSRunningApplication(processIdentifier: window.pid), app.isHidden { app.unhide() }
        if window.isMinimized { AX.set(window.element, kAXMinimizedAttribute, kCFBooleanFalse) }
        AX.set(window.element, kAXMainAttribute, kCFBooleanTrue)
        AX.perform(window.element, kAXRaiseAction)
        activate(pid: window.pid)
    }

    static func activate(pid: pid_t) {
        AX.set(AX.application(pid), kAXFrontmostAttribute, kCFBooleanTrue)
        NSRunningApplication(processIdentifier: pid)?.activate()
    }

    static func minimize(_ window: WindowEntry) {
        AX.set(window.element, kAXMinimizedAttribute, kCFBooleanTrue)
    }

    static func close(_ window: WindowEntry) {
        if let button: AXUIElement = AX.attribute(window.element, kAXCloseButtonAttribute) {
            AX.perform(button, kAXPressAction)
        }
    }
}
