import AppKit
import SwiftUI

enum IconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(_ path: String) -> NSImage {
        if let hit = cache[path] { return hit }
        let image = NSWorkspace.shared.icon(forFile: path)
        cache[path] = image
        return image
    }
}

struct BarStyle {
    let prefs: Prefs

    var foreground: Color {
        switch prefs.theme {
        case .glass: .primary
        case .light: .black
        case .dark: .white
        case .custom: Color(hex: prefs.foregroundHex)
        }
    }

    var highlight: Color { Color(hex: prefs.highlightHex) }
    var badge: Color { Color(hex: prefs.badgeHex) }

    var colorScheme: ColorScheme? {
        switch prefs.theme {
        case .light: .light
        case .dark: .dark
        case .glass, .custom: nil
        }
    }

    @ViewBuilder
    var background: some View {
        switch prefs.theme {
        case .glass:
            Color.clear.glassEffect(.regular, in: Rectangle())
        case .light:
            Color(white: 0.96).opacity(prefs.backgroundOpacity)
        case .dark:
            Color(white: 0.11).opacity(prefs.backgroundOpacity)
        case .custom:
            Color(hex: prefs.backgroundHex).opacity(prefs.backgroundOpacity)
        }
    }
}
