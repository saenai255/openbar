import AppKit
import Carbon

enum SystemActions {
    private static func sendToLoginWindow(_ code: String) {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.loginwindow")
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass), eventID: fourCC(code),
                                           targetDescriptor: target, returnID: AEReturnID(kAutoGenerateReturnID),
                                           transactionID: AETransactionID(kAnyTransactionID))
        _ = try? event.sendEvent(options: [.noReply], timeout: 5)
    }

    private static func fourCC(_ s: String) -> AEEventID {
        s.utf8.reduce(0) { ($0 << 8) | AEEventID($1) }
    }

    private static func confirm(_ message: String, button: String) -> Bool {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func sleep() { sendToLoginWindow("slep") }

    static func restart() {
        if confirm("Are you sure you want to restart your computer now?", button: "Restart") { sendToLoginWindow("rest") }
    }

    static func shutDown() {
        if confirm("Are you sure you want to shut down your computer now?", button: "Shut Down") { sendToLoginWindow("shut") }
    }

    static func logOut() {
        if confirm("Are you sure you want to quit all your applications and log out now?", button: "Log Out") {
            sendToLoginWindow("rlgo")
        }
    }

    static func lockScreen() {
        typealias LockFn = @convention(c) () -> Void
        if let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_NOW),
           let sym = dlsym(handle, "SACLockScreenImmediate") {
            unsafeBitCast(sym, to: LockFn.self)()
            return
        }
        run("/usr/bin/pmset", ["displaysleepnow"])
    }

    static func showDesktop() {
        typealias NotifyFn = @convention(c) (CFString, UnsafeMutableRawPointer?) -> Void
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CoreDockSendNotification") else { return }
        unsafeBitCast(sym, to: NotifyFn.self)("com.apple.showdesktop.awake" as CFString, nil)
    }

    static func emptyTrash() {
        let alert = NSAlert()
        alert.messageText = "Are you sure you want to permanently erase the items in the Trash?"
        alert.informativeText = "You can’t undo this action."
        alert.addButton(withTitle: "Empty Trash")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        var error: NSDictionary?
        NSAppleScript(source: "tell application \"Finder\" to empty trash")?.executeAndReturnError(&error)
    }

    static func openTrash() {
        var error: NSDictionary?
        NSAppleScript(source: "tell application \"Finder\"\nopen trash\nactivate\nend tell")?.executeAndReturnError(&error)
    }

    static func open(path: String) { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }

    static func openSystemSettings() { open(path: "/System/Applications/System Settings.app") }

    static func openActivityMonitor() { open(path: "/System/Applications/Utilities/Activity Monitor.app") }

    static func forceQuitDialog() {
        // Cmd-Opt-Esc equivalent.
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Escape), keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Escape), keyDown: false)
        down?.flags = [.maskCommand, .maskAlternate]
        up?.flags = [.maskCommand, .maskAlternate]
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    @discardableResult
    static func run(_ launchPath: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }
}
