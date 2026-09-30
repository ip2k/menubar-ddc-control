# Investigation log

Hardware: an M1 Max MacBook Pro running macOS 26, with a CORSAIR XENEON EDGE (14.5", 2560×720) and a
second DDC/CI monitor for comparison. All VCP values are from that one Edge.

## 2026-09-25: how the Edge is controlled

**Starting point.** The Edge has no on-screen menu; iCUE (Windows only) is its only official control,
and it was assumed to use a proprietary protocol.

**Connected over HDMI, DDC/CI never answered.** A first probe (`tools/probes/ddc-probe.swift`) found
the Edge's `DCPAVServiceProxy`, read its EDID and sent Get VCP requests for nine common codes: no
reply to any. The same probe got full answers from the second monitor, so the probe was sound.
`tools/probes/ddc-return-codes.swift` then showed every I2C transfer on the Edge's port failing with
`IOReturn 0xE0114000`, while the EDID (with an HDMI vendor block) read fine. The monitor never saw the
request: the M1 Max MacBook Pro's built-in HDMI port blocks DDC/CI.

**The USB side.** The Edge's USB cable exposes `1b1c:1d0d` "XENEON EDGE" (vendor HID, usage page
`0xFF1B`, 64-byte reports with report ID 1: Corsair's "Bragi" channel) and `27c0:0859` "TouchScreen".
Prior work (linked from [README.md](README.md)) showed Bragi GET framing works, but no project had
found picture controls on it; OpenLinkHub's Edge module only renders widgets. Every existing tool did
picture settings over DDC/CI.

**Over USB-C (DisplayPort Alt Mode), everything answered.** The owner switched cables. The probe
returned brightness 95/100, contrast 50, preset User 1, gains 151/127/139, and a full MCCS 2.2
capabilities string from a Realtek scaler (`model(RTK)`). So the "proprietary protocol" was standard
DDC/CI all along; HDMI was the obstacle. Read-only probing of the rarer codes found the colour
temperature pair (`0x0B` = 100 K steps, `0x0C` = 35 → 6500 K), sharpness 0–4, 60.30 Hz, and no gamma
(`0x72` unsupported).

**Incident 1: the calibration was wiped.** To learn the factory presets' gains, presets were cycled
over DDC (`0x0C` writes, then presets 04, 05, 06, 08, 01 sRGB, 02 Native) and User 1 re-selected.
User 1's gains came back 255/255/255 and brightness/contrast 16/16: far too bright, washed-out blacks.
Gain writes (200, 100, 151) were acknowledged and ignored. The Edge has no menu, so the owner could
not fix it. Brightness and contrast were rewritten; **VCP `0x08` (restore colour defaults) brought back
151/127/139**, the factory calibration. Two lessons became rules: never experiment with writes on a
menu-less monitor without a saved state and a known way back; and verify every write by reading it back.
A stray reading of brightness "16" was also traced to the app and the CLI interleaving transactions on
the same bus, which led to the cross-process `flock` in `DDCChannel`.

**Narrowing the trigger (later that day).** With the state saved and the recovery known, a round trip
through only the temperature presets (`04`, `06`) and back to User 1 kept everything intact. The
wipe therefore came from sRGB/Native or the `0x0C` writes; which one was not isolated, on purpose.

**What followed from it.** The white-point slider had been writing `0x0C`, which only selects presets
(writes snap: 21→20, 25→20, 30→10 with sRGB selected, 40→35, 50→45). Hardware white point became a
menu of the four temperature presets; fine white point moved to the GPU. The app reads every monitor's
state, read-only, before allowing any write, offers "Restore Previous Values" and "Reset Values to
Factory Defaults" (`0x04` then `0x08`), and repairs User 1 automatically on return to it.

**Debug dump.** Reading every advertised code showed `0x52` (active control) simply echoes the previous
reply (35/63 after `0x0C`, 139/255 after `0x1A`) and the restore codes read as 0/1.

## 2026-09-25: first public release

Renamed from "Xeneon Control" to Menubar DDC Control to avoid using CORSAIR's mark as a product name.
Published at [ip2k/menubar-ddc-control](https://github.com/ip2k/menubar-ddc-control) (MIT) with CI, a
tag-driven release workflow and a same-repo Homebrew tap. The first `brew install` failed:
current Homebrew refuses casks from a tap until `brew trust <tap>`, which the README now says.

## 2026-09-25: icons and theme

The owner's artwork became the app icon (see [decisions.md](decisions.md)); a greyscale downscale
for the menu bar was unreadable at 18 pt, so the glyph is drawn in code
([menubar-icon-comparison.png](menubar-icon-comparison.png)). Rosé Pine Moon/Dawn were contrast-checked
before use ([colour-science.md](colour-science.md)).

## 2026-09-25: green–magenta tint

Researched Duv and implemented tint in Adobe's units ([colour-science.md](colour-science.md)).
Verified on the Edge at its 7500 K preset: Magenta 25 took green to 93 % and blue to 98 %.

**Incident 2: the installed app's settings were wiped.** Screenshot runs used `pkill -x
MenubarDDCControl` and `defaults delete com.ip2k.MenubarDDCControl`, which by then were the owner's
installed app and its settings. Relaunching re-ran the one-time migration from the old
`com.ip2k.XeneonControl` domain, which restored snapshots and first-seen originals; changes made in
0.2.0 were lost. Debug builds now have their own bundle ID (`scripts/build-app.sh --debug`).

## 2026-09-29/30

0.3.0 released. Research artefacts that had lived in a temporary directory were lost to a temp
cleanup; the tools and notes here were rebuilt from the session record, and the icon pipeline was
checked to reproduce the shipped `AppIcon.icns` byte for byte.
