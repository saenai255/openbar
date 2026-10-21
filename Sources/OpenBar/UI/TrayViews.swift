import AppKit
import Combine
import SwiftUI

final class TrayModel: ObservableObject {
    static let shared = TrayModel()

    @Published var battery: BatteryState?
    @Published var volume: Float?
    @Published var muted = false
    @Published var trashFull = false

    private var fastTimer: Timer?
    private var slowTimer: Timer?

    private init() {
        refreshFast()
        refreshSlow()
        fastTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refreshFast() }
        slowTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in self?.refreshSlow() }
    }

    func refreshFast() {
        let v = Volume.level
        let m = Volume.isMuted
        if v != volume { volume = v }
        if m != muted { muted = m }
    }

    func refreshSlow() {
        let b = BatteryState.read()
        if b != battery { battery = b }
        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        let full = ((try? FileManager.default.contentsOfDirectory(atPath: trash.path)) ?? [])
            .contains { $0 != ".DS_Store" }
        if full != trashFull { trashFull = full }
    }

    func nudgeVolume(_ delta: CGFloat) {
        let next = (volume ?? 0) + Float(delta) * 0.03
        Volume.level = next
        refreshFast()
    }

    func setVolume(_ value: Float) {
        Volume.level = value
        refreshFast()
    }

    func toggleMute() {
        Volume.isMuted.toggle()
        refreshFast()
    }
}

struct TrayButton<Label: View, Popover: View>: View {
    let thickness: CGFloat
    let style: BarStyle
    var onLeft: ((NSRect) -> Void)?
    var onRight: ((NSRect) -> Void)?
    var onScroll: ((CGFloat) -> Void)?
    @ViewBuilder let label: () -> Label
    @ViewBuilder let popover: () -> Popover
    var hasPopover = true

    @State private var showing = false
    @State private var hovering = false

    var body: some View {
        label()
            .foregroundStyle(style.foreground)
            .padding(.horizontal, 6)
            .frame(minWidth: thickness * 0.8, minHeight: thickness * 0.8)
            .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? style.foreground.opacity(0.12) : .clear))
            .contentShape(Rectangle())
            .overlay(MouseCatcher(
                onLeft: { anchor in
                    if let onLeft { onLeft(anchor) } else if hasPopover { showing.toggle() }
                },
                onRight: onRight,
                onHover: { inside, _ in hovering = inside },
                onScroll: onScroll
            ))
            .popover(isPresented: $showing, arrowEdge: Prefs.shared.position.popoverEdge) {
                popover().padding(12)
            }
    }
}

extension BarPosition {
    var popoverEdge: Edge {
        switch self {
        case .bottom: .top
        case .top: .bottom
        case .left: .trailing
        case .right: .leading
        }
    }
}

struct ClockView: View {
    let thickness: CGFloat
    let style: BarStyle
    let vertical: Bool
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        TrayButton(thickness: thickness, style: style) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: vertical ? .center : .trailing, spacing: 0) {
                    Text(context.date, format: timeFormat)
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                    if prefs.clockShowDate && (thickness >= 34 || vertical) {
                        Text(context.date, format: .dateTime.day().month(.abbreviated))
                            .font(.system(size: 10))
                            .opacity(0.8)
                    }
                }
                .lineLimit(1)
                .fixedSize()
            }
        } popover: {
            CalendarPopover()
        }
    }

    private var timeFormat: Date.FormatStyle {
        prefs.clockShowSeconds
            ? .dateTime.hour().minute().second()
            : .dateTime.hour().minute()
    }
}

struct CalendarPopover: View {
    @State private var date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide).year())
                .font(.headline)
            DatePicker("", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
            Button("Open Date & Time Settings…") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Date-Time-Settings.extension")!)
            }
            .buttonStyle(.link)
        }
        .frame(width: 260)
    }
}

struct BatteryView: View {
    let thickness: CGFloat
    let style: BarStyle
    @ObservedObject var tray = TrayModel.shared

    var body: some View {
        if let battery = tray.battery {
            TrayButton(thickness: thickness, style: style) {
                HStack(spacing: 3) {
                    Image(systemName: battery.symbolName)
                    if thickness >= 34 {
                        Text("\(battery.percent)%").font(.system(size: 11).monospacedDigit())
                    }
                }
            } popover: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Battery: \(battery.percent)%").font(.headline)
                    Text(battery.isCharging ? "Charging" : (battery.onAC ? "Power Adapter" : "Discharging"))
                    if let minutes = battery.minutesRemaining {
                        Text("\(battery.isCharging ? "Time until fully charged" : "Time until empty"): \(minutes / 60):\(String(format: "%02d", minutes % 60))")
                    }
                    Button("Open Battery Settings…") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")!)
                    }
                    .buttonStyle(.link)
                }
                .frame(minWidth: 200, alignment: .leading)
            }
        }
    }
}

struct SoundView: View {
    let thickness: CGFloat
    let style: BarStyle
    @ObservedObject var tray = TrayModel.shared

    private var symbol: String {
        guard let v = tray.volume, !tray.muted, v > 0 else { return "speaker.slash.fill" }
        return v < 0.34 ? "speaker.wave.1.fill" : (v < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill")
    }

    var body: some View {
        TrayButton(thickness: thickness, style: style,
                   onRight: { _ in tray.toggleMute() },
                   onScroll: { tray.nudgeVolume($0) }) {
            Image(systemName: symbol).frame(width: 18)
        } popover: {
            VStack(alignment: .leading, spacing: 8) {
                Text(tray.muted ? "Volume: Mute" : "Volume: \(Int((tray.volume ?? 0) * 100))%").font(.headline)
                HStack {
                    Button { tray.toggleMute() } label: { Image(systemName: symbol) }
                        .buttonStyle(.borderless)
                    Slider(value: Binding(get: { Double(tray.volume ?? 0) },
                                          set: { tray.setVolume(Float($0)) }), in: 0...1)
                }
                Button("Open Sound Settings…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
                }
                .buttonStyle(.link)
            }
            .frame(width: 220)
        }
    }
}

struct TrashView: View {
    let thickness: CGFloat
    let style: BarStyle
    @ObservedObject var tray = TrayModel.shared

    var body: some View {
        TrayButton(thickness: thickness, style: style,
                   onLeft: { _ in SystemActions.openTrash() },
                   onRight: { anchor in
                       let menu = NSMenu()
                       menu.add("Open Trash", symbol: "trash") { SystemActions.openTrash() }
                       menu.add("Empty Trash…", symbol: "trash.slash") {
                           SystemActions.emptyTrash()
                           tray.refreshSlow()
                       }
                       menu.popUp(at: anchor)
                   }) {
            Image(systemName: tray.trashFull ? "trash.fill" : "trash")
        } popover: {
            EmptyView()
        }
    }
}

struct MenuButtonView: View {
    let thickness: CGFloat
    let style: BarStyle

    var body: some View {
        TrayButton(thickness: thickness, style: style,
                   onLeft: { MenuBuilder.mainMenu().popUp(at: $0) },
                   onRight: { MenuBuilder.mainMenu().popUp(at: $0) }) {
            OpenRingGlyph(size: thickness * 0.46)
        } popover: {
            EmptyView()
        }
    }
}

struct ShowDesktopStrip: View {
    let vertical: Bool
    let style: BarStyle
    @State private var hovering = false

    var body: some View {
        Rectangle()
            .fill(hovering ? style.foreground.opacity(0.2) : style.foreground.opacity(0.06))
            .frame(width: vertical ? nil : 8, height: vertical ? 8 : nil)
            .overlay(MouseCatcher(
                onLeft: { _ in SystemActions.showDesktop() },
                onHover: { inside, _ in hovering = inside }
            ))
            .help("Show Desktop")
    }
}

/// The OpenBar mark: a ring opened at the lower right.
struct OpenRingGlyph: View {
    let size: CGFloat
    private let gap = 0.134

    var body: some View {
        Circle()
            .trim(from: 0, to: 1 - gap)
            .stroke(style: StrokeStyle(lineWidth: size * 0.2, lineCap: .round))
            // Trim's gap sits just above 3 o'clock; turn it to the lower right.
            .rotationEffect(.degrees(45 + gap * 360 / 2))
            .frame(width: size, height: size)
    }
}
