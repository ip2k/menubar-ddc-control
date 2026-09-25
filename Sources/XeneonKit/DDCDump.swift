import Foundation

/// Every VCP value a monitor answers for, with its identity and capabilities string: a
/// human-readable JSON record for debugging, sharing and writing settings back.
public struct DDCDump: Codable, Equatable, Sendable {
    public struct Display: Codable, Equatable, Sendable {
        public var name: String?
        public var manufacturerID: String
        public var vendor: UInt32
        public var model: UInt32
    }

    public struct Value: Codable, Equatable, Sendable {
        /// Hex, e.g. "0x10", so the file reads like the MCCS tables.
        public var code: String
        public var name: String
        public var current: Int
        public var maximum: Int
        /// Whether loading this file writes the value back.
        public var restorable: Bool
    }

    public var format = "xeneonkit-ddc-dump/1"
    public var capturedAt: Date
    public var display: Display
    public var capabilities: String
    public var values: [Value]
    /// Codes that were read but did not answer.
    public var unanswered: [String]

    /// The writable subset, in the form `DDCChannel.restore` takes.
    public var restorableState: DisplayState {
        var state: [UInt8: Int] = [:]
        for value in values where value.restorable {
            if let code = Self.parse(value.code) { state[code.rawValue] = value.current }
        }
        return DisplayState(values: state, capturedAt: capturedAt)
    }

    /// Whether this dump was taken from the same kind of monitor (vendor and model).
    public func matches(_ identity: EDIDIdentity) -> Bool {
        display.vendor == identity.vendor && display.model == identity.model
    }

    static func parse(_ text: String) -> VCPCode? {
        let hex = text.lowercased().hasPrefix("0x") ? String(text.dropFirst(2)) : text
        return UInt8(hex, radix: 16).map(VCPCode.init(rawValue:))
    }

    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

extension DDCChannel {
    /// Reads every code the capabilities string advertises. Never writes. Blocking.
    public func dump(identity: EDIDIdentity, capabilities: Capabilities?) -> DDCDump {
        let restorable = Set(DisplayState.restorableCodes)
        let codes = capabilities.map { Array($0.vcp.keys).sorted() } ?? DisplayState.restorableCodes
        var values: [DDCDump.Value] = []
        var unanswered: [String] = []
        for code in codes {
            if let reading = try? readVCP(code) {
                values.append(.init(code: code.description, name: VCPNames.featureName(code), current: reading.current,
                                    maximum: reading.maximum, restorable: restorable.contains(code)))
            } else {
                unanswered.append(code.description)
            }
        }
        return DDCDump(
            capturedAt: .now,
            display: .init(name: identity.name, manufacturerID: identity.manufacturerID, vendor: identity.vendor, model: identity.model),
            capabilities: capabilities?.raw ?? "",
            values: values,
            unanswered: unanswered
        )
    }
}

extension VCPNames {
    /// MCCS 2.2 feature names for the codes monitors commonly advertise.
    public static func featureName(_ code: VCPCode) -> String {
        let names: [UInt8: String] = [
            0x02: "New control value", 0x04: "Restore factory defaults", 0x05: "Restore brightness and contrast",
            0x06: "Restore geometry", 0x08: "Restore colour defaults", 0x0B: "Colour temperature increment",
            0x0C: "Colour temperature request", 0x10: "Brightness", 0x12: "Contrast", 0x14: "Colour preset",
            0x16: "Red gain", 0x18: "Green gain", 0x1A: "Blue gain", 0x52: "Active control", 0x60: "Input source",
            0x62: "Audio volume", 0x72: "Gamma", 0x87: "Sharpness", 0xAC: "Horizontal frequency",
            0xAE: "Vertical frequency", 0xB2: "Flat-panel sub-pixel layout", 0xB6: "Display technology type",
            0xC6: "Application enable key", 0xC8: "Display controller type", 0xC9: "Display firmware level",
            0xCA: "OSD", 0xCC: "OSD language", 0xD6: "Power mode", 0xDF: "VCP version",
        ]
        return names[code.rawValue] ?? (code.rawValue >= 0xE0 ? "Manufacturer specific" : "Unknown")
    }
}
