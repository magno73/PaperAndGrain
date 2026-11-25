# Contributing to Paper & Grain

Thank you for helping. Paper & Grain is a native Mac app written in SwiftUI; it is source-available under the [PolyForm Noncommercial License](LICENSE). By contributing you agree that your contribution is offered under the same terms.

## Build and test

You need Xcode 26 or later (the macOS 26 SDK). From the repository root:

```sh
swift build                    # compile
swift test                     # run the unit tests
./scripts/build-app.sh debug   # build the app bundle and install it in ~/Applications
```

Test access to Photos with the bundle, not with `swift run`: macOS grants that permission to the signed app. **Open the Sample Book** on the welcome screen needs no permissions at all.

Every pull request runs `swift build` and `swift test` on GitHub Actions with Xcode 26.6 and Xcode 27.2.

## Before you open a pull request

- **Read [AGENTS.md](AGENTS.md).** It lists the entry points of the code and the working rules; it applies to people and to coding agents alike.
- **Keep saved books readable.** New fields in the document model must be optional, and a book saved by an older version must still open.
- **Synthetic images only.** Never commit personal photos, screenshots of private albums, real books or draft texts. Use `Resources/Demo.png` or images generated for the purpose, and the command line (`cli build`) to make test books.
- **Strings in both languages.** Every user-visible string is in the String Catalog (`Resources/Localizable.xcstrings`) with English and Italian. The English text is the key; use an explicit key when the same English needs a different Italian translation. Never inline Italian text in Swift; run `python3 scripts/l10n-pairs.py check` before you commit. Accessibility labels count; command-line output stays in English.
- **Update the documentation in the same change.** The README describes what the app does now, never what changed; the in-app help (`HelpView` in `AboutAndHelp.swift`) follows the README; user-visible changes go in [CHANGELOG.md](CHANGELOG.md); contracts go in [docs/architecture.md](docs/architecture.md); the command-line contract in [docs/cli.md](docs/cli.md); what you verified, and what remains to be tested, in [docs/status.md](docs/status.md).
- **Add a test** for every fix that can be tested without the user interface, and describe how you checked the rest.
- **Run the analysis on the Mac only.** Photo analysis uses Vision locally; nothing is sent over the network.

## Reporting a problem

Open an issue with the macOS version, what you did, what you expected and what happened. If a book or PDF is involved, attach a synthetic example that shows the problem, never a private book.
