import AppKit
import CoreGraphics
import Foundation
import Observation
import XeneonKit

/// Every external display, the installed ICC profiles, saved snapshots, and the gamma
/// baselines that software colour is applied on top of.
@MainActor @Observable
final class AppModel {
    var displays: [DisplayModel] = []
    var selectedID: String?
    var profiles: [ICCProfile] = []
    var snapshots: [Snapshot] = [] {
        didSet { save(snapshots, forKey: Keys.snapshots) }
    }

    /// Each display's ramp as ColorSync loaded it (including any calibration curve).
    @ObservationIgnored private var baselines: [CGDirectDisplayID: GammaRamp] = [:]
    /// Whether this process has changed any gamma table; until then nothing needs restoring.
    @ObservationIgnored private var gammaTouched = false
    @ObservationIgnored private var rescanTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private enum Keys {
        static let snapshots = "snapshots"
        static func software(_ key: String) -> String { "software.\(key)" }
    }

    init() {
        snapshots = load([Snapshot].self, forKey: Keys.snapshots) ?? []
        rescan()
        reloadProfiles()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleRescan() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleRescan() }
        })
    }

    var selected: DisplayModel? {
        displays.first { $0.id == selectedID } ?? displays.first
    }

    // MARK: Displays

    func scheduleRescan() {
        rescanTask?.cancel()
        rescanTask = Task {
            // Display changes arrive in bursts; wait for the last one.
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            rescan()
        }
    }

    func rescan() {
        var next: [DisplayModel] = []
        for display in DisplayDirectory.externalDisplays() {
            let model: DisplayModel
            if let existing = displays.first(where: { $0.id == display.persistentKey }) {
                existing.replace(display: display)
                model = existing
            } else {
                let software = load(SoftwareAdjustment.self, forKey: Keys.software(display.persistentKey)) ?? .identity
                model = DisplayModel(display: display, name: Self.screenName(display.id) ?? display.name, software: software, app: self)
            }
            model.profile = ICCProfiles.current(for: model.displayID)
            next.append(model)
            Task { await model.probe() }
        }
        displays = next
        rebaseline()
    }

    private static func screenName(_ id: CGDirectDisplayID) -> String? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }?.localizedName
    }

    // MARK: Software colour

    /// Captures every display's ColorSync ramp and re-applies software adjustments on top.
    /// Runs after anything that makes ColorSync reload ramps: reconnects, wake, profile changes.
    private func rebaseline() {
        if gammaTouched { SoftwareColor.restoreAll() }
        baselines = [:]
        for model in displays {
            baselines[model.displayID] = SoftwareColor.currentRamp(of: model.displayID)
        }
        gammaTouched = false
        for model in displays where !model.software.isIdentity { applySoftware(model) }
    }

    private func applySoftware(_ model: DisplayModel) {
        guard let baseline = baselines[model.displayID] ?? SoftwareColor.currentRamp(of: model.displayID) else { return }
        baselines[model.displayID] = baseline
        SoftwareColor.apply(baseline.applying(model.software), to: model.displayID)
        gammaTouched = true
    }

    func softwareChanged(_ model: DisplayModel) {
        save(model.software, forKey: Keys.software(model.id))
        applySoftware(model)
    }

    // MARK: ICC profiles

    func reloadProfiles() {
        Task {
            profiles = await Task.detached { ICCProfiles.installedDisplayProfiles() }.value
        }
    }

    /// Profiles that name this display come first; macOS also generates one per display it has seen.
    func profileGroups(for model: DisplayModel) -> (matching: [ICCProfile], other: [ICCProfile]) {
        var all = profiles
        if let current = model.profile, !all.contains(where: { $0.url == current.url }) { all.append(current) }
        let matches = { (p: ICCProfile) in
            p.name.localizedCaseInsensitiveContains(model.name) || p.url.lastPathComponent.localizedCaseInsensitiveContains(model.name)
        }
        return (all.filter(matches), all.filter { !matches($0) })
    }

    func assign(_ profile: ICCProfile?, to model: DisplayModel) {
        guard ICCProfiles.assign(profile, to: model.displayID) else {
            model.message = "ColorSync refused the profile"
            return
        }
        Task {
            // ColorSync loads the new profile's calibration curve asynchronously.
            try? await Task.sleep(for: .milliseconds(500))
            model.profile = ICCProfiles.current(for: model.displayID)
            rebaseline()
        }
    }

    func importProfile(from url: URL, for model: DisplayModel) {
        do {
            let installed = try ICCProfiles.install(fileAt: url)
            assign(ICCProfile(url: installed, name: installed.deletingPathExtension().lastPathComponent), to: model)
            reloadProfiles()
        } catch {
            model.message = "Couldn't install the profile: \(error.localizedDescription)"
        }
    }

    // MARK: Snapshots

    func saveSnapshot(named name: String, of model: DisplayModel) {
        snapshots.append(model.snapshot(named: name))
    }

    func apply(_ snapshot: Snapshot) {
        displays.first { $0.id == snapshot.displayKey }?.apply(snapshot)
    }

    func snapshots(for model: DisplayModel) -> [Snapshot] {
        snapshots.filter { $0.displayKey == model.id }
    }

    // MARK: Persistence

    private func save<T: Encodable>(_ value: T, forKey key: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private func load<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}
