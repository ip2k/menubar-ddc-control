import Foundation

/// The identity fields of an EDID base block that CoreGraphics also exposes, so an I2C
/// service can be paired with its `CGDirectDisplayID`.
public struct EDIDIdentity: Hashable, Sendable {
    /// Big-endian PNP manufacturer ID; equals `CGDisplayVendorNumber`.
    public var vendor: UInt32
    /// Little-endian product code; equals `CGDisplayModelNumber`.
    public var model: UInt32
    /// Little-endian serial; equals `CGDisplaySerialNumber`.
    public var serial: UInt32
    /// The monitor name descriptor (tag 0xFC), if present.
    public var name: String?

    public init(vendor: UInt32, model: UInt32, serial: UInt32, name: String?) {
        self.vendor = vendor
        self.model = model
        self.serial = serial
        self.name = name
    }

    public init?(edid data: Data) {
        let b = [UInt8](data)
        guard b.count >= 128, b[0..<8] == [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00] else { return nil }
        vendor = UInt32(b[8]) << 8 | UInt32(b[9])
        model = UInt32(b[11]) << 8 | UInt32(b[10])
        serial = UInt32(b[15]) << 24 | UInt32(b[14]) << 16 | UInt32(b[13]) << 8 | UInt32(b[12])
        name = nil
        for offset in stride(from: 54, through: 108, by: 18) where b[offset] == 0 && b[offset + 1] == 0 && b[offset + 3] == 0xFC {
            let text = b[(offset + 5)..<(offset + 18)].prefix { $0 != 0x0A }
            name = String(decoding: text, as: UTF8.self).trimmingCharacters(in: .whitespaces)
        }
    }

    /// The three-letter PNP ID, e.g. "CRX" for Corsair's panels.
    public var manufacturerID: String {
        let letters = [(vendor >> 10) & 0x1F, (vendor >> 5) & 0x1F, vendor & 0x1F]
        return String(letters.map { (1...26).contains($0) ? Character(UnicodeScalar(UInt8(64 + $0))) : "?" })
    }
}
