import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettings().tabItem { Label("Appearance", systemImage: "paintbrush") }
            AppsSettings().tabItem { Label("Apps", systemImage: "square.grid.2x2") }
            AreasSettings().tabItem { Label("Areas", systemImage: "rectangle.split.3x1") }
            PermissionsSettings().tabItem { Label("Permissions", systemImage: "lock.shield") }
        }
        .frame(width: 620, height: 520)
    }
}

private struct GeneralSettings: View {
    @ObservedObject var prefs = Prefs.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Bar") {
                Picker("Position on screen", selection: $prefs.position) {
                    Text("Bottom").tag(BarPosition.bottom)
                    Text("Top").tag(BarPosition.top)
                    Text("Left").tag(BarPosition.left)
                    Text("Right").tag(BarPosition.right)
                }
                if DockController.occupiedEdge == prefs.position && !prefs.docklessMode {
                    Text("The Dock is on the same screen edge. Enable Dock-less mode or move the Dock.")
                        .font(.caption).foregroundStyle(.orange)
                }
                Picker("Size", selection: $prefs.size) {
                    Text("Small").tag(BarSize.small)
                    Text("Medium").tag(BarSize.medium)
                    Text("Large").tag(BarSize.large)
                }
                Picker("Alignment", selection: $prefs.alignment) {
                    Text("Left").tag(BarAlignment.leading)
                    Text("Center").tag(BarAlignment.center)
                }
                Toggle("Automatically hide and show the bar", isOn: $prefs.autoHide)
                Toggle("Show on all displays", isOn: $prefs.allDisplays)
                if prefs.allDisplays {
                    Toggle("Only show windows on the bar's own display", isOn: $prefs.windowsOnOwnDisplay)
                    Toggle("Show favorites on every display", isOn: $prefs.favoritesOnAllDisplays)
                        .disabled(!prefs.windowsOnOwnDisplay)
                }
                Toggle("Keep resized windows from going under the bar", isOn: $prefs.keepWindowsClear)
                    .disabled(prefs.autoHide)
            }
            Section("Behaviour") {
                Toggle("Group windows by app", isOn: $prefs.groupWindows)
                Toggle("Left-click to display grouped window list", isOn: $prefs.groupClickShowsList)
                    .disabled(!prefs.groupWindows)
                Toggle("Clicking the active app hides it when it has one window", isOn: $prefs.clickActiveToHide)
                Toggle("Display window previews", isOn: $prefs.showPreviews)
                Toggle("Show app badges", isOn: $prefs.showBadges)
                Toggle("Flash apps that want attention", isOn: $prefs.flashAttention)
            }
            Section("Dock") {
                Toggle("Dock-less mode", isOn: $prefs.docklessMode)
                Text("Hides the Dock by giving it an extreme auto-hide delay. Turning it off restores your previous Dock settings.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Updates") {
                Picker("Check for updates", selection: $prefs.updateFrequency) {
                    Text("Daily").tag(UpdateFrequency.daily)
                    Text("Weekly").tag(UpdateFrequency.weekly)
                    Text("Never").tag(UpdateFrequency.never)
                }
                HStack {
                    Text("Version \(UpdateChecker.shared.currentVersion)")
                        .foregroundStyle(.secondary)
                    if let last = UpdateChecker.shared.lastCheck {
                        Text("· last checked \(last, format: .relative(presentation: .named))")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Check Now") { UpdateChecker.shared.check(userInitiated: true) }
                }
                .font(.callout)
            }
            Section {
                Toggle("Open on login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AppearanceSettings: View {
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Theme", selection: $prefs.theme) {
                    Text("Glass").tag(BarTheme.glass)
                    Text("Light").tag(BarTheme.light)
                    Text("Dark").tag(BarTheme.dark)
                    Text("Custom").tag(BarTheme.custom)
                }
                .pickerStyle(.segmented)
                if prefs.theme != .glass {
                    Slider(value: $prefs.backgroundOpacity, in: 0.2...1) { Text("Background opacity") }
                }
                if prefs.theme == .custom {
                    ColorPicker("Background color", selection: $prefs.backgroundHex.asColor, supportsOpacity: false)
                    ColorPicker("Foreground color", selection: $prefs.foregroundHex.asColor, supportsOpacity: false)
                }
                ColorPicker("Highlight color", selection: $prefs.highlightHex.asColor, supportsOpacity: false)
                ColorPicker("Badge color", selection: $prefs.badgeHex.asColor, supportsOpacity: false)
            }
            Section("Display") {
                Toggle("Show app titles", isOn: $prefs.showTitles)
                    .disabled(prefs.position.isVertical)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AppsSettings: View {
    @ObservedObject var prefs = Prefs.shared
    @State private var selectedFavorite: String?
    @State private var selectedExcluded: String?

    var body: some View {
        Form {
            Section("Running apps") {
                Picker("App order", selection: $prefs.appOrder) {
                    Text("Launch order").tag(AppOrder.launch)
                    Text("Alphabetical").tag(AppOrder.alphabetical)
                    Text("Manual (drag to arrange)").tag(AppOrder.manual)
                }
                Toggle("Only show apps on the current Space", isOn: $prefs.currentSpaceOnly)
                Toggle("Exclude apps with zero windows", isOn: $prefs.excludeZeroWindowApps)
            }
            Section("Favorites") {
                List(selection: $selectedFavorite) {
                    ForEach(prefs.favorites, id: \.self) { path in
                        HStack {
                            Image(nsImage: IconCache.icon(path)).resizable().frame(width: 18, height: 18)
                            Text(FileManager.default.displayName(atPath: path))
                        }
                        .tag(path)
                    }
                    .onMove { prefs.favorites.move(fromOffsets: $0, toOffset: $1) }
                }
                .frame(minHeight: 140)
                HStack {
                    Button("Add a folder or application…") { addFavorite() }
                    Button("Remove") {
                        if let s = selectedFavorite { prefs.favorites.removeAll { $0 == s } }
                    }
                    .disabled(selectedFavorite == nil)
                }
            }
            Section("Excluded apps") {
                if prefs.excludedBundleIDs.isEmpty {
                    Text("Right-click an app in the bar and choose Add to Exclusions.").foregroundStyle(.secondary)
                } else {
                    List(selection: $selectedExcluded) {
                        ForEach(prefs.excludedBundleIDs, id: \.self) { Text($0).tag($0) }
                    }
                    .frame(minHeight: 80)
                    Button("Remove from Exclusions") {
                        if let s = selectedExcluded { prefs.excludedBundleIDs.removeAll { $0 == s } }
                    }
                    .disabled(selectedExcluded == nil)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func addFavorite() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !prefs.isFavorite(url.standardizedFileURL.path) {
            prefs.favorites.append(url.standardizedFileURL.path)
        }
    }
}

private struct AreasSettings: View {
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        Form {
            Section("Standard items") {
                Toggle("Show menu", isOn: $prefs.showMenu)
                Toggle("Show Trash", isOn: $prefs.showTrash)
                Toggle("Show Sound", isOn: $prefs.showSound)
                Toggle("Show Battery", isOn: $prefs.showBattery)
                Toggle("Show Desktop button", isOn: $prefs.showDesktopButton)
            }
            Section("Clock") {
                Toggle("Show Clock", isOn: $prefs.showClock)
                Toggle("Show date", isOn: $prefs.clockShowDate).disabled(!prefs.showClock)
                Toggle("Show seconds", isOn: $prefs.clockShowSeconds).disabled(!prefs.showClock)
            }
        }
        .formStyle(.grouped)
    }
}

private struct PermissionsSettings: View {
    @State private var axTrusted = AX.isTrusted
    @State private var screenRecording = WindowPreviews.hasPermission
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                row("Accessibility", granted: axTrusted,
                    detail: "Required to list, raise, minimize, resize and close windows.") {
                    AX.requestTrust()
                    open("Privacy_Accessibility")
                }
                row("Screen Recording", granted: screenRecording,
                    detail: "Allows window previews. OpenBar must relaunch after granting.") {
                    WindowPreviews.requestPermission()
                    open("Privacy_ScreenCapture")
                }
                row("Full Disk Access", granted: nil,
                    detail: "Optional. Lets OpenBar see whether the Trash is empty.") {
                    open("Privacy_AllFiles")
                }
            }
            Section {
                Button("Relaunch OpenBar") { relaunch() }
            }
        }
        .formStyle(.grouped)
        .onReceive(timer) { _ in
            axTrusted = AX.isTrusted
            screenRecording = WindowPreviews.hasPermission
        }
    }

    private func row(_ title: String, granted: Bool?, detail: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top) {
            Image(systemName: granted == true ? "checkmark.circle.fill" : (granted == false ? "xmark.circle.fill" : "circle.dashed"))
                .foregroundStyle(granted == true ? .green : (granted == false ? .red : .secondary))
            VStack(alignment: .leading) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if granted != true { Button("Open Settings…", action: action) }
        }
    }

    private func open(_ anchor: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!)
    }

    private func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5; open \"\(path)\""]
        try? task.run()
        NSApp.terminate(nil)
    }
}
