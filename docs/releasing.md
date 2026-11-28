# Releasing Paper & Grain

Run the release commands from a clean checkout of the release branch on a Mac with Xcode and an authenticated GitHub CLI. Verify the version in `Resources/Info.plist` and update the corresponding section in [CHANGELOG.md](../CHANGELOG.md).

1. Run `swift test --disable-sandbox` and the relevant checks in [testing status](status.md). Use the sample book or synthetic images for screenshots and files.
2. Run `./scripts/package-release.sh`. It builds an app with both macOS architectures, checks the signature and zip, and writes the download and SHA-256 file under `dist/`. It leaves installed copies of the app in place. The bundle includes [the app license](../LICENSE) and the credits for its bundled assets.
3. Run `./scripts/publish-github.sh --dry-run --tag vX.Y.Z`. The script prepares a public copy of the selected history, removes the internal paths listed in the script and uses GitHub’s noreply address for commit and tag metadata. Check that the push will fast-forward the public branch.
4. Run `./scripts/publish-github.sh --tag vX.Y.Z`, then `./scripts/github-release.sh`. The first command pushes code and tag together. The second checks the checksum and tag before publishing a prerelease. Open the [GitHub release page](https://github.com/magno73/PaperAndGrain/releases) and verify both downloads.

## Signing and notarization

The default beta build is ad hoc signed. Follow the install steps in the [README](../README.md) when testing a downloaded zip on another Mac.

To create a notarized zip, set `PAPERGRAIN_SIGNING_IDENTITY` to an installed **Developer ID Application** identity. Store the Apple notarization credentials in a local Keychain profile using `xcrun notarytool store-credentials`, then set `PAPERGRAIN_NOTARY_PROFILE` to that profile name and run `./scripts/package-release.sh`. The script signs with the Hardened Runtime and a secure timestamp, submits the zip, validates the stapled ticket and regenerates the checksum. Verify the result on a separate Mac and update the release notes before publication. [Apple’s notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
