import CoreGraphics
import Foundation
import Observation
import SwiftUI
import XeneonKit

/// One external display: its hardware controls (DDC/CI), software colour and ICC profile,
/// and the state it was in when the app launched.
@MainActor @Observable
final class DisplayModel: Identifiable {
    enum Link: Equatable {
        case probing
        case hardware
        /// The connection carries no DDC/CI (e.g. the M1-generation built-in HDMI port).
        case softwareOnly
    }

    /// Controls read on every refresh.
    static let liveCodes: [VCPCode] = [
        .brightness, .contrast, .sharpness, .colorPreset, .colorTemperatureIncrement,
        .colorTemperatureRequest, .redGain, .greenGain, .blueGain, .osdLanguage,
    ]
    /// Read-only facts, read once per probe.
    static let infoCodes: [VCPCode] = [.verticalFrequency, .displayTechnology, .controllerManufacturer, .vcpVersion]
    static let gainCodes: [VCPCode] = [.redGain, .greenGain, .blueGain]
    /// Writing a preset can reset temperature and gains, so they are written after it.
    static let snapshotOrder: [VCPCode] = [
        .colorPreset, .colorTemperatureRequest, .redGain, .greenGain, .blueGain, .brightness, .contrast, .sharpness,
    ]

    private(set) var display: ExternalDisplay
    let name: String
    /// The display's persistent key; a replacement `display` always has the same one.
    let id: String
    var link: Link = .probing
    var capabilities: Capabilities?
    var readings: [VCPCode: VCPReading] = [:]
    var info: [VCPCode: VCPReading] = [:]
    var message: String?
    var profile: ICCProfile?
    /// A restore or reset is running; controls are disabled meanwhile.
    var isBusy = false
    /// Codes the monitor accepted a write for without changing (the Edge's RGB gains).
    var ignoredCodes: Set<VCPCode> = []
    var software: SoftwareAdjustment {
        didSet { if software != oldValue { app?.softwareChanged(self) } }
    }

    /// Hardware settings read before this launch wrote anything. Writes are refused until it exists.
    private(set) var launchState: DisplayState?
    private(set) var launchProfile: ICCProfile?

    @ObservationIgnored weak var app: AppModel?
    @ObservationIgnored private var editedAt: [VCPCode: Date] = [:]
    @ObservationIgnored private var rereadTask: Task<Void, Never>?
    @ObservationIgnored private var verifyTasks: [VCPCode: Task<Void, Never>] = [:]

    var displayID: CGDirectDisplayID { display.id }

    init(display: ExternalDisplay, name: String, software: SoftwareAdjustment, app: AppModel) {
        self.display = display
        id = display.persistentKey
        self.name = name
        self.software = software
        self.app = app
        profile = ICCProfiles.current(for: display.id)
        launchProfile = profile
        if display.quirks.ignoresGainWrites { ignoredCodes.formUnion(Self.gainCodes) }
        configureChannel()
    }

    func replace(display newDisplay: ExternalDisplay) {
        display = newDisplay
        configureChannel()
    }

    private func configureChannel() {
        display.ddc?.onWriteError = { [weak self] code, error in
            Task { @MainActor in self?.message = "Couldn't set \(code): \(error)" }
        }
    }

    // MARK: Reading

    func supports(_ code: VCPCode) -> Bool {
        if let capabilities, !capabilities.vcp.isEmpty { return capabilities.supports(code) && readings[code] != nil }
        return readings[code] != nil
    }

    /// For write-only commands (the restore codes), which never produce a reading.
    func advertises(_ code: VCPCode) -> Bool {
        capabilities?.supports(code) ?? false
    }

    func probe() async {
        guard let ddc = display.ddc else {
            link = .softwareOnly
            return
        }
        link = .probing
        let (caps, brightness) = await Task.detached {
            (try? ddc.capabilities(), try? ddc.readVCP(.brightness))
        }.value
        guard caps != nil || brightness != nil else {
            link = .softwareOnly
            return
        }
        capabilities = caps
        if launchState == nil {
            // Read-only, and before `link` becomes `.hardware`, so nothing can have been written yet.
            let state = await Task.detached { ddc.captureState { caps?.supports($0) ?? true } }.value
            launchState = state
            app?.recordOriginal(state, profile: launchProfile, for: self)
        }
        if let brightness { readings[.brightness] = brightness }
        link = .hardware
        message = nil
        await refresh()
        let infoCodes = Self.infoCodes.filter { caps?.supports($0) ?? true }
        info = await Self.read(infoCodes, from: ddc)
    }

    /// Re-reads the live controls, keeping values the user changed in the last moment so a
    /// slider being dragged does not jump back.
    func refresh() async {
        guard link == .hardware, let ddc = display.ddc else { return }
        let codes = Self.liveCodes.filter { code in capabilities.map { $0.vcp.isEmpty || $0.supports(code) } ?? true }
        let fresh = await Self.read(codes, from: ddc)
        let cutoff = Date.now.addingTimeInterval(-1.5)
        for (code, reading) in fresh where (editedAt[code] ?? .distantPast) < cutoff {
            readings[code] = reading
        }
        syncReferenceWhitePoint()
    }

    private static func read(_ codes: [VCPCode], from ddc: DDCChannel) async -> [VCPCode: VCPReading] {
        await Task.detached {
            var result: [VCPCode: VCPReading] = [:]
            for code in codes {
                if let reading = try? ddc.readVCP(code) { result[code] = reading }
            }
            return result
        }.value
    }

    private func scheduleReread(after delay: Duration = .milliseconds(600)) {
        rereadTask?.cancel()
        rereadTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }

    /// The white the monitor's current preset produces, which the GPU white point shifts from.
    var presetKelvin: Int? {
        guard let request = readings[.colorTemperatureRequest]?.current else { return nil }
        return ColorTemperature.kelvin(forRequest: request, increment: max(value(.colorTemperatureIncrement), 1))
    }

    private func syncReferenceWhitePoint() {
        guard let kelvin = presetKelvin.map(Double.init), kelvin != software.referenceWhitePoint else { return }
        let unshifted = abs(software.whitePoint - software.referenceWhitePoint) < 1
        software.referenceWhitePoint = kelvin
        if unshifted { software.whitePoint = kelvin }
    }

    // MARK: Writing

    func value(_ code: VCPCode) -> Int { readings[code]?.current ?? 0 }
    func maximum(_ code: VCPCode) -> Int { max(readings[code]?.maximum ?? 100, 1) }

    func binding(_ code: VCPCode) -> Binding<Double> {
        Binding(get: { Double(self.value(code)) }, set: { self.set(code, Int($0.rounded())) })
    }

    var isUserPresetActive: Bool {
        readings[.colorPreset].map { VCPNames.isUserPreset(UInt8(clamping: $0.current)) } ?? false
    }

    var canWrite: Bool { link == .hardware && launchState != nil && !isBusy }

    func set(_ code: VCPCode, _ value: Int) {
        guard canWrite, !ignoredCodes.contains(code), let ddc = display.ddc else { return }
        let clamped = min(max(value, 0), readings[code]?.maximum ?? Int(UInt16.max))
        readings[code, default: VCPReading(current: clamped, maximum: Int(UInt16.max))].current = clamped
        editedAt[code] = .now
        message = nil
        ddc.enqueueWrite(code, UInt16(clamped))
        if code == .colorPreset { scheduleReread() }
        scheduleVerify(code, clamped)
    }

    /// Reads a control back once the writes stop. A monitor that acknowledges a write but keeps
    /// its old value (the Edge's RGB gains) gets that control disabled rather than a slider that lies.
    private func scheduleVerify(_ code: VCPCode, _ written: Int) {
        guard let ddc = display.ddc else { return }
        verifyTasks[code]?.cancel()
        verifyTasks[code] = Task {
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled,
                  let actual = await Task.detached(operation: { try? ddc.readVCP(code) }).value else { return }
            guard actual.current != written, readings[code]?.current == written else { return }
            readings[code] = actual
            if code == .colorPreset { return }
            ignoredCodes.insert(code)
            message = "\(name) ignores changes to \(Self.title(of: code)) over DDC/CI."
        }
    }

    static func title(of code: VCPCode) -> String {
        switch code {
        case .brightness: "brightness"
        case .contrast: "contrast"
        case .sharpness: "sharpness"
        case .colorPreset: "the colour preset"
        case .colorTemperatureRequest: "the preset white point"
        case .redGain: "red gain"
        case .greenGain: "green gain"
        case .blueGain: "blue gain"
        case .osdLanguage: "the menu language"
        default: "VCP \(code)"
        }
    }

    // MARK: Restore

    /// Whether anything differs from how the display was when the app launched.
    var differsFromLaunch: Bool {
        // Before launch no software adjustment was active: macOS drops them when a process exits.
        if !software.isIdentity || profile?.url != launchProfile?.url { return true }
        guard let launchState else { return false }
        let now = DisplayState(values: Dictionary(uniqueKeysWithValues: readings.map { ($0.key.rawValue, $0.value.current) }))
        let userPreset = launchState[.colorPreset].map { VCPNames.isUserPreset(UInt8(clamping: $0)) } ?? false
        return launchState.differences(from: now).contains { !(userPreset && $0 == .colorTemperatureRequest) }
    }

    /// Puts the monitor, the software adjustment and the ICC profile back as they were at launch.
    func restorePreviousValues() {
        restore(to: launchState, profile: launchProfile, software: .identity.withReference(software.referenceWhitePoint),
                label: "before launch")
    }

    func restore(to state: DisplayState?, profile targetProfile: ICCProfile?, software targetSoftware: SoftwareAdjustment, label: String) {
        software = targetSoftware
        if targetProfile?.url != profile?.url { app?.assign(targetProfile, to: self) }
        guard link == .hardware, let state, let ddc = display.ddc else { return }
        let allowColorDefaults = advertises(.restoreColorDefaults)
        runExclusive {
            let report = await Task.detached { ddc.restore(state, allowColorDefaults: allowColorDefaults) }.value
            if report.succeeded {
                self.message = "Restored the settings from \(label)."
            } else {
                let names = report.mismatches.map { Self.title(of: $0.code) }.joined(separator: ", ")
                self.message = "Couldn't restore \(names)."
            }
        }
    }

    func resetToFactoryDefaults() {
        software = SoftwareAdjustment.identity.withReference(software.referenceWhitePoint)
        guard link == .hardware, let ddc = display.ddc else { return }
        let caps = capabilities
        runExclusive {
            _ = await Task.detached { ddc.resetToFactoryDefaults(capabilities: caps) }.value
            self.message = "Reset to factory defaults. Restore Previous Values undoes this."
        }
    }

    /// Sends one MCCS restore command (0x04, 0x05 or 0x08), then re-reads everything.
    func restore(_ command: VCPCode) {
        guard link == .hardware, let ddc = display.ddc else { return }
        runExclusive {
            let sent = await Task.detached { (try? ddc.writeVCP(command, 1)) != nil }.value
            try? await Task.sleep(for: .seconds(2.5))
            self.message = sent ? nil : "The monitor didn't accept the restore command."
        }
    }

    /// Runs `body` with the controls disabled, then re-reads everything.
    private func runExclusive(_ body: @escaping @MainActor () async -> Void) {
        guard !isBusy, let ddc = display.ddc else { return }
        isBusy = true
        Task {
            await Task.detached { ddc.drain() }.value
            await body()
            editedAt = [:]
            await refresh()
            isBusy = false
        }
    }

    // MARK: Snapshots

    func snapshot(named name: String) -> Snapshot {
        var hardware: [UInt8: Int] = [:]
        for code in Self.snapshotOrder where supports(code) {
            if Self.gainCodes.contains(code), !isUserPresetActive { continue }
            if code == .colorTemperatureRequest, isUserPresetActive { continue }
            hardware[code.rawValue] = value(code)
        }
        return Snapshot(name: name, displayKey: id, displayName: self.name, hardware: hardware,
                        software: software, profilePath: profile?.url.path)
    }

    func apply(_ snapshot: Snapshot) {
        let targetProfile = snapshot.profilePath.map { ICCProfile(url: URL(fileURLWithPath: $0), name: "") } ?? profile
        restore(to: DisplayState(values: snapshot.hardware), profile: targetProfile, software: snapshot.software,
                label: "“\(snapshot.name)”")
    }
}

extension SoftwareAdjustment {
    /// No adjustment, with the white point sitting at `kelvin` (the preset's own white).
    func withReference(_ kelvin: Double) -> SoftwareAdjustment {
        var copy = SoftwareAdjustment.identity
        copy.referenceWhitePoint = kelvin
        copy.whitePoint = kelvin
        return copy
    }
}

struct Snapshot: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var displayKey: String
    var displayName: String
    var hardware: [UInt8: Int]
    var software: SoftwareAdjustment
    var profilePath: String?
}
