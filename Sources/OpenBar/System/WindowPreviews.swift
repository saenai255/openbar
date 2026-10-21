import AppKit
import ScreenCaptureKit

enum WindowPreviews {
    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    static func requestPermission() { CGRequestScreenCaptureAccess() }

    static func capture(_ ids: [CGWindowID], maxSide: CGFloat) async -> [CGWindowID: NSImage] {
        guard hasPermission, !ids.isEmpty,
              let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        else { return [:] }
        var result: [CGWindowID: NSImage] = [:]
        for id in ids {
            guard let window = content.windows.first(where: { $0.windowID == id }) else { continue }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            let scale = min(1, maxSide / max(window.frame.width, window.frame.height))
            let pixelScale = CGFloat(filter.pointPixelScale)
            config.width = max(1, Int(window.frame.width * scale * pixelScale))
            config.height = max(1, Int(window.frame.height * scale * pixelScale))
            config.showsCursor = false
            config.ignoreShadowsSingleWindow = true
            if let cg = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) {
                result[id] = NSImage(cgImage: cg, size: NSSize(width: window.frame.width * scale,
                                                               height: window.frame.height * scale))
            }
        }
        return result
    }
}
