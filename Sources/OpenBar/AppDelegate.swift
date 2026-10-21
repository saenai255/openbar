import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate!

    private var bars: [BarController] = []
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private let prefs = Prefs.shared

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !AX.isTrusted { AX.requestTrust() }
        _ = TaskbarModel.shared
        _ = TrayModel.shared

        rebuildBars()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.rebuildBars() }

        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self?.bars.forEach { $0.updateFullscreenState() }
                }
            }
        }

        Publishers.MergeMany(
            prefs.$position.map { _ in () }.eraseToAnyPublisher(),
            prefs.$size.map { _ in () }.eraseToAnyPublisher(),
            prefs.$allDisplays.map { _ in () }.eraseToAnyPublisher(),
            prefs.$autoHide.map { _ in () }.eraseToAnyPublisher(),
            prefs.$keepWindowsClear.map { _ in () }.eraseToAnyPublisher()
        )
        .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
        .sink { [weak self] in self?.rebuildBars() }
        .store(in: &cancellables)

        prefs.$docklessMode
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { DockController.apply(dockless: $0) }
            .store(in: &cancellables)

        if UserDefaults.standard.object(forKey: "didOnboard") == nil {
            UserDefaults.standard.set(true, forKey: "didOnboard")
            showSettings()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    private func rebuildBars() {
        let screens = prefs.allDisplays ? NSScreen.screens : Array(NSScreen.screens.prefix(1))
        let ids = Set(screens.map(\.displayID))
        bars.filter { !ids.contains($0.displayID) }.forEach { $0.close() }
        let keep = bars.filter { ids.contains($0.displayID) }
        bars = screens.map { screen in keep.first { $0.displayID == screen.displayID } ?? BarController(screen: screen) }
        bars.forEach { $0.layout() }

        WindowGuard.shared.update(bars: bars.map { ($0.barFrame, $0.screen) }, edge: prefs.position,
                                  enabled: prefs.keepWindowsClear && !prefs.autoHide)
    }

    func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 520),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "OpenBar Settings"
            window.contentViewController = NSHostingController(rootView: SettingsView())
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "OpenBar",
            .credits: NSAttributedString(string: "A taskbar for macOS."),
        ])
    }
}
