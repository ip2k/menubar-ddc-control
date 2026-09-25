#!/bin/zsh
# Packages build/Menubar DDC Control.app into build/Menubar-DDC-Control-<version>.dmg, with an
# Applications shortcut to drag it onto. Run scripts/build-app.sh first. Prints the DMG's path.
# Fails if the image holds anything else; ALLOW_EXTRA_FILES=1 only warns (for local test builds).
set -euo pipefail
cd "${0:A:h}/.."

app="build/Menubar DDC Control.app"
[[ -d "$app" ]] || { echo "build the app first: scripts/build-app.sh" >&2; exit 1; }
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
dmg="build/Menubar-DDC-Control-$version.dmg"

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"
rm -f "$dmg"
# Build a writable image first and remove anything but the app and the shortcut: tools that
# watch for new volumes (Hedge, for one) drop marker files into it while hdiutil has it mounted.
rw="$staging.rw.dmg"
hdiutil create -quiet -volname "Menubar DDC Control $version" -srcfolder "$staging" -fs HFS+ -format UDRW -ov "$rw"
mount="$(mktemp -d)"
hdiutil attach -quiet -nobrowse -noautoopen -mountpoint "$mount" "$rw"
find "$mount" -mindepth 1 -maxdepth 1 ! -name "Menubar DDC Control.app" ! -name Applications -exec rm -rf {} +
hdiutil detach -quiet "$mount"
hdiutil convert -quiet "$rw" -format UDZO -o "$dmg"
rm -f "$rw"

# Refuse to hand over an image with anything else in it (release builds run on clean CI runners).
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$mount" "$dmg"
extra="$(find "$mount" -mindepth 1 -maxdepth 1 ! -name "Menubar DDC Control.app" ! -name Applications -exec basename {} \;)"
hdiutil detach -quiet "$mount"
if [[ -n "$extra" ]]; then
  echo "unexpected files in $dmg: ${extra//$'\n'/ }" >&2
  [[ -n "${ALLOW_EXTRA_FILES:-}" ]] || exit 1
fi
echo "$dmg"
