import Foundation

/// Correlated colour temperature → RGB channel multipliers, for shifting a display's white
/// point on the GPU.
public enum WhitePoint {
    public static let range = 3000.0...9300.0
    public static let step = 10.0

    /// The CIE standard daylight illuminants, as the kelvin they sit at.
    public static let markers: [(name: String, kelvin: Double)] = [
        ("D50", 5003), ("D65", 6504), ("D75", 7504), ("D93", 9305),
    ]

    /// CIE 1931 xy chromaticity: the CIE daylight locus from 4000 K (where the D illuminants
    /// are defined), the Planckian locus (Kim et al. cubic fit) below.
    public static func chromaticity(kelvin: Double) -> (x: Double, y: Double) {
        let t = min(max(kelvin, 1667), 25000)
        if t >= 4000 {
            let x = t <= 7000
                ? -4.6070e9 / (t * t * t) + 2.9678e6 / (t * t) + 0.09911e3 / t + 0.244063
                : -2.0064e9 / (t * t * t) + 1.9018e6 / (t * t) + 0.24748e3 / t + 0.237040
            return (x, -3.000 * x * x + 2.870 * x - 0.275)
        }
        let x = -0.2661239e9 / (t * t * t) - 0.2343589e6 / (t * t) + 0.8776956e3 / t + 0.179910
        let y = t >= 2222
            ? -0.9549476 * x * x * x - 1.37418593 * x * x + 2.09137015 * x - 0.16748867
            : -1.1063814 * x * x * x - 1.34811020 * x * x + 2.18555832 * x - 0.20219683
        return (x, y)
    }

    /// Linear-light sRGB of the white at `kelvin`, luminance 1.
    static func linearRGB(kelvin: Double) -> (Double, Double, Double) {
        linearRGB(chromaticity(kelvin: kelvin))
    }

    /// Linear-light sRGB of chromaticity `xy` at luminance 1.
    static func linearRGB(_ xy: (x: Double, y: Double)) -> (Double, Double, Double) {
        let (x, y) = xy
        let X = x / y, Y = 1.0, Z = (1 - x - y) / y
        return (
            3.2406 * X - 1.5372 * Y - 0.4986 * Z,
            -0.9689 * X + 1.8758 * Y + 0.0415 * Z,
            0.0557 * X - 0.2040 * Y + 1.0570 * Z
        )
    }

    // MARK: Green–magenta (tint)

    /// Adobe's Tint scale (Lightroom, Camera Raw, DNG SDK): Tint = −3000 × Duv, so positive
    /// Tint is magenta (below the Planckian locus) and negative is green (above it).
    public static let tintScale = -3000.0
    public static let tintRange = -50.0...50.0
    /// ANSI C78.377's ±0.006 Duv tolerance for lamps, in Tint units (±18).
    public static let ansiTintTolerance = 0.006 * 3000

    /// The Planckian locus in CIE 1960 uv (Krystek 1985, 1000–15000 K).
    static func planckianUV(kelvin t: Double) -> (u: Double, v: Double) {
        let u = (0.860117757 + 1.54118254e-4 * t + 1.28641212e-7 * t * t) / (1 + 8.42420235e-4 * t + 7.08145163e-7 * t * t)
        let v = (0.317398726 + 4.22806245e-5 * t + 4.20481691e-8 * t * t) / (1 - 2.89741816e-5 * t + 1.61456053e-7 * t * t)
        return (u, v)
    }

    /// Unit normal to the Planckian locus at `kelvin`, pointing above it (towards green, +Duv).
    static func locusNormal(kelvin t: Double) -> (u: Double, v: Double) {
        let a = planckianUV(kelvin: t - 1), b = planckianUV(kelvin: t + 1)
        let (du, dv) = (b.u - a.u, b.v - a.v)            // tangent, towards higher CCT
        let length = (du * du + dv * dv).squareRoot()
        let n = (u: -dv / length, v: du / length)      // tangent rotated 90°
        return n.v > 0 ? n : (-n.u, -n.v)               // "above" the locus has larger v
    }

    /// The chromaticity of `kelvin` (daylight locus from 4000 K, as `chromaticity`) moved
    /// `duv` across the locus in CIE 1960 uv.
    public static func chromaticity(kelvin: Double, duv: Double) -> (x: Double, y: Double) {
        let (x, y) = chromaticity(kelvin: kelvin)
        guard duv != 0 else { return (x, y) }
        let d = -2 * x + 12 * y + 3
        let n = locusNormal(kelvin: min(max(kelvin, 1000), 15000))
        let u = 4 * x / d + duv * n.u, v = 6 * y / d + duv * n.v
        let e = 2 * u - 8 * v + 4
        return (3 * u / e, 2 * v / e)
    }

    /// Gamma-encoded channel multipliers that shift white by `tint` (Adobe units) at `kelvin`,
    /// relative to no tint. The strongest channel stays at 1.
    public static func tintGains(tint: Double, kelvin: Double, gamma: Double = 2.2) -> (red: Double, green: Double, blue: Double) {
        let t = linearRGB(chromaticity(kelvin: kelvin, duv: tint / tintScale))
        let r = linearRGB(chromaticity(kelvin: kelvin))
        var m = (t.0 / r.0, t.1 / r.1, t.2 / r.2)
        let peak = max(m.0, m.1, m.2)
        m = (m.0 / peak, m.1 / peak, m.2 / peak)
        return (pow(max(m.0, 0), 1 / gamma), pow(max(m.1, 0), 1 / gamma), pow(max(m.2, 0), 1 / gamma))
    }

    /// Multipliers for gamma-encoded values that move white from `reference` to `target`.
    /// The strongest channel stays at 1, so nothing clips; shifting away from the panel's
    /// own white dims it slightly, as a hardware white-point change on a fixed backlight does.
    public static func encodedGains(target: Double, reference: Double, gamma: Double = 2.2) -> (red: Double, green: Double, blue: Double) {
        let t = linearRGB(kelvin: target), r = linearRGB(kelvin: reference)
        var m = (t.0 / r.0, t.1 / r.1, t.2 / r.2)
        let peak = max(m.0, m.1, m.2)
        m = (m.0 / peak, m.1 / peak, m.2 / peak)
        return (pow(max(m.0, 0), 1 / gamma), pow(max(m.1, 0), 1 / gamma), pow(max(m.2, 0), 1 / gamma))
    }
}
