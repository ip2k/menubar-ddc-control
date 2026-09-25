import Foundation

/// A monitor's writable settings at one moment, read without writing anything.
public struct DisplayState: Codable, Equatable, Sendable {
    public var values: [UInt8: Int]
    public var capturedAt: Date

    public init(values: [UInt8: Int], capturedAt: Date = .now) {
        self.values = values
        self.capturedAt = capturedAt
    }

    /// The settings a restore writes back.
    public static let restorableCodes: [VCPCode] = [
        .colorPreset, .colorTemperatureRequest, .redGain, .greenGain, .blueGain,
        .brightness, .contrast, .sharpness, .osdLanguage,
    ]

    public subscript(code: VCPCode) -> Int? { values[code.rawValue] }

    /// Codes whose current value differs from this state.
    public func differences(from other: DisplayState) -> [VCPCode] {
        values.keys.sorted().map { VCPCode($0) }.filter { other[$0] != self[$0] }
    }
}

/// What a restore or reset managed to do, checked by reading every value back.
public struct RestoreReport: Sendable, Equatable {
    public struct Mismatch: Sendable, Equatable {
        public var code: VCPCode
        public var wanted: Int
        public var actual: Int?
    }

    public var mismatches: [Mismatch] = []
    /// VCP 0x08 was sent because the monitor ignored direct gain writes.
    public var usedColorDefaults = false
    public var final: DisplayState?

    public var succeeded: Bool { mismatches.isEmpty }
}

extension DDCChannel {
    /// Reads every restorable setting the monitor answers for. Never writes.
    public func captureState(supported: (VCPCode) -> Bool = { _ in true }) -> DisplayState {
        var values: [UInt8: Int] = [:]
        for code in DisplayState.restorableCodes where supported(code) {
            if let reading = try? readVCP(code) { values[code.rawValue] = reading.current }
        }
        return DisplayState(values: values)
    }

    private func current(_ code: VCPCode) -> Int? { try? readVCP(code).current }

    /// Writes `value` unless it is already set, then reads it back.
    private func writeVerified(_ code: VCPCode, _ value: Int, settle: TimeInterval = 0.3) -> Bool {
        if current(code) == value { return true }
        guard (try? writeVCP(code, UInt16(clamping: value))) != nil else { return false }
        Thread.sleep(forTimeInterval: settle)
        return current(code) == value
    }

    /// Puts the monitor back into `state`. Order matters: selecting a preset can reset the
    /// temperature and gains, so the preset goes first and luminance last. Some monitors
    /// (the Xeneon Edge) ignore direct gain writes; their calibrated gains come back only
    /// through "restore colour defaults" (0x08), which is tried when `allowColorDefaults` is set.
    /// Blocking; call off the main thread.
    public func restore(_ state: DisplayState, allowColorDefaults: Bool) -> RestoreReport {
        var report = RestoreReport()

        if let preset = state[.colorPreset] {
            _ = writeVerified(.colorPreset, preset, settle: 1.0)
        }
        let userPreset = state[.colorPreset].map { VCPNames.isUserPreset(UInt8(clamping: $0)) } ?? false
        // In a User preset 0x0C is not independent: writing it would select another preset.
        if !userPreset, let temperature = state[.colorTemperatureRequest] {
            _ = writeVerified(.colorTemperatureRequest, temperature)
        }

        let gains: [VCPCode] = [.redGain, .greenGain, .blueGain].filter { state[$0] != nil }
        let gainsMatch = { gains.allSatisfy { self.current($0) == state[$0] } }
        if !gainsMatch() {
            for code in gains { _ = writeVerified(code, state[code]!) }
            if !gainsMatch(), allowColorDefaults {
                _ = try? writeVCP(.restoreColorDefaults, 1)
                report.usedColorDefaults = true
                Thread.sleep(forTimeInterval: 2.5)
                if let preset = state[.colorPreset] { _ = writeVerified(.colorPreset, preset, settle: 1.0) }
            }
        }

        for code in [VCPCode.brightness, .contrast, .sharpness, .osdLanguage] {
            if let value = state[code] { _ = writeVerified(code, value) }
        }

        let final = captureState { state[$0] != nil }
        report.final = final
        for code in state.values.keys.sorted().map({ VCPCode($0) }) where final[code] != state[code] {
            if code == .colorTemperatureRequest, userPreset { continue }
            report.mismatches.append(.init(code: code, wanted: state[code]!, actual: final[code]))
        }
        return report
    }

    /// MCCS factory reset (0x04) followed by restore colour defaults (0x08), which on the Xeneon
    /// Edge is what brings back its factory-calibrated gains. Returns the settings afterwards.
    /// Blocking; call off the main thread.
    public func resetToFactoryDefaults(capabilities: Capabilities?) -> DisplayState {
        let advertises = { (code: VCPCode) in capabilities?.supports(code) ?? true }
        if advertises(.restoreFactoryDefaults) {
            _ = try? writeVCP(.restoreFactoryDefaults, 1)
            Thread.sleep(forTimeInterval: 3)
        }
        if advertises(.restoreColorDefaults) {
            _ = try? writeVCP(.restoreColorDefaults, 1)
            Thread.sleep(forTimeInterval: 2.5)
        }
        return captureState { capabilities?.supports($0) ?? true }
    }
}
