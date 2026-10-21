import SwiftUI

struct BarView: View {
    let displayID: CGDirectDisplayID
    @ObservedObject var prefs = Prefs.shared
    @ObservedObject var model = TaskbarModel.shared

    private var style: BarStyle { BarStyle(prefs: prefs) }
    private var vertical: Bool { prefs.position.isVertical }
    private var thickness: CGFloat { prefs.size.thickness }
    private var stack: AnyLayout {
        vertical ? AnyLayout(VStackLayout(spacing: 2)) : AnyLayout(HStackLayout(spacing: 2))
    }

    var body: some View {
        ZStack {
            style.background
            edgeLine
            stack {
                if prefs.showMenu {
                    MenuButtonView(thickness: thickness, style: style)
                    divider
                }
                items
                tray
            }
            .padding(vertical ? .vertical : .horizontal, 4)
        }
        .environment(\.colorScheme, style.colorScheme ?? systemScheme)
    }

    private var systemScheme: ColorScheme {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
    }

    private var edgeLine: some View {
        let alignment: Alignment = switch prefs.position {
        case .bottom: .top
        case .top: .bottom
        case .left: .trailing
        case .right: .leading
        }
        return Rectangle()
            .fill(style.foreground.opacity(0.15))
            .frame(width: vertical ? 0.5 : nil, height: vertical ? nil : 0.5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }

    private var divider: some View {
        Rectangle()
            .fill(style.foreground.opacity(0.2))
            .frame(width: vertical ? thickness * 0.5 : 1, height: vertical ? 1 : thickness * 0.5)
    }

    private var items: some View {
        let isPrimary = NSScreen.screens.first?.displayID == displayID
        let list = model.items(grouped: prefs.groupWindows, displayID: displayID, isPrimary: isPrimary)
        let showTitles = prefs.showTitles && !vertical
        return GeometryReader { geo in
            let available = vertical ? geo.size.height : geo.size.width
            let spacing: CGFloat = 2
            let ideal: CGFloat = showTitles ? 180 : thickness
            let minimum: CGFloat = showTitles ? max(thickness + 16, 56) : thickness
            let fitted = (available - spacing * CGFloat(max(list.count - 1, 0))) / CGFloat(max(list.count, 1))
            let length = max(min(ideal, fitted), minimum)
            let fits = length * CGFloat(list.count) <= available + 1
            let titles = showTitles && fitted >= minimum

            ScrollView(vertical ? .vertical : .horizontal, showsIndicators: false) {
                stack {
                    ForEach(list) { item in
                        AppButton(item: item, thickness: thickness, showTitle: titles,
                                  position: prefs.position, style: style)
                            .frame(width: vertical ? geo.size.width : (titles ? length : nil),
                                   height: vertical ? nil : geo.size.height)
                    }
                }
                .frame(minWidth: vertical ? nil : (fits ? geo.size.width : nil),
                       minHeight: vertical ? (fits ? geo.size.height : nil) : nil,
                       alignment: prefs.alignment == .center ? .center : (vertical ? .top : .leading))
            }
            .scrollDisabled(fits)
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                Task { @MainActor in
                    var urls: [URL] = []
                    for provider in providers {
                        if let url = try? await provider.loadFileURL() { urls.append(url.standardizedFileURL) }
                    }
                    BarDrop.handle(urls, onto: nil, edge: .after)
                }
                return true
            }
        }
    }

    @ViewBuilder
    private var tray: some View {
        let anyTray = prefs.showTrash || prefs.showSound || prefs.showBattery || prefs.showClock
        if anyTray { divider }
        if prefs.showTrash { TrashView(thickness: thickness, style: style) }
        if prefs.showSound { SoundView(thickness: thickness, style: style) }
        if prefs.showBattery { BatteryView(thickness: thickness, style: style) }
        if prefs.showClock { ClockView(thickness: thickness, style: style, vertical: vertical) }
        if prefs.showDesktopButton { ShowDesktopStrip(vertical: vertical, style: style) }
    }
}
