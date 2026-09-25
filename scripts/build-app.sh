#!/bin/zsh
# Builds build/Xeneon Control.app (release, ad-hoc signed). Pass --install to copy it to ~/Applications.
set -euo pipefail
cd "${0:A:h}/.."

swift build -c release --product XeneonControl
swift build -c release --product xeneonctl
bin="$(swift build -c release --show-bin-path)"

app="build/Xeneon Control.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp "$bin/XeneonControl" "$app/Contents/MacOS/XeneonControl"
cp "$bin/xeneonctl" "$app/Contents/Resources/xeneonctl"
codesign --force --sign - --timestamp=none "$app/Contents/Resources/xeneonctl"
codesign --force --sign - --timestamp=none "$app"
echo "Built $app"

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p ~/Applications
  rm -rf ~/Applications/"Xeneon Control.app"
  cp -R "$app" ~/Applications/
  echo "Installed to ~/Applications/Xeneon Control.app"
fi
