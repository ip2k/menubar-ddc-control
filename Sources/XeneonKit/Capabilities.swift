import Foundation

/// A parsed MCCS capabilities string, e.g.
/// `(prot(monitor)type(LCD)model(RTK)cmds(01 02 03)vcp(10 12 14(01 02 0B) 16)mccs_ver(2.2))`.
public struct Capabilities: Equatable, Sendable {
    public var raw: String
    public var fields: [String: String]
    /// Supported VCP codes; a non-empty array lists the values a non-continuous control accepts.
    public var vcp: [VCPCode: [UInt8]]

    public var model: String? { fields["model"] }
    public var mccsVersion: String? { fields["mccs_ver"] }

    public func supports(_ code: VCPCode) -> Bool { vcp[code] != nil }

    public init(parsing raw: String) {
        self.raw = raw
        var body = Substring(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        if body.hasPrefix("("), body.hasSuffix(")") { body = body.dropFirst().dropLast() }
        fields = Capabilities.topLevelFields(body)
        vcp = Capabilities.parseVCPList(fields["vcp"] ?? "")
    }

    /// Splits `key(value)key(value)…` where values may themselves contain parentheses.
    static func topLevelFields(_ s: Substring) -> [String: String] {
        var result: [String: String] = [:]
        var key = ""
        var value = ""
        var depth = 0
        for ch in s {
            switch (ch, depth) {
            case ("(", 0):
                depth = 1
            case ("(", _):
                depth += 1
                value.append(ch)
            case (")", 1):
                depth = 0
                result[key.trimmingCharacters(in: .whitespaces)] = value
                key = ""
                value = ""
            case (")", _) where depth > 1:
                depth -= 1
                value.append(ch)
            case (_, 0):
                key.append(ch)
            default:
                value.append(ch)
            }
        }
        return result
    }

    /// Parses `10 12 14(01 02 0B) 16`. Some monitors omit the spaces (`101214(01020B)16`),
    /// so codes are read as consecutive hex pairs rather than split on whitespace.
    static func parseVCPList(_ s: String) -> [VCPCode: [UInt8]] {
        var result: [VCPCode: [UInt8]] = [:]
        var last: VCPCode?
        var inValues = false
        var pending = ""
        func flush() {
            guard pending.count == 2, let byte = UInt8(pending, radix: 16) else { pending = ""; return }
            pending = ""
            if inValues, let code = last {
                result[code, default: []].append(byte)
            } else {
                last = VCPCode(byte)
                result[VCPCode(byte)] = result[VCPCode(byte)] ?? []
            }
        }
        for ch in s {
            if ch.isHexDigit {
                pending.append(ch)
                if pending.count == 2 { flush() }
            } else {
                pending = ""
                if ch == "(" { inValues = true } else if ch == ")" { inValues = false }
            }
        }
        return result
    }
}

/// Human names for MCCS values that the UI shows.
public enum VCPNames {
    public static func colorPreset(_ value: UInt8) -> String {
        switch value {
        case 0x01: "sRGB"
        case 0x02: "Native"
        case 0x03: "4000 K"
        case 0x04: "5000 K"
        case 0x05: "6500 K"
        case 0x06: "7500 K"
        case 0x07: "8200 K"
        case 0x08: "9300 K"
        case 0x09: "10000 K"
        case 0x0A: "11500 K"
        case 0x0B: "User 1"
        case 0x0C: "User 2"
        case 0x0D: "User 3"
        default: String(format: "Preset 0x%02X", value)
        }
    }

    public static func osdLanguage(_ value: UInt8) -> String {
        let names: [UInt8: String] = [
            0x01: "Chinese (Traditional)", 0x02: "English", 0x03: "French", 0x04: "German", 0x05: "Italian",
            0x06: "Japanese", 0x07: "Korean", 0x08: "Portuguese (Portugal)", 0x09: "Russian", 0x0A: "Spanish",
            0x0B: "Swedish", 0x0C: "Turkish", 0x0D: "Chinese (Simplified)", 0x0E: "Portuguese (Brazil)",
            0x0F: "Arabic", 0x10: "Bulgarian", 0x11: "Croatian", 0x12: "Czech", 0x13: "Danish", 0x14: "Dutch",
            0x15: "Estonian", 0x16: "Finnish", 0x17: "Greek", 0x18: "Hebrew", 0x19: "Hindi", 0x1A: "Hungarian",
            0x1B: "Latvian", 0x1C: "Lithuanian", 0x1D: "Norwegian", 0x1E: "Polish", 0x1F: "Romanian",
            0x20: "Serbian", 0x21: "Slovak", 0x22: "Slovenian", 0x23: "Thai", 0x24: "Ukrainian", 0x25: "Vietnamese",
        ]
        return names[value] ?? String(format: "Language 0x%02X", value)
    }

    public static func displayTechnology(_ value: Int) -> String {
        let names = ["CRT (shadow mask)", "CRT (aperture grille)", "LCD (TFT)", "LCoS", "Plasma", "OLED", "EL", "Dynamic MEM", "Static MEM"]
        return names.indices.contains(value - 1) ? names[value - 1] : "Unknown (\(value))"
    }

    /// The white point a colour-temperature preset (MCCS 0x03–0x0A) is named for, in kelvin.
    public static func presetKelvin(_ value: UInt8) -> Int? {
        [0x03: 4000, 0x04: 5000, 0x05: 6500, 0x06: 7500, 0x07: 8200, 0x08: 9300, 0x09: 10000, 0x0A: 11500][value]
    }

    /// Presets whose RGB gains are user-editable.
    public static func isUserPreset(_ value: UInt8) -> Bool { (0x0B...0x0D).contains(value) }
}

/// MCCS colour temperature: VCP 0x0C holds `(kelvin - 3000) / increment`, where the
/// increment in kelvin comes from VCP 0x0B.
public enum ColorTemperature {
    public static let baseKelvin = 3000

    public static func kelvin(forRequest value: Int, increment: Int) -> Int {
        baseKelvin + value * increment
    }

    public static func request(forKelvin kelvin: Int, increment: Int) -> Int {
        guard increment > 0 else { return 0 }
        return max(0, (kelvin - baseKelvin) / increment)
    }
}
