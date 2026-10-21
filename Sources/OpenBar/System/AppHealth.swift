import AppKit

/// Detects hung apps the way the WindowServer reports them: events 750/751
/// (app unresponsive / responsive again) plus a direct query for the initial state.
enum AppHealth {
    private typealias NotifyProc = @convention(c) (UInt32, UnsafeMutableRawPointer?, Int, UnsafeMutableRawPointer?) -> Void
    private typealias RegisterFn = @convention(c) (Int32, NotifyProc, UInt32, UnsafeMutableRawPointer?) -> Int32
    private typealias ConnectionFn = @convention(c) () -> Int32
    private typealias IsUnresponsiveFn = @convention(c) (Int32, UnsafePointer<ProcessSerialNumber>) -> Bool
    private typealias PSNForPIDFn = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

    private static let handle = UnsafeMutableRawPointer(bitPattern: -2)
    private static func symbol<T>(_ name: String, as: T.Type) -> T? {
        dlsym(handle, name).map { unsafeBitCast($0, to: T.self) }
    }

    private static let connection: Int32 = symbol("CGSDefaultConnectionForThread", as: ConnectionFn.self)?() ?? 0
    private static let isUnresponsiveFn = symbol("CGSEventIsAppUnresponsive", as: IsUnresponsiveFn.self)
    private static let psnForPID = symbol("GetProcessForPID", as: PSNForPIDFn.self)

    /// Called on the main thread when an app's responsiveness changes.
    static var onChange: (() -> Void)?

    static func startListening() {
        guard let register = symbol("CGSRegisterConnectionNotifyProc", as: RegisterFn.self) else { return }
        let proc: NotifyProc = { _, _, _, _ in
            DispatchQueue.main.async { AppHealth.onChange?() }
        }
        _ = register(connection, proc, 750, nil)
        _ = register(connection, proc, 751, nil)
    }

    static func isUnresponsive(_ pid: pid_t) -> Bool {
        guard let isUnresponsiveFn, let psnForPID else { return false }
        var psn = ProcessSerialNumber()
        guard psnForPID(pid, &psn) == noErr else { return false }
        return isUnresponsiveFn(connection, &psn)
    }

    /// Force quits and relaunches once the old process is gone.
    static func forceRelaunch(_ app: NSRunningApplication, path: String) {
        app.forceTerminate()
        func reopen(attempt: Int) {
            if app.isTerminated || attempt > 50 {
                SystemActions.open(path: path)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { reopen(attempt: attempt + 1) }
            }
        }
        reopen(attempt: 0)
    }
}
