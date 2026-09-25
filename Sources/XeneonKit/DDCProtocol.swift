import Foundation

/// A VCP (Virtual Control Panel) feature code from the VESA MCCS standard.
public struct VCPCode: RawRepresentable, Hashable, Sendable, Comparable, CustomStringConvertible {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public init(_ rawValue: UInt8) { self.rawValue = rawValue }

    public static let restoreFactoryDefaults = VCPCode(0x04)
    public static let restoreBrightnessContrast = VCPCode(0x05)
    public static let restoreColorDefaults = VCPCode(0x08)
    public static let brightness = VCPCode(0x10)
    public static let contrast = VCPCode(0x12)
    public static let colorPreset = VCPCode(0x14)
    public static let redGain = VCPCode(0x16)
    public static let greenGain = VCPCode(0x18)
    public static let blueGain = VCPCode(0x1A)
    public static let sharpness = VCPCode(0x87)
    /// Colour temperature step in kelvin (read-only).
    public static let colorTemperatureIncrement = VCPCode(0x0B)
    /// Colour temperature as `3000 K + value × increment`.
    public static let colorTemperatureRequest = VCPCode(0x0C)
    public static let verticalFrequency = VCPCode(0xAE)
    public static let displayTechnology = VCPCode(0xB6)
    public static let controllerManufacturer = VCPCode(0xC8)
    public static let osdLanguage = VCPCode(0xCC)
    public static let vcpVersion = VCPCode(0xDF)

    public static func < (a: VCPCode, b: VCPCode) -> Bool { a.rawValue < b.rawValue }
    public var description: String { String(format: "0x%02X", rawValue) }
}

/// A continuous control's reading: current value and the maximum the monitor reports.
public struct VCPReading: Equatable, Sendable {
    public var current: Int
    public var maximum: Int
    public init(current: Int, maximum: Int) {
        self.current = current
        self.maximum = maximum
    }
}

public enum DDCError: Error, Equatable, CustomStringConvertible {
    case unavailable
    case transport(Int32)
    case noReply
    case unsupported(VCPCode)

    public var description: String {
        switch self {
        case .unavailable: "This display's connection does not carry DDC/CI"
        case .transport(let rc): String(format: "I2C transfer failed (IOReturn 0x%08X)", UInt32(bitPattern: rc))
        case .noReply: "The display did not answer"
        case .unsupported(let code): "The display does not support VCP \(code)"
        }
    }
}

/// DDC/CI message framing (VESA DDC/CI 1.1). Pure functions, no I/O.
///
/// On the wire a host→display message is `6E 51 <0x80|len> <payload…> <checksum>`.
/// `IOAVServiceWriteI2C` takes the 7-bit address (0x37 = 0x6E >> 1) and the
/// source byte 0x51 as separate arguments, so the buffers here start at the length byte.
public enum DDCProtocol {
    public static let i2cAddress: UInt32 = 0x37
    public static let hostSubaddress: UInt32 = 0x51
    static let displayWriteAddress: UInt8 = 0x6E
    /// Replies are checksummed as if addressed to the "virtual host" 0x50.
    static let virtualHostAddress: UInt8 = 0x50

    public static let capabilitiesChunkReadLength = 38
    public static let vcpReplyLength = 11

    static func frame(_ payload: [UInt8]) -> [UInt8] {
        var bytes = [0x80 | UInt8(payload.count)] + payload
        bytes.append(bytes.reduce(displayWriteAddress ^ UInt8(hostSubaddress), ^))
        return bytes
    }

    public static func getVCP(_ code: VCPCode) -> [UInt8] {
        frame([0x01, code.rawValue])
    }

    public static func setVCP(_ code: VCPCode, _ value: UInt16) -> [UInt8] {
        frame([0x03, code.rawValue, UInt8(value >> 8), UInt8(value & 0xFF)])
    }

    public static func capabilitiesRequest(offset: Int) -> [UInt8] {
        frame([0xF3, UInt8((offset >> 8) & 0xFF), UInt8(offset & 0xFF)])
    }

    /// Validates the reply's length byte and checksum and returns its payload.
    static func payload(ofReply reply: [UInt8]) -> [UInt8]? {
        guard reply.count >= 3, reply[0] == displayWriteAddress, reply[1] & 0x80 != 0 else { return nil }
        let length = Int(reply[1] & 0x7F)
        guard reply.count >= length + 3 else { return nil }
        let body = reply[0..<(length + 2)]
        guard body.reduce(virtualHostAddress, ^) == reply[length + 2] else { return nil }
        return Array(reply[2..<(length + 2)])
    }

    public enum VCPReply: Equatable, Sendable {
        case value(VCPReading)
        case unsupported
    }

    /// Parses a "Get VCP Feature" reply: `02 <result> <code> <type> <maxH> <maxL> <curH> <curL>`.
    public static func parseVCPReply(_ reply: [UInt8], for code: VCPCode) -> VCPReply? {
        guard let p = payload(ofReply: reply), p.count >= 8, p[0] == 0x02, p[2] == code.rawValue else { return nil }
        if p[1] != 0x00 { return .unsupported }
        return .value(VCPReading(current: Int(p[6]) << 8 | Int(p[7]), maximum: Int(p[4]) << 8 | Int(p[5])))
    }

    /// Parses one capabilities fragment: `E3 <offH> <offL> <data…>`. Empty data marks the end.
    public static func parseCapabilitiesFragment(_ reply: [UInt8], expectedOffset: Int) -> [UInt8]? {
        guard let p = payload(ofReply: reply), p.count >= 3, p[0] == 0xE3,
              Int(p[1]) << 8 | Int(p[2]) == expectedOffset else { return nil }
        return Array(p[3...])
    }
}
