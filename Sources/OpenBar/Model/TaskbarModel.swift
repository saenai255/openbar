import AppKit
import Combine

struct AppEntry: Identifiable, Equatable {
    var path: String
    var name: String
    var bundleID: String?
    var pid: pid_t?
    var isFavorite: Bool
    var isActive: Bool
    var isHidden: Bool
    var isFolder: Bool
    var windows: [WindowEntry]
    var badge: String?
    var isLaunching = false
    var isUnresponsive = false
    var wantsAttention = false

    var id: String { path }
    var isRunning: Bool { pid != nil }
    var runningApp: NSRunningApplication? { pid.flatMap(NSRunningApplication.init(processIdentifier:)) }

    func with(windows: [WindowEntry]) -> AppEntry {
        var copy = self
        copy.windows = windows
        return copy
    }
}

struct BarItem: Identifiable, Equatable {
    let app: AppEntry
    let window: WindowEntry?

    var id: String { window.map { "\(app.id)#\($0.id)" } ?? app.id }
    var title: String {
        guard let window, !window.title.isEmpty else { return app.name }
        return window.title
    }
}

final class TaskbarModel: ObservableObject {
    static let shared = TaskbarModel()

    @Published private(set) var apps: [AppEntry] = []

    private let prefs = Prefs.shared
    private let queue = DispatchQueue(label: "openbar.refresh", qos: .userInitiated)
    private var launchOrder: [pid_t: Int] = [:]
    private var launchCounter = 0
    private var timer: Timer?
    private var badges: [String: String] = [:]
    private var lastBadgeRead = Date.distantPast
    private var refreshPending = false
    private var cancellables = Set<AnyCancellable>()
    /// Paths launched but not yet showing a window, with when they started.
    private var launching: [String: Date] = [:]

    private init() {
        for app in NSWorkspace.shared.runningApplications { noteLaunch(app.processIdentifier) }

        let nc = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification, NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification,
        ]
        for name in names {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                if name == NSWorkspace.didLaunchApplicationNotification,
                   let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                    self?.noteLaunch(app.processIdentifier)
                    if let path = app.bundleURL?.standardizedFileURL.path, self?.launching[path] == nil {
                        self?.launching[path] = Date()
                    }
                }
                self?.refresh()
            }
        }

        prefs.objectWillChange
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] in self?.refresh() }
            .store(in: &cancellables)

        AppHealth.onChange = { [weak self] in self?.refresh() }
        AppHealth.startListening()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.refresh() }
        refresh()
    }

    private func noteLaunch(_ pid: pid_t) {
        guard launchOrder[pid] == nil else { return }
        launchCounter += 1
        launchOrder[pid] = launchCounter
    }

    func refresh() {
        guard !refreshPending else { return }
        refreshPending = true

        let snapshot = Snapshot(prefs: prefs, launchOrder: launchOrder, launching: Set(launching.keys))
        let readBadges = prefs.showBadges && Date().timeIntervalSince(lastBadgeRead) > 2
        queue.async { [weak self] in
            guard let self else { return }
            let badges = readBadges ? DockBadges.current() : nil
            let apps = Self.build(snapshot, badges: badges ?? self.badges)
            DispatchQueue.main.async {
                self.refreshPending = false
                if let badges {
                    self.badges = badges
                    self.lastBadgeRead = Date()
                }
                self.settleLaunching(apps)
                if apps != self.apps { self.apps = apps }
            }
        }
    }

    func noteLaunchRequested(_ path: String) {
        launching[path] = Date()
        refresh()
    }

    private func settleLaunching(_ apps: [AppEntry]) {
        let timeout = Date().addingTimeInterval(-15)
        for (path, started) in launching where started < timeout { launching[path] = nil }
        for app in apps where launching[app.path] != nil && !app.isLaunching && app.isRunning {
            launching[app.path] = nil
        }
    }

    private struct Snapshot {
        let favorites: [String]
        let excluded: Set<String>
        let order: AppOrder
        let currentSpaceOnly: Bool
        let excludeZeroWindowApps: Bool
        let showBadges: Bool
        let launchOrder: [pid_t: Int]
        let running: [NSRunningApplication]
        let frontPID: pid_t?
        let displays: [DisplayRect]
        let launching: Set<String>

        init(prefs: Prefs, launchOrder: [pid_t: Int], launching: Set<String>) {
            self.launching = launching
            favorites = prefs.favorites
            excluded = Set(prefs.excludedBundleIDs)
            order = prefs.appOrder
            currentSpaceOnly = prefs.currentSpaceOnly
            excludeZeroWindowApps = prefs.excludeZeroWindowApps
            showBadges = prefs.showBadges
            self.launchOrder = launchOrder
            let me = ProcessInfo.processInfo.processIdentifier
            running = NSWorkspace.shared.runningApplications.filter {
                $0.activationPolicy == .regular && $0.processIdentifier != me && !$0.isTerminated
            }
            frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            displays = prefs.allDisplays && NSScreen.screens.count > 1 ? MainActor.assumeIsolated { DisplayRect.current } : []
        }
    }

    private static func build(_ s: Snapshot, badges: [String: String]) -> [AppEntry] {
        var runningByPath: [String: NSRunningApplication] = [:]
        for app in s.running {
            guard let path = app.bundleURL?.standardizedFileURL.path else { continue }
            if let existing = runningByPath[path], existing.processIdentifier < app.processIdentifier { continue }
            runningByPath[path] = app
        }
        let spacePIDs = s.currentSpaceOnly ? WindowList.pidsOnCurrentSpace() : []

        func entry(path: String, app: NSRunningApplication?, favorite: Bool) -> AppEntry {
            let windows = app.map { WindowList.windows(of: $0.processIdentifier, displays: s.displays) } ?? []
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            let isFolder = isDir.boolValue && !path.hasSuffix(".app")
            let name = app?.localizedName
                ?? FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
            let isActive = app != nil && app?.processIdentifier == s.frontPID
            let settled = app.map { $0.isFinishedLaunching && (!windows.isEmpty || isActive) } ?? false
            return AppEntry(path: path, name: name, bundleID: app?.bundleIdentifier ?? Bundle(path: path)?.bundleIdentifier,
                            pid: app?.processIdentifier, isFavorite: favorite, isActive: isActive,
                            isHidden: app?.isHidden ?? false, isFolder: isFolder, windows: windows,
                            badge: s.showBadges ? badges[path] : nil,
                            isLaunching: s.launching.contains(path) && !settled,
                            isUnresponsive: app.map { AppHealth.isUnresponsive($0.processIdentifier) } ?? false)
        }

        var runningByBundleID: [String: NSRunningApplication] = [:]
        for app in runningByPath.values {
            if let id = app.bundleIdentifier { runningByBundleID[id] = app }
        }

        var claimed = Set<pid_t>()
        var result: [AppEntry] = s.favorites.map { path in
            let app = runningByPath[path] ?? Bundle(path: path)?.bundleIdentifier.flatMap { runningByBundleID[$0] }
            if let app { claimed.insert(app.processIdentifier) }
            return entry(path: path, app: app, favorite: true)
        }

        var others = s.running.filter { app in
            guard let path = app.bundleURL?.standardizedFileURL.path, runningByPath[path] === app,
                  !claimed.contains(app.processIdentifier) else { return false }
            return !s.excluded.contains(app.bundleIdentifier ?? "")
        }
        switch s.order {
        case .launch:
            others.sort { (s.launchOrder[$0.processIdentifier] ?? 0) < (s.launchOrder[$1.processIdentifier] ?? 0) }
        case .alphabetical:
            others.sort { ($0.localizedName ?? "").localizedStandardCompare($1.localizedName ?? "") == .orderedAscending }
        }

        for app in others {
            let e = entry(path: app.bundleURL!.standardizedFileURL.path, app: app, favorite: false)
            if s.excludeZeroWindowApps && e.windows.isEmpty && !e.isActive { continue }
            if s.currentSpaceOnly && !spacePIDs.contains(app.processIdentifier)
                && !e.windows.contains(where: \.isMinimized) && !e.isActive { continue }
            result.append(e)
        }
        return result
    }

    /// Items for the bar on `displayID`. Windows go to the bar on their own display;
    /// favorites and window-less apps live on the primary bar.
    func items(grouped: Bool, displayID: CGDirectDisplayID, isPrimary: Bool) -> [BarItem] {
        let split = prefs.allDisplays && prefs.windowsOnOwnDisplay && NSScreen.screens.count > 1
        let visible: [AppEntry] = !split ? apps : apps.compactMap { app in
            let mine = app.windows.filter { $0.displayID == displayID || ($0.displayID == nil && isPrimary) }
            if !mine.isEmpty { return app.with(windows: mine) }
            let pinnedHere = app.isFavorite && (isPrimary || prefs.favoritesOnAllDisplays)
            let homeless = app.windows.isEmpty && isPrimary
            return pinnedHere || homeless ? app.with(windows: []) : nil
        }
        return visible.flatMap { app -> [BarItem] in
            if grouped || app.windows.isEmpty { return [BarItem(app: app, window: nil)] }
            return app.windows.map { BarItem(app: app, window: $0) }
        }
    }

    // MARK: - Actions

    func primaryClick(_ item: BarItem, anchor: NSRect) {
        let app = item.app
        if app.isFolder {
            MenuBuilder.folderMenu(path: app.path).popUp(at: anchor)
            return
        }
        guard let running = app.runningApp else {
            noteLaunchRequested(app.path)
            SystemActions.open(path: app.path)
            return
        }
        if let window = item.window {
            let focused: AXUIElement? = AX.attribute(AX.application(running.processIdentifier), kAXFocusedWindowAttribute)
            let isFront = app.isActive && !window.isMinimized && focused.map { CFEqual($0, window.element) } == true
            if isFront && prefs.clickActiveToHide {
                WindowList.minimize(window)
            } else {
                WindowList.focus(window)
            }
            refreshSoon()
            return
        }
        if app.isActive && !app.isHidden && !app.windows.isEmpty {
            let focused = focusedWindow(of: app, pid: running.processIdentifier)
            let cycle = app.windows.filter { !$0.isMinimized }.sorted { ($0.windowID ?? 0) < ($1.windowID ?? 0) }
            if app.windows.count > 1 && prefs.groupClickShowsList {
                MenuBuilder.windowListMenu(for: app).popUp(at: anchor)
            } else if focused == nil, let first = cycle.first ?? app.windows.first {
                WindowList.focus(first)
                lastCycled = (first.id, Date())
            } else if cycle.count > 1 {
                let index = cycle.firstIndex { $0.id == focused?.id } ?? -1
                let next = cycle[(index + 1) % cycle.count]
                WindowList.focus(next)
                lastCycled = (next.id, Date())
            } else if prefs.clickActiveToHide {
                running.hide()
            }
        } else if app.windows.count > 1 && prefs.groupClickShowsList {
            MenuBuilder.windowListMenu(for: app).popUp(at: anchor)
        } else if app.windows.isEmpty {
            // Reopen event makes apps like Finder/Safari create a window.
            SystemActions.open(path: app.path)
        } else {
            if running.isHidden { running.unhide() }
            if let firstVisible = app.windows.first(where: { !$0.isMinimized }) ?? app.windows.first {
                WindowList.focus(firstVisible)
            } else {
                WindowList.activate(pid: running.processIdentifier)
            }
        }
        refreshSoon()
    }

    private var lastCycled: (id: String, at: Date)?

    /// The app's focused window among `app.windows`, or nil if it is elsewhere.
    /// Prefers the last cycled window briefly, since AX focus lags behind rapid clicks.
    private func focusedWindow(of app: AppEntry, pid: pid_t) -> WindowEntry? {
        if let last = lastCycled, Date().timeIntervalSince(last.at) < 1,
           let hit = app.windows.first(where: { $0.id == last.id }) { return hit }
        guard let element: AXUIElement = AX.attribute(AX.application(pid), kAXFocusedWindowAttribute) else { return nil }
        return app.windows.first { CFEqual($0.element, element) }
    }

    func middleClick(_ item: BarItem) {
        if let window = item.window {
            WindowList.close(window)
        } else {
            SystemActions.open(path: item.app.path)
        }
        refreshSoon()
    }

    func refreshSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.refresh() }
    }
}
