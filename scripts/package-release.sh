#!/bin/bash
# Builds the universal release app and packs it for a GitHub Release:
#   dist/Paper-and-Grain-<version>.zip and its .sha256.
# The app is signed ad hoc, not notarized: the README explains how to open it.
set -euo pipefail
cd "$(dirname "$0")/.."
version="$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)"
./scripts/build-app.sh release >/dev/null
app="dist/$version/Paper & Grain.app"
zip="dist/Paper-and-Grain-$version.zip"
rm -f "$zip" "$zip.sha256"
ditto -c -k --keepParent --sequesterRsrc "$app" "$zip"
(cd dist && shasum -a 256 "$(basename "$zip")" > "$(basename "$zip").sha256")
codesign --verify --deep --strict "$app"
printf '%s\n%s\n' "$PWD/$zip" "$PWD/$zip.sha256"
