# Status

The state of testing for Paper & Grain 0.10.0 (25 November 2026), plus the work in progress for 0.11.0 (so far T1, the live Issues list; T2, print guides; T3, Duplicate Page; T4, photo captions; T5, multiple selection; T7, relink; T8, similar photos; and T10, the print-service profile engine). The list of changes is in the [changelog](../CHANGELOG.md). Record here what you verify, how, and what remains to be tried. Use only the sample book or synthetic books built with `cli build` from `Resources/Demo.png` and generated images.

## How the app is checked

- **Unit tests.** `swift test` runs 302 tests with no failures (one timing test is skipped unless `PAPERGRAIN_PREFLIGHT_BOOK` names a package). They cover the document model and its compatibility with older projects, saving, opening and moving packages, drafts, imports, page geometry, layers, snapping, photo drops and swaps, typography, the film pipeline and LUT parsing, adjustments, photo analysis and story matching, the print PDF and the print-service catalog (every entry rendered at every size), and every command-line command. Every pull request runs `swift build` and `swift test` on GitHub Actions with Xcode 26.6 and Xcode 27.2.
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
- Print-service follow-ups (T10 review), unit tests: a saved size that no longer matches falls back to the size with the book's trim; sizes, boards, hinge, wrap and both bleeds given per order (a test-only entry modelled on WhiteWall) are missing until typed and then export with the typed boxes; a quote from 0 accepts 0; a fold-over inside the board keeps the cover's outer width at 26 and 100 pages while the hinge zone grows from 8.975 to 17.018 mm; page limits per paper; endpapers print blank first and last pages with page 1 on its side; an odd count is padded to the step and the warnings give the printer's count and the book's pages; a text box 7 mm from the binding is flagged for Pixartprinting and for a 45 pt binding margin and not on the outer side; one broken file, a partial edge set and a bad array entry are skipped with a readable reason while the Pixartprinting entry stays; measures saved from the export sheet are one undo step. The 10-page Pixartprinting, first-page-right and Generic Print exports are still identical to the base commit.
- Issues list (T1), unit tests only: issue ids are stable across two runs, unique, and follow the page and object rather than the printed number; each target (photo, text box, story, caption, cover face) resolves to its page or face, and one pointing to nothing resolves to nothing; an overflowing box or story is its own blocker with its target and disappears when the text is shortened; a photo whose pixels fall under the target raises a warning on that photo; groups come out book-wide, pages in order, cover last; six changes inside one pause start one run; a run overtaken by a newer change never publishes; stopping the monitor cancels the pending run. The catalog compiles into the debug bundle with the new Italian strings.

### Captions (T4)

- Unit tests (`CaptionTests`): a 0.10 manifest decodes without the new fields and encodes with no caption key; on every template and every page type, empty, blank and hidden captions leave the photo frames exactly as without captions; a gallery of three with one caption (automatic gallery and studio galleries) gives up one band, with the caption half a line under its photo; a four-photo grid keeps one baseline per row and the longest caption sets the band; a manual frame does not change and its caption moves with it; full-bleed photos and panoramas resolve to a band on the photo, text inside the safe line and off the gutter; a photo on two pages shows its caption on both, hidden on one leaves the other; explicit above and on-photo positions; layout is deterministic; **Caption does not fit** for a tall caption on a small photo and for one under a frame at the bottom edge, targeted at the caption; a caption that fits but crosses the safe line raises **Text crosses the safe margin** on the caption (T2's check); place-and-date text in English and Italian; with the Pixartprinting profile, captions under frames that reach the binding stay inside its 15 mm text margin on left and right pages, and raise no safe-margin warning; **Use This One** copies a replaced photo's caption to a chosen photo without one, keeps the chosen photo's own, and reports a different one (`SimilarPhotos.captionCarry`); the default caption style of every template exists on the Mac; in a viewing PDF of each of the twelve templates and the basic style the captions are searchable text in the caption typeface; `build` with `caption`, `photoPlacements.captionPosition` and `typography.caption`, `photos` listing the caption, `patch` on both fields, and the refusals (caption style on a page, unknown position, placement for an asset not on the page).
- Caption style on all twelve templates and the basic style: a synthetic book (Demo.png and two `sips` variants; a three-photo gallery with two captions, a four-photo grid, full bleed, text beside photo, a manual frame with a caption below, two stacked bleed photos, text over photo and a panorama) was built with `cli build`, exported with `export-pdf --profile proof` and rendered to PNG with PDFKit. Captions read at their size on every paper, dark papers included; Japanese Interval, Monograph and Road Log were changed to another face of their family (values in [templates](templates.md)). The panorama's band caption stays on the left page. After T10, the same book in Journal and Berlin Notebook was exported through Generic Print, Generic Print with facing-page spreads and the Pixartprinting profile: bands on full-bleed photos run into the 3 mm bleed on the outer edges and stop at the trim on the binding edge of a spread, like the photo under them; the panorama's band runs across the gutter with its text on the left page.
- Cost, after the review: composing a four-photo gallery page in a release build takes about 0.003 ms with no caption, 0.027 ms with two captions, and 0.30 ms with a pasted caption of 10,000 characters, which is cut to 600 (it took 62 ms before the cut and the single typesetting). A page without printed captions does no caption work. Unit tests cover the cut (characters and lines, with a **Caption does not fit** warning), a frame across the gutter of a panorama (the wider side, or the whole width with a warning) and the absence of caption work on a page without captions.

### Multiple selection (T5)

- Unit tests (`GroupSelectionTests`): ⇧/⌘ toggling and a click on the other page of a spread; the selection rectangle drawn both ways, touching versus missing, and an empty one; the group move clamped at each of the four page edges and for a bleeding photo; a group move on a page keeps page, photo and box ids, fixes the other automatic frames and moves the box; the story moves as one group; the six alignments, also to a safe area; distribution of four frames of unequal size, outer two fixed, equal gaps, horizontally and vertically; same width and same height from the last selected, with and without proportions; front, back, forward and backward on a selection of non-adjacent layers keep their order, and nothing moves past the top. The ⌘A and modifier tests of the monitor.

## Not yet verified

### Multiple selection (T5)

Nothing of T5 was seen on screen (no GUI access). With a bundle from `./scripts/build-app.sh` and a synthetic two-page spread holding a text box and two photos:

1. Draw a rectangle from blank paper across the box and both photos: all three get an outline and no handles; the Page tab says "3 objects selected"; VoiceOver says it. Drag one photo: all three move together, the guides show for the bounding box, and the group stops at the page edge as a whole. Nudge with → and ⇧→. **Arrange › Align › Align Top**. Then ⌘Z four times: the page is as it started. Save, close, reopen: the frames after the moves are kept when the undos are not made.
2. ⇧-click one photo out of the selection and back in; ⌘-click a photo on the other page: a new single selection there. ⌘A on the canvas, and in a text field (selects text instead). Esc and ⇧⌘A deselect.
3. **Distribute Horizontally** with three objects, **Make Same Width** with two photos (proportions kept) and with two boxes; the inspector buttons and the context menu on a selected object show the same actions. **Bring Forward** with two objects keeps their order.
4. Delete with photos and a box selected: they leave the page, the photos are back in the Photo Library; ⌘Z returns them.
5. A selected photo with a caption: the caption follows the group drag. Drop a selection onto another photo: no swap.
6. Single-selection regression list, each to check: click; double-click to crop; double-click to type in a box and in the story; resize by a corner and by a side handle; swap by drop; ⌥-drag to overlap without snapping; context menu on a photo, box and story; layer commands; Delete and ⌘Z; arrow keys; ⌘D duplicates the page.

### Captions (T4)

Not seen on screen (no GUI access in this run). With a bundle from `./scripts/build-app.sh` and a book with two photos on a gallery page:

1. Select a photo. The **Photo** tab starts with **Caption**; type "Etosha". The caption appears under the photo on the canvas, in the Pages thumbnail and in **Browse the Book**, and both photos on the page shrink by the same amount. Type more words, pause, type again: **Edit › Undo** removes one burst of typing at a time.
2. **Position**: choose **Above**, **On Photo** and **Hidden**; each is one undo step named **Caption Position**. Place the same photo on another page: the caption is there too; hiding it on one page leaves the other.
3. Drag the photo (after the first move its frame is manual): the caption follows during the drag and stays attached after release; resize it from a corner and the caption takes the new width. With **On Photo**, start a drag on the band and from the bottom corner handles: the photo moves or resizes; double-click the photo away from the band: crop opens.
4. Click the caption: its photo is selected. Double-click a caption below the photo, and a band on the photo: a text field opens where the caption is; type, then press Esc. Right-click the photo: **Edit Caption** (or **Add Caption** without one) opens the field where the caption will be, and the first letter does not move it. While typing a caption, a text box or story stacked above the photo stays above it.
5. On a photo with a place and a date (a book from Photos, or a photo whose place the library has read), **Fill from Place and Date** writes "Place, 12 May 2024"; switch the interface to Italian and it writes "12 maggio 2024". The button is disabled for a photo with neither. **Photo › Caption Photos on This Page** fills only empty captions, says how many, and one **Undo** removes them all.
6. **Book & Print › Book Typography › Captions**: change font, size, color and alignment; every caption follows. Check the labels in English and Italian, and VoiceOver on the caption field, the position picker and a caption on the canvas.
7. A full-bleed photo with a caption shows a band at the bottom; a long caption on a small photo set **On Photo** raises **Caption does not fit** in **Issues**, and clicking the row selects the photo.
8. Typing in a caption on the 50-page synthetic book must not stutter.
9. With **Stack Similar Photos** on and two near-duplicates, give the placed one a caption and open **Compare…**: under the other, **Use This One** says it takes the caption; click it, the page shows the chosen photo with that caption, and one ⌘Z brings back both the photo and the empty caption. Give the chosen one a different caption first: the sheet says it keeps its own.


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

### Spelling (T9)

Unit tests (`SpellingTests`, with a fake checker) cover the page and target of each row (story, text box, caption, back cover), skipped words (ignored, learned, place names, capitals, digits, short), one row per word, stable unique ids, re-checking only the changed text, captions checked once and only when placed, the context text, and a 0.10 book decoding without `ignoredSpellings`. Tests with the real `NSSpellChecker` (skipped where the dictionaries are missing) found "bellisima" in an Italian sentence and "markett" in an English one, left ordinary Italian headings unflagged, checked a German sentence as German, and measured the first pass over 50 stories: about 220 ms in all, the first text 7 ms, then about 4.3 ms each. A literal 0.10 manifest decodes unchanged. The export sheet does not show spelling rows (by design). `BookCLITests` builds a book with `ignoredSpellings`. Not seen on screen:

1. In a book, double-click a story on the canvas and type "una giornata bellisima": the word gets a red underline while typing; type "the markett" in a text box: underlined too. Do the same in the Page tab's story field, a text box in the Text tab, the page heading field, a photo's caption (Photo tab and in place), the cover title and the back cover text. If a field shows no underline, **Edit › Spelling and Grammar › Check Spelling While Typing** must be ticked; report which field ignored `checksSpelling()`.
2. Repeat with **Settings › App Language** on Italian and on English: the Edit menu reads "Ortografia e grammatica" in Italian, and both languages are underlined in both.
3. **Issues** lists both words as warnings ("p. 1 · “bellisima” · … a few words …") within a second of stopping to type. Click the row: the text opens for editing with the caret in it.
4. **Ignore in This Book** on the row: it goes; ⌘Z brings it back; ignore again, save, quit and reopen the book: the row stays away. **Learn Spelling** on another word: it goes, and the word is accepted in other apps too (remove it with System Settings › Keyboard › Text Replacements is not needed; use Edit › Spelling and Grammar › Show Spelling and Grammar › Forget).
5. A place name from the photos' metadata (for example a town in the Photo Library's place sort) and a word in capitals do not appear.
6. **Settings › Check spelling in the issues list** off: the rows disappear at once; on: they return.
7. Typing stays smooth in a 50-page book (the check runs on the main actor in slices of a few milliseconds and only the changed text is asked again). With the cursor in a text field of the inspector (page heading, caption) and then in the photo search field or a numeric typography field: only the book text fields underline; the others do not.
8. Edit › Spelling and Grammar › Check Spelling While Typing, set off by hand, stays off in the search field after you have typed in a caption (the probe restores the field editor).
9. Help › Text topic has a spelling line in both languages.

### Similar photos (T8)

Unit tests (`SimilarPhotosTests`) cover transitive groups, the time rule at 9, 10 and 11 bits and at 119 s, 121 s and without dates, photos without a hash, stable results for shuffled input, the choice of the shown photo, `substitutePhoto` (frame, crop, layer, duplicate on the page), generated pictures (a brightened copy always groups, 2 % shifts mostly, different scenes never) and the 1,000-photo timing: about 0.3 ms release, 40 ms debug. Not seen on screen. With the sample book (it has few near-duplicates: add a copy of a photo by importing the same file twice, and a slightly brightened or cropped copy exported from Preview):

1. Analyse the photos, then **Photo Library menu › Stack Similar Photos**: near-duplicates show as one thumbnail with a count badge at the top right; the menu item has a check and the choice survives a restart. Turn it off: the library is exactly as before.
2. Click the badge: the group opens in place, the other members have a dashed outline; click again: it closes. Dragging a stack's thumbnail drags the photo shown (check the click on the badge does not start a drag, and a click elsewhere on the tile still selects it).
3. Place one member on a page: it becomes the one shown. Remove it: the sharpest is shown.
4. Right-click a stack or one of its members: **Compare…** shows up to four photos side by side with size, date and page; with five or more members **Next** and **Previous** page through them. **Use This One** on one: every placement of the others (also on the cover) now shows it in the same frame; one ⌘Z restores all; the photos stay in the library.
5. Sorting, **Unused**, **On Page** and the search field with stacks on. Add a new photo while analysis runs: the stacks update when it ends.
6. Italian: menu item, badge help, sheet.
7. With 1,000 photos, turn stacks on and scroll: no stall.
8. Put one member of a group on a page, choose **Unused**: the stack shows the best of the unused members (not nothing); search for a word that matches only one member: that photo shows alone, without a badge.
9. Compare sheet: under **Use This One** a line says which pages change (or that nothing is close enough / not placed); **Previous**, **Next** and **Done** have help text. With a chain of shots, **Use This One** leaves the members that are not near the chosen one.
10. VoiceOver on a stack tile: the value says the count, and the actions list shows "Show the similar photos". A member opened from the stack says it is in a stack.
11. Double-click the badge: the stack opens and closes, and the photo is not added to the page.

### Relink (T7)

Unit tests (`PhotoRelinkTests`) cover, with a real workspace and package: one asset deleted, then relinked to an image with other proportions (id, placements and page kept, new file in the package, blocker gone, manifest saved, proportion warning reported); a text file refused with the photo unchanged; a read-only book refuses; folder matching with other case and extension, subfolders, hidden files and non-images; the 1 % proportion rule. Not seen on screen. With a copy of the sample book (never a draft), after deleting one or two files from its `assets` folder in Finder:

1. Open the book: the missing photo shows a grey frame with an icon (and "Photo file missing" on a large frame) on the canvas, in the Pages thumbnails and in the Photo Library tile, at the photo's proportions, with no spinner. **Issues** shows the problem.
2. Click **Relink…** on the issue row: a file sheet opens on the book window. Choose another image: the photo shows it in the same frame with the same crop; the problem goes; the analysis restarts. Quit and reopen: still linked. ⌘Z does not bring the missing file back (by design).
3. Choose an image with other proportions: a message names the photo and says the crops may have shifted. Choose a text file: a message says the image is unavailable and the photo stays missing.
4. Right-click the photo on the canvas, and in the Photo Library: **Relink…**. Select it: the **Photo** tab shows "Photo file missing" with **Relink…**.
5. Delete two or more files: the Issues list ends with **Relink All from Folder…**. Choose a folder holding the originals under other case or extension: a confirmation says "found N of M", lists the not found and says ⌘Z cannot undo it; **Cancel** changes nothing; **Relink** reports the result.
6. A photo imported from Photos: **Copy Again from Photos** copies the original when access was granted; with access denied it explains and does not show the system prompt.
7. Open a book from a read-only volume: the commands are greyed out.
8. Italian: all of the above.
9. The export sheet lists the missing file without a button (documented limit).
10. Delete a file of an open book in Finder while it is open: within a second or so of the live check, the photo's context menu and **Photo** tab offer **Relink…**; put the file back at the same path and the placeholder goes away.
11. A missing front or back cover photo: its issue row has **Relink…**. Two subfolders with the same file name: the folder relink lists it as "Several files named" unless one has the photo's size.
12. Start an import and relink at once: a message asks to try again when the import has finished. Italian labels of the placeholder follow Settings › Language.

### Print guides (T2)

Unit tests cover the frames (210 × 210 mm, 3 mm bleed, 10 mm safe), the photo-edge rule (on the trim, 0.2 mm, 1.5 mm and 5 mm inside, bleeding), the safe-line rule, both warnings, stable issue ids, the binding edge, and that no template and arrangement of the standard pages raises either warning. Not seen on screen (no GUI access in this run). With the sample book:

1. **View › Show Print Guides**: each page shows a dashed accent line inside it and a thin line just outside; in a two-page view the thin line goes around both pages. A notice with the legend appears for four seconds, only the first time in the session. The menu item reads **Hide Print Guides**. The page does not move or resize when the guides come on. Quit and reopen: the choice is kept.
2. The zoom menu in the corner of the canvas has **Print Guides** as well, and it matches the View menu item. Check a full spread (one dashed rectangle around the whole spread) and a first page with the first page on the right (blank left side has none).
3. Thumbnails in **Pages**, **Browse the Book** and an exported PDF show no guides. Export the same book with guides on and off and compare (`cmp` after removing dates, or open both).
4. **Book & Print**: change **Safe margin** from 10 to 20 mm: the dashed line moves in. Change **Bleed**: the outer line moves.
5. Drag a text box so its edge crosses the dashed line: within a second **Issues** shows "Text crosses the safe margin" under the page, and the row selects the box. Drag a photo so its left edge is 1.5 mm inside the page edge: a row says "Photo ends 1.5 mm inside the trim…". Move it to the edge: the row goes.
6. Dragging, selecting and cropping work with guides on (the overlay ignores the pointer).
7. Italian: **Vista › Mostra guide di stampa**, the legend and both rows. Dark appearance: both lines are visible on white and on a dark photo.
8. Shadow: with the guides on, the soft shadow is around the page edge only, not around the dashed or bleed lines. With them off, the page looks as in 0.10. Covers keep their shadow.
9. Scroll padding: set **Bleed** to 25 mm in **Book & Print**, turn the guides on and choose **Fit Width** zoom. The outer bleed line must be fully visible on all four sides after scrolling to the edges (it may need a little horizontal scrolling), never cut off by the canvas edge. The page itself must not change size when the guides are toggled. With 3 mm bleed at Fit Width, nothing scrolls extra.
10. Not done: guides on the cover faces, and the two warnings for the cover.

### Print-service profiles (T10)

None of this was seen on screen (no GUI access in this run). With the bundle from `./scripts/build-app.sh` and a synthetic 21 × 21 cm book with a cover:

1. **Book & Print › Print service** lists **None (generic print)** and, under **Pixartprinting**, **Photo book, hardcover · 21 × 21 cm**. Choose it: **Bleed** reads 3 and **Safe margin** 5; the rules read "Page count in steps of 2", "The count includes 4 cover pages" and "Keep text 5 mm from the edges and 15 mm from the binding"; the notice shows "Specification checked on 26 November 2026", a working **Printer's page** link and the not-affiliated sentence. **Apply**, reopen the sheet: the choice is kept. ⌘Z undoes it in one step.
2. Change **Size** to 20 × 20 cm with the product chosen: the section says the product does not offer 20 × 20 cm, lists 21 × 21 cm, and **Use 21 × 21 cm** puts the size back. The size never changes by itself.
3. **Issues** with the product chosen and no spine width: a problem "Cover · Spine width missing: enter it from the printer's quote". Type a spine in **Book & Print › Print service › Spine width from the quote (mm)** (or the cover's **Spine width (mm)**): the row goes away. Remove a page so the count is odd: no warning; the export has one more blank page at the end.
3b. **File › Export PDF** with the product: change the spine in the sheet and **Continue**; cancel the save panel. **Edit › Undo Print Service Measures** is offered, and **Book & Print** shows the new spine.
3c. **View › Show Print Guides** on a Pixartprinting book: a light band 15 mm wide along the binding of each page and the dashed line inside it; on a full spread no band. Drag a text box into the band: within a second **Issues** says the text crosses the safe margin.
3d. Change **Size** in **Book & Print** between sizes of a product with several sizes (T11 entries): the **Print service** menu follows the size and no "size not offered" row appears.
4. **File › Export PDF**: the list shows **Viewing PDF**, **Generic Print**, **Pixartprinting · Photo book, hardcover · 21 × 21 cm** with "One PDF with the flat cover first. Single pages of 216 × 216 mm." and **Other print service…**. The product shows the spine field filled from the cover, the sRGB note and the notice. **Other print service…** shows a service menu. Export and open the PDF: flat cover first, then single pages.
5. A book with no print service: the export sheet has no product row, only **Other print service…**; **Issues** behaves as in 0.10.
6. New book from an album: the **Print service** menu above **Book Size** filters the sizes to the product's; **Any print service** brings the common sizes back.
7. Italian: **Libro e stampa › Servizio di stampa**, the rules, the notice and the export sheet rows in Italian; VoiceOver reads the link and the measure fields.
8. Put a broken `.json` file in the bundle's `Contents/Resources/PrintProfiles` (a copy of the app): **Book & Print** names it under **Print service**, Pixartprinting is still listed, and Console shows the reason under the category `print-profiles`.
9. New book with a print service in the filter: the notice with the date and link appears under the menu.

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
- **One safe margin.** The layout keeps one safe margin on every side. A product's larger binding margin (15 mm for Pixartprinting) is not applied to the layout: the guides show it and the preflight warns about text inside it.
- **sRGB only.** PDFs are written in sRGB; check the color requirements of the product you order.
- **Analysis is a suggestion.** Vision labels describe what the model recognizes. They do not establish where a photo was taken or who appears in it. The animal detector locates only cats and dogs; wildlife relies on scene labels.
- **Noncommercial LUTs.** The bundled film-emulation LUTs are CC BY-NC-SA 4.0 and cannot be used commercially.
