import CoreGraphics
import Foundation

/// An external display, and its DDC channel when the connection carries one.
public struct ExternalDisplay: Identifiable, Sendable {
    public let id: CGDirectDisplayID
    public let identity: EDIDIdentity
    /// Present when an I2C service was found for this display. It may still not answer
    /// (the M1-generation built-in HDMI port rejects every transfer), so probe before trusting it.
    public let ddc: DDCChannel?

    public var name: String { identity.name ?? "Display \(id)" }
    public var isXeneonEdge: Bool { identity.name?.uppercased().contains("XENEON EDGE") == true }

    /// Stable across reconnects and reboots, unlike `CGDirectDisplayID`.
    public var persistentKey: String { "\(identity.vendor)-\(identity.model)-\(identity.serial)" }
}

public enum DisplayDirectory {
    /// The online external displays, Xeneon Edge first.
    public static func externalDisplays() -> [ExternalDisplay] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }

        var services = IOAV.externalServices().compactMap { entry in
            EDIDIdentity(edid: entry.edid).map { (identity: $0, service: entry.service) }
        }

        let displays = ids.prefix(Int(count)).filter { CGDisplayIsBuiltin($0) == 0 }.map { id -> ExternalDisplay in
            let vendor = CGDisplayVendorNumber(id), model = CGDisplayModelNumber(id), serial = CGDisplaySerialNumber(id)
            // Identical monitors can share vendor, model and serial 0; in that case they are
            // paired in enumeration order, which can swap two indistinguishable panels.
            let index = services.firstIndex { $0.identity.vendor == vendor && $0.identity.model == model && $0.identity.serial == serial }
                ?? services.firstIndex { $0.identity.vendor == vendor && $0.identity.model == model }
            guard let index else {
                return ExternalDisplay(id: id, identity: EDIDIdentity(vendor: vendor, model: model, serial: serial, name: nil), ddc: nil)
            }
            let match = services.remove(at: index)
            return ExternalDisplay(id: id, identity: match.identity, ddc: DDCChannel(service: match.service, label: "\(id)"))
        }
        return displays.sorted { $0.isXeneonEdge && !$1.isXeneonEdge }
    }
}

/// Behaviour of specific monitors that their capabilities strings don't reveal.
public struct DisplayQuirks: Sendable {
    /// Acknowledges RGB gain writes over DDC/CI but keeps the old values.
    public var ignoresGainWrites = false
    /// Selecting a factory preset resets the User preset's gains; 0x08 restores them.
    public var leavingUserPresetResetsGains = false

    public static func of(_ identity: EDIDIdentity) -> DisplayQuirks {
        var quirks = DisplayQuirks()
        // CORSAIR XENEON EDGE ("CRX", product 0xED00), verified 2026-09-25.
        if identity.manufacturerID == "CRX", identity.model == 0xED00 {
            quirks.ignoresGainWrites = true
            quirks.leavingUserPresetResetsGains = true
        }
        return quirks
    }
}

extension ExternalDisplay {
    public var quirks: DisplayQuirks { .of(identity) }
}
