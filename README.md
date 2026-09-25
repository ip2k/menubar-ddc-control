# Xeneon Control

Control a CORSAIR XENEON EDGE, or any DDC/CI monitor, from macOS without iCUE.

The Edge's colour and picture settings are not a proprietary protocol. They are standard
VESA DDC/CI, which macOS itself doesn't expose for third-party monitors. Xeneon Control
talks DDC/CI directly on Apple Silicon and adds a menu bar popover and a settings window.

## Features

- **Hardware controls** (sent to the monitor): brightness, contrast, sharpness, colour
  preset, white point in kelvin, red/green/blue gain, OSD language, and the monitor's
  restore-defaults commands. The controls shown come from the monitor's own capabilities
  string.
- **ICC colour profiles**: assign any installed display profile, import `.icc`/`.icm`
  files (such as ones made with a colorimeter), or revert to the factory profile. This is
  the same setting as System Settings → Displays, so it persists without the app.
- **Software adjustment**: GPU gamma-table brightness, RGB balance and gamma for links
  without DDC/CI, or to dim below the backlight's minimum. It is applied on top of the
  profile's calibration curve and lasts while the app runs.
- **Snapshots**: save and re-apply complete setups (hardware, software and profile).
- **`xeneonctl` CLI** for scripting, e.g. `xeneonctl set brightness 40`.

## Connection matters

DDC/CI needs a link that carries it. **Connect the Edge over USB-C (DisplayPort Alt
Mode).** On M1-generation MacBook Pros the built-in HDMI port blocks DDC/CI, and the app
falls back to software adjustment there. Some docks and adapters also drop DDC/CI.

## Build

Requires Xcode 16+ on an Apple Silicon Mac running macOS 14 or later.

```sh
swift test                      # unit tests
./scripts/build-app.sh --install   # builds and copies "Xeneon Control.app" to ~/Applications
```

The app is ad-hoc signed, unsandboxed (the I2C and ColorSync calls need it), and uses
private `IOAVService` functions, so it cannot be distributed through the App Store.
