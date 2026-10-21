import AppKit

enum UpdateFrequency: String, CaseIterable, Identifiable {
    case daily, weekly, never
    var id: String { rawValue }

    var interval: TimeInterval? {
        switch self {
        case .daily: 86_400
        case .weekly: 604_800
        case .never: nil
        }
    }
}

/// Checks GitHub releases for a newer version.
final class UpdateChecker {
    static let shared = UpdateChecker()

    private let latestURL = URL(string: "https://api.github.com/repos/saenai255/openbar/releases/latest")!
    private let lastCheckKey = "lastUpdateCheck"
    private let skippedKey = "skippedUpdateVersion"
    private var timer: Timer?
    private var checking = false

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    var lastCheck: Date? { UserDefaults.standard.object(forKey: lastCheckKey) as? Date }

    func start() {
        checkIfDue()
        // Hourly tick so a Mac that stays awake for days still checks on schedule.
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in self?.checkIfDue() }
    }

    private func checkIfDue() {
        guard let interval = Prefs.shared.updateFrequency.interval else { return }
        if let lastCheck, Date().timeIntervalSince(lastCheck) < interval { return }
        check(userInitiated: false)
    }

    func check(userInitiated: Bool) {
        guard !checking else { return }
        checking = true
        var request = URLRequest(url: latestURL, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("OpenBar/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, response, error in
            let release = data.flatMap { try? JSONDecoder().decode(Release.self, from: $0) }
            let ok = (response as? HTTPURLResponse)?.statusCode == 200 && release != nil
            DispatchQueue.main.async {
                self.checking = false
                if ok { UserDefaults.standard.set(Date(), forKey: self.lastCheckKey) }
                self.handle(release: ok ? release : nil, error: error, userInitiated: userInitiated)
            }
        }.resume()
    }

    private func handle(release: Release?, error: Error?, userInitiated: Bool) {
        guard let release else {
            if userInitiated {
                alert("Couldn’t check for updates.", info: error?.localizedDescription ?? "GitHub didn’t return release information.")
            }
            return
        }
        let latest = release.version
        guard Self.isNewer(latest, than: currentVersion) else {
            if userInitiated { alert("You’re up to date.", info: "OpenBar \(currentVersion) is the latest version.") }
            return
        }
        if !userInitiated && UserDefaults.standard.string(forKey: skippedKey) == latest { return }
        offer(release)
    }

    private func offer(_ release: Release) {
        let viaHomebrew = Self.isHomebrewInstall
        let alert = NSAlert()
        alert.messageText = "OpenBar \(release.version) is available"
        alert.informativeText = viaHomebrew
            ? "You have \(currentVersion). Update with:\n\nbrew upgrade --cask openbar"
            : "You have \(currentVersion)."
        alert.addButton(withTitle: viaHomebrew ? "Copy Command" : "Download")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Skip This Version")
        alert.addButton(withTitle: "Release Notes")
        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if viaHomebrew {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("brew upgrade --cask openbar", forType: .string)
            } else {
                NSWorkspace.shared.open(release.dmgURL ?? release.htmlURL)
            }
        case .alertThirdButtonReturn:
            UserDefaults.standard.set(release.version, forKey: skippedKey)
        case NSApplication.ModalResponse(rawValue: NSApplication.ModalResponse.alertThirdButtonReturn.rawValue + 1):
            NSWorkspace.shared.open(release.htmlURL)
        default:
            break
        }
    }

    private func alert(_ title: String, info: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = info
        NSApp.activate()
        alert.runModal()
    }

    private static var isHomebrewInstall: Bool {
        ["/opt/homebrew/Caskroom/openbar", "/usr/local/Caskroom/openbar"]
            .contains { FileManager.default.fileExists(atPath: $0) }
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ v: String) -> [Int] {
            v.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                .split(separator: "-").first.map { $0.split(separator: ".").map { Int($0) ?? 0 } } ?? []
        }
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private struct Release: Decodable {
        let tagName: String
        let htmlURL: URL
        let assets: [Asset]

        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: URL

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case assets
        }

        var version: String { tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV")) }
        var dmgURL: URL? { assets.first { $0.name.hasSuffix(".dmg") }?.browserDownloadURL }
    }
}
