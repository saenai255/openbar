import AppKit
import Combine
import SwiftUI

enum BarPosition: String, CaseIterable, Identifiable {
    case bottom, top, left, right
    var id: String { rawValue }
    var isVertical: Bool { self == .left || self == .right }
}

enum BarSize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var thickness: CGFloat {
        switch self {
        case .small: 30
        case .medium: 38
        case .large: 48
        }
    }
}

enum AppOrder: String, CaseIterable, Identifiable {
    case launch, alphabetical, manual
    var id: String { rawValue }
}

enum BarTheme: String, CaseIterable, Identifiable {
    case glass, light, dark, custom
    var id: String { rawValue }
}

enum BarAlignment: String, CaseIterable, Identifiable {
    case leading, center
    var id: String { rawValue }
}

final class Prefs: ObservableObject {
    static let shared = Prefs()

    private func store(_ key: String, _ value: Any) {
        UserDefaults.standard.set(value, forKey: key)
    }

    @Published var position: BarPosition { didSet { store("position", position.rawValue) } }
    @Published var size: BarSize { didSet { store("size", size.rawValue) } }
    @Published var alignment: BarAlignment { didSet { store("alignment", alignment.rawValue) } }
    @Published var autoHide: Bool { didSet { store("autoHide", autoHide) } }
    @Published var allDisplays: Bool { didSet { store("allDisplays", allDisplays) } }
    @Published var windowsOnOwnDisplay: Bool { didSet { store("windowsOnOwnDisplay", windowsOnOwnDisplay) } }
    @Published var favoritesOnAllDisplays: Bool { didSet { store("favoritesOnAllDisplays", favoritesOnAllDisplays) } }
    @Published var keepWindowsClear: Bool { didSet { store("keepWindowsClear", keepWindowsClear) } }
    @Published var docklessMode: Bool { didSet { store("docklessMode", docklessMode) } }

    @Published var showTitles: Bool { didSet { store("showTitles", showTitles) } }
    @Published var groupWindows: Bool { didSet { store("groupWindows", groupWindows) } }
    @Published var groupClickShowsList: Bool { didSet { store("groupClickShowsList", groupClickShowsList) } }
    @Published var clickActiveToHide: Bool { didSet { store("clickActiveToHide", clickActiveToHide) } }
    @Published var currentSpaceOnly: Bool { didSet { store("currentSpaceOnly", currentSpaceOnly) } }
    @Published var excludeZeroWindowApps: Bool { didSet { store("excludeZeroWindowApps", excludeZeroWindowApps) } }
    @Published var showPreviews: Bool { didSet { store("showPreviews", showPreviews) } }
    @Published var showBadges: Bool { didSet { store("showBadges", showBadges) } }
    @Published var flashAttention: Bool { didSet { store("flashAttention", flashAttention) } }
    @Published var appOrder: AppOrder { didSet { store("appOrder", appOrder.rawValue) } }
    @Published var favorites: [String] { didSet { store("favorites", favorites) } }
    /// Running (unpinned) app paths in the order the user dragged them.
    @Published var runningOrder: [String] { didSet { store("runningOrder", runningOrder) } }
    @Published var excludedBundleIDs: [String] { didSet { store("excludedBundleIDs", excludedBundleIDs) } }

    @Published var showMenu: Bool { didSet { store("showMenu", showMenu) } }
    @Published var showClock: Bool { didSet { store("showClock", showClock) } }
    @Published var clockShowDate: Bool { didSet { store("clockShowDate", clockShowDate) } }
    @Published var clockShowSeconds: Bool { didSet { store("clockShowSeconds", clockShowSeconds) } }
    @Published var showBattery: Bool { didSet { store("showBattery", showBattery) } }
    @Published var showSound: Bool { didSet { store("showSound", showSound) } }
    @Published var showTrash: Bool { didSet { store("showTrash", showTrash) } }
    @Published var showDesktopButton: Bool { didSet { store("showDesktopButton", showDesktopButton) } }

    @Published var theme: BarTheme { didSet { store("theme", theme.rawValue) } }
    @Published var backgroundOpacity: Double { didSet { store("backgroundOpacity", backgroundOpacity) } }
    @Published var backgroundHex: String { didSet { store("backgroundHex", backgroundHex) } }
    @Published var foregroundHex: String { didSet { store("foregroundHex", foregroundHex) } }
    @Published var highlightHex: String { didSet { store("highlightHex", highlightHex) } }
    @Published var badgeHex: String { didSet { store("badgeHex", badgeHex) } }

    private init() {
        Prefs.migrateFromZubar()
        let d = UserDefaults.standard
        func str(_ k: String) -> String? { d.string(forKey: k) }
        position = BarPosition(rawValue: str("position") ?? "") ?? .bottom
        size = BarSize(rawValue: str("size") ?? "") ?? .medium
        alignment = BarAlignment(rawValue: str("alignment") ?? "") ?? .leading
        appOrder = AppOrder(rawValue: str("appOrder") ?? "") ?? .launch
        theme = BarTheme(rawValue: str("theme") ?? "") ?? .glass

        autoHide = d.object(forKey: "autoHide") as? Bool ?? false
        allDisplays = d.object(forKey: "allDisplays") as? Bool ?? true
        windowsOnOwnDisplay = d.object(forKey: "windowsOnOwnDisplay") as? Bool ?? true
        favoritesOnAllDisplays = d.object(forKey: "favoritesOnAllDisplays") as? Bool ?? false
        keepWindowsClear = d.object(forKey: "keepWindowsClear") as? Bool ?? true
        docklessMode = d.object(forKey: "docklessMode") as? Bool ?? false
        showTitles = d.object(forKey: "showTitles") as? Bool ?? true
        groupWindows = d.object(forKey: "groupWindows") as? Bool ?? true
        groupClickShowsList = d.object(forKey: "groupClickShowsList") as? Bool ?? false
        clickActiveToHide = d.object(forKey: "clickActiveToHide") as? Bool ?? true
        currentSpaceOnly = d.object(forKey: "currentSpaceOnly") as? Bool ?? false
        excludeZeroWindowApps = d.object(forKey: "excludeZeroWindowApps") as? Bool ?? false
        showPreviews = d.object(forKey: "showPreviews") as? Bool ?? true
        showBadges = d.object(forKey: "showBadges") as? Bool ?? true
        flashAttention = d.object(forKey: "flashAttention") as? Bool ?? true
        favorites = d.stringArray(forKey: "favorites") ?? Prefs.defaultFavorites
        excludedBundleIDs = d.stringArray(forKey: "excludedBundleIDs") ?? []
        runningOrder = d.stringArray(forKey: "runningOrder") ?? []

        showMenu = d.object(forKey: "showMenu") as? Bool ?? true
        showClock = d.object(forKey: "showClock") as? Bool ?? true
        clockShowDate = d.object(forKey: "clockShowDate") as? Bool ?? true
        clockShowSeconds = d.object(forKey: "clockShowSeconds") as? Bool ?? false
        showBattery = d.object(forKey: "showBattery") as? Bool ?? true
        showSound = d.object(forKey: "showSound") as? Bool ?? true
        showTrash = d.object(forKey: "showTrash") as? Bool ?? true
        showDesktopButton = d.object(forKey: "showDesktopButton") as? Bool ?? true

        backgroundOpacity = d.object(forKey: "backgroundOpacity") as? Double ?? 0.85
        backgroundHex = str("backgroundHex") ?? "#1E1E22"
        foregroundHex = str("foregroundHex") ?? "#FFFFFF"
        highlightHex = str("highlightHex") ?? "#0A84FF"
        badgeHex = str("badgeHex") ?? "#FF3B30"
    }

    /// Carries settings over from the app's previous name (bundle ID com.zubar.Zubar).
    private static func migrateFromZubar() {
        let d = UserDefaults.standard
        guard d.object(forKey: "didOnboard") == nil,
              let old = CFPreferencesCopyMultiple(nil, "com.zubar.Zubar" as CFString, kCFPreferencesCurrentUser,
                                                  kCFPreferencesAnyHost) as? [String: Any], !old.isEmpty else { return }
        for (key, value) in old { d.set(value, forKey: key) }
    }

    private static var defaultFavorites: [String] {
        ["/System/Applications/Finder.app", "/System/Library/CoreServices/Finder.app",
         "/Applications/Safari.app", "/System/Applications/Mail.app",
         "/System/Applications/System Settings.app"]
            .filter { FileManager.default.fileExists(atPath: $0) }
    }

    func isFavorite(_ path: String) -> Bool { favorites.contains(path) }

    func toggleFavorite(_ path: String) {
        if let i = favorites.firstIndex(of: path) { favorites.remove(at: i) } else { favorites.append(path) }
    }

    enum Move { case back, forward, first, last }

    func moveFavorite(_ path: String, _ move: Move) {
        guard let i = favorites.firstIndex(of: path) else { return }
        var list = favorites
        list.remove(at: i)
        let target: Int = switch move {
        case .back: max(0, i - 1)
        case .forward: min(list.count, i + 1)
        case .first: 0
        case .last: list.count
        }
        list.insert(path, at: target)
        favorites = list
    }

    /// Pins `path` at `index`, moving it if already pinned.
    func insertFavorite(_ path: String, at index: Int) {
        var list = favorites
        var target = index
        if let existing = list.firstIndex(of: path) {
            list.remove(at: existing)
            if existing < target { target -= 1 }
        }
        list.insert(path, at: min(max(target, 0), list.count))
        favorites = list
    }

    func exclude(_ bundleID: String) {
        if !excludedBundleIDs.contains(bundleID) { excludedBundleIDs.append(bundleID) }
    }
}

extension Color {
    init(hex: String) {
        self.init(nsColor: NSColor(hex: hex) ?? .gray)
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                  green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "#000000" }
        return String(format: "#%02X%02X%02X",
                      Int(round(c.redComponent * 255)), Int(round(c.greenComponent * 255)),
                      Int(round(c.blueComponent * 255)))
    }
}

extension Binding where Value == String {
    var asColor: Binding<Color> {
        Binding<Color>(
            get: { Color(hex: wrappedValue) },
            set: { wrappedValue = NSColor($0).hexString }
        )
    }
}
