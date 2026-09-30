#!/bin/zsh
# Renders docs/research/menubar-icon-comparison.png from the current MenuBarIcon.swift.
set -euo pipefail
cd "${0:A:h}/../../.."
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
swiftc -O tools/icon/make-app-icon.swift -o "$work/make-app-icon"
"$work/make-app-icon" tools/icon/icon-source.jpg "$work/AppIcon-1024.png" >/dev/null
swiftc -O tools/icon/menubar-preview/main.swift Sources/MenubarDDCControl/MenuBarIcon.swift -o "$work/preview"
"$work/preview" "$work/AppIcon-1024.png" docs/research/menubar-icon-comparison.png
