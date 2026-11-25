# Paper & Grain

Paper & Grain is a native Mac editor for travel photobooks. The interface is in English and Italian. Work from the repository root and read the [README](README.md) for the user flow. These instructions apply to people and to coding agents alike.

## Entry points

- `PaperAndGrainApp.swift` and `Workspace.swift` connect windows, opening, autosave and running tasks.
- `BookCLI.swift` connects composition and terminal commands. `BookCLIEditing.swift` applies patches and creates variants, `BookCLIMedia.swift` handles import and export, and `BookCLIPhotoIndex.swift` exposes the catalog and search. Update the contract in [CLI](docs/cli.md) when arguments, input or output change.
- `AlbumPicker.swift` and `PhotoLibrary.swift` connect the selection, PhotoKit and the copying of images. `DroppedPhotos.swift` imports files into the library of the open book. `PhotoPromiseDropTarget.swift` receives files promised by macOS apps.
- `BookModel.swift` and `BookStorage.swift` define the data, the geometry and the project format. `AppErrors.swift` holds the errors shown to the author (book moved, newer format, read-only location, damaged manifest, image unavailable).
- `EditorView.swift` holds the state of the open book, the window structure and the shared tools. The `EditorView+*.swift` extensions split it by area: `Navigator` (pages and reordering), `Canvas` (spread, HUD, view controls), `Cover`, `Inspector`, `PhotoTray` (photo library), `Film`, `Adjustments`, `Selection` (clicks, keyboard, deletion), `PageEditing` (templates and text), `PhotoPlacement` (dragging, cropping and moving photos), `Commands` (toolbar, title menu, menu commands), `Layers` and `Browser` (Browse the Book). State stays in the main structure, so the extensions declare no stored properties.
- `EditorCommands.swift` defines the app actions passed to the editor, the Insert, Page, Photo, Arrange and View menus (through `focusedSceneValue`) and the resizable divider. `Theme.swift` gathers the light and dark semantic colors and the Liquid Glass panels with their fallback to materials. `BookFormatPresets.swift` lists the preset photobook sizes without changing the document schema.
- `PageComposition.swift` resolves frames, crops, text and cover into typographic points. `CanvasObjectControls.swift` handles moving and resizing, and `CanvasCropControl.swift` edits the image and the frame while cropping. Both cover faces use the same canvas controls and keep position and crop separately in the document. `CanvasStoryGroup.swift` moves heading, story and background together.
- `PhotoDrop.swift` decides what happens when a photo from the photo library is dropped on a photo, on an empty slot or on an empty page, with no hidden cropping. `PhotoResolution.swift` measures the print resolution of a placed photo, crop and zoom included; the preflight warnings, the canvas badge and the Photo tab share it. `ColorSwatches.swift` is the color picker of the panels. `AboutAndHelp.swift` contains the About window and the in-app help (`HelpView`).
- `CanvasAlignment.swift` computes snapping between photos and boxes. `CanvasAlignmentGuides.swift` draws the temporary guides on the canvas. `CanvasPhotoSwap.swift` finds the photo under the pointer during a drag and swaps the two frames.
- `CanvasDeleteShortcut.swift` observes clicks, scroll wheel and right-clicks and forwards keyboard commands in the book window. `EditorView+Layers.swift` builds the canvas context menu and changes the layer order saved in `BookPage.layerOrder`. The map in `EditorPhotoHitTest.swift` uses the drawing geometry to select the visible object. `EditorPreviewLoader.swift` separates the loading of previews and thumbnails.
- `EditorFilePanels.swift` presents the file panels and the print dialog as asynchronous sheets of the window. Operational errors stay visible in the window without needing to activate it.
- `InspectorPhotoLibraryCache.swift` filters the library. `PhotoLibraryOrdering.swift` groups photos by date, place, subject and usage. Places come from local metadata or from original photos the user already authorized.
- `PhotoAnalysis.swift` produces labels, detections and OCR with Vision and ranks the results that match a story. `PhotoVisualSignals.swift` measures palette, brightness, contrast, detail and pixel similarity.
- `BookTemplate.swift` defines paper, editorial geometry and the types shared by preview and export. `EditorialTypography.swift` resolves the book styles and local changes. `PageArrangement.swift` defines the single-page layouts. [Templates](docs/templates.md) documents the visual choices.
- `FilmPipeline.swift` shares color development, LUTs and grain between editor and print.
- `PhotoAdjustments.swift` analyses the photo and applies the adjustments before the film look. `PhotoAdjustmentsPanel.swift` exposes the same values in the inspector.
- `BundledFilmLooks.swift` lists the film-emulation LUTs bundled in `Resources/FilmLooks`, with descriptive names and no film or camera trademarks. Update the catalog, the integrity checks and the [attribution](Resources/FilmLooks/CREDITS.md) together with the resources.
- `BookSettingsView.swift`, `PDFExportChooser.swift`, `PixartPrintProfile.swift` and `BookPDF.swift` handle settings, profile selection, format and printing. [Architecture](docs/architecture.md) describes the contracts between these components.
- `L10n.swift` is the localization lookup: it resolves a key from the String Catalog in the interface language chosen in **Settings**, and falls back to the key.

The Swift sources are in `Sources/PaperAndGrain/`. `scripts/build-app.sh` builds and prepares the bundle for testing and always copies it to `~/Applications/Paper & Grain.app`. Tell the user that path after every build.

## Working in increments

Before changing a flow, read the relevant part of the documentation and look at which views and files call the code. Keep saved projects compatible. A schema change needs a strategy for reading older projects. Check page IDs and that items are kept when a photo moves or the layout changes.

Use themes and labels as suggestions the author can choose from. Analysis must stay on the Mac. Use synthetic images or authorized test material for commits, screenshots and repeatable checks. Open real albums only during a test session in which the user can choose the photos. Private copies, local projects and draft texts stay out of Git.

## Strings and localization

- Every new user-visible string goes into the String Catalog `Resources/Localizable.xcstrings` with English and Italian. Accessibility labels count.
- English is the source language and the English text is the key. When the same English text needs different Italian translations, use an explicit key with a comment in the catalog.
- Never inline Italian text in Swift. Look strings up through `L10n`.
- Command-line output stays in English and is not localized.
- Check every new visible label in English and in Italian.

## Verification and documentation

- Build with `./scripts/build-app.sh`, run `swift test` and try the path the change belongs to. Use the sample book for tests that need no Photos permission.
- For a change to export, open the resulting PDF and check size, long text, full-page photos and the continuity of spreads.
- For a change to gestures, try a spread with a text box and two photos. Check dragging, selection, resizing, reordering from the navigator and reopening the project.
- For a change to analysis, try at least one Italian story, one English story and one text with no matches. Check that the suggested matches can be explained by the labels and that they stay editable.
- In the same commit as any user-visible change, update both the README and the in-app help (`HelpView` in `AboutAndHelp.swift`). Keep them aligned with the app.
- The README is in English and uses the app's English labels. It describes only the current state of the app: no "now", "no longer", "new" or comparisons with earlier versions. The history of changes goes in [CHANGELOG.md](CHANGELOG.md).
- Update [Architecture](docs/architecture.md) when a contract changes. In [Status](docs/status.md), record what you verified and what remains to be tested.
- For a handover, record the observed result and the next concrete action. Put durable technical details in the documentation.
