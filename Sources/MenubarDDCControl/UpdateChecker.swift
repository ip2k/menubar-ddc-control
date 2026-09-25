import AppKit
import DDCKit
import Foundation
import Observation

/// Checks this project's GitHub releases for a newer version, weekly by default. It only reads
/// the public releases API (no account, nothing sent but the request itself) and never installs
/// anything: it offers the download, or the `brew upgrade` command when Homebrew installed the app.
@MainActor @Observable
final class UpdateChecker {
    static let repository = "ip2k/menubar-ddc-control"
    static let interval: TimeInterval = 7 * 24 * 60 * 60
    static let caskName = "menubar-ddc-control"

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String)
        case failed(String)
    }

    var status: Status = .idle
    private(set) var available: GitHubRelease?

    var checksAutomatically: Bool {
        didSet { UserDefaults.standard.set(checksAutomatically, forKey: Keys.automatic) }
    }

    var lastChecked: Date? { UserDefaults.standard.object(forKey: Keys.lastChecked) as? Date }

    @ObservationIgnored private var timer: Timer?

    private enum Keys {
        static let automatic = "checksForUpdatesAutomatically"
        static let lastChecked = "lastUpdateCheck"
        static let skipped = "skippedUpdateVersion"
    }

    static var currentVersion: AppVersion {
        AppVersion(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0") ?? AppVersion("0")!
    }

    /// Homebrew casks are installed from the Caskroom; such installs should update through brew.
    static var installedWithHomebrew: Bool {
        ["/opt/homebrew/Caskroom", "/usr/local/Caskroom"].contains {
            FileManager.default.fileExists(atPath: "\($0)/\(caskName)")
        }
    }

    init() {
        checksAutomatically = UserDefaults.standard.object(forKey: Keys.automatic) as? Bool ?? true
    }

    /// Checks now if a week has passed, then keeps checking while the app runs.
    func start() {
        checkIfDue()
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkIfDue() }
        }
    }

    private func checkIfDue() {
        guard checksAutomatically, !Self.isDevelopmentBuild else { return }
        if let lastChecked, Date.now.timeIntervalSince(lastChecked) < Self.interval { return }
        Task { await check(userInitiated: false) }
    }

    /// Builds run straight from `swift build` or with `--debug-*` flags don't nag.
    private static var isDevelopmentBuild: Bool {
        CommandLine.arguments.contains { $0.hasPrefix("--debug") } || Bundle.main.bundleURL.pathExtension != "app"
    }

    func check(userInitiated: Bool) async {
        status = .checking
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MenubarDDCControl/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else {
                status = code == 404 ? .upToDate : .failed("GitHub answered \(code)")
                return
            }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            UserDefaults.standard.set(Date.now, forKey: Keys.lastChecked)
            guard release.isUpdate(over: Self.currentVersion), let version = release.version else {
                available = nil
                status = .upToDate
                return
            }
            available = release
            status = .available(version: version.description)
            let skipped = UserDefaults.standard.string(forKey: Keys.skipped)
            if userInitiated || skipped != version.description { prompt(for: release, version: version) }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func prompt(for release: GitHubRelease, version: AppVersion) {
        let alert = NSAlert()
        alert.messageText = "Menubar DDC Control \(version) is available"
        let notes = release.body.map { String($0.prefix(600)) } ?? ""
        let how = Self.installedWithHomebrew
            ? "Update with: brew upgrade --cask \(Self.caskName)"
            : "Download the new version, open the disk image, and drag the app to Applications to replace this one."
        alert.informativeText = "You have \(Self.currentVersion).\n\n\(how)" + (notes.isEmpty ? "" : "\n\n\(notes)")
        alert.addButton(withTitle: Self.installedWithHomebrew ? "Copy Command" : "Download")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Skip This Version")
        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if Self.installedWithHomebrew {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("brew upgrade --cask \(Self.caskName)", forType: .string)
            } else {
                NSWorkspace.shared.open(release.downloadURL)
            }
        case .alertThirdButtonReturn:
            UserDefaults.standard.set(version.description, forKey: Keys.skipped)
        default:
            break
        }
    }
}
