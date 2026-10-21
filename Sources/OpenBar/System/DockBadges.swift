import AppKit
import ApplicationServices

/// Reads app badges from the Dock's accessibility tree (AXStatusLabel on each dock item).
enum DockBadges {
    static func current() -> [String: String] {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return [:] }
        let root = AX.application(dock.processIdentifier)
        guard let lists: [AXUIElement] = AX.attribute(root, kAXChildrenAttribute) else { return [:] }
        var badges: [String: String] = [:]
        for list in lists {
            guard let items: [AXUIElement] = AX.attribute(list, kAXChildrenAttribute) else { continue }
            for item in items {
                guard let label: String = AX.attribute(item, "AXStatusLabel"), !label.isEmpty,
                      let url: URL = AX.attribute(item, kAXURLAttribute) else { continue }
                badges[url.standardizedFileURL.path] = label
            }
        }
        return badges
    }
}
