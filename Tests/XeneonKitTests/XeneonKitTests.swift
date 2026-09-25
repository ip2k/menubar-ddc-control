import Foundation
import Testing
@testable import XeneonKit

/// The Edge's capabilities string, read over USB-C on 2026-09-25.
let edgeCapabilities = "(prot(monitor)type(LCD)model(RTK)cmds(01 02 03 07 0C E3 F3)vcp(02 04 05 06 08 0B 0C 10 12 14(01 02 04 05 06 08 0B) 16 18 1A 52 60(01 03 04 0F 10 11 12) 87 AC AE B2 B6 C6 C8 CA CC(01 02 03 04 06 0A 0D) D6(01 04 05) DF FD FF)mswhql(1)asset_eep(40)mccs_ver(2.2))"

@Suite struct DDCFraming {
    @Test func getVCPRequest() {
        // 6E ^ 51 ^ 82 ^ 01 ^ 10 = 0xAC
        #expect(DDCProtocol.getVCP(.brightness) == [0x82, 0x01, 0x10, 0xAC])
    }

    @Test func setVCPRequest() {
        let bytes = DDCProtocol.setVCP(.brightness, 0x0150)
        #expect(Array(bytes.prefix(5)) == [0x84, 0x03, 0x10, 0x01, 0x50])
        #expect(bytes.last == bytes.dropLast().reduce(0x6E ^ 0x51, ^))
    }

    @Test func capabilitiesRequestCarriesOffset() {
        #expect(Array(DDCProtocol.capabilitiesRequest(offset: 0x0120).prefix(4)) == [0x83, 0xF3, 0x01, 0x20])
    }

    @Test func parsesRealBrightnessReply() {
        // The Edge's reply to "get 0x10": brightness 95 of 100.
        let reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x5F, 0x9F]
        #expect(DDCProtocol.parseVCPReply(reply, for: .brightness) == .value(VCPReading(current: 95, maximum: 100)))
    }

    @Test func rejectsCorruptedReply() {
        var reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x5F, 0x9F]
        reply[9] = 0x60
        #expect(DDCProtocol.parseVCPReply(reply, for: .brightness) == nil)
    }

    @Test func rejectsReplyForAnotherCode() {
        let reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x5F, 0x9F]
        #expect(DDCProtocol.parseVCPReply(reply, for: .contrast) == nil)
    }

    @Test func reportsUnsupportedCode() {
        var reply: [UInt8] = [0x6E, 0x88, 0x02, 0x01, 0xFD, 0x00, 0x00, 0x00, 0x00, 0x00]
        reply.append(reply.reduce(0x50, ^))
        #expect(DDCProtocol.parseVCPReply(reply, for: VCPCode(0xFD)) == .unsupported)
    }

    @Test func parsesCapabilitiesFragments() {
        var reply: [UInt8] = [0x6E, 0x86, 0xE3, 0x00, 0x20, 0x28, 0x70, 0x72]
        reply.append(reply.reduce(0x50, ^))
        #expect(DDCProtocol.parseCapabilitiesFragment(reply, expectedOffset: 0x20) == Array("(pr".utf8))
        #expect(DDCProtocol.parseCapabilitiesFragment(reply, expectedOffset: 0) == nil)

        var end: [UInt8] = [0x6E, 0x83, 0xE3, 0x00, 0x40]
        end.append(end.reduce(0x50, ^))
        #expect(DDCProtocol.parseCapabilitiesFragment(end, expectedOffset: 0x40) == [])
    }
}

@Suite struct CapabilitiesParsing {
    @Test func parsesTheEdge() {
        let caps = Capabilities(parsing: edgeCapabilities)
        #expect(caps.model == "RTK")
        #expect(caps.mccsVersion == "2.2")
        #expect(caps.vcp[.colorPreset] == [0x01, 0x02, 0x04, 0x05, 0x06, 0x08, 0x0B])
        #expect(caps.vcp[.osdLanguage] == [0x01, 0x02, 0x03, 0x04, 0x06, 0x0A, 0x0D])
        #expect(caps.vcp[.brightness] == [])
        #expect(caps.supports(.sharpness))
        #expect(caps.supports(.colorTemperatureRequest))
        #expect(!caps.supports(VCPCode(0x62)))
        #expect(caps.vcp.count == 28)
    }

    @Test func parsesUnspacedLists() {
        let caps = Capabilities(parsing: "(vcp(101214(010B)16)mccs_ver(2.1))")
        #expect(caps.vcp[.colorPreset] == [0x01, 0x0B])
        #expect(caps.supports(.brightness) && caps.supports(.contrast) && caps.supports(.redGain))
        #expect(caps.mccsVersion == "2.1")
    }

    @Test func toleratesEmptyString() {
        #expect(Capabilities(parsing: "").vcp.isEmpty)
    }
}

@Suite struct EDIDParsing {
    static func sampleEDID() -> Data {
        var b = [UInt8](repeating: 0, count: 128)
        b[0..<8] = [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00]
        b[8...15] = [0x0E, 0x58, 0x00, 0xED, 0x01, 0x01, 0x01, 0x01]
        let descriptor: [UInt8] = [0, 0, 0, 0xFC, 0] + Array("XENEON EDGE\n ".utf8)
        b.replaceSubrange(72..<90, with: descriptor)
        return Data(b)
    }

    @Test func matchesCoreGraphicsNumbering() throws {
        let id = try #require(EDIDIdentity(edid: Self.sampleEDID()))
        // Values CoreGraphics reports for the Edge.
        #expect(id.vendor == 3672)
        #expect(id.model == 60672)
        #expect(id.serial == 16843009)
        #expect(id.name == "XENEON EDGE")
        #expect(id.manufacturerID == "CRX")
    }

    @Test func rejectsNonEDID() {
        #expect(EDIDIdentity(edid: Data(repeating: 0, count: 128)) == nil)
    }
}

@Suite struct GammaMath {
    @Test func identityKeepsRamp() {
        let ramp = GammaRamp.linear(count: 256)
        #expect(ramp.applying(.identity) == ramp)
    }

    @Test func gainScalesOneChannel() {
        var adjustment = SoftwareAdjustment()
        adjustment.enabled = true
        adjustment.red = 0.5
        let out = GammaRamp.linear(count: 3).applying(adjustment)
        #expect(out.red == [0, 0.25, 0.5])
        #expect(out.green == [0, 0.5, 1])
    }

    @Test func brightnessAndGammaCompose() {
        var adjustment = SoftwareAdjustment()
        adjustment.enabled = true
        adjustment.brightness = 0.5
        adjustment.gamma = 2
        let out = GammaRamp.linear(count: 3).applying(adjustment)
        #expect(out.blue == [0, 0.125, 0.5])
    }

    @Test func keepsCalibrationCurve() {
        // A non-linear baseline (as a calibrated profile's VCGT would load) is scaled, not replaced.
        let baseline = GammaRamp(red: [0, 0.3, 0.9], green: [0, 0.3, 0.9], blue: [0, 0.3, 0.9])
        var adjustment = SoftwareAdjustment()
        adjustment.enabled = true
        adjustment.brightness = 0.5
        #expect(baseline.applying(adjustment).green == [0, 0.15, 0.45])
    }

    @Test func clampsOutOfRangeValues() {
        var adjustment = SoftwareAdjustment()
        adjustment.enabled = true
        adjustment.red = 3
        adjustment.brightness = -1
        let out = GammaRamp.linear(count: 2).applying(adjustment)
        #expect(out.red == [0, 0])
    }
}

@Suite struct Names {
    @Test func colorTemperatureMapping() {
        #expect(ColorTemperature.kelvin(forRequest: 35, increment: 100) == 6500)
        #expect(ColorTemperature.request(forKelvin: 9300, increment: 100) == 63)
    }

    @Test func presetNames() {
        #expect(VCPNames.colorPreset(0x0B) == "User 1")
        #expect(VCPNames.isUserPreset(0x0B))
        #expect(!VCPNames.isUserPreset(0x05))
    }
}

@Suite struct WhitePointMath {
    @Test func d65IsNearSRGBWhite() {
        let (x, y) = WhitePoint.chromaticity(kelvin: 6504)
        #expect(abs(x - 0.3127) < 0.0005 && abs(y - 0.3290) < 0.0005)
    }

    @Test func sameTargetIsIdentity() {
        let g = WhitePoint.encodedGains(target: 6500, reference: 6500)
        #expect(abs(g.red - 1) < 1e-9 && abs(g.green - 1) < 1e-9 && abs(g.blue - 1) < 1e-9)
    }

    @Test func warmerCutsBlueCoolerCutsRed() {
        let warm = WhitePoint.encodedGains(target: 5003, reference: 6504)
        #expect(warm.red == 1 && warm.blue < warm.green && warm.green < 1)
        let cool = WhitePoint.encodedGains(target: 9305, reference: 6504)
        #expect(cool.blue == 1 && cool.red < cool.green && cool.green < 1)
    }

    @Test func tenKelvinStepsAreDistinct() {
        let a = WhitePoint.encodedGains(target: 5010, reference: 6500)
        let b = WhitePoint.encodedGains(target: 5040, reference: 6500)
        #expect(a.blue != b.blue)
    }

    @Test func whitePointFeedsTheRamp() {
        var adjustment = SoftwareAdjustment()
        adjustment.enabled = true
        #expect(adjustment.isIdentity)
        adjustment.whitePoint = 5000
        #expect(!adjustment.isIdentity)
        let out = GammaRamp.linear(count: 2).applying(adjustment)
        #expect(out.red.last == 1 && out.blue.last! < 1)
    }

    @Test func decodesSettingsSavedBeforeWhitePoint() throws {
        let old = #"{"brightness":0.5,"red":1,"green":1,"blue":1,"gamma":1}"#
        let decoded = try JSONDecoder().decode(SoftwareAdjustment.self, from: Data(old.utf8))
        #expect(decoded.brightness == 0.5 && decoded.whitePoint == 6500 && decoded.referenceWhitePoint == 6500)
    }
}

@Suite struct DisplayStateDiffs {
    @Test func reportsChangedCodes() {
        let launch = DisplayState(values: [0x10: 95, 0x12: 50, 0x16: 151])
        let now = DisplayState(values: [0x10: 60, 0x12: 50, 0x16: 255])
        #expect(launch.differences(from: now) == [.brightness, .redGain])
        #expect(launch.differences(from: launch).isEmpty)
    }
}

@Suite struct GPUOptIn {
    @Test func offByDefaultAndIgnoredWhileOff() {
        var adjustment = SoftwareAdjustment()
        #expect(!adjustment.enabled)
        adjustment.brightness = 0.3
        adjustment.whitePoint = 4000
        #expect(adjustment.isIdentity)
        let ramp = GammaRamp.linear(count: 4)
        #expect(ramp.applying(adjustment) == ramp)
        adjustment.enabled = true
        #expect(!adjustment.isIdentity && ramp.applying(adjustment) != ramp)
    }

    @Test func savedAdjustmentsFromBeforeTheSwitchStayOff() throws {
        let old = #"{"brightness":0.5,"red":1,"green":1,"blue":1,"gamma":1}"#
        let decoded = try JSONDecoder().decode(SoftwareAdjustment.self, from: Data(old.utf8))
        #expect(!decoded.enabled && decoded.isIdentity)
    }
}

@Suite struct DumpFiles {
    static func sample() -> DDCDump {
        DDCDump(capturedAt: Date(timeIntervalSince1970: 1_790_000_000),
                display: .init(name: "XENEON EDGE", manufacturerID: "CRX", vendor: 3672, model: 60672),
                capabilities: edgeCapabilities,
                values: [
                    .init(code: "0x10", name: "Brightness", current: 95, maximum: 100, restorable: true),
                    .init(code: "0x16", name: "Red gain", current: 151, maximum: 255, restorable: true),
                    .init(code: "0xAE", name: "Vertical frequency", current: 6030, maximum: 65535, restorable: false),
                ],
                unanswered: ["0xFD", "0xFF"])
    }

    @Test func roundTripsThroughJSON() throws {
        let data = try DDCDump.encoder.encode(Self.sample())
        #expect(String(decoding: data, as: UTF8.self).contains(#""code" : "0x10""#))
        #expect(try DDCDump.decoder.decode(DDCDump.self, from: data) == Self.sample())
    }

    @Test func writesBackOnlyRestorableValues() {
        #expect(Self.sample().restorableState.values == [0x10: 95, 0x16: 151])
    }

    @Test func refusesAnotherModel() {
        let edge = EDIDIdentity(vendor: 3672, model: 60672, serial: 0, name: nil)
        let other = EDIDIdentity(vendor: 3672, model: 1, serial: 0, name: nil)
        #expect(Self.sample().matches(edge) && !Self.sample().matches(other))
    }
}
