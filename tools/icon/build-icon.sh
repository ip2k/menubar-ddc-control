#!/bin/zsh
# Rebuilds Resources/AppIcon.icns and docs/images/icon.png from tools/icon/icon-source.jpg.
set -euo pipefail
cd "${0:A:h}/../.."
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
swiftc -O tools/icon/make-app-icon.swift -o "$work/make-app-icon"
"$work/make-app-icon" tools/icon/icon-source.jpg "$work/AppIcon-1024.png"
mkdir "$work/AppIcon.iconset"
for s in 16 32 128 256 512; do
  sips -z $s $s "$work/AppIcon-1024.png" --out "$work/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) "$work/AppIcon-1024.png" --out "$work/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$work/AppIcon.iconset" -o Resources/AppIcon.icns
sips -z 256 256 "$work/AppIcon-1024.png" --out docs/images/icon.png >/dev/null
echo "wrote Resources/AppIcon.icns and docs/images/icon.png"
