# Status

The state of testing for Paper & Grain 0.11.0 (26 November 2026), which adds the live Issues list, print guides, Duplicate Page, photo captions, multiple selection, copy and paste, relinking of missing photos, similar-photo stacks, spelling, print-service profiles, CMYK output with a soft proof, and map pages, and keeps what 0.10.0 (25 November 2026) verified. The list of changes is in the [changelog](../CHANGELOG.md). Record here what you verify, how, and what remains to be tried. Use only the sample book or synthetic books built with `cli build` from `Resources/Demo.png` and generated images.

## How the app is checked

- **Unit tests.** `swift test` runs 373 tests with no failures (two timing tests are skipped unless their environment variable names a package). They cover the document model and its compatibility with older projects, saving, opening and moving packages, drafts, imports, page geometry, layers, snapping, photo drops and swaps, typography, the film pipeline and LUT parsing, adjustments, photo analysis and story matching, the print PDF and the print-service catalog (every entry rendered at every size), and every command-line command. Every pull request runs `swift build` and `swift test` on GitHub Actions with Xcode 26.6 and Xcode 27.2.
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
- Photo drops on a synthetic book with real drags: replacing a photo in a four-photo template, filling the lower-right slot, replacing in an automatic gallery with the other frames unchanged, swapping two photos on the same page, and a click on the paper after a photo (no focus ring left). With the Slide template: a panorama on a portrait slot of a two-photo template (frame reduced, note shown) and a portrait photo in the Slide gallery (fitted, not cropped).
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
- Color output (T12), unit tests: known patches (white, black, mid gray, red, a skin tone) through the system's Generic CMYK agree with Little CMS 2's relative colorimetric with black point compensation within 4/255, and with ColorSync's own relative conversion away from black; images agree with solid colors within 3/255; neutral grays use black ink only; the Generic Print PDF holds a four-component ICC-based DCT image, black text as `0 0 0 K`, no RGB color and an output intent naming the profile; an sRGB book exports as before; an RGB profile is refused, the profile is copied into the package, and a deleted copy blocks the export with a preflight blocker; a print service asking for CMYK warns an sRGB book; flattened transparency leaves no `/ca` below 1 and keeps the text searchable; the PSO download refuses a wrong profile and a failed fetch and leaves nothing behind. With Adobe's Coated FOGRA39 from the build Mac (not bundled), the 10-page Pixartprinting export in CMYK keeps every box and renders within the gamut change of the sRGB one (mean difference 0.7 to 13 of 255 per page, largest on saturated gradients).
- Soft proof (T13), unit tests: with the bundled FOGRA39 a saturated synthetic image is above the 10 % warning share; a gray ramp, skin and sky tones (sky 90, 150, 220), a navy shadow, a dark red and a night blue are below; only the part of a photo shown in its frame is measured; the proof keeps mid gray within 4/255 and dulls pure blue; the preflight never renders, lists the missing estimates, and after `GamutEstimator` fills them warns for the saturated photo of a CMYK book only (not the gray one, not an sRGB book); a second enqueue of the same requests adds nothing. Cost (release build of the converter, FOGRA39, a 4000 × 3000 JPEG): building the converter with both tables 62 ms once per profile; a 160 px render 25 ms and the estimate 11 ms, about 36 ms per photo, done in the background two at a time after the first check publishes; proofing a 1440 × 1080 canvas preview 34 ms, so a spread with six photos adds about 0.2 s of preview rendering, spread over the canvas lanes.
- CMYK file size (QA fix, debug build, the 50-page synthetic book with three photos a page). Before the fix every photo's JPEG carried the whole ICC profile (the QA check measured Pixartprinting CMYK 824 MB against 17 MB sRGB, Peecho 1.0 GB, Saal 830 MB, Lulu with GRACoL 349 MB). CMYK JPEG data is now written untagged and tagged again with the profile's color space, so all photos of a file share one ICCBased object; the output intent embeds the profile a second time, as Quartz always writes it. After the fix: Generic Print sRGB 7.4 MB (Interior 5.8, Cover 1.9); CMYK with the bundled Coated_Fogra39L_VIGC_300 48 MB (28.5 and 20.7); with GRACoL2006_Coated1v2 28 MB (18.2 and 10.1); Pixartprinting sRGB 7.3 MB, CMYK FOGRA39 33 MB. What remains above sRGB is the profile, twice per file (Coated_Fogra39L_VIGC_300 compresses only to 8 MB, GRACoL to about 2.7 MB), and CMYK JPEG data without chroma subsampling; a unit test checks one ICCBased object for three photos.
- Size and memory (T12): a 50-page, 150-photo synthetic book (4000 × 3000 JPEGs from `Resources/Demo.png`, three photos, a heading, a paragraph and a text box per page, a cover; 402 MB) exported with **Generic Print** in a release build: sRGB 5.5 s, 7.6 MB (Interior 5.8 MB, Cover 1.8 MB), peak 223 MB; CMYK with Coated FOGRA39 6.1 s, 32.5 MB (26 MB and 6.5 MB), peak 271 MB (`/usr/bin/time -l`). The photos are smaller on these pages than in the 0.10 measurement, so the absolute sizes differ from the 200 MB recorded there; the CMYK data is about 4.4 times the sRGB data because ImageIO writes CMYK JPEG without chroma subsampling. The T12 review measured the same export on a book with larger photos: 6.7 s to 10.4 s (+55 %) and +15 % peak memory for CMYK; the extra time grows with the pixels converted and encoded.
- Printers' checks (T12, open item O2): not done; it needs the user's account at a printer that asks for CMYK.
- Print-service follow-ups (T10 review), unit tests: a saved size that no longer matches falls back to the size with the book's trim; sizes, boards, hinge, wrap and both bleeds given per order (a test-only entry modelled on WhiteWall) are missing until typed and then export with the typed boxes; a quote from 0 accepts 0; a fold-over inside the board keeps the cover's outer width at 26 and 100 pages while the hinge zone grows from 8.975 to 17.018 mm; page limits per paper; endpapers print blank first and last pages with page 1 on its side; an odd count is padded to the step and the warnings give the printer's count and the book's pages; a text box 7 mm from the binding is flagged for Pixartprinting and for a 45 pt binding margin and not on the outer side; one broken file, a partial edge set and a bad array entry are skipped with a readable reason while the Pixartprinting entry stays; measures saved from the export sheet are one undo step. The 10-page Pixartprinting, first-page-right and Generic Print exports are still identical to the base commit.
- Issues list (T1), unit tests only: issue ids are stable across two runs, unique, and follow the page and object rather than the printed number; each target (photo, text box, story, caption, cover face) resolves to its page or face, and one pointing to nothing resolves to nothing; an overflowing box or story is its own blocker with its target and disappears when the text is shortened; a photo whose pixels fall under the target raises a warning on that photo; groups come out book-wide, pages in order, cover last; six changes inside one pause start one run; a run overtaken by a newer change never publishes; stopping the monitor cancels the pending run. The catalog compiles into the debug bundle with the new Italian strings.

### Captions (T4)

- Release candidate fix: a caption set to **Below** or **Above** that would cross the safe line goes on the photo, on full-bleed, full-page and hand-placed frames in Atlas, Essential and Nocturne, with no safe-margin or fit warning, while a frame in the middle of the page keeps the chosen position (`CaptionTests`). The command line keeps a typed trim inside a size given per order (WhiteWall 270 × 352 mm) and refuses one outside it (`BookCLITests`).
- Unit tests (`CaptionTests`): a 0.10 manifest decodes without the new fields and encodes with no caption key; on every template and every page type, empty, blank and hidden captions leave the photo frames exactly as without captions; a gallery of three with one caption (automatic gallery and studio galleries) gives up one band, with the caption half a line under its photo; a four-photo grid keeps one baseline per row and the longest caption sets the band; a manual frame does not change and its caption moves with it; full-bleed photos and panoramas resolve to a band on the photo, text inside the safe line and off the gutter; a photo on two pages shows its caption on both, hidden on one leaves the other; explicit above and on-photo positions; layout is deterministic; **Caption does not fit** for a tall caption on a small photo and for one under a frame at the bottom edge, targeted at the caption; a caption that fits but crosses the safe line raises **Text crosses the safe margin** on the caption (T2's check); place-and-date text in English and Italian; with the Pixartprinting profile, captions under frames that reach the binding stay inside its 15 mm text margin on left and right pages, and raise no safe-margin warning; **Use This One** copies a replaced photo's caption to a chosen photo without one, keeps the chosen photo's own, and reports a different one (`SimilarPhotos.captionCarry`); the default caption style of every template exists on the Mac; in a viewing PDF of each of the twelve templates and the basic style the captions are searchable text in the caption typeface; `build` with `caption`, `photoPlacements.captionPosition` and `typography.caption`, `photos` listing the caption, `patch` on both fields, and the refusals (caption style on a page, unknown position, placement for an asset not on the page).
- Caption style on all twelve templates and the basic style: a synthetic book (Demo.png and two `sips` variants; a three-photo gallery with two captions, a four-photo grid, full bleed, text beside photo, a manual frame with a caption below, two stacked bleed photos, text over photo and a panorama) was built with `cli build`, exported with `export-pdf --profile proof` and rendered to PNG with PDFKit. Captions read at their size on every paper, dark papers included; Japanese Interval, Monograph and Road Log were changed to another face of their family (values in [templates](templates.md)). The panorama's band caption stays on the left page. After T10, the same book in Journal and Berlin Notebook was exported through Generic Print, Generic Print with facing-page spreads and the Pixartprinting profile: bands on full-bleed photos run into the 3 mm bleed on the outer edges and stop at the trim on the binding edge of a spread, like the photo under them; the panorama's band runs across the gutter with its text on the left page.
- Cost, after the review: composing a four-photo gallery page in a release build takes about 0.003 ms with no caption, 0.027 ms with two captions, and 0.30 ms with a pasted caption of 10,000 characters, which is cut to 600 (it took 62 ms before the cut and the single typesetting). A page without printed captions does no caption work. Unit tests cover the cut (characters and lines, with a **Caption does not fit** warning), a frame across the gutter of a panorama (the wider side, or the whole width with a warning) and the absence of caption work on a page without captions.

### Map pages (T14)

- Hiding and framing (`MapTests`): hiding Milan and Munich on a book that also has five Namibian places removes their dots, names and route legs, lists them as hidden with their names, and fits the map to Namibia; with every place hidden the map keeps its region; the same page at two sizes gets the same region; a drag's offset follows the pointer and is limited; towns name places within 50 km on a regional map and up to 150 km on a wide one.
- Unit tests (`MapTests`, on `Tests/Fixtures/test-map.mapdata`, synthetic shapes named TEST): the data format decodes (and refuses other data); Mercator at 0°, ±45° and the 80° limit, north up; the region for one place (minimum span, frame proportions, centred), for five places in Namibia (all inside a padded frame), across the 180° meridian (the narrow window) and zoomed; nearby points merge in order; polygon and line clipping; label placement is deterministic, inside the frame, never over another label or a dot, and drops names on a crowded map; a map of five places merges two photos at one place, draws a route of five stops and names them from the photos, then the nearest TEST town within 50 km (Italian name with English fallback), then nothing; the author's name and a hidden place; a map without located photos is an Issues blocker; only placed photos count unless `all`; the two templates lay out (safe area, trim in Essential, map above the story); only a book with a map page is stamped `writerVersion` 2, and a manifest from a newer writer that cannot be decoded reads as newer; the CLI builds a map page with its `map` object, refuses a zoom of 20, and the exported PDF holds the place names as text, no image, under 300 KB.
- With the fixture copied in as the bundled data (not committed), a synthetic book with five located photos was exported through Generic Print in Journal, Swiss Grid and Nocturne and rendered to PNG: land, lake, dots, route and labels draw in the template's colors, also on Nocturne's black paper, and **Map above text** keeps the story below the map.
- Map data: `scripts/make-map-data.py` downloaded Natural Earth v5.1.2 (with the author's consent) and wrote `Resources/MapData/world.mapdata`: 465,649 bytes, 1,419 land rings with 55,956 points, 393 border lines, 7,342 places; the downloaded GeoJSON stayed in the scratch folder. Reading it takes 23 ms in a release build, off the main thread.
- Real data, rendered (Generic Print, PDFKit to PNG, looked at): five synthetic located photos in Namibia on all twelve templates, **Map** and **Map above text**: a recognizable coast, the Angolan, Botswanan and South African borders, five dots with names (two from the photos, the others the nearest towns: Walvis Bay, Ongwediva) and the route; on Nocturne, Gallery and Berlin Notebook the land is a lighter tint of the dark paper; Essential, Berlin Notebook and Postcard reach the trim. Labels have a halo of the land's tint where the route crosses them. A trip across the 180° meridian in Fiji (Nadi, Suva, Taveuni) shows the narrow window; a single place (Rome) shows the Lazio coast. A viewing PDF of one map page is 7.5 to 11 KB, all vector.
- Timing (release build, real data): clipping the world for the Namibia map 0.27 ms; composing and drawing it at 1,200 px 2.2 ms before the map cache, for a full-bleed photo page's composition of 0.002 ms (its picture arrives from the preview loader). Composed maps are now cached by their inputs (`MapCompositionCache`), so redraws and other surfaces reuse them; page turning was not measured on screen.
- Second review: random one- to three-byte corruptions of the fixture and of the real file (200 each) are all refused, a truncated file too, and 3,000 corruptions behind a valid frame never crash the decoder (an overflowing delta and a point off the globe throw); a CMYK print of a Nocturne map page after the editor composed it has no RGB color operator and no DeviceRGB, and the canvas afterwards still gets RGB names; each place name is in the PDF's text once; the command line refuses a `map` on a text page and lowers the version when a patch removes the last map page; the zoom slider's steps. Re-rendered the Namibia map after the glyph-outline halo.
- After the review: a map page is saved as `textOnly` with a `map` field; a 0.10-shaped model (its arrangements, no `map` field) decodes such a book and reads `writerVersion` 2, and 0.11 reads the pages back as maps, unchanged (`MapTests`).

### Copy and paste (T6)

- Unit tests (`CanvasClipboardTests`): every kind encodes and decodes (with `kind`, in drawing order) and an unknown kind is refused; a private pasteboard carries the objects and the plain text, and plain text from elsewhere reads as text; paste on another page keeps frames, crop, caption position and order, with new box ids, on top; on the same page boxes move 12 pt and the photo is skipped as already there; into another book photos are skipped and text boxes and the story paste; a story becomes the page's story on a page without one (and shows on a gallery page) and a text box on a page with one; plain text becomes a centered box; cut removes photos, boxes and the story; three pasted objects removed leave the page empty. The responder chain: the canvas responder sits after the window, a text view that is first responder answers copy: before it, validation follows the selection and the pasteboard, it is never inserted twice and leaves the chain with its view.

### Multiple selection (T5)

- Unit tests (`GroupSelectionTests`): ⇧/⌘ toggling and a click on the other page of a spread; the selection rectangle drawn both ways, touching versus missing, and an empty one; the group move clamped at each of the four page edges and for a bleeding photo; a group move on a page keeps page, photo and box ids, fixes the other automatic frames and moves the box; the story moves as one group; the six alignments, also to a safe area; distribution of four frames of unequal size, outer two fixed, equal gaps, horizontally and vertically; same width and same height from the last selected, with and without proportions; front, back, forward and backward on a selection of non-adjacent layers keep their order, and nothing moves past the top. The ⌘A and modifier tests of the monitor (⌘A by character, so ⌘Q on AZERTY stays Quit). After review: a bleeding photo no longer freezes a group (members clamp by their own limits), and one text object aligns inside a print service's binding margin on both sides.

## Not yet verified

None of the eleven 0.11 features was seen on screen: the runs that wrote them had no access to the interface, so they are covered by unit tests, PDF checks and the measurements above. The checklist below is **one pass on screen**, grouped by feature and ordered so each group can be done in one go. Items marked with a number are exact steps. The open items that depend on other people or on a printer are after the list.

### 1. Set up

Do these checks in one pass, in this order, in one sitting. Each item is a box to tick; record anything that fails or looks wrong with the item number, and write the result in the **Verified** section above when it passes.

- [ ] **1.1** Quit any running Paper & Grain, then build with `./scripts/build-app.sh` (it installs `~/Applications/Paper & Grain.app`) and open that copy. **Paper & Grain › About** shows version 0.11.0.
- [ ] **1.2** Use **Open the Sample Book** (no Photos permission) for most items. For the items that name a synthetic book, build one with the command line: `cli build spec.json Test.papergrain` from `Resources/Demo.png` and generated images (a 10-page book with a cover, and a 50-page book with 150 photos of 12 MP for the speed items). Never open the drafts in `~/Library/Application Support/PaperAndGrain/Drafts`.
- [ ] **1.3** For the items that need Photos (an album, **Copy Again from Photos**, places read from Photos), choose the photos yourself in the album picker.
- [ ] **1.4** Switch **Settings › App Language** between English and Italian wherever an item says "Italian"; switch the Mac to dark appearance once and walk through the new popovers and sheets.

### 2. Issues (T1)

None of this was seen on screen (no GUI access in this run). With the bundle from `./scripts/build-app.sh` and the sample book:

- [ ] **2.1** Open the sample book. The toolbar shows **Issues** between **Film** and **Export**: a check mark, or a triangle with a number. Hover it: the help reads "Show problems and warnings found in the book". With VoiceOver the button says the counts in words.
- [ ] **2.2** Select a photo on a page and enlarge it with a large crop zoom, or place a small photo: within a second the number rises and the triangle appears. Click the button: the popover lists a warning under "Page N". Click the row: the canvas goes to that page and the photo is selected, with the inspector on the **Photo** tab.
- [ ] **2.3** Type a long text in a text box until it overflows: a row under **Problems** appears about 0.6 s after you stop typing; click it and the box is selected. Shorten the text: the row goes away and the count falls. While typing, the window must not stutter.
- [ ] **2.4** Do the same for the story (heading and text of a page) and for the cover title on the front and the back: the row selects the story, or shows that cover face.
- [ ] **2.5** With no issues the popover says "The book is ready for print." and the toolbar shows the check mark.
- [ ] **2.6** **View › Show Issues** (⇧⌘I) opens and closes the popover, and the menu item then reads **Hide Issues**. Check ⇧⌘I does not collide with a system shortcut. Remove **Issues** from the toolbar with **Customize Toolbar…** and press ⇧⌘I again: the popover must still open, near the top right corner of the canvas. With the toolbar button present, ⇧⌘I opens the popover under the button instead (two popovers are never open at once). Rename the open package in Finder: the list is rechecked, with no stale "Photo file missing". With a blocker the button shows an octagon, with only warnings a triangle.
- [ ] **2.7** **File › Export PDF**: the sheet shows the same rows (not clickable), grouped by page, with a scroll area when there are many. **Continue** stays disabled while a problem remains.
- [ ] **2.8** Italian: switch **Settings › Language** to Italian and check the button help, the popover headings (Problemi, Avvisi, Pagina N, Tutto il libro) and the help topic **Stampa**.
- [ ] **2.9** Dark appearance and a narrow window: the popover stays 360 pt wide and readable.

### 3. Print guides (T2)

Unit tests cover the frames (210 × 210 mm, 3 mm bleed, 10 mm safe), the photo-edge rule (on the trim, 0.2 mm, 1.5 mm and 5 mm inside, bleeding), the safe-line rule, both warnings, stable issue ids, the binding edge, and that no template and arrangement of the standard pages raises either warning. Not seen on screen (no GUI access in this run). With the sample book:

- [ ] **3.1** **View › Show Print Guides**: each page shows a dashed accent line inside it and a thin line just outside; in a two-page view the thin line goes around both pages. A notice with the legend appears for four seconds, only the first time in the session. The menu item reads **Hide Print Guides**. The page does not move or resize when the guides come on. Quit and reopen: the choice is kept.
- [ ] **3.2** The zoom menu in the corner of the canvas has **Print Guides** as well, and it matches the View menu item. Check a full spread (one dashed rectangle around the whole spread) and a first page with the first page on the right (blank left side has none).
- [ ] **3.3** Thumbnails in **Pages**, **Browse the Book** and an exported PDF show no guides. Export the same book with guides on and off and compare (`cmp` after removing dates, or open both).
- [ ] **3.4** **Book & Print**: change **Safe margin** from 10 to 20 mm: the dashed line moves in. Change **Bleed**: the outer line moves.
- [ ] **3.5** Drag a text box so its edge crosses the dashed line: within a second **Issues** shows "Text crosses the safe margin" under the page, and the row selects the box. Drag a photo so its left edge is 1.5 mm inside the page edge: a row says "Photo ends 1.5 mm inside the trim…". Move it to the edge: the row goes.
- [ ] **3.6** Dragging, selecting and cropping work with guides on (the overlay ignores the pointer).
- [ ] **3.7** Italian: **Vista › Mostra guide di stampa**, the legend and both rows. Dark appearance: both lines are visible on white and on a dark photo.
- [ ] **3.8** Shadow: with the guides on, the soft shadow is around the page edge only, not around the dashed or bleed lines. With them off, the page looks as in 0.10. Covers keep their shadow.
- [ ] **3.9** Scroll padding: set **Bleed** to 25 mm in **Book & Print**, turn the guides on and choose **Fit Width** zoom. The outer bleed line must be fully visible on all four sides after scrolling to the edges (it may need a little horizontal scrolling), never cut off by the canvas edge. The page itself must not change size when the guides are toggled. With 3 mm bleed at Fit Width, nothing scrolls extra.
- [ ] **3.10** Not done: guides on the cover faces, and the two warnings for the cover.

### 4. Duplicate Page (T3)

Unit tests cover the copy (only the page id and box ids differ, the layer order refers only to boxes on the copy). Not seen on screen (no GUI access in this run). With the sample book:

- [ ] **4.1** Select page 2 and choose **Page › Duplicate Page** (⌘D): a copy appears right after it and is selected; the inspector stays on the Page tab. Check a page with a text box, two photos and a changed layer order: the copy looks the same, and moving a box on the copy does not move it on the original.
- [ ] **4.2** ⌘Z: the copy goes and the original is selected again; the Edit menu said "Undo Duplicate Page". ⇧⌘Z brings the copy back.
- [ ] **4.3** Right-click a thumbnail in the Pages sidebar: **Duplicate Page** sits after **Insert Page After**.
- [ ] **4.4** Select the front cover, then the back cover: **Duplicate Page** is greyed out. Double-click a text box to type, and open the Page menu: it is greyed out too (⌘D does nothing).
- [ ] **4.5** Italian: **Pagina › Duplica pagina**, and the undo item reads "Annulla Duplica pagina".
- [ ] **4.6** Close and reopen the book: the copy is still there.

### 5. Captions (T4)

Not seen on screen (no GUI access in this run). With a bundle from `./scripts/build-app.sh` and a book with two photos on a gallery page:

- [ ] **5.1** Select a photo. The **Photo** tab starts with **Caption**; type "Etosha". The caption appears under the photo on the canvas, in the Pages thumbnail and in **Browse the Book**, and both photos on the page shrink by the same amount. Type more words, pause, type again: **Edit › Undo** removes one burst of typing at a time.
- [ ] **5.2** **Position**: choose **Above**, **On Photo** and **Hidden**; each is one undo step named **Caption Position**. Place the same photo on another page: the caption is there too; hiding it on one page leaves the other.
- [ ] **5.3** Drag the photo (after the first move its frame is manual): the caption follows during the drag and stays attached after release; resize it from a corner and the caption takes the new width. With **On Photo**, start a drag on the band and from the bottom corner handles: the photo moves or resizes; double-click the photo away from the band: crop opens.
- [ ] **5.4** Click the caption: its photo is selected. Double-click a caption below the photo, and a band on the photo: a text field opens where the caption is; type, then press Esc. Right-click the photo: **Edit Caption** (or **Add Caption** without one) opens the field where the caption will be, and the first letter does not move it. While typing a caption, a text box or story stacked above the photo stays above it.
- [ ] **5.5** On a photo with a place and a date (a book from Photos, or a photo whose place the library has read), **Fill from Place and Date** writes "Place, 12 May 2024"; switch the interface to Italian and it writes "12 maggio 2024". The button is disabled for a photo with neither. **Photo › Caption Photos on This Page** fills only empty captions, says how many, and one **Undo** removes them all.
- [ ] **5.6** **Book & Print › Book Typography › Captions**: change font, size, color and alignment; every caption follows. Check the labels in English and Italian, and VoiceOver on the caption field, the position picker and a caption on the canvas.
- [ ] **5.7** A full-bleed photo with a caption shows a band at the bottom; a long caption on a small photo set **On Photo** raises **Caption does not fit** in **Issues**, and clicking the row selects the photo.
- [ ] **5.8** Typing in a caption on the 50-page synthetic book must not stutter.
- [ ] **5.9** With **Stack Similar Photos** on and two near-duplicates, give the placed one a caption and open **Compare…**: under the other, **Use This One** says it takes the caption; click it, the page shows the chosen photo with that caption, and one ⌘Z brings back both the photo and the empty caption. Give the chosen one a different caption first: the sheet says it keeps its own.
- [ ] **5.10** On a full-bleed page (the **Full bleed** template, and a photo dragged to fill a page by hand), set a caption's **Position** to **Below**, then **Above**: the caption goes on the photo, inside the safe margin, and **Issues** shows no "Text crosses the safe margin" for it. On a photo in the middle of a page, **Below** and **Above** stay where chosen.

### 6. Multiple selection (T5)

Nothing of T5 was seen on screen (no GUI access). With a bundle from `./scripts/build-app.sh` and a synthetic two-page spread holding a text box and two photos:

- [ ] **6.1** Draw a rectangle from blank paper across the box and both photos: all three get an outline and no handles; the Page tab says "3 objects selected"; VoiceOver says it. Drag one photo: all three move together, the guides show for the bounding box, and the group stops at the page edge as a whole. Nudge with → and ⇧→. **Arrange › Align › Align Top**. Then ⌘Z four times: the page is as it started. Save, close, reopen: the frames after the moves are kept when the undos are not made.
- [ ] **6.2** ⇧-click one photo out of the selection and back in; ⌘-click a photo on the other page: a new single selection there. ⌘A on the canvas, and in a text field (selects text instead). Esc and ⇧⌘A deselect.
- [ ] **6.3** **Distribute Horizontally** with three objects, **Make Same Width** with two photos (proportions kept) and with two boxes; the inspector buttons and the context menu on a selected object show the same actions. **Bring Forward** with two objects keeps their order.
- [ ] **6.4** Delete with photos and a box selected: they leave the page, the photos are back in the Photo Library; ⌘Z returns them.
- [ ] **6.5** A selected photo with a caption: the caption follows the group drag. Drop a selection onto another photo: no swap.
- [ ] **6.6** While typing in a box, a story or a caption, ⇧-click inside the text extends the text selection and the object stays edited. Start a group drag and turn the page with the trackpad: the page does not turn; draw a rectangle, then open a sheet mid-drag: nothing stays drawn.
- [ ] **6.7** Single-selection regression list, each to check: click; double-click to crop; double-click to type in a box and in the story; resize by a corner and by a side handle; swap by drop; ⌥-drag to overlap without snapping; context menu on a photo, box and story; layer commands; Delete and ⌘Z; arrow keys; ⌘D duplicates the page.

### 7. Copy and paste (T6)

Not seen on screen (no GUI access). With a bundle from `./scripts/build-app.sh` and a synthetic book:

- [ ] **7.1** Select a text box and two photos, **Edit › Copy**, go to an empty page, **Edit › Paste**: the three appear in the same places and order and are selected. ⌘Z once: the page is empty again.
- [ ] **7.2** **Edit › Paste** again on the first page: the box lands 12 pt lower and right, and a note says the photos are already on the page. ⌘D with a text box selected duplicates it (the Edit menu shows ⌘D next to Duplicate); with nothing or only photos selected ⌘D is **Page › Duplicate Page**. With **Book & Print** open, ⌘X and ⌘V do nothing to the page behind it; Paste is greyed out after clicking the Pages sidebar.
- [ ] **7.3** Copy a story and paste it on a gallery page without text (it becomes the story) and on a page with a story (it becomes a text box). **Edit › Cut** a box: it leaves the page and pastes back.
- [ ] **7.4** Copy from a second open book: the text pastes, the photos are left out with a note. Copy text in TextEdit and paste on the canvas: a text box in the middle. Copy a box and paste in TextEdit: its text.
- [ ] **7.5** While typing in a box, a story, a caption, the inspector, **Book & Print** or **Settings**: Cut, Copy, Paste and Select All act on the text. The menu items are disabled with nothing selected and nothing to paste.

### 8. Missing photos (T7)

Unit tests (`PhotoRelinkTests`) cover, with a real workspace and package: one asset deleted, then relinked to an image with other proportions (id, placements and page kept, new file in the package, blocker gone, manifest saved, proportion warning reported); a text file refused with the photo unchanged; a read-only book refuses; folder matching with other case and extension, subfolders, hidden files and non-images; the 1 % proportion rule. Not seen on screen. With a copy of the sample book (never a draft), after deleting one or two files from its `assets` folder in Finder:

- [ ] **8.1** Open the book: the missing photo shows a grey frame with an icon (and "Photo file missing" on a large frame) on the canvas, in the Pages thumbnails and in the Photo Library tile, at the photo's proportions, with no spinner. **Issues** shows the problem.
- [ ] **8.2** Click **Relink…** on the issue row: a file sheet opens on the book window. Choose another image: the photo shows it in the same frame with the same crop; the problem goes; the analysis restarts. Quit and reopen: still linked. ⌘Z does not bring the missing file back (by design).
- [ ] **8.3** Choose an image with other proportions: a message names the photo and says the crops may have shifted. Choose a text file: a message says the image is unavailable and the photo stays missing.
- [ ] **8.4** Right-click the photo on the canvas, and in the Photo Library: **Relink…**. Select it: the **Photo** tab shows "Photo file missing" with **Relink…**.
- [ ] **8.5** Delete two or more files: the Issues list ends with **Relink All from Folder…**. Choose a folder holding the originals under other case or extension: a confirmation says "found N of M", lists the not found and says ⌘Z cannot undo it; **Cancel** changes nothing; **Relink** reports the result.
- [ ] **8.6** A photo imported from Photos: **Copy Again from Photos** copies the original when access was granted; with access denied it explains and does not show the system prompt.
- [ ] **8.7** Open a book from a read-only volume: the commands are greyed out.
- [ ] **8.8** Italian: all of the above.
- [ ] **8.9** The export sheet lists the missing file without a button (documented limit).
- [ ] **8.10** Delete a file of an open book in Finder while it is open: within a second or so of the live check, the photo's context menu and **Photo** tab offer **Relink…**; put the file back at the same path and the placeholder goes away.
- [ ] **8.11** A missing front or back cover photo: its issue row has **Relink…**. Two subfolders with the same file name: the folder relink lists it as "Several files named" unless one has the photo's size.
- [ ] **8.12** Start an import and relink at once: a message asks to try again when the import has finished. Italian labels of the placeholder follow Settings › Language.

### 9. Similar photos (T8)

Unit tests (`SimilarPhotosTests`) cover transitive groups, the time rule at 9, 10 and 11 bits and at 119 s, 121 s and without dates, photos without a hash, stable results for shuffled input, the choice of the shown photo, `substitutePhoto` (frame, crop, layer, duplicate on the page), generated pictures (a brightened copy always groups, 2 % shifts mostly, different scenes never) and the 1,000-photo timing: about 0.3 ms release, 40 ms debug. Not seen on screen. With the sample book (it has few near-duplicates: add a copy of a photo by importing the same file twice, and a slightly brightened or cropped copy exported from Preview):

- [ ] **9.1** Analyse the photos, then **Photo Library menu › Stack Similar Photos**: near-duplicates show as one thumbnail with a count badge at the top right; the menu item has a check and the choice survives a restart. Turn it off: the library is exactly as before.
- [ ] **9.2** Click the badge: the group opens in place, the other members have a dashed outline; click again: it closes. Dragging a stack's thumbnail drags the photo shown (check the click on the badge does not start a drag, and a click elsewhere on the tile still selects it).
- [ ] **9.3** Place one member on a page: it becomes the one shown. Remove it: the sharpest is shown.
- [ ] **9.4** Right-click a stack or one of its members: **Compare…** shows up to four photos side by side with size, date and page; with five or more members **Next** and **Previous** page through them. **Use This One** on one: every placement of the others (also on the cover) now shows it in the same frame; one ⌘Z restores all; the photos stay in the library.
- [ ] **9.5** Sorting, **Unused**, **On Page** and the search field with stacks on. Add a new photo while analysis runs: the stacks update when it ends.
- [ ] **9.6** Italian: menu item, badge help, sheet.
- [ ] **9.7** With 1,000 photos, turn stacks on and scroll: no stall.
- [ ] **9.8** Put one member of a group on a page, choose **Unused**: the stack shows the best of the unused members (not nothing); search for a word that matches only one member: that photo shows alone, without a badge.
- [ ] **9.9** Compare sheet: under **Use This One** a line says which pages change (or that nothing is close enough / not placed); **Previous**, **Next** and **Done** have help text. With a chain of shots, **Use This One** leaves the members that are not near the chosen one.
- [ ] **9.10** VoiceOver on a stack tile: the value says the count, and the actions list shows "Show the similar photos". A member opened from the stack says it is in a stack.
- [ ] **9.11** Double-click the badge: the stack opens and closes, and the photo is not added to the page.

### 10. Spelling (T9)

Unit tests (`SpellingTests`, with a fake checker) cover the page and target of each row (story, text box, caption, back cover), skipped words (ignored, learned, place names, capitals, digits, short), one row per word, stable unique ids, re-checking only the changed text, captions checked once and only when placed, the context text, and a 0.10 book decoding without `ignoredSpellings`. Tests with the real `NSSpellChecker` (skipped where the dictionaries are missing) found "bellisima" in an Italian sentence and "markett" in an English one, left ordinary Italian headings unflagged, checked a German sentence as German, and measured the first pass over 50 stories: about 220 ms in all, the first text 7 ms, then about 4.3 ms each. A literal 0.10 manifest decodes unchanged. The export sheet does not show spelling rows (by design). `BookCLITests` builds a book with `ignoredSpellings`. Not seen on screen:

- [ ] **10.1** In a book, double-click a story on the canvas and type "una giornata bellisima": the word gets a red underline while typing; type "the markett" in a text box: underlined too. Do the same in the Page tab's story field, a text box in the Text tab, the page heading field, a photo's caption (Photo tab and in place), the cover title and the back cover text. If a field shows no underline, **Edit › Spelling and Grammar › Check Spelling While Typing** must be ticked; report which field ignored `checksSpelling()`.
- [ ] **10.2** Repeat with **Settings › App Language** on Italian and on English: the Edit menu reads "Ortografia e grammatica" in Italian, and both languages are underlined in both.
- [ ] **10.3** **Issues** lists both words as warnings ("p. 1 · “bellisima” · … a few words …") within a second of stopping to type. Click the row: the text opens for editing with the caret in it.
- [ ] **10.4** **Ignore in This Book** on the row: it goes; ⌘Z brings it back; ignore again, save, quit and reopen the book: the row stays away. **Learn Spelling** on another word: it goes, and the word is accepted in other apps too (remove it with System Settings › Keyboard › Text Replacements is not needed; use Edit › Spelling and Grammar › Show Spelling and Grammar › Forget).
- [ ] **10.5** A place name from the photos' metadata (for example a town in the Photo Library's place sort) and a word in capitals do not appear.
- [ ] **10.6** **Settings › Check spelling in the issues list** off: the rows disappear at once; on: they return.
- [ ] **10.7** Typing stays smooth in a 50-page book (the check runs on the main actor in slices of a few milliseconds and only the changed text is asked again). With the cursor in a text field of the inspector (page heading, caption) and then in the photo search field or a numeric typography field: only the book text fields underline; the others do not.
- [ ] **10.8** Edit › Spelling and Grammar › Check Spelling While Typing, set off by hand, stays off in the search field after you have typed in a caption (the probe restores the field editor).
- [ ] **10.9** Help › Text topic has a spelling line in both languages.

### 11. Print services (T10 and T11)

None of this was seen on screen (no GUI access in this run). With the bundle from `./scripts/build-app.sh` and a synthetic 21 × 21 cm book with a cover:

- [ ] **11.1** **Book & Print › Print service** lists **None (generic print)** and, under **Pixartprinting**, **Photo book, hardcover · 21 × 21 cm**. Choose it: **Bleed** reads 3 and **Safe margin** 5; the rules read "Page count in steps of 2", "The count includes 4 cover pages" and "Keep text 5 mm from the edges and 15 mm from the binding"; the notice shows "Specification checked on 26 November 2026", a working **Printer's page** link and the not-affiliated sentence. **Apply**, reopen the sheet: the choice is kept. ⌘Z undoes it in one step.
- [ ] **11.2** Change **Size** to 20 × 20 cm with the product chosen: the section says the product does not offer 20 × 20 cm, lists 21 × 21 cm, and **Use 21 × 21 cm** puts the size back. The size never changes by itself.
- [ ] **11.3** **Issues** with the product chosen and no spine width: a problem "Cover · Spine width missing: enter it from the printer's quote". Type a spine in **Book & Print › Print service › Spine width from the quote (mm)** (or the cover's **Spine width (mm)**): the row goes away. Remove a page so the count is odd: no warning; the export has one more blank page at the end.
- [ ] **11.3b** **File › Export PDF** with the product: change the spine in the sheet and **Continue**; cancel the save panel. **Edit › Undo Print Service Measures** is offered, and **Book & Print** shows the new spine.
- [ ] **11.3c** **View › Show Print Guides** on a Pixartprinting book: a light band 15 mm wide along the binding of each page and the dashed line inside it; on a full spread no band. Drag a text box into the band: within a second **Issues** says the text crosses the safe margin.
- [ ] **11.3d** Change **Size** in **Book & Print** between sizes of a product with several sizes (T11 entries): the **Print service** menu follows the size and no "size not offered" row appears.
- [ ] **11.4** **File › Export PDF**: the list shows **Viewing PDF**, **Generic Print**, **Pixartprinting · Photo book, hardcover · 21 × 21 cm** with "One PDF with the flat cover first. Single pages of 216 × 216 mm." and **Other print service…**. The product shows the spine field filled from the cover, the sRGB note and the notice. **Other print service…** shows a service menu. Export and open the PDF: flat cover first, then single pages.
- [ ] **11.5** A book with no print service: the export sheet has no product row, only **Other print service…**; **Issues** behaves as in 0.10.
- [ ] **11.6** New book from an album: the **Print service** menu above **Book Size** filters the sizes to the product's; **Any print service** brings the common sizes back.
- [ ] **11.7** Italian: **Libro e stampa › Servizio di stampa**, the rules, the notice and the export sheet rows in Italian; VoiceOver reads the link and the measure fields.
- [ ] **11.8** Put a broken `.json` file in the bundle's `Contents/Resources/PrintProfiles` (a copy of the app): **Book & Print** names it under **Print service**, Pixartprinting is still listed, and Console shows the reason under the category `print-profiles`.
- [ ] **11.9** New book with a print service in the filter: the notice with the date and link appears under the menu.

Checks of the catalog entries added after the engine, on screen (the numbers themselves are in `docs/print-services.md`):

- [ ] **11.10** **Book & Print › Print service** lists Pixartprinting, Saal Digital, Blurb, Peecho, WhiteWall, Lulu and Mixam with their products. For each, choose a size, read the rules shown (page count, margins, first and last pages) and the line "Specification checked on 26 Nov 2026" with its link; **Export PDF** of a 10-page book writes the files the entry names (one PDF for Pixartprinting and Peecho; an interior and a cover for the others) and **Issues** shows the page-count rule ("Needs at least 24 pages (has 18)") with the printer's count.
- [ ] **11.11** Saal Digital: the export of the 21 × 28 cm size has one PDF page per double page; the cover is one spread; the spine and fold-over change when you add pages (26 pages 12.0 mm spine, 160 pages 36.0 mm).
- [ ] **11.12** Peecho layflat: the export is one PDF whose first page is the cover and whose pages have no bleed; there is no spine field.
- [ ] **11.13** WhiteWall: the export sheet asks for the page and cover sizes, bleed, fold, wrap and spine; the export is refused without the spine; the guides show the 5 mm margin.
- [ ] **11.14** Lulu: the sheet shows the computed spine for the book's page count (paperback formula; hardcover table) and asks for the casewrap's board, fold and wrap.
- [ ] **11.15** Mixam: the sheet asks for the spine; a digest book with a 0.35 in spine writes a cover of 13.35 × 10.1 in.
- [ ] **11.16** Blurb: the sheet shows the CMYK line and "not a certified PDF/X file"; Standard Landscape shows the tabled spine, the other formats ask for the spine and the panel width; the book's first page on the right gives a 20-page interior of 20 pages.

### 12. Color output (T12)

None of this was seen on screen. With the bundle and the 10-page synthetic book:

- [ ] **12.1** **Book & Print › Color**: choose **CMYK**. The profile menu lists **ECI › Download PSO Coated v3 from ECI…** and, under **On This Mac**, the CMYK profiles installed (Adobe's, if present). Choose one: the menu shows its name and the note "CMYK with … Not a certified PDF/X file…". **Apply**: the package has a `profiles/` folder with the file.
- [ ] **12.2** **Download PSO Coated v3 from ECI…**: the line under the menu says it contacts eci.org once and that the profile is ECI's; the progress line, then the profile is chosen (its SHA-256 is pinned in `ECIProfile.expectedSHA256`). Without network: the message says to download it by hand and use **Choose ICC Profile…**.
- [ ] **12.2b** Choose **Pixartprinting** in **Print service** and **CMYK**: the section says the printer asks for FOGRA39 and chooses the bundled Coated_Fogra39L_VIGC_300. Choose a profile and press **Cancel**: the package has no new file in `profiles/`.
- [ ] **12.3** **Choose ICC Profile…** with an RGB profile: "… is not a CMYK output profile".
- [ ] **12.4** **Export PDF › Generic Print**: the CMYK note; export and open the PDFs in Preview next to the sRGB ones: only the expected gamut change (record the impression here).
- [ ] **12.5** Delete the file from `profiles/` in Finder: **Issues** shows "The color profile … is missing…" and **Continue** is disabled.
- [ ] **12.6** A print service with `flattenTransparency` (T11, Lulu) and a classic text-over-photo page: the exported page shows the panel the same as before, and Acrobat's Output Preview shows no transparency.
- [ ] **12.7** Italian: **Colore**, the menu sections and messages.

### 13. Soft proof (T13)

Not seen on screen. With the bundle, a CMYK book (bundled FOGRA39) and a page with a saturated photo:

- [ ] **13.1** **View › Proof Colors** is greyed out for an sRGB book and available for the CMYK one. Turn it on: the canvas photos turn slightly duller where they are saturated, the page shows "Proof:" with the profile's description (for the bundled FOGRA39 the description is its file name, "Coated_Fogra39L_VIGC_300.icc"), and the Pages thumbnails do not change. Turn it off: the photos return.
- [ ] **13.2** Scroll through the 50-page book with the proof on: page turning stays smooth (record any stutter).
- [ ] **13.3** Open the CMYK book with a cold cache (first open, or after changing the book's look): the other issues appear at once and the gamut rows arrive a few seconds later without blocking typing. **Issues** lists "Colors will be duller in print (… % of the photo is outside the printer's range)" under the saturated photo's page; click it to select the photo.
- [ ] **13.4** Export the PDF with the proof on and off: identical files apart from dates; reopen the book: the proof is off and the manifest is unchanged.
- [ ] **13.5** Italian: **Vista › Prova colori**, the tag and the warning.

### 14. Map pages (T14)

Unit tests, the real data and the timings are under **Verified**. On screen:

- [ ] **14.1** **Insert › Map Page** on a book with located photos (a book from Photos, or photos whose place the library read): the page draws land, borders, dots, a route and names; the Page tab's photos picker, route, names, borders and zoom change it, and each is one ⌘Z step; rename a place with Return and hide it with the switch.
- [ ] **14.2** A book with no located photo shows "No photo in this book has a location" on the page and an **Issues** blocker.
- [ ] **14.3** Add a heading, a text box and a photo on top of the map; they stay editable.
- [ ] **14.4** On the 50-page synthetic book, turn pages to and from a map page: no stutter.
- [ ] **14.5** Open a book that has a map page in Paper & Grain 0.10 (the previous release): it shows the "newer format" message and opens read-only. (Proved only by decoding with a 0.10-shaped model in `MapTests`.)
- [ ] **14.7** On a book whose map shows departure photos far away (Milan, Munich and a trip in Namibia): switch Milan and Munich off in the Page tab's places: their dots, names and route legs disappear and the map fits Namibia; they stay listed, switched off, and switching them on brings them back.
- [ ] **14.8** Double-click the map's paper: a dashed frame and the **Adjust Map** bar. Drag to move, pinch and scroll to zoom, use − and + and the Page tab slider; the thumbnail and **Browse the Book** follow. **Done** (or Esc, or a click outside the map) ends it, and one ⌘Z restores the framing before the session. **Fit to Places** shows every place again. Outside the session, a click on the map deselects and a drag on it draws a selection rectangle, as on paper. Export: the PDF has the same framing.
- [ ] **14.6** Italian: **Inserisci › Pagina con mappa**, the Page tab and the place names in the interface language.

### 15. Older checks from 0.10 (still open)

**Documents**

- [ ] **15.1.1** In the app rather than in unit tests: renaming the open package in Finder, editing, quitting and reopening; ejecting the volume of an open book and using **Save As**; opening a book from a read-only volume; **Delete Draft…** and **Save As** from a draft.

**Editing**

- [ ] **15.2.1** Photo replacement on a full-bleed page, on a full spread, and with ⌥ held over a photo.
- [ ] **15.2.2** Context menu on a text box and on a story.
- [ ] **15.2.3** **Undo after typing.** Type in a story, a heading, a text box and the cover title, click elsewhere and press ⌘Z: the previous text should come back in one step, and redo should work. Page and layout undo keep typed text on purpose, so typing relies on the text field's own undo; this has not been checked in the window.
- [ ] **15.2.4** Scrolling pages with a classic notched mouse wheel.
- [ ] **15.2.5** Arrow keys in the Pages sidebar after deleting a page.
- [ ] **15.2.6** Snapping to the outer edge of a full spread.
- [ ] **15.2.7** Releasing a drag after forcing past the page edge, with a slow drag by hand.
- [ ] **15.2.8** Crop and inline text editing with the floating bar visible.
- [ ] **15.2.9** A large book of 50 pages and 150 photos of 12 MP: page change, selection, tray scrolling, typing, export, and the navigator at full width. Photo selection on an older Mac.
- [ ] **15.2.10** Dragging, resizing and cropping gestures on a spread with a text box and two photos, as a full manual pass in the open window.
- [ ] **15.2.11** Switching to other apps through the Dock while a book is open.

**Photos and film**

- [ ] **15.3.1** The album picker with a real Photos album chosen by the user: every thumbnail selected on the first click.
- [ ] **15.3.2** Dropping files from Finder and photos from Photos onto the window.
- [ ] **15.3.3** A photo edited in Photos, and a photo stored only in iCloud.
- [ ] **15.3.4** A HEIC HDR photo.
- [ ] **15.3.5** **Match Book** with many photos that have their own look.
- [ ] **15.3.6** Importing a LUT with **Change the whole book** ticked.
- [ ] **15.3.7** Photos access from the command line (`cli albums --request-access`) with the signed bundle.
- [ ] **15.3.8** The quality of story suggestions on a real travel album: at least one useful match and any missed photos.

**Printing**

- [ ] **15.4.1** A real printed copy: format, paper and binding chosen with the print shop; spine, grain and detail on faces checked on a proof.
- [ ] **15.4.2** The Pixartprinting PDF checked against an actual quote, and whether Pixartprinting accepts sRGB for this product (open item O1).
- [ ] **15.4.3** Text box background and border, and custom text color, in the print PDF.

**Platforms and accessibility**

- [ ] **15.5.1** macOS 14 and 15 (and 26): the app has only been run on macOS 27.
- [ ] **15.5.2** VoiceOver: Pages sidebar, canvas objects, inspector tabs, template chooser.
- [ ] **15.5.3** Every screen in Italian and in English after the move of all strings to the String Catalog: welcome window, editor with each inspector tab, template chooser, album picker, Book & Print, export sheet, help, About and menus.

### 16. Release candidate checks

- [ ] **16.1** Copy one of the user's own 0.10 books (not a draft in use), open the copy in 0.11, change a page and a caption, save, close; reopen it in 0.10: it opens as before, and the 0.11 additions are simply not shown. Then add a map page in 0.11, save, and open in 0.10: the "newer format" message, read-only.
- [ ] **16.2** Open a book saved with the film-brand template id that 0.11 removed: note the message shown, and that the book opens (or how to recover it).
- [ ] **16.3** Saal Digital: export a book and check where the first and last pages go (on the inside covers); does the export sheet make that clear before the export?
- [ ] **16.4** Blurb: open the export sheet with a book whose **Color** is sRGB; note what the sheet says and whether it lets the export go ahead.
- [ ] **16.5** CMYK export with each bundled profile (GRACoL, FOGRA39) and with PSO Coated v3 on the 50-page synthetic book: file size and time; open the result in Preview and in Acrobat (Output Preview, if available) and check the colors and that no page is blank.

### Open items

These do not need the interface; they wait for other people, other machines or a printer.

- **Pixartprinting, other sizes.** Only the 21 × 21 cm hardcover is in the catalog. The other sizes wait for the user's quote instructions and the printer's cover templates (cover geometry is not scaled from 21 × 21). The instructions PDF also settles whether the interior wants CMYK (the product page asks for FOGRA 39); until then this entry says so in its notes and **Color** can be set to CMYK.
- **Blurb upload check.** No test upload was made (it needs the user's Blurb account, open item O2). The file is CMYK but not certified PDF/X-3:2002, so Blurb's check may refuse it. Record the result here.
- **Printers' CMYK check (T12, open item O2).** Whether a CMYK file from the app is accepted by the upload check of at least one printer that asks for CMYK.
- **Saal Digital, options other than the defaults.** The tables were read for the default options only (glossy unpadded cover, matte photo paper, standard barcode). Other covers and papers, the three smaller sizes (8.5 × 6, 6 × 8.5, 6 × 6 in), XT, Professional Line and softcover are not in the catalog.
- **Mixam layflat.** No readable page gives its sizes or page limits.
- **A real printed copy.** Spine, grain and detail on faces have never been checked on paper, and neither has the Pixartprinting PDF against an actual quote.
- **WhiteWall fold and page range.** Peecho (hardcover and layflat), WhiteWall and Mixam (hardcover) were re-read in a real browser on 26 November 2026 and match the catalog entries: Peecho's sizes, page ranges, no bleed, 10 mm margins (none on the layflat inner edge) and RGB; WhiteWall's sRGB, 1 GB / 250 MB limits, three-edge bleed, 5 mm safety area, 2 mm spine margin and pages added in fours; Mixam's cover formula, 0.8 in cover bleed and 0.125 in interior bleed. Not re-read: WhiteWall's 10–12 mm cover fold and its 28–200 page range (both typed in by the author per order).
- **Print-service entries: what each could not confirm.** The paragraphs below say, per printer, what was read, what the tests pin and what stays unconfirmed.


Blurb: entered from the planning research of 26 November 2026 and checked against the PDF-to-Book page and the calculator page (their static text lists the formats, the covers, the paper limits and the standard; the tables load by script and are not in it). The tests pin the trims, margins, the Standard Landscape spine tables and the documented 20-page page and cover sizes (693 × 594 pt inside page, 1483 × 648 pt ImageWrap cover, 1390 × 594 pt softcover cover). Left unconfirmed, listed here: **the other formats' spine and panel widths** (quote-typed); **the page counts where each spine step changes** (the next column's value is used); **the paper limits** (the page's list is ambiguous: 440/480, 240 for Premium and Proline, and 80 pages for a case it does not name; the entry uses 240 and 110 for layflat from the spine table); **the inside bleed** (the page says 0.125 in on all sides, the calculator's page sizes show the outer edge only; the calculator is followed); **whether the file passes Blurb's check**: no test upload was made (needs the user's Blurb account, open item O2), and the file is CMYK but not certified PDF/X-3:2002, so Blurb may refuse it. (Steps: 11.16.) The export sheet shows the CMYK line and the "not certified" note, asks for the spine and panel width on the other formats, and writes Standard Landscape with the tabled spine.

Mixam: read on 26 November 2026 from the hardcover setup, file setup, binding, page count and CMYK pages (plain page requests with a browser user agent; the automated fetch tool is refused). Left unconfirmed, listed here: **Mixam layflat** (no sizes or page limits on a readable page), **page limits** of the hardcover (per order), **how the two cover pages in Mixam's count appear in the interior file** (the page says "page 2 is blank, the first printed page is page 3" and "include 2 pages for your cover in your total"; the entry counts two cover pages and starts on the right, so the calculator's page count and the file check on upload decide), the **UK millimetre values** (20 mm / 5 mm) which could not be read, and the **cover quiet area at the spine edge** (0.4 in on one page, 0.6 in on another; 0.6 in is in the notes). Not seen on screen: the export sheet asks for the spine and writes the cover at 13.35 × 10.1 in for a digest with a 0.35 in spine (a unit test checks that).

Lulu: read on 26 November 2026 from the Book Creation Guide (the PDF, text extracted), the PDF settings and casewrap help pages and the products page. The hardcover spine table (27 rows to 800 pages) and the paperback formula are captured whole and pinned by `testLuluSpineTableAndFormulaFollowTheGuide`. Left unconfirmed, listed here: **which trims Lulu offers for hardcover casewrap** (the guide's table is for all bindings; the seven photo-book trims of the planning research are listed, and the entry's notes say to check Lulu's calculator); **the casewrap board, fold and wrap**, quote-typed because they are in the cover template generated per order; the other 13 trims of the guide (novel and comic sizes) are not in the catalog. Not seen on screen: the export sheet shows the computed spine for the book's page count and asks for the casewrap measures.

WhiteWall: read on 26 November 2026 from the PDF-upload page, four help-center articles (through the help center's public JSON) and the product page. The page and cover sizes, bleed, wrap, spine and fold are typed from the order, as the structure's quote-typed measures; nothing was estimated. The nominal sizes in the entry come from the product page, whose size table is the only place the six formats are listed. `testWhiteWallTakesEveryMeasureFromTheOrder` pins this. Not seen on screen: the export sheet asks for the six measures, refuses an export without the spine, and the guides show the 5 mm margin.

Peecho: the three entries were read from Peecho's help articles (through the help center's public JSON, because the article pages refuse automated fetches) on 26 November 2026. The catalog tests render every size (boxes), and `PrintCatalogEntriesTests` pins the numbers and checks that text keeps inside the 10 mm margin. Not seen on screen: **Book & Print › Print service › Peecho** lists the three products with their sizes, the page-count rules ("Needs at least 24 pages (has 18)") and the "Specification checked on 26 Nov 2026" line with the link; **Export PDF** for the layflat product writes one PDF whose first page is the cover.

Entries left out because a number could not be confirmed on the printer's own page:

- **Saal Digital, other cover and paper options and the three small sizes.** (The default options were added from the tables the lead read in a browser; see `docs/print-services.md`.) Formerly: all products. The dimension tables (spread, cover, spine, fold-over in pixels at 300 dpi) are not in the pages' text: they load by script on the Professional Zone page, on the EU, US, German and Italian sites alike, and a fetch of the HTML holds none (searched for the example values 5031 and 3260 too). The 21 × 28 cm page gives the closed size as 21.5 × 27.5 cm, which does not agree with the 210 × 280 mm trim the planning research implies, and the example spread in the planning research (5031 × 3260 px) works out to a 270 mm trim height, not 280 mm. Needs the tables read in a browser or the downloadable templates. See `docs/print-services.md`.


## Known limitations

- **Not notarized.** The downloadable app is signed but not notarized by Apple; macOS blocks it the first time (see the README).
- **Tested only on macOS 27.** macOS 14, 15 and 26 are supported but untested.
- **Spine never printed.** The spine geometry has been checked in PDFs only; a real printed spine has never been checked.
- **Font embedding.** The templates use fonts that ship with macOS. Their license for embedding in PDFs of books that are sold has not been checked.
- **Few print-service entries.** The catalog holds Pixartprinting (21 × 21 cm only), Saal Digital (default options), Blurb, Peecho, WhiteWall, Lulu and Mixam's hardcover. Mixam layflat, Pixartprinting's other sizes and Blurb's trade and magazine formats are missing for the reasons in `docs/print-services.md`. Other products use the generic print PDF with the bleed and spine of the product's specifications.
- **One safe margin.** The layout keeps one safe margin on every side. A product's larger binding margin (15 mm for Pixartprinting) is not applied to the layout: the guides show it and the preflight warns about text inside it.
- **Time and size of CMYK exports depend on photo size.** On the test book with small photos CMYK took +11 % time and +21 % memory; the reviewer measured +55 % time (6.7 s to 10.4 s) and +15 % memory on a book with larger photos.
- **CMYK files are larger.** ImageIO writes CMYK JPEG without chroma subsampling: at the same quality the CMYK print PDF of the 50-page test book is about 4.4 times the sRGB one.
- **Analysis is a suggestion.** Vision labels describe what the model recognizes. They do not establish where a photo was taken or who appears in it. The animal detector locates only cats and dogs; wildlife relies on scene labels.
- **Noncommercial LUTs.** The bundled film-emulation LUTs are CC BY-NC-SA 4.0 and cannot be used commercially.
