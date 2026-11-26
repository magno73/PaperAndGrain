#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# release (default): optimized universal binary for Apple silicon and Intel. debug: fast local build.
configuration="${1:-release}"
version="$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)"
app="dist/$version/Paper & Grain.app"
if [ "$configuration" = "release" ]; then
    flags=(--disable-sandbox --configuration release --arch arm64 --arch x86_64)
else
    flags=(--disable-sandbox --configuration "$configuration")
fi
swift build "${flags[@]}"
build_dir="$(swift build "${flags[@]}" --show-bin-path)"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/it.lproj"
cp "$build_dir/PaperAndGrain" "$app/Contents/MacOS/"
cp Resources/Info.plist "$app/Contents/"
cp Resources/Demo.png "$app/Contents/Resources/"
cp Resources/AppIcon.icns "$app/Contents/Resources/"
cp -R Resources/FilmLooks "$app/Contents/Resources/"
cp -R Resources/PrintProfiles "$app/Contents/Resources/"
if [ -d Resources/ICCProfiles ]; then cp -R Resources/ICCProfiles "$app/Contents/Resources/"; fi
cp Resources/it.lproj/InfoPlist.strings "$app/Contents/Resources/it.lproj/"
xcrun xcstringstool compile Resources/Localizable.xcstrings --output-directory "$app/Contents/Resources"
codesign --force --sign - --entitlements Resources/PhotoLibrary.entitlements "$app"
# Every build also lands in one fixed place, so the latest app is always easy to find.
install_dir="${PAPERGRAIN_INSTALL_DIR:-$HOME/Applications}"
installed="$install_dir/$(basename "$app")"
mkdir -p "$install_dir"
rm -rf "$installed"
ditto "$app" "$installed"
printf '%s\n' "$installed"
