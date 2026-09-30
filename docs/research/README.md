# Research notes

How Menubar DDC Control came to work the way it does: what was tried on a real CORSAIR XENEON
EDGE, what was found, and why each decision was taken. The device-level reference, with every VCP
code, is [../xeneon-edge-ddc.md](../xeneon-edge-ddc.md). This folder is the story around it.

| File | What it is |
|---|---|
| [investigation-log.md](investigation-log.md) | Chronological log of the investigation, 2026-09-25 to 09-30, including the two incidents and how they were recovered |
| [colour-science.md](colour-science.md) | White point (daylight/Planckian locus), green–magenta tint (Duv), GPU gamma stacked on calibration, and the Rosé Pine contrast analysis |
| [decisions.md](decisions.md) | Decision record: what was chosen, the alternatives turned down, and why |
| [menubar-icon-comparison.png](menubar-icon-comparison.png) | The vector menu bar glyph against a greyscale downscale of the app icon, at 1x/2x on light/dark menu bars (regenerate with `tools/icon/menubar-preview/run.sh`) |
| [data/xeneon-edge-user1-factory-state.json](data/xeneon-edge-user1-factory-state.json) | The Edge's settings in its factory User 1 state, saved with `ddc-control state save`; restore with `ddc-control state restore <file>` |
| [data/xeneon-edge-dump-2026-09-30.json](data/xeneon-edge-dump-2026-09-30.json) | Every advertised VCP code, read-only (`ddc-control dump`), from the same unit as the owner had it set on 2026-09-30 |

The state file stores values as `[code, value, code, value, …]` (decimal). Decoded:
`0x0C` 35 (6500 K) · `0x10` 95 · `0x12` 50 · `0x14` 11 (User 1) · `0x16/18/1A` 151/127/139 ·
`0x87` 2 · `0xCC` 2 (English).

Tools used along the way are in [../../tools/](../../tools/).

Other projects' protocol notes that informed this work (the USB IDs, the HID report layout, the touch
controller) are GPL-licensed, so they are linked rather than copied:
[aabdelghani/corsair-xeneon-edge-linux](https://github.com/aabdelghani/corsair-xeneon-edge-linux) `PROTOCOL.md`,
[pascallink/MacOS-Corsair-Xenon](https://github.com/pascallink/MacOS-Corsair-Xenon) `PROTOCOL-MACOS.md`, and
[jurkovic-nikola/OpenLinkHub](https://github.com/jurkovic-nikola/OpenLinkHub) `src/devices/xeneonedge/`.
