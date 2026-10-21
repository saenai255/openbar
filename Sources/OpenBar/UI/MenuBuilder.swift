import AppKit

/// NSMenuItem whose action is a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, symbol: String? = nil, key: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
        if let symbol { image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func fire() { handler() }
}

extension NSMenu {
    func add(_ title: String, symbol: String? = nil, _ handler: @escaping () -> Void) {
        addItem(ClosureMenuItem(title, symbol: symbol, handler: handler))
    }

    func popUp(at anchor: NSRect) {
        let barPosition = Prefs.shared.position
        let point: NSPoint = switch barPosition {
        case .bottom: NSPoint(x: anchor.minX, y: anchor.maxY + 4)
        case .top: NSPoint(x: anchor.minX, y: anchor.minY - 4)
        case .left: NSPoint(x: anchor.maxX + 4, y: anchor.maxY)
        case .right: NSPoint(x: anchor.minX - 4, y: anchor.maxY)
        }
        if barPosition == .bottom {
            // NSMenu grows downward from the point; shift it up by its height.
            popUp(positioning: nil, at: NSPoint(x: point.x, y: point.y + size.height), in: nil)
        } else if barPosition == .right {
            popUp(positioning: nil, at: NSPoint(x: point.x - size.width, y: point.y), in: nil)
        } else {
            popUp(positioning: nil, at: point, in: nil)
        }
    }
}

enum MenuBuilder {
    private static let model = TaskbarModel.shared
    private static let prefs = Prefs.shared

    static func mainMenu() -> NSMenu {
        let menu = NSMenu()
        let header = NSMenuItem(title: NSFullUserName(), action: nil, keyEquivalent: "")
        header.image = NSImage(systemSymbolName: "person.crop.circle.fill", accessibilityDescription: nil)
        menu.addItem(header)
        menu.addItem(.separator())
        menu.add("About OpenBar", symbol: "info.circle") { AppDelegate.shared.showAbout() }
        menu.add("Settings…", symbol: "gearshape") { AppDelegate.shared.showSettings() }
        menu.addItem(.separator())
        menu.add("System Settings…", symbol: "switch.2") { SystemActions.openSystemSettings() }
        menu.add("Activity Monitor", symbol: "waveform.path.ecg") { SystemActions.openActivityMonitor() }
        menu.add("Force Quit…", symbol: "xmark.octagon") { SystemActions.forceQuitDialog() }
        menu.addItem(.separator())
        menu.addItem(applicationsSubmenu())
        menu.addItem(.separator())
        menu.add("Sleep", symbol: "moon") { SystemActions.sleep() }
        menu.add("Restart…", symbol: "arrow.clockwise") { SystemActions.restart() }
        menu.add("Shut Down…", symbol: "power") { SystemActions.shutDown() }
        menu.addItem(.separator())
        menu.add("Lock Screen", symbol: "lock") { SystemActions.lockScreen() }
        menu.add("Log Out \(NSFullUserName())…", symbol: "rectangle.portrait.and.arrow.right") { SystemActions.logOut() }
        menu.addItem(.separator())
        menu.add("Quit OpenBar", symbol: "xmark") { NSApp.terminate(nil) }
        return menu
    }

    private static func applicationsSubmenu() -> NSMenuItem {
        let item = NSMenuItem(title: "Applications", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: nil)
        item.submenu = directoryMenu(URL(fileURLWithPath: "/Applications"), extra: [URL(fileURLWithPath: "/System/Applications")])
        return item
    }

    static func folderMenu(path: String) -> NSMenu {
        let menu = directoryMenu(URL(fileURLWithPath: path))
        menu.insertItem(.separator(), at: 0)
        menu.insertItem(ClosureMenuItem("Open in Finder", symbol: "folder") { SystemActions.open(path: path) }, at: 0)
        return menu
    }

    private static func directoryMenu(_ url: URL, extra: [URL] = []) -> NSMenu {
        let menu = NSMenu()
        let fm = FileManager.default
        let entries = ([url] + extra).flatMap {
            (try? fm.contentsOfDirectory(at: $0, includingPropertiesForKeys: [.isDirectoryKey],
                                         options: [.skipsHiddenFiles])) ?? []
        }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        for entry in entries {
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let isPackage = entry.pathExtension == "app"
            let title = entry.deletingPathExtension().lastPathComponent
            let icon = NSWorkspace.shared.icon(forFile: entry.path)
            icon.size = NSSize(width: 16, height: 16)
            let item: NSMenuItem
            if isDir && !isPackage {
                item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.submenu = LazyDirectoryMenu(url: entry)
            } else {
                item = ClosureMenuItem(title) { NSWorkspace.shared.open(entry) }
            }
            item.image = icon
            menu.addItem(item)
        }
        if entries.isEmpty {
            let empty = NSMenuItem(title: "No items", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        return menu
    }

    final class LazyDirectoryMenu: NSMenu, NSMenuDelegate {
        private let url: URL
        private var loaded = false

        init(url: URL) {
            self.url = url
            super.init(title: url.lastPathComponent)
            delegate = self
            addItem(NSMenuItem(title: "…", action: nil, keyEquivalent: ""))
        }

        required init(coder: NSCoder) { fatalError() }

        func menuNeedsUpdate(_ menu: NSMenu) {
            guard !loaded else { return }
            loaded = true
            removeAllItems()
            let built = MenuBuilder.folderMenu(path: url.path)
            for item in built.items {
                built.removeItem(item)
                addItem(item)
            }
        }
    }

    static func windowListMenu(for app: AppEntry) -> NSMenu {
        let menu = NSMenu()
        for window in app.windows {
            let title = window.title.isEmpty ? app.name : window.title
            let item = ClosureMenuItem(title, symbol: window.isMinimized ? "minus.square" : "macwindow") {
                WindowList.focus(window)
                model.refreshSoon()
            }
            menu.addItem(item)
        }
        return menu
    }

    static func contextMenu(for item: BarItem) -> NSMenu {
        let app = item.app
        let menu = NSMenu()

        if !app.windows.isEmpty {
            for window in app.windows {
                let title = window.title.isEmpty ? app.name : window.title
                let w = ClosureMenuItem(title, symbol: window.isMinimized ? "minus.square" : "macwindow") {
                    WindowList.focus(window)
                    model.refreshSoon()
                }
                if item.window == window { w.state = .on }
                menu.addItem(w)
            }
            menu.addItem(.separator())
        }

        if let window = item.window {
            menu.add(window.isMinimized ? "Restore" : "Minimize") {
                window.isMinimized ? WindowList.focus(window) : WindowList.minimize(window)
                model.refreshSoon()
            }
            menu.add("Close Window") { WindowList.close(window); model.refreshSoon() }
            menu.addItem(.separator())
        }

        if let running = app.runningApp {
            menu.add("New Window / Reopen") { SystemActions.open(path: app.path) }
            menu.add(running.isHidden ? "Unhide \(app.name)" : "Hide \(app.name)") {
                if running.isHidden { running.unhide() } else { running.hide() }
                model.refreshSoon()
            }
            menu.add("Hide Others") {
                for other in NSWorkspace.shared.runningApplications
                    where other.processIdentifier != running.processIdentifier && other.activationPolicy == .regular {
                    other.hide()
                }
                WindowList.activate(pid: running.processIdentifier)
            }
        } else if !app.isFolder {
            menu.add("Launch \(app.name)") { SystemActions.open(path: app.path) }
        } else {
            menu.add("Open") { SystemActions.open(path: app.path) }
        }

        menu.addItem(.separator())
        if app.isFavorite {
            let move = NSMenuItem(title: "Move", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            sub.add("Move to First") { prefs.moveFavorite(app.path, .first) }
            sub.add("Move Back") { prefs.moveFavorite(app.path, .back) }
            sub.add("Move Forward") { prefs.moveFavorite(app.path, .forward) }
            sub.add("Move to Last") { prefs.moveFavorite(app.path, .last) }
            move.submenu = sub
            menu.addItem(move)
            menu.add("Remove from Favorites", symbol: "pin.slash") { prefs.toggleFavorite(app.path) }
        } else {
            menu.add("Add to Favorites", symbol: "pin") { prefs.toggleFavorite(app.path) }
            if let bundleID = app.bundleID {
                menu.add("Add to Exclusions", symbol: "eye.slash") { prefs.exclude(bundleID) }
            }
        }
        menu.add("Show in Finder", symbol: "folder") {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.path)])
        }

        if let running = app.runningApp {
            menu.addItem(.separator())
            menu.add("Quit \(app.name)") { running.terminate(); model.refreshSoon() }
            menu.add("Force Quit \(app.name)") { running.forceTerminate(); model.refreshSoon() }
            if app.isUnresponsive {
                menu.add("Force Relaunch \(app.name)", symbol: "arrow.clockwise") {
                    AppHealth.forceRelaunch(running, path: app.path)
                }
            }
        }
        return menu
    }
}
