# Decisions

Each entry: what was decided, what was turned down, and why.

**A menu bar app, not a driver.** System Settings → Displays offers brightness and colour controls
only for Apple displays, and third-party code cannot add them to that panel. A SwiftUI menu bar app
with a settings window was the reachable equivalent.

**DDC/CI, not Corsair's HID channel.** The Edge's picture settings are standard MCCS over DDC/CI.
The `1b1c:1d0d` HID channel has no known picture commands, and guessing writes to a menu-less
monitor's firmware risked bricking it. HID stays an open question (it may be how iCUE sets gains).

**Capabilities-driven controls.** Controls are built from the monitor's capabilities string and
greyed out if the monitor acknowledges writes but ignores them (verified by read-back), so the app
works on other DDC/CI monitors and never shows a slider that does nothing.

**Private `IOAVService` I2C, resolved with `dlsym`.** It is the only DDC path on Apple Silicon (as in
m1ddc and MonitorControl). Resolving at runtime makes a future macOS that drops it lose DDC instead
of crashing. It rules out the Mac App Store.

**Hardware first; GPU opt-in.** By default only the monitor's own settings change. GPU adjustments
(fine white point, tint, gamma, balance, extra dimming) sit behind "Adjust colours using GPU", greyed
out at defaults until ticked; unticking stops applying them and keeps their values. The owner wanted
users to see what the hardware can do before reaching for the GPU.

**Hardware white point as a menu.** `0x0C` only selects presets, so a slider promised steps that do
not exist. It is a drop-down of the four temperature presets, with a note that the Edge has only four.

**Read-only launch snapshot, then verified restores.** Writes are refused until every monitor's state
has been read. Restores go preset → temperature → gains (falling back to `0x08`) → luminance, and read
every value back. A "first seen" copy is kept for good. This followed incident 1 in the log.

**Name: Menubar DDC Control.** "Xeneon Control" used CORSAIR's mark as the product name; the app names
the monitor it works with ("built for the CORSAIR XENEON EDGE") and says it is not affiliated.

**Ad-hoc signed, not notarized.** The owner's choice: notarizing with a Developer ID would put a legal
name in the signature and need Apple credentials in CI. The README documents opening it the first time.

**Releases from CI on a tag; Homebrew tap in the same repo.** The official `homebrew/cask` needs
notability and (as understood) notarized apps. A same-repo tap is bumped by the release workflow with
the built-in token, so no personal token goes into secrets. Users must `brew trust` the tap.

**Update checker instead of Sparkle.** A weekly `GET` of the latest GitHub release, on by default and
switchable, that prompts to download the DMG (or copies `brew upgrade` for Homebrew installs). Sparkle
needs EdDSA keys and an appcast: more than an unsigned app benefits from.

**Icons.** The owner's artwork, masked with macOS's continuous-corner shape (22.37 % radius, just
inside the artwork's 19 %) on Apple's 824/1024 grid. For the menu bar, a vector template glyph (two
arrows around two gears) drawn in code, chosen over a downscale of the artwork on the evidence of
[menubar-icon-comparison.png](menubar-icon-comparison.png). The Edge runs at 1x, where the gears merge;
a pixel-tuned 1x variant is possible if it matters.

**Rosé Pine with contrast fixes.** Moon/Dawn follow the system appearance. Secondary text is `subtle`
nudged towards `text`, Dawn's gold is kept off text, and links avoid Dawn's iris; see
[colour-science.md](colour-science.md).

**Debug builds are isolated.** Screenshot and debug runs use `scripts/build-app.sh --debug` (bundle
`com.ip2k.MenubarDDCControl.debug`) and never touch the installed app's process or settings, after
incident 2.
