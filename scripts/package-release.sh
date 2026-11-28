#!/bin/bash
# Build a universal zip for GitHub Releases without replacing the locally installed app.
set -euo pipefail
cd "$(dirname "$0")/.."
version="$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)"
# Sign on a local volume before publishing the archive to dist.
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
app="$staging/Paper & Grain.app"
zip="dist/Paper-and-Grain-$version.zip"
if [ -n "${PAPERGRAIN_NOTARY_PROFILE:-}" ] && [ -z "${PAPERGRAIN_SIGNING_IDENTITY:-}" ]; then
    echo "Set PAPERGRAIN_SIGNING_IDENTITY to a Developer ID Application identity before notarizing." >&2
    exit 2
fi
PAPERGRAIN_BUNDLE_DIR="$staging" PAPERGRAIN_SKIP_INSTALL=1 ./scripts/build-app.sh release >/dev/null
mkdir -p dist
codesign --verify --deep --strict "$app"
architectures="$(lipo -archs "$app/Contents/MacOS/PaperAndGrain")"
for architecture in arm64 x86_64; do
    if [[ " $architectures " != *" $architecture "* ]]; then
        echo "The release bundle is missing the $architecture slice." >&2
        exit 1
    fi
done

archive() {
    rm -f "$zip"
    ditto -c -k --keepParent --norsrc --noextattr "$app" "$zip"
}

archive
if [ -n "${PAPERGRAIN_NOTARY_PROFILE:-}" ]; then
    xcrun notarytool submit "$zip" --keychain-profile "$PAPERGRAIN_NOTARY_PROFILE" --wait
    xcrun stapler staple "$app"
    xcrun stapler validate "$app"
    archive
fi

unzip -tq "$zip" >/dev/null
(cd dist && shasum -a 256 "$(basename "$zip")" > "$(basename "$zip").sha256")
printf '%s\n%s\n' "$PWD/$zip" "$PWD/$zip.sha256"
