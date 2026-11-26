# Status

The state of testing for Paper & Grain 0.10.0 (25 November 2026), plus the work in progress for 0.11.0 (so far T1, the live Issues list, and T10, the print-service profile engine). The list of changes is in the [changelog](../CHANGELOG.md). Record here what you verify, how, and what remains to be tried. Use only the sample book or synthetic books built with `cli build` from `Resources/Demo.png` and generated images.

## How the app is checked

- **Unit tests.** `swift test` runs 250 tests with no failures (one timing test is skipped unless `PAPERGRAIN_PREFLIGHT_BOOK` names a package). They cover the document model and its compatibility with older projects, saving, opening and moving packages, drafts, imports, page geometry, layers, snapping, photo drops and swaps, typography, the film pipeline and LUT parsing, adjustments, photo analysis and story matching, the print PDF and the print-service catalog (every entry rendered at every size), and every command-line command. Every pull request runs `swift build` and `swift test` on GitHub Actions with Xcode 26.6 and Xcode 27.2.
- **The app on macOS 27.** Interactive checks are made with the bundle from `./scripts/build-app.sh`, on the sample book or on synthetic books.
- **PDF output.** Exports are opened and checked for size, boxes, long text, full-page photos and spreads.
- **Profiling.** The main thread is sampled with `sample <pid> 6 1` on a synthetic book of 50 pages and 150 photos of 12 MP.
- **Timing without the interface.** In a release build on this Mac, a 180 px thumbnail of a 12 MP photo takes about 15 ms; with several thumbnail lanes the tray of a 150-photo book fills in about 0.4 s instead of about 2.2 s. Composing and typesetting one page thumbnail takes about 0.06 ms, so redrawing the visible thumbnails while typing costs well under a millisecond and needs no cache.

- **Live preflight timing (T1).** A synthetic book of 50 pages and 150 photos (4000 × 3000 px JPEGs made with `sips` from `Resources/Demo.png`, three photos, a heading, a paragraph and a text box per page, a cover; built with `cli build`, 372 MB) was read from disk and checked with the `.print` profile 21 times in a release build (`PAPERGRAIN_PREFLIGHT_BOOK=… swift test -c release -Xswiftc -enable-testing --filter testPreflightTimingOnAPackage`): 7.8 ms for the first run, a median of 4.0 ms and a maximum of 4.1 ms for the others, against a budget of 150 ms. No per-page cache is needed. The check reads no pixels: it tests that each photo file exists and typesets each story and box once.

## Verified

### Documents

- String Catalog merge driver (`scripts/l10n-merge.py`, T0): unit tests run it on the catalog merged with itself (byte-identical), on two branches adding different keys (both kept, sorted) and on two Italian translations of one key (exit 1, key named, file untouched). A real `git merge` with the `git config merge.l10n-catalog.driver` entry set was run in a scratch clone.

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
- Print-service profiles (T10). The Pixartprinting export of a 10-page synthetic book (`cli build` from `Resources/Demo.png` and five generated 2400 × 1800 gradients; full pages, galleries, a full spread, text pages, a cover with front and back photos) was written with the binary of the base commit `88beb03` and with the catalog entry, and compared with `CGPDFDocument`: 13 pages in both, identical media, trim and bleed boxes on every page, and renders of every page at half scale identical to the pixel, cover included. The same holds for the variant with the first page on the right and a 12.5 mm spine (11 pages), for Generic Print (`Interior.pdf` and `Cover.pdf`, both variants) and for the viewing PDF, so a book with no profile exports as before. Unit tests: every catalog entry and the three test-only entries decode, follow the catalog rules and round-trip; broken entries are refused naming the file and the reason; spine and hinge from a table per paper and page count, from a formula and from the quote, with the author's value first; size, page-count and missing-spine issues with the product's numbers; a 0.10 manifest without the new fields decodes and stays generic; every size of every entry renders the media, trim and bleed boxes it describes, including bleed on three edges, no bleed, covers as first and last page, one spread per page and separate files; `export-pdf` with a catalog id, `--size`, `--paper` and `--spine-mm`, `print-profiles`, the build spec's `printService` and the patch checks.
- Issues list (T1), unit tests only: issue ids are stable across two runs, unique, and follow the page and object rather than the printed number; each target (photo, text box, story, caption, cover face) resolves to its page or face, and one pointing to nothing resolves to nothing; an overflowing box or story is its own blocker with its target and disappears when the text is shortened; a photo whose pixels fall under the target raises a warning on that photo; groups come out book-wide, pages in order, cover last; six changes inside one pause start one run; a run overtaken by a newer change never publishes; stopping the monitor cancels the pending run. The catalog compiles into the debug bundle with the new Italian strings.

## Not yet verified

### Issues (T1)

None of this was seen on screen (no GUI access in this run). With the bundle from `./scripts/build-app.sh` and the sample book:

1. Open the sample book. The toolbar shows **Issues** between **Film** and **Export**: a check mark, or a triangle with a number. Hover it: the help reads "Show problems and warnings found in the book". With VoiceOver the button says the counts in words.
2. Select a photo on a page and enlarge it with a large crop zoom, or place a small photo: within a second the number rises and the triangle appears. Click the button: the popover lists a warning under "Page N". Click the row: the canvas goes to that page and the photo is selected, with the inspector on the **Photo** tab.
3. Type a long text in a text box until it overflows: a row under **Problems** appears about 0.6 s after you stop typing; click it and the box is selected. Shorten the text: the row goes away and the count falls. While typing, the window must not stutter.
4. Do the same for the story (heading and text of a page) and for the cover title on the front and the back: the row selects the story, or shows that cover face.
5. With no issues the popover says "The book is ready for print." and the toolbar shows the check mark.
6. **View › Show Issues** (⇧⌘I) opens and closes the popover, and the menu item then reads **Hide Issues**. Check ⇧⌘I does not collide with a system shortcut. Remove **Issues** from the toolbar with **Customize Toolbar…** and press ⇧⌘I again: the popover must still open, near the top right corner of the canvas. With the toolbar button present, ⇧⌘I opens the popover under the button instead (two popovers are never open at once). Rename the open package in Finder: the list is rechecked, with no stale "Photo file missing". With a blocker the button shows an octagon, with only warnings a triangle.
7. **File › Export PDF**: the sheet shows the same rows (not clickable), grouped by page, with a scroll area when there are many. **Continue** stays disabled while a problem remains.
8. Italian: switch **Settings › Language** to Italian and check the button help, the popover headings (Problemi, Avvisi, Pagina N, Tutto il libro) and the help topic **Stampa**.
9. Dark appearance and a narrow window: the popover stays 360 pt wide and readable.

### Duplicate Page (T3)

Unit tests cover the copy (only the page id and box ids differ, the layer order refers only to boxes on the copy). Not seen on screen (no GUI access in this run). With the sample book:

1. Select page 2 and choose **Page › Duplicate Page** (⌘D): a copy appears right after it and is selected; the inspector stays on the Page tab. Check a page with a text box, two photos and a changed layer order: the copy looks the same, and moving a box on the copy does not move it on the original.
2. ⌘Z: the copy goes and the original is selected again; the Edit menu said "Undo Duplicate Page". ⇧⌘Z brings the copy back.
3. Right-click a thumbnail in the Pages sidebar: **Duplicate Page** sits after **Insert Page After**.
4. Select the front cover, then the back cover: **Duplicate Page** is greyed out. Double-click a text box to type, and open the Page menu: it is greyed out too (⌘D does nothing).
5. Italian: **Pagina › Duplica pagina**, and the undo item reads "Annulla Duplica pagina".
6. Close and reopen the book: the copy is still there.

### Print guides (T2)

Unit tests cover the frames (210 × 210 mm, 3 mm bleed, 10 mm safe), the photo-edge rule (on the trim, 0.2 mm, 1.5 mm and 5 mm inside, bleeding), the safe-line rule, both warnings, stable issue ids, the binding edge, and that no template and arrangement of the standard pages raises either warning. Not seen on screen (no GUI access in this run). With the sample book:

1. **View › Show Print Guides**: each page shows a dashed accent line inside it and a thin line just outside; in a two-page view the thin line goes around both pages. A notice with the legend appears for four seconds, only the first time in the session. The menu item reads **Hide Print Guides**. The page does not move or resize when the guides come on. Quit and reopen: the choice is kept.
2. The zoom menu in the corner of the canvas has **Print Guides** as well, and it matches the View menu item. Check a full spread (one dashed rectangle around the whole spread) and a first page with the first page on the right (blank left side has none).
3. Thumbnails in **Pages**, **Browse the Book** and an exported PDF show no guides. Export the same book with guides on and off and compare (`cmp` after removing dates, or open both).
4. **Book & Print**: change **Safe margin** from 10 to 20 mm: the dashed line moves in. Change **Bleed**: the outer line moves.
5. Drag a text box so its edge crosses the dashed line: within a second **Issues** shows "Text crosses the safe margin" under the page, and the row selects the box. Drag a photo so its left edge is 1.5 mm inside the page edge: a row says "Photo ends 1.5 mm inside the trim…". Move it to the edge: the row goes.
6. Dragging, selecting and cropping work with guides on (the overlay ignores the pointer).
7. Italian: **Vista › Mostra guide di stampa**, the legend and both rows. Dark appearance: both lines are visible on white and on a dark photo.
8. Not done: guides on the cover faces, and the two warnings for the cover.

### Print-service profiles (T10)

None of this was seen on screen (no GUI access in this run). With the bundle from `./scripts/build-app.sh` and a synthetic 21 × 21 cm book with a cover:

1. **Book & Print › Print service** lists **None (generic print)** and, under **Pixartprinting**, **Photo book, hardcover · 21 × 21 cm**. Choose it: **Bleed** reads 3 and **Safe margin** 5; the rules read "Page count in steps of 2", "The count includes 4 cover pages" and "Keep text 5 mm from the edges and 15 mm from the binding"; the notice shows "Specification checked on 26 November 2026", a working **Printer's page** link and the not-affiliated sentence. **Apply**, reopen the sheet: the choice is kept. ⌘Z undoes it in one step.
2. Change **Size** to 20 × 20 cm with the product chosen: the section says the product does not offer 20 × 20 cm, lists 21 × 21 cm, and **Use 21 × 21 cm** puts the size back. The size never changes by itself.
3. **Issues** with the product chosen and no spine width: a problem "Cover · Spine width missing: enter it from the printer's quote". Type a spine in **Book & Print › Spine width (mm)**: the row goes away. Remove pages until the count is odd: a warning "Needs a multiple of 2 pages (has …)".
4. **File › Export PDF**: the list shows **Viewing PDF**, **Generic Print**, **Pixartprinting · Photo book, hardcover · 21 × 21 cm** with "One PDF with the flat cover first. Single pages of 216 × 216 mm." and **Other print service…**. The product shows the spine field filled from the cover, the sRGB note and the notice. **Other print service…** shows a service menu. Export and open the PDF: flat cover first, then single pages.
5. A book with no print service: the export sheet has no product row, only **Other print service…**; **Issues** behaves as in 0.10.
6. New book from an album: the **Print service** menu above **Book Size** filters the sizes to the product's; **Any print service** brings the common sizes back.
7. Italian: **Libro e stampa › Servizio di stampa**, the rules, the notice and the export sheet rows in Italian; VoiceOver reads the link and the measure fields.

### Documents

- In the app rather than in unit tests: renaming the open package in Finder, editing, quitting and reopening; ejecting the volume of an open book and using **Save As**; opening a book from a read-only volume; **Delete Draft…** and **Save As** from a draft.

### Editing

- Photo replacement on a full-bleed page, on a full spread, and with ⌥ held over a photo.
- Context menu on a text box and on a story.
- **Undo after typing.** Type in a story, a heading, a text box and the cover title, click elsewhere and press ⌘Z: the previous text should come back in one step, and redo should work. Page and layout undo keep typed text on purpose, so typing relies on the text field's own undo; this has not been checked in the window.
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
- The Pixartprinting PDF checked against an actual quote, and whether Pixartprinting accepts sRGB for this product (open item O1).
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
- **One print-service entry.** The catalog holds only the Pixartprinting 21 × 21 cm hardcover; the other services of the 0.11 plan come as data (T11). Other products use the generic print PDF with the bleed and spine of the product's specifications.
- **One safe margin.** The layout keeps one safe margin on every side. A product's larger binding margin (15 mm for Pixartprinting) is shown with its rules, not applied to the layout. `PrintPlan.guideZones` computes it for the print guides, but the canvas does not draw it yet.
- **sRGB only.** PDFs are written in sRGB; check the color requirements of the product you order.
- **Analysis is a suggestion.** Vision labels describe what the model recognizes. They do not establish where a photo was taken or who appears in it. The animal detector locates only cats and dogs; wildlife relies on scene labels.
- **Noncommercial LUTs.** The bundled film-emulation LUTs are CC BY-NC-SA 4.0 and cannot be used commercially.
