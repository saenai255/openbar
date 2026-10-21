import Foundation

/// Dock-less mode: pushes the Dock out of the way by making its auto-hide delay effectively infinite.
/// The hide animation stays instant: Mission Control force-shows the Dock, and a slow
/// animation would then leave it stuck on screen.
enum DockController {
    private static let backupKey = "dockBackup"
    private static let managedKeys = ["autohide", "autohide-delay", "autohide-time-modifier", "no-bouncing"]

    private static var dockDefaults: UserDefaults? { UserDefaults(suiteName: "com.apple.dock") }

    static func apply(dockless: Bool) {
        let isApplied = UserDefaults.standard.dictionary(forKey: backupKey) != nil
        if dockless && !isApplied {
            enable()
        } else if !dockless && isApplied {
            disable()
        } else if dockless && dockDefaults?.double(forKey: "autohide-time-modifier") != 0 {
            // Repairs installs from 1.0.0, which set a huge animation time.
            write("autohide-time-modifier", "-float", "0")
            restartDock()
        }
    }

    private static func enable() {
        var backup: [String: Any] = [:]
        for key in managedKeys {
            if let v = dockDefaults?.object(forKey: key) { backup[key] = v }
        }
        UserDefaults.standard.set(backup, forKey: backupKey)
        write("autohide", "-bool", "YES")
        write("autohide-delay", "-float", "1000000")
        write("autohide-time-modifier", "-float", "0")
        write("no-bouncing", "-bool", "YES")
        restartDock()
    }

    private static func disable() {
        let backup = UserDefaults.standard.dictionary(forKey: backupKey) ?? [:]
        for key in managedKeys {
            switch backup[key] {
            case let v as Bool: write(key, "-bool", v ? "YES" : "NO")
            case let v as NSNumber: write(key, "-float", v.stringValue)
            default: SystemActions.run("/usr/bin/defaults", ["delete", "com.apple.dock", key])
            }
        }
        UserDefaults.standard.removeObject(forKey: backupKey)
        restartDock()
    }

    private static func write(_ key: String, _ type: String, _ value: String) {
        SystemActions.run("/usr/bin/defaults", ["write", "com.apple.dock", key, type, value])
    }

    private static func restartDock() { SystemActions.run("/usr/bin/killall", ["Dock"]) }

    /// Edge the Dock occupies, or nil when it auto-hides.
    static var occupiedEdge: BarPosition? {
        guard dockDefaults?.bool(forKey: "autohide") != true else { return nil }
        switch dockDefaults?.string(forKey: "orientation") {
        case "left": return .left
        case "right": return .right
        default: return .bottom
        }
    }
}
