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
- `xeneonctl` command-line tool: `list`, `caps`, `get`, `set`, `profiles`, `profile`.
