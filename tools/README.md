# Tools

Not part of the app build (SwiftPM only builds `Sources/` and `Tests/`).

| Tool | What it does |
|---|---|
| `icon/build-icon.sh` | Rebuilds `Resources/AppIcon.icns` and `docs/images/icon.png` from `icon/icon-source.jpg` (the owner's artwork). Reproduces the shipped icon byte for byte. |
| `icon/make-app-icon.swift` | The masking step: crops the artwork's rounded square and places it on Apple's 824/1024 icon grid with a continuous-corner mask and shadow. |
| `icon/measure.swift` | Finds a source image's rounded square and corner radius (for a new artwork, update the crop in `make-app-icon.swift`). |
| `icon/menubar-preview/run.sh` | Renders `docs/research/menubar-icon-comparison.png`: the menu bar glyph against a downscaled icon, 1x/2x, light/dark. |
| `probes/ddc-probe.swift` | The first DDC/CI probe (EDID, Get VCP, capabilities). Historical; use `ddc-control`. |
| `probes/ddc-return-codes.swift` | The probe that showed HDMI I2C failing with `0xE0114000`. Historical. |

The probes do not take the cross-process bus lock: quit Menubar DDC Control before running them.
