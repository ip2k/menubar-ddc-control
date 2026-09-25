# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- Menu bar app with quick controls for brightness, contrast, colour preset, white point and
  colour balance, and a settings window with every control the monitor advertises.
- Hardware control over DDC/CI: sharpness, OSD language, and restoring colour,
  brightness/contrast or factory defaults (the last one asks first).
- ICC colour profile assignment per display, profile import, and reverting to the factory profile.
- Software (GPU) brightness, RGB balance and gamma for connections without DDC/CI, such as
  the built-in HDMI port on M1 Pro/Max MacBook Pros. It stacks on top of the profile's calibration.
- Snapshots that save and re-apply a display's full setup.
- Open at login.
- `xeneonctl` command-line tool: `list`, `caps`, `get`, `set`, `profiles`, `profile`, and
  `state show|save|restore` to save a monitor's settings to a file and put them back.
- **Restore Previous Values**: every monitor's settings are read, without changing anything,
  when the app starts, and one click puts them back (including the colour profile), checking
  each value afterwards. A copy from the first time each monitor was seen is kept too.
- **Reset Values to Factory Defaults**, with a confirmation step.
- **Monitor and GPU controls are now separate, clearly labelled sections.** By default only the
  monitor's own settings (DDC/CI) are adjustable. GPU adjustments (fine white point, gamma, colour
  balance, extra dimming) stay greyed out at their defaults until you tick "Adjust on the GPU".
- Hardware white point: a menu of the monitor's built-in white points (on the Xeneon Edge, only
  four: 5000, 6500, 7500 and 9300 K), with a note explaining the limit.
- Fine white point on the GPU from 3000 to 9300 K in 10 K steps, with D50, D65, D75 and D93 marks you can tap.
- Gamma in the menu bar popover (GPU; the Xeneon Edge has no hardware gamma).
- Switching the Xeneon Edge back to User 1 restores its factory calibration automatically if
  another preset reset it.
- Debug tools in Settings: read every DDC/CI value into a table, save it as JSON, and load a saved
  file to write its settings back (same monitor model only; verified afterwards).
  `xeneonctl dump` and `xeneonctl load` do the same from the command line.

### Documentation

- A DDC/CI reference for the Xeneon Edge (`docs/xeneon-edge-ddc.md`): every VCP code with its
  range, factory value and behaviour, the quirks, and a recovery procedure.

### Fixed

- Expanding Colour balance no longer pushes Settings and Quit out of the popover.
- The white point slider no longer jumps between 5000, 6500, 7500 and 9300 K. Those were the
  monitor's presets; the white point is now adjusted smoothly on the GPU instead, so the
  monitor's own calibration is never touched.
- The Xeneon Edge's RGB gains are shown read-only: the monitor ignores changes to them, and
  a slider that did nothing was misleading.
- A note under the preset menu explains that some presets on the Xeneon Edge can reset User 1's
  factory calibration, and that switching back restores it.
- Information messages no longer look like warnings.
- Running the app and `xeneonctl` at the same time no longer produces wrong readings.
