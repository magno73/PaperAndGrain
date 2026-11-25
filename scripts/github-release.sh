#!/bin/bash
# Creates the GitHub Release for the current version with the packaged zip.
# Run after scripts/package-release.sh and scripts/publish-github.sh --tag v<version>.
# The release notes are the CHANGELOG.md section of that version.
set -euo pipefail
cd "$(dirname "$0")/.."
repo="${PAPERGRAIN_GITHUB_SLUG:-magno73/PaperAndGrain}"
version="$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)"
tag="v$version"
zip="dist/Paper-and-Grain-$version.zip"
[ -f "$zip" ] || { echo "Missing $zip: run scripts/package-release.sh first." >&2; exit 1; }
notes="$(mktemp)"
trap 'rm -f "$notes"' EXIT
# The section between "## <version>" and the next "## " heading.
awk -v v="$version" '$0 ~ "^## " { if (found) exit; if (index($0, v)) { found = 1; next } } found' CHANGELOG.md > "$notes"
[ -s "$notes" ] || { echo "CHANGELOG.md has no section for $version." >&2; exit 1; }
gh release create "$tag" "$zip" "$zip.sha256" --repo "$repo" --title "Paper & Grain $version" --notes-file "$notes"
