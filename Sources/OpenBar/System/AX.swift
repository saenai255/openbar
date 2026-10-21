import AppKit
import ApplicationServices

private typealias GetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

private let axGetWindow: GetWindowFn? = {
    guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else { return nil }
    return unsafeBitCast(sym, to: GetWindowFn.self)
}()

enum AX {
    static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    @discardableResult
    static func set(_ element: AXUIElement, _ name: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(element, name as CFString, value) == .success
    }

    static func perform(_ element: AXUIElement, _ action: String) {
        AXUIElementPerformAction(element, action as CFString)
    }

    static func application(_ pid: pid_t) -> AXUIElement {
        let el = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(el, 0.25)
        return el
    }

    static func windowID(_ element: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        guard let fn = axGetWindow, fn(element, &id) == .success, id != 0 else { return nil }
        return id
    }

    static func point(_ element: AXUIElement, _ name: String) -> CGPoint? {
        guard let v: AXValue = attribute(element, name) else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(v, .cgPoint, &p) ? p : nil
    }

    static func size(_ element: AXUIElement, _ name: String) -> CGSize? {
        guard let v: AXValue = attribute(element, name) else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(v, .cgSize, &s) ? s : nil
    }

    /// Frame in AX (top-left origin) coordinates.
    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let p = point(element, kAXPositionAttribute), let s = size(element, kAXSizeAttribute) else { return nil }
        return CGRect(origin: p, size: s)
    }

    static func setFrame(_ element: AXUIElement, _ frame: CGRect) {
        var p = frame.origin
        var s = frame.size
        if let pv = AXValueCreate(.cgPoint, &p) { set(element, kAXPositionAttribute, pv) }
        if let sv = AXValueCreate(.cgSize, &s) { set(element, kAXSizeAttribute, sv) }
        // Re-apply position: some apps clamp size against the old origin.
        if let pv = AXValueCreate(.cgPoint, &p) { set(element, kAXPositionAttribute, pv) }
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}

extension CGRect {
    /// Converts between Cocoa (bottom-left) and AX/CG (top-left) global coordinates.
    var flippedToScreenSpace: CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: minX, y: primaryHeight - maxY, width: width, height: height)
    }
}
