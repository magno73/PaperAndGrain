# Architecture

## Flow

`AlbumPicker` selects photos and the book size. `PhotoLibrary` asks PhotoKit for the current version of the images. An explicit import from Finder goes through `LocalImages`. `Workspace` saves every resource locally and creates the document. It starts the analysis, one photo at a time, once the editor is available.

`EditorView` edits the document through SwiftUI bindings. A change to a photo or a text updates the view. The workspace triggers autosave itself: after a short pause it takes a copy of the document, and a serial queue encodes it and writes it atomically. Explicit saves and the package copy of **Save As** keep the order of the queue. The workspace keeps the last saved snapshot and skips the write while the book equals it, so opening and closing a book leaves `manifest.json` byte-identical. Opening a book decodes the manifest off the main thread; only quitting still flushes synchronously. `BookPDF` works on a copy of the document so that every export stays consistent.

## Book package

A `.papergrain` project has a `manifest.json`, an `assets/` folder and, when needed, a `looks/` folder. Fields added after the first release are optional in schema v1.

| Data | Contents |
|---|---|
| Book | ID, title, size in mm, page order, schema version and the optional `writerVersion` of the app that last wrote it |
| Photo | ID, name, capture date, oriented dimensions, local file name, optional place and analysis |
| Page | ID, layout type, photos in placement order, heading and story, text position, optional framing and layer order |
| Analysis | List of Vision labels, stable theme keys and revision |
| Film | Book look, per-photo overrides and reference to the LUT stored in the project |
| Print | Bleed, safe margin, PPI, side of the first page and optional cover |
| Cover | Title, back text, photos, and optional positions and crops kept separately for front and back |

The manifest is replaced atomically. **Save Project** updates the existing package. The first save of a draft and **Save As** copy the package to the chosen destination on the save queue, behind a progress overlay, and adopt it once it is written; edits made during the copy are saved in the new place. After a successful **Save As** from a draft, the draft moves to the Trash. Resources resolve under `assets/`. Changes that add optional data must still decode projects saved without those fields.

The workspace checks the folder identity while saving. When the open package no longer matches it (renamed or moved in Finder), the workspace finds it again by volume and file number and keeps saving there. A package that cannot be found (ejected, deleted or in the Trash) shows a clear message; **Save As** writes the current book to a new place, and **Back to Library** or opening another book asks whether to save elsewhere or close without saving.

A book whose `writerVersion` is newer than the app's opens read-only with a message; **Save As** and imports are disabled for it. A book in a read-only location opens without errors and can be copied elsewhere with **Save As**, which makes the copy editable. Writes that fail because of a read-only volume or a missing permission report the read-only location and stop retrying.

The editor is keyed on the document session, not on the book ID: Save As copies and Finder duplicates share the book ID, and the session changes when another package is opened or the book is closed. The old editor clears its undo actions when it goes away.

Drafts live in `~/Library/Application Support/PaperAndGrain/Drafts`, one folder per book named by UUID. The welcome window lists that folder next to the recently opened packages, so a draft stays reachable even when it drops out of the recents list. **Delete Draft…** asks first and moves the draft to the Trash. At launch the app reopens the last suitable project.

`BookStorage.validate` checks every manifest that is read and throws `BookStorage.ValidationError` with an English message that names the page, photo or field, for example `Page 2 (pages[1]) references unknown photo <UUID> in photoIDs`. Photo `pixelWidth` and `pixelHeight` must be between 1 and 1,000,000. `AppErrors.swift` gathers the errors the app shows to the author in the interface language: book moved, newer format, read-only location, damaged manifest, image unavailable (with the file name) and a partial import that lists the unavailable files.

## Analysis and story matching

`PhotoAnalyzer` uses ImageIO to normalize the orientation and Vision to classify the scene. After a confidence filter it keeps the most relevant labels. It maps those labels to stable themes such as `desert`, `wildlife`, `water` and `people`. Theme translations are for the interface. Matching uses English labels and common synonyms in Italian and English, with positive scores for the words or phrases found. Words read in a photo (OCR) count only from four letters up and outside an Italian and English stop list. A theme describes what the model recognizes and is only a suggestion. The current classification does not establish where a photo was taken or who appears in it.

Photos that come from PhotoKit may come from iCloud. The copy asks for the current version, including edits visible in Photos. The analysis works on the local copy and writes the revision and the results to the document. Revision 2 stores classifications with confidence, detections, OCR, pixel measures and a visual fingerprint. The editor applies updates in small batches and stops the analysis when the book changes. Photos added while an analysis runs are queued and analysed when the run ends.

The photo library also accepts dragged files and files promised by Photos. Each file is checked from its image header and copied to a temporary folder, without reading it whole into memory; the readable images are added to the project library. The tray's **Import Files…** uses the same path. A drop follows the document session, so Save As or a move during a slow import does not discard it: the photos are installed in the current package after any copy in progress. Moving the assets and writing the manifest run on the save queue, in a single manifest write.

The inspector computes suggestions off the interface thread when the heading, story, page photos or available photos change. It uses matches with subjects, OCR and themes and shows the most specific source. It cancels the previous search when any of these inputs changes.

## Geometry and PDF

Book dimensions are in millimeters. The gallery geometry goes through `BookLayoutGeometry` and keeps proportions, order and gaps. The first draft groups photos by capture day.

For a full-bleed photo, `framing` goes from 0 to 1 along the axis that is cut when the photo fills the page. A missing value means 0.5. This field is still read when the newer two-axis crop is missing. A spread uses the same image rectangle for both sides. The PDF draws that rectangle through two clipping windows and leaves out the guides. Core Text keeps the text selectable.

`PageComposition` resolves automatic rows, manual frames, text and rules into typographic points, from the top left. Manual frames of photos and text boxes use coordinates normalized to the trim size. A photo placed by hand does not take a slot in the automatic grid. The first move of a photo out of the grid fixes the other visible frames. Canvas zoom only scales the on-screen size, while the photo crop controls the magnification within the frame and the alignment on both axes, including for the print-resolution calculation. The navigator order matches `Book.pages`, with each panorama shown as a single entry.

With a page template, `PageArrangement` assigns frames in the order of the page's photo IDs. `PageComposition` shares the rectangles with the canvas, thumbnails and PDF. Photos beyond the capacity stay in the page data. Applying a template resets the frames and keeps crops, story and boxes. Moving one frame leaves the others in their slots. The **Insert** menu creates pages with page templates; legacy layouts in older books (`gallery`, `text`, `mixed`, `fullPage`, `fullSpread`) render as before.

Full-bleed templates spread the frames to the edges of the format and leave out rules and folios. The PDF extends into the bleed only the frames that reach the outer edge. Edges between photos stay shared.

The fields `BookPage.arrangement`, `BookPage.photoPlacements`, `BookPage.textBoxes`, `BookPage.layerOrder` and `BookCover.backText` are optional. The text box fields `backgroundColor`, `hidesBackground`, `borderColor` and `borderWidth` are optional too.

`BookPage.layerOrder` lists the layers from bottom to top as the strings `photo:UUID`, `story` and `box:UUID`. The story, the heading and their background form a single layer. Without the field, photos sit below the story and boxes above it, as in older projects. After a reorder, a new photo goes to the bottom and a new box to the top. `PageComposition.layers` resolves the order once, and the canvas (`zIndex`), thumbnails, click map, the detection of the photo under the pointer and the PDF all share it. IDs no longer on the page are ignored.

`EditorialTextStyle` adds `color` (0xRRGGBB) and `lineSpacing` (a multiple of the line height, from 0.8 to 2). Both inherit from the book like font, size and alignment. `EditorialStyle.typography` applies them as the Core Text color and `lineHeightMultiple`, so the editor and the PDF match. `BookCoverGeometry` resolves the two faces for the editor and for `Cover.pdf`, for a given face size. The back cover can hold text and a photo. The title page is an interior text page inserted at the start of `Book.pages`.

Cropping opens a temporary edit directly on the page. Gestures adjust the photo and the frame. Confirming applies position and crop together in a single undoable step. On-screen edits do not activate the app and keyboard focus stays where the window puts it. File panels are presented as asynchronous sheets attached to the book window, never to Help or Settings. The workspace checks the identity of the book and its folder before it uses the result of a sheet.

Snapping uses the free position at every update of the drag. It looks for edges and centers of the other photos and boxes on the same page within six screen points, regardless of zoom, with one guide per axis. The page itself, or the cover face, is passed as `edges` and pulls harder, by `CanvasAlignment.edgeToleranceFactor` (1.5 times the reach, so nine screen points). With equal positions, the reference that is closest relative to its reach wins. The guides show the chosen references and disappear when snapping ends. A released drag commits exactly the placement shown on screen and holds it until the document updates. The project stores only the final frame position.

Swapping uses the pointer position on the canvas and starts inside another visible photo on the same page. The command swaps frames and order, keeps the crops tied to the photos and undoes in a single step. In fixed-position templates, automatic frames stay automatic. In proportion-based grids the visible frames are fixed before the swap.

Resizing keeps the opposite corner. Photos keep their proportions, and the crop handles can snap one axis independently of the other. The window monitor forwards the click after the button is released. The selection map uses the frames already computed by the canvas, in drawing order. Shortcuts respect active text fields. A click in the library resolves the thumbnail coordinates and keeps the inspector mode that is open.

The bundled film-emulation LUTs (`Resources/FilmLooks`) are sRGB resources with descriptive names. The catalog separates LUTs meant for linear contrast from those meant for images already developed with a standard slide-film look. When one is chosen, the package receives the CUBE copy with the same naming scheme as imported LUTs. The shared render of the editor and the PDF keeps reading the LUT from the package.

Thumbnails use `PageComposition` to draw each photo with its actual frame and crop. The navigator keeps the pages side by side even in single-page view. Dragging is bound to a single `BookPage`, panoramas that span two physical pages included.

Photo rectangles can be up to four times the page size. The model keeps a reachable part of the photo on the canvas and applies the trim only on screen and in print. Text boxes keep using coordinates inside the page. The box being typed in shares the saved text with the inspector and with Core Text.

The optional frames of heading, story and cover text use normalized coordinates. The editor offers dragging and resizing with corner and side handles. The first change to the frames of a page keeps the position of the other block. Missing fields rebuild the starting positions from the template and the typography. Rendering uses the full width of manual frames. The inner margin of free text boxes is configurable. An empty text box prints only what the author styled: a fill other than the paper, or a border; the navigator thumbnails follow the same rule.

Dragging the story as a group applies the same offset to the heading, the text and any background frames. The overall box keeps the move within the page edges. Background frames are saved as normalized coordinates and keep their position while the single texts are dragged. Thumbnails and PDF use the same frames.

Swiss Grid, Berlin Notebook and Japanese Interval define positions for automatic galleries and panels for **Text over photo**. `PageComposition` resolves frames, heading size and panel position. The editor, thumbnails, template chooser and exporter draw the panel with the palette and the graphic mark of `EditorialStyle`. The size set by the author takes precedence over the automatic heading scaling.

`BookPhoto.adjustments` is optional in existing projects. `PhotoAdjustments` measures a reduced copy of the photo to propose repeatable light and color changes. The shared pipeline applies the adjustments to the photo before the film look and the grain. The PDF, the editor and the thumbnails use the same values. The imported image file stays the reference for comparison. Sharpening and noise-reduction radii are fractions of the long edge, so a preview and the print render get the same effect at the same viewing size.

`PhotoResolution` measures the print resolution of a placed photo: its pixels over the printed size, crop and zoom included. The preflight warnings, the canvas badge and the **Photo** tab share it. Values are compared rounded, so a photo exactly at the target does not warn.

`EditorPreviewLoader` shares identical requests and uses separate caches and queues for thumbnails and canvas previews. While a slider moves, provisional values update only the canvas preview, at intervals. The **Film** preview during a gesture uses its own queue and at most 640 pixels on the long side. On release, the editor registers a single undoable action and loads the high-resolution preview. Thumbnails use the committed values. Cover frames and crops are shared by canvas, thumbnails and PDF. In print, each photo is clipped to its own face and bleed.

The inspector observes its own navigation. Filtered library results can be sorted by day, place, main subject or usage. The place comes from IPTC or GPS fields and from the location in Photos when available. For older projects the inspector reads the metadata of the copies in the background. For copies without a place it can query Photo IDs the user already authorized, without asking for access. Unnamed coordinates are grouped in zones of about 0.05°. The coordinates of library thumbnails are measured inside the inspector and read on click. The swatches of the **Film** panel have a render queue separate from the book and library thumbnails.

The binary with the `cli` argument uses the app's model, import, analysis and rendering without opening the window. Editing commands work on a private copy of the package and publish with an exclusive rename. `inspect` returns the validated manifest with the original indices for JSON Patch. Results and errors are JSON. [CLI contract](cli.md)

### Print output

Before any export, `BookPDF.preflight` checks text overflow, unknown photos, photo files missing on disk and unreadable LUTs for the chosen profile, and returns them as blockers separate from the print warnings (resolution below the target, compensation blanks). Each `PreflightIssue` carries the printed page number, the page's id, an optional `IssueTarget` (photo, text box, story, caption or cover face) and an `id` built from the problem kind, page id and target, so rows keep their identity between runs. `destination(in:)` resolves an issue to a page or a cover face. `Problem.kind`, `Problem.symbol`, `PreflightIssue.message` and `EditorView.issueFix(for:)` are exhaustive `switch` statements: a new `Problem` case does not compile until each handles it, and a kind gets a fix button by returning an `IssueFix` from `issueFix(for:)`.

`IssueMonitor` keeps the result for the open book: each change restarts a 0.6 s wait, the check runs on a detached task off the main thread, and a run that a newer change overtakes is cancelled and never published. The monitor takes its clock and check as closures so tests can drive it. `IssueList` draws the rows (blockers, then warnings, each grouped by page) for the toolbar popover and for the export sheet. The menu command opens the same popover from an anchor on the canvas, so it works without the toolbar item, and a change of the package location reruns the check. A cancelled run also cancels the detached check, which stops at the next page. The export sheet takes the same `fix` provider as the popover, but the app scene that opens it cannot reach the editor, so it passes none yet. A photo placed twice on a page gets an `occurrence` in its id; an overflow message names its subject (story, first words of the box, cover face). The live list uses the `.print` profile until print-service profiles choose another. On the 50-page, 150-photo synthetic book the check takes about 4 ms in a release build.

`PrintGuides.frames(pageSize:settings:zones:)` is the one place that computes the trim, the safe line (`safeMM` inside) and the bleed line (`bleedMM` outside) of a page in points; its `zones` input is where print-service profiles will add hinge, inner-margin and spine areas. `PrintGuidesOverlay` draws it over the canvas only (never in `mini`, **Browse the Book** or `BookPDF`, so the PDF is unaffected by the toggle, which is an `@AppStorage` flag). The same value feeds two preflight warnings for the profiles that have print settings: `.textOutsideSafeMargin` (the frame of a story or printing text box is not inside the safe line) and `.photoNearEdge` (a photo frame edge is more than 0.25 mm and less than the bleed inside the trim; the binding-side edge of a single page is skipped, a full spread has none). Both are computed from the composition at bleed 0.\n\nThe export sheet shows blockers as errors and disables **Continue** while any remain. The progress card shows the share of sheets rendered.

Every profile composes pages and covers at the editor's frame size and computes the crop for that frame. A photo that reaches the trim is carried into the bleed with its real pixels where the crop has spare image, and with a pixel-exact reflection only where it has none, so the picture inside the trim matches the editor. The underlap that hides antialiased seams between full-bleed tiles follows the layer order: a photo extends under each neighbor painted after it. A cover band or rule that reaches the trim continues to the outer edge of its face.

Renders are embedded as JPEG-backed images: quality 0.95 at the book's target resolution for the print profiles, 0.85 at about 150 ppi for the viewing PDF. The PDF is written to a hidden file next to the destination, page by page, and moved into place when complete, so an error never replaces an existing file. The exporter keeps its last developed photo, so both halves of a panorama and a photo repeated on the next page are rendered once.

The print export uses explicit TrimBox and BleedBox and embeds sRGB as the output intent. Books that start on the right and panoramas can need compensation blanks; these are filled with the template's paper color, bleed included. Printed folios and print warnings use `PageComposition.pageNumbers`, the same numbering as the navigator, so blanks never shift page numbers. Print writes the interior and the cover as separate files. Before rendering, it checks the destination folder: a folder that holds only a previous `Interior.pdf`, `Cover.pdf` and `.DS_Store` is replaced, any other content is refused at once. Bleed and spine must be set from the specifications of the chosen product.

The Pixartprinting 21 × 21 cm profile writes a single PDF that opens with the flat hardcover. Both cover faces are laid out on the real 207 × 220 mm panel, so the title is fitted in the width it is drawn in; the cover plane follows the spine width from the quote and includes hinges and turn-ins. A cover overflow is reported as the cover. The interior pages have 3 mm of bleed on each side, follow the project order and stay single even for panoramas. The exporter keeps sRGB rendering and selectable type.

## Film

`FilmRenderer` reads the oriented image with ImageIO, normalizes it to sRGB with ColorSync and applies the look, or a 3D CUBE or HaldCLUT PNG. A `.cube` file accepts `DOMAIN_MIN`, `DOMAIN_MAX` and `LUT_3D_INPUT_RANGE` and skips other keywords; 1D LUTs are refused with a clear message. Hald PNGs are accepted from level 2 to 12; level 12 is resampled to a 64-step cube. Strength blends the look with the scene, and grain adds a repeatable variation to the luminance. The original view in the editor is a temporary viewing mode. The document stores the book look and the per-photo overrides. The preview cache is limited and keyed on image, look details and resolution. The PDF reads the copy again at the resolution the format needs.

The book template is optional. Page color, typography, text column and gaps come from the parameters in `BookTemplate.swift`. The print safe zone sets the minimum margin. [Book templates](templates.md) describes how they are applied and previewed.

PostScript font, size in points and alignment are optional fields and inherit one by one. The book template gives the starting values. The book can override those of headings and body text. A page can add changes to its own heading or story. The front cover, the back cover and the boxes can override their text style as well. Core Text applies the resolved style on the canvas, in thumbnails and in the PDF. Rendering falls back to the template typeface when the chosen font is missing on the Mac.

## Canvas, events and previews

`CanvasDeleteShortcut` observes keyboard, clicks and scroll wheel in the window without intercepting them, except in the cases it handles. A right-click on the canvas selects the object under the pointer and shows an `NSMenu` built at that moment by `EditorView.canvasMenu(at:)`, so the items always act on that object. `PageScrollGesture` turns one page per trackpad gesture or per wheel notch and absorbs the momentum. It does so only with the **Fit Page** zoom and with no edit in progress. Arrow keys first move the selected object, then change page in the navigator or on the empty canvas. The floating controls above the page register their own frame (`EditorDropTarget.canvasHUD`, `.canvasViewControls`): a click on them does not change the selection.

Sliders do not use `Slider(step:)`. On macOS the step creates a tick mark for every value, and AppKit recomputes hundreds of rectangles per slider when the panel appears or disappears. The value is rounded in the setter (`PhotoAdjustmentsPanel.quantized`). The **Adjust** sections start collapsed. The navigator is wrapped in `Memoized`, which redraws it only when `NavigatorKey` changes: book, current page, width, insertion during a drag and comparison with the original. Actions read the live state at click time, so they are not part of the key. Any new data shown by the navigator must be added to the key.

Film has a single visible interface at a time. With a photo selected it sits in the **Photo** tab and changes `BookPhoto.film`. If **Change the whole book** is ticked, it changes `Book.film` and removes the selected photo's override in the same undoable action. With nothing selected, the **Film** tab changes `Book.film`. `filmScope` derives from the tab and the checkbox.

`BookPage.duplicated()` (`PageDuplication.swift`) backs **Page › Duplicate Page**: the copy gets a new page id and new text box ids, `layerOrder` is rewritten to the new box ids, and photo ids are kept because a photo may sit on several pages. `EditorView.duplicatePage` inserts it after the original in one `editPages` step and registers a second undo action that moves the page selection back to the original (and forward again on redo). The command is off on the covers and while text, a crop or a library search is active, which is what lets ⌘D stay free of the text field.

Dropping a photo from the photo library on a page goes through `EditorView.photoDropAction`. There are five outcomes:
- **swap**, with a photo on the same page;
- **replace** (`BookPage.replacePhoto`): the new photo takes the order position, template slot, frame and layer of the one under the pointer. In an automatic gallery the visible frames are fixed first, so the page is not laid out again;
- **empty slot** (`BookPage.fillSlot`): if the order position already matches the slot, the photo stays automatic; otherwise it gets the slot as its frame;
- **first photo** of an empty automatic page;
- **free frame**, always with **⌥**.

`PageComposition.emptySlots` treats a slot as empty when no photo covers at least half of it. The canvas placeholders and the drop both use it. Canvas objects are `focusable` but have no system focus ring (`focusEffectDisabled`): the app draws the selection itself.

`EditorPreviewLoader` runs up to four canvas previews in parallel, newest request first. `EditorPreview` asks for the size that suits the on-screen frame (480, 720, 1080, 1440 or 2048 px, taking Retina screens and the crop into account) and shows the navigator thumbnail already in memory at once, while the sharp one arrives.

## Localization

The interface is in English and Italian. Strings live in the String Catalog `Resources/Localizable.xcstrings`, with English as the source language and the English text as the key; where the same English needs different Italian, an explicit key is used. `L10n` resolves a key in the interface language chosen in **Settings** (system, Italian or English) by loading the matching `.lproj` bundle, and falls back to the key, so `swift test`, `swift run` and the CLI show English. Command-line output is not localized. Views and commands conform to `Localizing` (`tr("Page")`, `tr("Layout", key:)`, `tr("%lld pages", n)`); counts use the catalog's plural variations with positional format arguments. The CLI calls `L10n.useEnglishOnly()`; its `templates` output takes Italian names from a small table that a test keeps equal to the catalog. Preflight results are `PreflightIssue` values (a location and a problem) localized when shown, so the export sheet is in the interface language and `export-pdf` reports English. `scripts/l10n-pairs.py check` guards against inline strings, missing keys and unused keys. `Resources/it.lproj/InfoPlist.strings` holds the Italian Photos permission text.
