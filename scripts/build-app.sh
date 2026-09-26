#!/bin/zsh
# Builds build/Menubar DDC Control.app (release, arm64, ad-hoc signed) and stamps the exact
# build identity into its Info.plist, which Settings → About shows.
#
#   VERSION=0.2.0 ./scripts/build-app.sh      version to stamp (default: Resources/Info.plist's)
#   ./scripts/build-app.sh --install          also copy the app to ~/Applications
#   ./scripts/build-app.sh --debug            build/debug/…, bundle ID com.ip2k.MenubarDDCControl.debug:
#                                             its own settings, so screenshot runs never touch a
#                                             real install's settings or its process
set -euo pipefail
cd "${0:A:h}/.."

swift build -c release --product MenubarDDCControl
swift build -c release --product ddc-control
bin="$(swift build -c release --show-bin-path)"

debug=false
[[ "${1:-}" == "--debug" ]] && debug=true
if $debug; then app="build/debug/Menubar DDC Control.app"; else app="build/Menubar DDC Control.app"; fi
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp "$bin/MenubarDDCControl" "$app/Contents/MacOS/MenubarDDCControl"
cp "$bin/ddc-control" "$app/Contents/Resources/ddc-control"
cp LICENSE "$app/Contents/Resources/LICENSE"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"

plist="$app/Contents/Info.plist"
set_key() { /usr/libexec/PlistBuddy -c "Delete :$1" "$plist" >/dev/null 2>&1 || true
            /usr/libexec/PlistBuddy -c "Add :$1 $2 $3" "$plist"; }
version="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)}"
set_key CFBundleShortVersionString string "${version#v}"
if $debug; then set_key CFBundleIdentifier string com.ip2k.MenubarDDCControl.debug; fi
set_key CFBundleVersion string "$(git rev-list --count HEAD 2>/dev/null || echo 0)"
set_key DDCGitCommit string "$(git rev-parse HEAD 2>/dev/null || echo unknown)"
set_key DDCGitDirty bool "$([[ -n "$(git status --porcelain 2>/dev/null)" ]] && echo true || echo false)"
set_key DDCBuildDate string "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
set_key DDCBuildOrigin string "${GITHUB_RUN_ID:+GitHub Actions run $GITHUB_RUN_ID}"
[[ -n "${GITHUB_RUN_ID:-}" ]] || set_key DDCBuildOrigin string "local build"

codesign --force --sign - --timestamp=none "$app/Contents/Resources/ddc-control"
codesign --force --sign - --timestamp=none "$app"
echo "Built $app (version ${version#v}, commit $(git rev-parse --short HEAD 2>/dev/null))"

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p ~/Applications
  rm -rf ~/Applications/"Menubar DDC Control.app"
  cp -R "$app" ~/Applications/
  echo "Installed to ~/Applications/Menubar DDC Control.app"
fi
