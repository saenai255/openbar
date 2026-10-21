import AppKit
import ApplicationServices

/// Diagnostic: `open -n OpenBar.app --args --probe-dock <file> [seconds]` logs every Dock item's
/// AX attributes and notifications, to find what changes while an app requests attention.
enum DockProbe {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--probe-dock"), i + 1 < args.count else { return false }
        let out = URL(fileURLWithPath: args[i + 1])
        let seconds = i + 2 < args.count ? Double(args[i + 2]) ?? 12 : 12
        FileManager.default.createFile(atPath: out.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: out) else { return true }
        func log(_ s: String) { handle.write((s + "\n").data(using: .utf8)!) }

        log("trusted \(AX.isTrusted)")
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return true
        }
        let root = AX.application(dock.processIdentifier)

        var observer: AXObserver?
        let callback: AXObserverCallback = { _, element, note, refcon in
            let title: String = AX.attribute(element, kAXTitleAttribute) ?? "?"
            let h = Unmanaged<FileHandle>.fromOpaque(refcon!).takeUnretainedValue()
            h.write("note \(Date().timeIntervalSince1970) \(note) \(title)\n".data(using: .utf8)!)
        }
        if AXObserverCreate(dock.processIdentifier, callback, &observer) == .success, let observer {
            let ref = Unmanaged.passUnretained(handle).toOpaque()
            for note in ["AXUIElementDestroyed", "AXCreated", "AXValueChanged", "AXTitleChanged", "AXLayoutChanged",
                         "AXSelectedChildrenChanged", "AXMoved", "AXResized", "AXAnnouncementRequested"] {
                AXObserverAddNotification(observer, root, note as CFString, ref)
            }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }

        var last: [String: String] = [:]
        let start = Date()
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { timer in
            let t = String(format: "%.1f", Date().timeIntervalSince(start))
            for list in (AX.attribute(root, kAXChildrenAttribute) as [AXUIElement]?) ?? [] {
                for item in (AX.attribute(list, kAXChildrenAttribute) as [AXUIElement]?) ?? [] {
                    let title: String = AX.attribute(item, kAXTitleAttribute) ?? "?"
                    var names: CFArray?
                    AXUIElementCopyAttributeNames(item, &names)
                    let all = ((names as? [String]) ?? []).sorted().map { name -> String in
                        var value: CFTypeRef?
                        AXUIElementCopyAttributeValue(item, name as CFString, &value)
                        return "\(name)=\(value.map { String(describing: $0).prefix(60) } ?? "nil")"
                    }.joined(separator: " | ")
                    if last[title] != all {
                        log("\(t) \(title): \(all)")
                        last[title] = all
                    }
                }
            }
            if Date().timeIntervalSince(start) > seconds {
                timer.invalidate()
                try? handle.close()
                exit(0)
            }
        }
        RunLoop.main.run()
        return true
    }
}
