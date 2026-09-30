# Colour science

## Hardware versus GPU

The Edge offers four hardware white points (the 5000/6500/7500/9300 K presets; User 1 is a calibrated
6500 K) and ignores RGB gain writes, and has no gamma control. Anything finer is done on the GPU by
rewriting the display's gamma table (`CGSetDisplayTransferByTable`). Those changes last only while the
process that made them runs; macOS restores the ColorSync ramp when it exits.

**Stacking on calibration.** A display's ICC profile can load a calibration curve (VCGT) into the same
gamma table. The app captures that ramp as a baseline and applies its adjustments on top:
`out = baseline(in)^gamma × channel gain × brightness`, with the strongest channel kept at 1 so nothing
clips. After anything that makes ColorSync reload ramps (reconnect, wake, profile change), it restores
ColorSync, recaptures the baseline and reapplies.

Gains computed in linear light are converted to gamma-encoded multipliers with a 2.2 exponent
(`encoded = linear^(1/2.2)`), since the ramp operates on encoded values.

## White point (along the locus)

The target white for a colour temperature *T* is taken on the **CIE daylight locus** from 4000 K
(where the D illuminants are defined; D65 comes out at x 0.3127, y 0.3290), and on the **Planckian
locus** below it (Kim et al. cubic fit):

- Daylight, 4000–7000 K: x = −4.6070×10⁹/T³ + 2.9678×10⁶/T² + 0.09911×10³/T + 0.244063
- Daylight, 7000–25000 K: x = −2.0064×10⁹/T³ + 1.9018×10⁶/T² + 0.24748×10³/T + 0.237040
- Daylight: y = −3.000x² + 2.870x − 0.275
- Planckian, below 4000 K: x = −0.2661239×10⁹/T³ − 0.2343589×10⁶/T² + 0.8776956×10³/T + 0.179910, with the matching cubic for y

xy → XYZ (Y = 1) → linear sRGB (IEC 61966-2-1 matrix); the gains are target ÷ reference white, where
the reference is the monitor preset's own white (from VCP `0x0C`), so an unshifted slider changes nothing.
The markers D50, D65, D75 and D93 sit at 5003, 6504, 7504 and 9305 K.

## Tint (across the locus)

Tint is the second white-balance axis. Colour temperature moves white *along* the blackbody locus
(amber ↔ blue); tint moves it *across* (green ↔ magenta). Lighting and photography measure it as
**Duv (Δuv)**: the signed distance from the Planckian locus in **CIE 1960 uv**, along an isotherm
(uv is used because isotherms are perpendicular to the locus there). Positive Duv lies above the locus
and looks green; negative lies below and looks magenta or pink.
ANSI C78.377 allows ±0.006 for general lamps.

**Units.** Adobe's Tint (Lightroom, Camera Raw, DNG SDK) is Duv scaled by 3000, with Lightroom's
slider running green (−) to magenta (+): **Tint = −3000 × Duv**. The app uses those units, range ±50
(about ±0.017 Duv); ±18 is the ANSI tolerance.

**Computation.** Planckian locus in uv (Krystek 1985, 1000–15000 K):

    u(T) = (0.860117757 + 1.54118254e-4·T + 1.28641212e-7·T²) / (1 + 8.42420235e-4·T + 7.08145163e-7·T²)
    v(T) = (0.317398726 + 4.22806245e-5·T + 4.20481691e-8·T²) / (1 − 2.89741816e-5·T + 1.61456053e-7·T²)

The tangent is taken numerically (T ± 1 K) and rotated 90°, oriented towards +v (green). The fine
white point's xy is converted to uv (u = 4x/(−2x + 12y + 3), v = 6y/(−2x + 12y + 3)), moved by
Duv along that normal, and converted back (x = 3u/(2u − 8v + 4), y = 2v/(2u − 8v + 4)). The daylight
locus runs close enough to parallel that the Planckian normal serves for both. The unit test checks
that a 0.01 shift moves the uv point exactly 0.01, perpendicular and upward.

**Driving the RGB sliders.** Tint is not applied as a separate multiplier: moving it scales red,
green and blue by the *change* in tint gains, so a balance set by hand is kept, and everything is scaled
back if a channel would exceed 1. Moving R/G/B by hand does not move Tint (inferring a tint from
arbitrary gains is ill-posed). Measured on the Edge at 7500 K: Magenta 25 → red 100 %, green 93 %,
blue 98 %; blue dips slightly because the locus normal at 7500 K leans towards blue.

Sources: [Yuji: All about the green–magenta shift](https://www.yujiintl.com/all-about-the-green-magenta-shift/);
[Strolls with my Dog: White point, CCT and tint](https://www.strollswithmydog.com/white-point-cct-tint/);
[DOE/PNNL: Color spaces and Planckian loci](https://www1.eere.energy.gov/buildings/publications/pdfs/ssl/miller-royer_color_portland2013.pdf);
Ohno 2014 and CIE 15:2018 for Duv; Krystek 1985 for the uv fit; Kim et al. for the Planckian xy fit.

## Rosé Pine contrast analysis

Palette values from [rose-pine/palette](https://github.com/rose-pine/palette) `palette.json` (MIT).
Checked with the WCAG ratio (4.5:1 for normal text, 3:1 for UI components):

| Pair | Moon | Dawn | Use |
|---|---|---|---|
| text on surface | 10.9 | 9.14 | body text |
| subtle on surface | 4.46 ⚠ | 4.23 ✗ | not used for text as-is |
| subtle 80 % + text 20 % on surface | 5.44 | 4.88 | secondary text and captions |
| same, on base | 5.92 | 4.64 | |
| muted on surface | 2.79 | 2.87 | decoration only (ticks, dashes) |
| gold on surface | 8.77 | **2.16** | warning *icons*; warning text stays `text` |
| iris on surface | 6.87 | 3.65 | accent for controls (≥ 3:1) |
| foam / pine on surface | 8.44 (foam) | 5.88 (pine) | links |
| love on surface (Dawn) | | 4.04 | red gain slider tint only |
