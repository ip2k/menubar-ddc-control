import CoreGraphics
import Foundation
import Observation
import SwiftUI
import XeneonKit

/// One external display: its hardware controls (DDC/CI), software colour and ICC profile.
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
    var link: Link = .probing
    var capabilities: Capabilities?
    var readings: [VCPCode: VCPReading] = [:]
    var info: [VCPCode: VCPReading] = [:]
    var message: String?
    var profile: ICCProfile?
    var software: SoftwareAdjustment {
        didSet { if software != oldValue { app?.softwareChanged(self) } }
    }

    @ObservationIgnored weak var app: AppModel?
    @ObservationIgnored private var editedAt: [VCPCode: Date] = [:]
    @ObservationIgnored private var rereadTask: Task<Void, Never>?

    /// The display's persistent key; a replacement `display` always has the same one.
    let id: String
    var displayID: CGDirectDisplayID { display.id }

    init(display: ExternalDisplay, name: String, software: SoftwareAdjustment, app: AppModel) {
        self.display = display
        id = display.persistentKey
        self.name = name
        self.software = software
        self.app = app
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

    private func scheduleReread(after delay: Duration = .milliseconds(600), forgettingEdits: Bool = false) {
        rereadTask?.cancel()
        rereadTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            if forgettingEdits { editedAt = [:] }
            await refresh()
        }
    }

    // MARK: Writing

    func value(_ code: VCPCode) -> Int { readings[code]?.current ?? 0 }
    func maximum(_ code: VCPCode) -> Int { max(readings[code]?.maximum ?? 100, 1) }

    func binding(_ code: VCPCode) -> Binding<Double> {
        Binding(get: { Double(self.value(code)) }, set: { self.set(code, Int($0.rounded())) })
    }

    var userPreset: UInt8? {
        capabilities?.vcp[.colorPreset]?.first(where: VCPNames.isUserPreset) ?? 0x0B
    }

    var isUserPresetActive: Bool {
        readings[.colorPreset].map { VCPNames.isUserPreset(UInt8(clamping: $0.current)) } ?? false
    }

    func set(_ code: VCPCode, _ value: Int) {
        guard link == .hardware else { return }
        // RGB gains only take effect in a User preset; switch to one first, as the OSD does.
        if Self.gainCodes.contains(code), !isUserPresetActive, let user = userPreset, supports(.colorPreset) {
            write(.colorPreset, Int(user))
        }
        write(code, value)
        if code == .colorPreset || code == .colorTemperatureRequest { scheduleReread() }
    }

    private func write(_ code: VCPCode, _ value: Int) {
        guard let ddc = display.ddc else { return }
        let clamped = min(max(value, 0), readings[code]?.maximum ?? Int(UInt16.max))
        readings[code, default: VCPReading(current: clamped, maximum: Int(UInt16.max))].current = clamped
        editedAt[code] = .now
        message = nil
        ddc.enqueueWrite(code, UInt16(clamped))
    }

    /// Sends one of the MCCS restore commands (0x04, 0x05, 0x08) and re-reads everything.
    func restore(_ code: VCPCode) {
        guard let ddc = display.ddc else { return }
        Task {
            let result = await Task.detached { Result { try ddc.writeVCP(code, 1) } }.value
            if case .failure(let error) = result { message = "Restore failed: \(error)" }
            scheduleReread(after: .seconds(1.5), forgettingEdits: true)
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
        software = snapshot.software
        if let path = snapshot.profilePath, path != profile?.url.path {
            app?.assign(ICCProfile(url: URL(fileURLWithPath: path), name: ""), to: self)
        }
        guard link == .hardware, let ddc = display.ddc else { return }
        let writes = Self.snapshotOrder.compactMap { code in snapshot.hardware[code.rawValue].map { (code, UInt16(clamping: $0)) } }
        for (code, value) in writes { readings[code]?.current = Int(value) }
        Task {
            let failures = await Task.detached {
                writes.filter { (try? ddc.writeVCP($0.0, $0.1)) == nil }.count
            }.value
            if failures > 0 { message = "\(failures) setting(s) were not accepted" }
            scheduleReread(forgettingEdits: true)
        }
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
