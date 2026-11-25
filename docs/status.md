# Status

The state of testing for Paper & Grain 0.10.0 (25 November 2026). The list of changes is in the [changelog](../CHANGELOG.md). Record here what you verify, how, and what remains to be tried. Use only the sample book or synthetic books built with `cli build` from `Resources/Demo.png` and generated images.

## How the app is checked

- **Unit tests.** `swift test` runs 198 tests with no failures. They cover the document model and its compatibility with older projects, saving, opening and moving packages, drafts, imports, page geometry, layers, snapping, photo drops and swaps, typography, the film pipeline and LUT parsing, adjustments, photo analysis and story matching, the print and Pixartprinting PDFs, and every command-line command. Every pull request runs `swift build` and `swift test` on GitHub Actions with Xcode 26.6 and Xcode 27.2.
- **The app on macOS 27.** Interactive checks are made with the bundle from `./scripts/build-app.sh`, on the sample book or on synthetic books.
- **PDF output.** Exports are opened and checked for size, boxes, long text, full-page photos and spreads.
- **Profiling.** The main thread is sampled with `sample <pid> 6 1` on a synthetic book of 50 pages and 150 photos of 12 MP.

## Verified

### Documents

- Unit tests: opening and closing a book leaves `manifest.json` byte-identical; a package renamed while open keeps its edits after quit and reopen; a missing package reports the move and can still be saved elsewhere; a book from a newer version opens read-only and is never rewritten; a book in a read-only location opens without errors and **Save As** makes it editable; every draft is listed beyond the recents limit; **Save As** from a draft moves the draft to the Trash; **Delete Draft…** moves only a draft to the Trash; **Save As** runs off the main thread and keeps edits made meanwhile; the editor session changes for another package with the same book ID but not on **Save As**; quitting saves the book without a window; error messages exist in English and Italian.
- Older projects without the optional fields (`layerOrder`, text box styles, cover placements, adjustments) open with their previous appearance.

### Editing

- In the app, with the sample book: the welcome window, **Insert › Page**, dragging from the Photo Library to a page, reordering in the Pages sidebar and **Edit › Undo**; the template chooser from the toolbar (three families, twelve previews, **Cancel** changes nothing, a book with no template opens with no active choice); a template requested when a book is created from files; the floating bar, the contextual inspector tabs and **Browse the Book**; dark appearance.
- Navigation: arrow keys in the Pages sidebar from the cover to the back cover; the scroll wheel on the canvas forward and back.
- Context menu on a photo, and **Undo** after **Remove from Page**. **Send to Back** and a 17 pt centered style on a box, with the same order in a PDF exported from the CLI.
- A real click on **Adjust** in the floating bar keeps the selection and opens the section. A new box opens the **Text** tab.
- The window at 1,400 points wide shows the whole inspector, with a compact Photo Library. The recent-books grid with a portrait cover.
- Photo drops on a synthetic book with real drags: replacing a photo in a four-photo template, filling the lower-right slot, replacing in an automatic gallery with the other frames unchanged, swapping two photos on the same page, and a click on the paper after a photo (no focus ring left). With the Kodachrome template: a panorama on a portrait slot of a two-photo template (frame reduced, note shown) and a portrait photo in the Kodachrome gallery (fitted, not cropped).
- Text boxes with a colored background and a 2 pt border on the canvas. The **Text** tab for the cover title, and the cover panel.
- Page edges: a photo moved to about 5 points from the left edge snaps to it; resized from the handle to 4 points from the right edge, it reaches the edge.
- Photo selection speed: on the 150-photo synthetic book, moving from one photo to another kept the main thread busy for about 2.4 s; after the slider and navigator changes, about 0.1 s.

### Photos and film

- Film scope in the app: a look on one photo only; with **Change the whole book** ticked, a look on the whole book, and the photo follows the book again; the **Film** tab with no selection.
- LUTs: identity LUT, a 13³ table, the CUBE domain, `LUT_3D_INPUT_RANGE`, a truncated file refused, Hald level 12, repeatable grain, reopening after moving the package, and conversion of Display P3 SDR JPEG and HEIC to sRGB.
- Analysis on the sample photo and synthetic images: Italian and English matches and a story with no match; OCR words shorter than four letters or in the stop list do not match.
- Sharpening and noise reduction agree within 35 % between a 600 to 2048 px preview and the print render.

### Printing

- Viewing and print PDFs for all twelve templates on a ten-page synthetic book, including the spine title.
- PDF boxes, continuity across the inner edges of a panorama, and pagination with compensation blanks.
- Unit tests: printed folios match the editor when blanks are inserted; the Pixart cover title fits the panel it is drawn in; the print bleed keeps the editor crop inside the trim; preflight lists every blocker; a photo at the target resolution does not warn; progress per sheet; a previous print package is replaced; seam underlaps follow the layer order; blanks use the template paper; the classic cover band runs into the wrap; empty text boxes print only what the author styled.
- File size and memory on the 50-page synthetic book (release build): print PDF 907 MB to 200 MB, peak memory 2.76 GB to 0.43 GB; viewing PDF 976 MB to 46 MB; Pixart 907 MB to 197 MB. A gradient test shows no banding.
- The preflight check in the app with a real resolution warning, and the preset sizes in **Book & Print**.

## Not yet verified

### Documents

- In the app rather than in unit tests: renaming the open package in Finder, editing, quitting and reopening; ejecting the volume of an open book and using **Save As**; opening a book from a read-only volume; **Delete Draft…** and **Save As** from a draft.

### Editing

- Photo replacement on a full-bleed page, on a full spread, and with ⌥ held over a photo.
- Context menu on a text box and on a story.
- Scrolling pages with a classic notched mouse wheel.
- Arrow keys in the Pages sidebar after deleting a page.
- Snapping to the outer edge of a full spread.
- Releasing a drag after forcing past the page edge, with a slow drag by hand.
- Crop and inline text editing with the floating bar visible.
- A large book of 50 pages and 150 photos of 12 MP: page change, selection, tray scrolling, typing, export, and the navigator at full width. Photo selection on an older Mac.
- Dragging, resizing and cropping gestures on a spread with a text box and two photos, as a full manual pass in the open window.
- Switching to other apps through the Dock while a book is open.

### Photos and film

- The album picker with a real Photos album chosen by the user: every thumbnail selected on the first click.
- Dropping files from Finder and photos from Photos onto the window.
- A photo edited in Photos, and a photo stored only in iCloud.
- A HEIC HDR photo.
- **Match Book** with many photos that have their own look.
- Importing a LUT with **Change the whole book** ticked.
- Photos access from the command line (`cli albums --request-access`) with the signed bundle.
- The quality of story suggestions on a real travel album: at least one useful match and any missed photos.

### Printing

- A real printed copy: format, paper and binding chosen with the print shop; spine, grain and detail on faces checked on a proof.
- The Pixartprinting PDF checked against an actual quote.
- Text box background and border, and custom text color, in the print PDF.

### Platforms and accessibility

- macOS 14 and 15 (and 26): the app has only been run on macOS 27.
- VoiceOver: Pages sidebar, canvas objects, inspector tabs, template chooser.
- Every screen in Italian and in English after the move of all strings to the String Catalog: welcome window, editor with each inspector tab, template chooser, album picker, Book & Print, export sheet, help, About and menus.

## Known limitations

- **Not notarized.** The downloadable app is signed but not notarized by Apple; macOS blocks it the first time (see the README).
- **Tested only on macOS 27.** macOS 14, 15 and 26 are supported but untested.
- **Spine never printed.** The spine geometry has been checked in PDFs only; a real printed spine has never been checked.
- **Font embedding.** The templates use fonts that ship with macOS. Their license for embedding in PDFs of books that are sold has not been checked.
- **One print-shop profile.** The Pixartprinting profile exists only for the 21 × 21 cm hardcover. Other products use the generic print PDF with the bleed and spine of the product's specifications.
- **sRGB only.** PDFs are written in sRGB; check the color requirements of the product you order.
- **Analysis is a suggestion.** Vision labels describe what the model recognizes. They do not establish where a photo was taken or who appears in it. The animal detector locates only cats and dogs; wildlife relies on scene labels.
- **Noncommercial LUTs.** The bundled film-emulation LUTs are CC BY-NC-SA 4.0 and cannot be used commercially.
