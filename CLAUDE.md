# Xeneon Control

A macOS menu bar app and CLI that control a CORSAIR XENEON EDGE (and any other DDC/CI
monitor) from a Mac: brightness, contrast, sharpness, colour preset, white point, RGB
gains, OSD language, restore commands, ICC profile assignment, a GPU gamma fallback for
links without DDC/CI, and saved snapshots.

- **Ownership:** personal project (decided 2026-09-25). No business separation needed.
- **Skills adopted:** `apple-hig-expert` (UI), `code-review` (before merging). Both are pre-approved.
- **Last hygiene audit:** none yet. Baseline 1,968 Swift source lines at the first merge
  (branch `feature/2026-09-25@ddc-menubar-app`). Audit after roughly 10,000 more.

## Layout

- `Sources/XeneonKit`: no UI. DDC/CI framing and I2C over the private `IOAVService*`
  functions (resolved with `dlsym`), capabilities parsing, EDID pairing, ColorSync ICC and
  software gamma.
- `Sources/XeneonControl`: the SwiftUI app (`MenuBarExtra` + `Settings`), `LSUIElement`.
- `Sources/xeneonctl`: the CLI, also bundled inside the app at `Contents/Resources/xeneonctl`.
- `Tests/XeneonKitTests`: Swift Testing; fixtures are bytes captured from the real Edge.

## Commands

- `swift test`: unit tests (no hardware needed).
- `./scripts/build-app.sh [--install]`: builds `build/Xeneon Control.app`, ad-hoc signed,
  and with `--install` copies it to `~/Applications`.
- `swift run xeneonctl list|caps|get|set|profiles|profile`: talks to the real display.
- `"build/Xeneon Control.app/Contents/MacOS/XeneonControl" --debug-open-menu --debug-snapshot <dir>`
  opens the **real** menu bar popover (by sending its own status button a mouse-down) and writes
  every window to `<dir>/<n>.png`, then `<n>-expanded.png` with the GPU adjustments disclosure expanded.
  `--debug-show-ui` instead shows the popover content in a panel and opens Settings (enlarged
  to 900×1900 for the snapshot). This is how to look at the UI, because the terminal has neither
  Accessibility nor Screen Recording permission. Quit the installed app first (see the bus note below).
- Known-good Edge state: `~/Library/Application Support/Xeneon Control/xeneon-edge-known-good-2026-09-25.json`;
  `xeneonctl state restore <that file>` puts it back (it falls back to 0x08 for the gains).

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
  This happened once, on 2026-09-25, and was recovered with `xeneonctl set 0x08 1`.
- Two processes on the bus interleave transactions and read plausible but wrong values
  (brightness "16"). `DDCChannel` now takes an `flock` on `$TMPDIR/XeneonKit-DDC.lock` around
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
