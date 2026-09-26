# Menubar DDC Control

Public at https://github.com/ip2k/menubar-ddc-control (MIT). Renamed from "Xeneon Control" before the
first release to stay clear of CORSAIR's trademark; the app migrates the old `com.ip2k.XeneonControl` settings once.

A macOS menu bar app and CLI that control a CORSAIR XENEON EDGE (and any other DDC/CI
monitor) from a Mac: brightness, contrast, sharpness, colour preset, white point, RGB
gains, OSD language, restore commands, ICC profile assignment, a GPU gamma fallback for
links without DDC/CI, and saved snapshots.

- **Ownership:** personal project (decided 2026-09-25). No business separation needed.
- **Skills adopted:** `apple-hig-expert` (UI), `code-review` (before merging). Both are pre-approved.
- **Last hygiene audit:** none yet. Baseline 1,968 Swift source lines at the first merge
  (branch `feature/2026-09-25@ddc-menubar-app`). Audit after roughly 10,000 more.

## Layout

- `Sources/DDCKit`: no UI. DDC/CI framing and I2C over the private `IOAVService*`
  functions (resolved with `dlsym`), capabilities parsing, EDID pairing, ColorSync ICC and
  software gamma.
- `Sources/MenubarDDCControl`: the SwiftUI app (`MenuBarExtra` + `Settings`), `LSUIElement`.
- `Sources/ddc-control`: the CLI, also bundled inside the app at `Contents/Resources/ddc-control`.
- `Tests/DDCKitTests`: Swift Testing; fixtures are bytes captured from the real Edge.

## Commands

- `swift test`: unit tests (no hardware needed).
- `./scripts/build-app.sh [--install]`: builds `build/Menubar DDC Control.app` (arm64, ad-hoc signed),
  stamps version/commit/dirty flag/build date into Info.plist (`VERSION=x.y.z` overrides the version),
  and with `--install` copies it to `~/Applications`. `./scripts/make-dmg.sh` packages it, and fails if
  anything else ends up in the image. Hedge on the owner's Mac marks every mounted volume, so
  local DMGs need `ALLOW_EXTRA_FILES=1` and must not be published; releases come from CI.
- Releases: move `[Unreleased]` in CHANGELOG.md under `## [x.y.z] - date`, merge, push tag `vx.y.z`.
  `.github/workflows/release.yml` builds, publishes the release (notes = that CHANGELOG section) and
  bumps `Casks/menubar-ddc-control.rb` on `main`. The repo is its own Homebrew tap. Not notarized
  (ad-hoc signed, by choice).
- Theme: Rosé Pine Moon/Dawn in `Sources/MenubarDDCControl/Theme.swift` (values from rose-pine/palette).
  Use `Theme.*` colours, never system ones: `secondaryText` (subtle nudged toward text for 4.5:1),
  `gold` only for warning *icons* (2.2:1 on Dawn), `link` for links, `muted` for decoration only.
  Form sections are `ThemedSection`, forms get `.themedForm()`.
- Icons: `Resources/AppIcon.icns` is built from the owner's artwork (masked to Apple's 824/1024 grid);
  `MenuBarIcon.swift` draws the menu bar template glyph in code.
- README screenshots: build with `./scripts/build-app.sh --debug` (bundle ID `…MenubarDDCControl.debug`,
  at `build/debug/`) and only ever launch, kill (`pkill -f "build/debug/"`) and `defaults delete
  com.ip2k.MenubarDDCControl.debug` that copy. **Never `pkill -x MenubarDDCControl` or delete
  `com.ip2k.MenubarDDCControl`**: that is the owner's installed app and its settings (this wiped them
  once, 2026-09-25; the old-domain migration brought snapshots and originals back). Flags:
  `--debug-appearance dark|light`, `--debug-open-menu`/`--debug-show-ui`, `--debug-only XENEON` (hides
  the owner's other displays), `--debug-gpu-on`, `--debug-tint <n>` (changes the picture while it runs),
  `--debug-tab <n>`, `--debug-height <pt>`, `--debug-snapshot <dir>`. Crop into `docs/images/`
  (`sips --cropOffset 0 0` centres instead of cropping from the top; use 1 1). Snapshots always
  render at 2x; crop offsets for a 900x2600 pt settings capture: monitor 1+1340, ICC/GPU 1530+1380,
  Restore/Debug 2915+1940 (shift if sections grow).
- Known-good Edge state: `~/Library/Application Support/Menubar DDC Control/xeneon-edge-known-good-2026-09-25.json`;
  `ddc-control state restore <that file>` puts it back (it falls back to 0x08 for the gains).

## Hardware facts (verified on the owner's Edge, 2026-09-25)

The full, public reference is `docs/xeneon-edge-ddc.md`: keep it in step with anything newly
measured, and keep personal identifiers (USB serials, the owner's machine) out of it.

- The Edge's picture settings are **standard DDC/CI (MCCS 2.2)** on a Realtek scaler
  (`model(RTK)`). iCUE's USB HID channel (`1b1c:1d0d`, usage page `0xFF1B`) is not needed
  for any of them.
- On this M1 Max MacBook Pro, **the built-in HDMI port rejects every I2C transfer**
  (`IOReturn 0xE0114000`). Over USB-C (DP Alt mode) DDC works. The app falls back to GPU
  gamma when a link does not answer.
- Colour temperature: VCP `0x0B` = 100 K per step, `0x0C` = 0…63 → 3000–9300 K, **but the
  scaler snaps any write to a preset** (5000/6500/7500/9300 K) and switches the preset with it.
  So `0x0C` is a preset selector, not a fine control. Fine white point is done on the GPU.
- **The Edge has no on-screen menu.** Settings are reachable only over DDC (or iCUE on Windows).
- **User 1's factory calibration is R/G/B 151/127/139.** RGB gain writes (`0x16/18/1A`) are
  silently ignored over DDC, and leaving User 1 and returning resets its gains to 255/255/255
  (washed out, far too bright). **VCP `0x08` (restore colour defaults) brings back 151/127/139.**
  This happened once, on 2026-09-25, and was recovered with `ddc-control set 0x08 1`.
- Two processes on the bus interleave transactions and read plausible but wrong values
  (brightness "16"). `DDCChannel` now takes an `flock` on `$TMPDIR/DDCKit.lock` around
  every transaction; keep it.
- Presets (`0x14`): 01 sRGB, 02 Native, 04 5000 K, 05 6500 K, 06 7500 K, 08 9300 K, 0B User 1.
- `0x60` input and `0xD6` power are advertised but deliberately not exposed: the input list
  is the scaler's generic one (VGA/DVI/…) and does not match the Edge's real ports.
- `0xFD`/`0xFF` (manufacturer codes) do not answer reads.

## Upstream contribution candidates

- The Edge's full VCP map above (colour temperature, sharpness range, preset list, HDMI-on-M1
  finding) would help `aabdelghani/corsair-xeneon-edge-linux` and
  `pascallink/MacOS-Corsair-Xenon`. Their docs mark HID as the unknown and DDC as brightness
  only. Draft only; follow `oss-contributions` and get sign-off before posting.
