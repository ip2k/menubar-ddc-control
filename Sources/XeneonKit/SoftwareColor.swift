import CoreGraphics
import Foundation

/// Colour adjustment done by the GPU's gamma tables instead of the monitor. It works on
/// any connection, including ones without DDC/CI, but it only rescales the signal: it
/// cannot raise the backlight, and dimming this way costs contrast.
public struct SoftwareAdjustment: Codable, Equatable, Sendable {
    public var brightness: Double = 1
    public var red: Double = 1
    public var green: Double = 1
    public var blue: Double = 1
    /// Exponent applied on top of the display's calibrated curve; 1 leaves it unchanged.
    public var gamma: Double = 1
    /// Target white in kelvin, relative to `referenceWhitePoint` (the white the monitor
    /// already produces); equal values leave the white point alone.
    public var whitePoint: Double = 6500
    public var referenceWhitePoint: Double = 6500

    public init() {}

    // Settings saved before a field existed decode with that field's default.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        brightness = try c.decodeIfPresent(Double.self, forKey: .brightness) ?? 1
        red = try c.decodeIfPresent(Double.self, forKey: .red) ?? 1
        green = try c.decodeIfPresent(Double.self, forKey: .green) ?? 1
        blue = try c.decodeIfPresent(Double.self, forKey: .blue) ?? 1
        gamma = try c.decodeIfPresent(Double.self, forKey: .gamma) ?? 1
        whitePoint = try c.decodeIfPresent(Double.self, forKey: .whitePoint) ?? 6500
        referenceWhitePoint = try c.decodeIfPresent(Double.self, forKey: .referenceWhitePoint) ?? 6500
    }

    /// Per-channel gain combining the RGB balance with the white-point shift.
    public var channelGains: (red: Double, green: Double, blue: Double) {
        guard abs(whitePoint - referenceWhitePoint) >= 1 else { return (red, green, blue) }
        let w = WhitePoint.encodedGains(target: whitePoint, reference: referenceWhitePoint)
        return (red * w.red, green * w.green, blue * w.blue)
    }
    public static let identity = SoftwareAdjustment()
    public var isIdentity: Bool {
        brightness == 1 && red == 1 && green == 1 && blue == 1 && gamma == 1 && abs(whitePoint - referenceWhitePoint) < 1
    }

    public static let brightnessRange = 0.1...1.0
    public static let gainRange = 0.0...1.0
    public static let gammaRange = 0.5...2.0
}

/// A display's gamma ramp, one array per channel, values 0…1.
public struct GammaRamp: Equatable, Sendable {
    public var red: [CGGammaValue]
    public var green: [CGGammaValue]
    public var blue: [CGGammaValue]

    public static func linear(count: Int) -> GammaRamp {
        let values = (0..<count).map { CGGammaValue($0) / CGGammaValue(max(count - 1, 1)) }
        return GammaRamp(red: values, green: values, blue: values)
    }

    /// The ramp with `adjustment` applied on top of it: `out = in^gamma × gain × brightness`.
    /// Working from the current ramp keeps any calibration curve (VCGT) the ColorSync profile loaded.
    public func applying(_ adjustment: SoftwareAdjustment) -> GammaRamp {
        func map(_ channel: [CGGammaValue], _ gain: Double) -> [CGGammaValue] {
            let scale = CGGammaValue(min(max(gain, 0), 1) * min(max(adjustment.brightness, 0), 1))
            let exponent = CGGammaValue(adjustment.gamma)
            return channel.map { min(max(pow(max($0, 0), exponent) * scale, 0), 1) }
        }
        let gains = adjustment.channelGains
        return GammaRamp(red: map(red, gains.red), green: map(green, gains.green), blue: map(blue, gains.blue))
    }
}

/// Applies software adjustments to displays. macOS restores every display's ColorSync
/// ramp when the process that changed it exits, so adjustments last only while it runs.
public enum SoftwareColor {
    public static func currentRamp(of display: CGDirectDisplayID) -> GammaRamp? {
        let capacity = CGDisplayGammaTableCapacity(display)
        guard capacity > 0 else { return nil }
        var red = [CGGammaValue](repeating: 0, count: Int(capacity))
        var green = red, blue = red
        var count: UInt32 = 0
        guard CGGetDisplayTransferByTable(display, capacity, &red, &green, &blue, &count) == .success, count > 0 else { return nil }
        return GammaRamp(red: Array(red.prefix(Int(count))), green: Array(green.prefix(Int(count))), blue: Array(blue.prefix(Int(count))))
    }

    @discardableResult
    public static func apply(_ ramp: GammaRamp, to display: CGDirectDisplayID) -> Bool {
        let count = UInt32(min(ramp.red.count, ramp.green.count, ramp.blue.count))
        return CGSetDisplayTransferByTable(display, count, ramp.red, ramp.green, ramp.blue) == .success
    }

    /// Restores every display to its ColorSync profile's ramp.
    public static func restoreAll() {
        CGDisplayRestoreColorSyncSettings()
    }
}
