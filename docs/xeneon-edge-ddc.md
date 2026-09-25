# CORSAIR XENEON EDGE: DDC/CI reference

What we learned controlling the CORSAIR XENEON EDGE (14.5", 2560×720) from macOS without
iCUE, verified against a real unit on 2026-09-25. It's written for anyone building their own
tool for this monitor, on any OS.

**The short version:**
- The Edge's picture settings are **standard VESA DDC/CI (MCCS 2.2)** on a Realtek scaler.
  Brightness, contrast, sharpness and presets all work with any DDC/CI tool.
- The Edge has **no on-screen menu**. DDC/CI (or iCUE on Windows) is the only way to change
  its settings, so a bad write can leave you with no way back. Read [Recovery](#recovery) before you write anything.
- **RGB gain writes are silently ignored**, and **leaving the User 1 preset destroys its
  factory calibration** until you send VCP `0x08`. These two quirks cause almost every problem.

Status used below: **verified** (done and read back on the device), **read only** (we only
read it), **untested** (advertised, never sent), **not supported** (the monitor says so or
never answers).

## Connections

| Link | DDC/CI | Notes |
|---|---|---|
| USB-C (DisplayPort Alt Mode), direct to a Mac's Thunderbolt/USB-C port | ✅ works | Needs a cable that carries DP Alt Mode; a charge-only USB-C cable gives power but no picture. |
| HDMI into the built-in HDMI port of an M1 Max MacBook Pro | ❌ every I2C transfer fails with `IOReturn 0xE0114000` | The EDID still reads fine, so the display appears normally; only DDC/CI is blocked, on the Mac's side. Other hosts' HDMI ports were not tested. |

Over USB-C the Edge also shows up as USB devices:

| USB ID | What | Needed for picture settings? |
|---|---|---|
| `1b1c:1d0d` "XENEON EDGE" (CORSAIR) | Vendor HID, usage page `0xFF1B` usage `0x91`, report ID `0x01`, 63-byte input and output reports: Corsair's "Bragi" control channel used by iCUE | No. Everything below works without it. It may be how iCUE writes RGB gains (see [Open questions](#open-questions)). |
| `27c0:0859` "TouchScreen" (wch.cn) | Touch controller (HID digitizer and mouse-emulation interfaces) | No |

## Identity (EDID)

| Field | Value |
|---|---|
| Manufacturer (PNP ID) | `CRX` (`0x0E58`, 3672), which is what macOS reports as the vendor number |
| Product code | `0xED00` (60672) |
| Serial number field | `0x01010101` (a placeholder, identical across units, so don't use it to tell two Edges apart) |
| Monitor name descriptor | `XENEON EDGE` |
| Size | 256 bytes (base block + one CEA extension) |
| HDMI vendor-specific data block | Present when connected over HDMI, absent over USB-C |

## Capabilities string

Read with the standard fragmented Capabilities Request (`0xF3`), verbatim:

```
(prot(monitor)type(LCD)model(RTK)cmds(01 02 03 07 0C E3 F3)vcp(02 04 05 06 08 0B 0C 10 12 14(01 02 04 05 06 08 0B) 16 18 1A 52 60(01 03 04 0F 10 11 12) 87 AC AE B2 B6 C6 C8 CA CC(01 02 03 04 06 0A 0D) D6(01 04 05) DF FD FF)mswhql(1)asset_eep(40)mccs_ver(2.2))
```

`model(RTK)` and VCP `0xC8` both indicate a Realtek scaler. Parts of the list are the
scaler's generic firmware defaults rather than features of this monitor (see `0x60`, `0x06`, `0xCC`).

## VCP codes

"Range" is the maximum the monitor reports in its Get VCP reply. "Observed" is the value
read on a unit in its factory state: User 1 preset, factory-calibrated gains.

| Code | MCCS name | Range | Observed | Status | What it does and what we found |
|---|---|---|---|---|---|
| `0x02` | New control value | 0–2 | 1 | read only | Standard "a control changed" flag. |
| `0x04` | Restore factory defaults | write 1 | — | **untested** | Advertised. We never sent it, because the Edge has no menu to fix things if it misbehaves. |
| `0x05` | Restore brightness/contrast | write 1 | — | untested | Advertised. |
| `0x06` | Restore geometry | write 1 | — | untested | Advertised, but geometry means nothing on an LCD; generic scaler entry. |
| `0x08` | Restore colour defaults | write 1 (reads back 0, max 1) | — | **verified** | **The recovery command.** It restored User 1's gains to the factory 151/127/139 after they had been reset to 255/255/255. Brightness (95), contrast (50) and the preset (User 1) were unchanged by it. |
| `0x0B` | Colour temperature increment | — | 100 | read only | 100 K per step of `0x0C` (the reported maximum is 0, which is normal for this read-only code). |
| `0x0C` | Colour temperature request | 0–63 | 35 | verified: **snaps to a preset** | Kelvin = 3000 + value × 100, so 3000–9300 K. **It isn't a fine control:** every write selects a preset and the value snaps to that preset's temperature, as in the table after this one. So in effect it's a second preset selector, with the same User 1 hazard as `0x14`. |
| `0x10` | Luminance (brightness) | 0–100 | 95 | **verified** | Backlight. Writes take effect immediately and read back exactly (tested 95 → 80 → 95). |
| `0x12` | Contrast | 0–100 | 50 | **verified** | Writes read back exactly. |
| `0x14` | Select colour preset | advertised values `01 02 04 05 06 08 0B`; reported max 11 | 11 (`0x0B`) | verified: **hazard** | `01` sRGB, `02` Native, `04` 5000 K, `05` 6500 K, `06` 7500 K, `08` 9300 K, `0B` User 1 (MCCS names; the temperatures agree with `0x0C` readings). **Selecting any other preset and then returning to User 1 resets User 1's gains to 255/255/255**, which looks far too bright with washed-out blacks. Only `0x08` brings the calibration back. After cycling through several presets, brightness and contrast also read 16/16 on return and had to be rewritten. |
| `0x16` | Video gain: red | 0–255 | 151 | verified: **writes ignored** | Factory calibration of User 1. Writes are acknowledged but the value never changes (tried 200, 100 and 151, in User 1). Reads return User 1's gains whichever preset is active. |
| `0x18` | Video gain: green | 0–255 | 127 | writes ignored | As `0x16`. |
| `0x1A` | Video gain: blue | 0–255 | 139 | writes ignored | As `0x16`. |
| `0x52` | Active control | 0–63 | 35 | read only, unclear | Returned the same reply as `0x0C` when read straight after it, so it may be a stale reply; not relied on. |
| `0x60` | Input source | advertised `01 03 04 0F 10 11 12`; reported max 3 | 15 (`0x0F`, DisplayPort 1) over USB-C | read only | The advertised list (VGA, DVI, DP, HDMI…) is the scaler's generic one; the Edge only has USB-C and HDMI. **Not written:** switching to an unconnected input could blank the screen, and there's no menu to switch back. |
| `0x87` | Sharpness | 0–4 | 2 | read only | 5 steps. Never written. |
| `0xAC` | Horizontal frequency | — | 50600 | read only | Raw value as reported (50.6 kHz at 2560×720 @ 60 Hz). |
| `0xAE` | Vertical frequency | — | 6030 | read only | In 0.01 Hz: 60.30 Hz. |
| `0xB2` | Flat-panel sub-pixel layout | 0–1 | 1 | read only | MCCS `01` = RGB vertical stripe. |
| `0xB6` | Display technology type | 0–5 | 3 | read only | MCCS `03` = TFT LCD. |
| `0xC6` | Application enable key | 0–255 | 90 (`0x5A`) | read only | |
| `0xC8` | Display controller type | — | 9 | read only | MCCS manufacturer `0x09` = Realtek, matching `model(RTK)`. |
| `0xCA` | OSD | 0–2 | 1 | read only | The Edge has no OSD. |
| `0xCC` | OSD language | advertised `01 02 03 04 06 0A 0D`; max 13 | 2 (English) | read only | Traditional Chinese, English, French, German, Japanese, Spanish, Simplified Chinese. No visible OSD, so the effect of changing it is unknown. |
| `0xD6` | Power mode | advertised `01 04 05` | 1 (on) | read only | **Not written:** standby or off (`04`/`05`) may not be reversible over DDC/CI. |
| `0xDF` | VCP version | — | 514 (`0x0202`) | read only | MCCS 2.2. |
| `0xFD` | Manufacturer specific | — | — | not supported | Advertised, but reads get no reply. |
| `0xFF` | Manufacturer specific | — | — | not supported | Advertised, but reads get no reply. |
| `0x72` | Gamma | — | — | **not supported** | Not advertised; the reply's result code says unsupported. **The Edge has no hardware gamma.** |
| `0xF1` | (unassigned) | max 65535 | 1 | read only | Not advertised, but answers. Meaning unknown; never written. |
| `0xE0`–`0xFE` (others) | Manufacturer range | — | — | not supported | No reply to reads. |

### `0x0C` writes and presets

What each write became, read back about 0.4 s later:

| Written | Read back | Preset selected |
|---|---|---|
| 21 (5100 K) | 20 (5000 K) | `04` 5000 K |
| 25 (5500 K) | 20 (5000 K) | `04` 5000 K |
| 30 (6000 K) | 10 | `01` sRGB |
| 40 (7000 K) | 35 (6500 K) | `05` 6500 K |
| 50 (8000 K) | 45 (7500 K) | `06` 7500 K |

Each preset's own `0x0C` reading: `04` → 20, `05` → 35, `06` → 45, `08` → 63, `01` sRGB → 10,
`02` Native → 10. The snapping isn't simply "nearest preset" (6000 K selected sRGB).

## Quirks, in practice

1. **Fine white-point control isn't possible in hardware.** Gains are read-only and `0x0C`
   only picks presets, so a smooth white point has to be done on the host (GPU gamma tables).
   Xeneon Control does this relative to the preset's own white.
2. **Stay on User 1.** It holds the factory calibration (151/127/139). Touching `0x14` or `0x0C`
   loses it until `0x08`.
3. **Verify every write by reading it back.** The monitor acknowledges writes it ignores,
   so a successful write call proves nothing.
4. **Never let two programs talk to the bus at once.** Interleaved transactions from two
   processes produced replies that passed the checksum but belonged to the wrong request
   (brightness read as 16). Serialise access across processes; XeneonKit takes an `flock` on a
   shared lock file around each transaction.
5. **Timing:** 50 ms after each write before the next message is enough; replies were
   reliable at 40–200 ms. Always validate the reply checksum (XOR with `0x50`) and retry: a
   garbled reply is rare but happens.

## Recovery

If the Edge suddenly looks too bright, blue or washed out, User 1 has probably lost its gains:

1. Close every program that talks to the monitor over DDC/CI.
2. Select User 1: VCP `0x14` = `0x0B` (skip this if it's already active).
3. Send VCP `0x08` = 1 (restore colour defaults), then wait about 3 s.
4. Read back: `0x16/0x18/0x1A` should be 151/127/139. Rewrite brightness (`0x10`) and
   contrast (`0x12`) if they changed.

With this repo: `xeneonctl set 0x08 1`, then `xeneonctl state show`. `xeneonctl state save <file>`
and `state restore <file>` save and restore every value above, falling back to `0x08` for the gains.
With `ddcutil` on Linux, the same steps are `ddcutil setvcp 14 0x0b`, `ddcutil setvcp 08 1`, `ddcutil getvcp 16 18 1A`.

## macOS specifics

- On Apple Silicon, DDC/CI goes through the private `IOAVServiceReadI2C` / `IOAVServiceWriteI2C`
  functions (the approach of m1ddc and MonitorControl): 7-bit address `0x37`, sub-address `0x51`.
- Match the I2C service (`DCPAVServiceProxy`, `Location = External`) to a display by its EDID
  (vendor, product, serial) against `CGDisplayVendorNumber` / `ModelNumber` / `SerialNumber`.
  Skip proxies that can't return an EDID: unplugged displays leave dead ones behind that fail
  every transfer.
- ICC profiles are assigned per display with `ColorSyncDeviceSetCustomProfiles`, independent of the monitor.
- Gamma-table changes made by a process are reverted by macOS when that process exits.

## Open questions

- **How iCUE sets RGB gains.** Probably over the `1b1c:1d0d` HID channel; the protocol for it
  isn't public. That's the only known route to a hardware white point besides presets.
- Whether `0x04` (factory reset) is safe, and what it resets on this monitor.
- What `0xF1` and `0x52` mean here, and whether `0xCC` does anything with no OSD.
- Whether HDMI DDC/CI works from other hosts (a PC, or later Macs whose HDMI ports pass DDC).

## Sources and credit

- VESA MCCS 2.2 / DDC/CI 1.1 for code names and framing.
- [aabdelghani/corsair-xeneon-edge-linux](https://github.com/aabdelghani/corsair-xeneon-edge-linux) and
  [pascallink/MacOS-Corsair-Xenon](https://github.com/pascallink/MacOS-Corsair-Xenon), for the USB IDs, the HID report layout and the touch controller.
- [waydabber/m1ddc](https://github.com/waydabber/m1ddc) for the IOAVService approach.
- Everything in the VCP tables was measured on the device for this project.
