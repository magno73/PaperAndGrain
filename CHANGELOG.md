# Changelog

User-visible changes in each version of Paper & Grain, newest first. What has been tested, and what has not, is in [docs/status.md](docs/status.md).

## 0.11.0 · unreleased

### Print services

- **Book & Print › Print service** chooses a printer's product and size. It sets bleed and safe margin from the product, lists its page-count and margin rules, and offers the product's sizes, closest first, when the book's size is not one of them; the size changes only when you click **Use …**.
- **Export PDF** lists the book's print service and **Other print service…** for any product in the catalog, with the date the specification was checked, a link to the printer's page and a note that Paper & Grain is not affiliated with the printer.
- **Issues** checks the book against its print service: a size the product does not offer, a page count below the minimum, above the maximum or not in the product's steps, and a missing spine width.
- The new-book size menu can show only the sizes of one print service.
- Print services are described as data, one file per printer. The Pixartprinting 21 × 21 cm hardcover is the first entry and writes the same PDF as before.
- Command line: `export-pdf --profile` accepts a catalog id with `--size`, `--paper`, `--spine-mm`, `--hinge-mm` and `--wrap-mm`; `pixart` still works. `print-profiles` lists the catalog. A build spec accepts `printService`.

### Issues

- **Issues** in the toolbar, next to **Export** (**View › Show Issues**, ⇧⌘I): the preflight check now runs while you work. The button shows the number of problems and warnings, or a check mark when there are none. Its popover lists problems first, then warnings, under the page they belong to; click a row to go to the page and select the photo, text box, story or cover face.
- Each overflowing text box or story is now its own row, so you can go straight to it. The export sheet shows the same list.

### Missing photos

- A photo whose file is missing now shows a placeholder instead of an endless spinner. **Relink…** (issue row, photo context menu, **Photo** tab) copies a chosen image into the book and keeps the photo's id, placements, crops, adjustments and film look. **Relink All from Folder…** matches several missing photos to files by name. **Copy Again from Photos** fetches the original again when access to Photos is already allowed. Relinking is not undoable.

### Print guides

- **View › Show Print Guides** (also in the zoom menu on the canvas) draws the safe margin as a dashed line and the bleed as a thin line outside each page. They never appear in thumbnails, **Browse the Book** or the PDF.
- Two new warnings in **Issues**: text that crosses the safe margin, and a photo edge that ends between 0.25 mm and the bleed inside the page edge.

### Pages

- **Page › Duplicate Page** (⌘D, also in the Pages context menu) copies a page right after itself and selects the copy. One undo step.

## 0.10.0 · 2026-11-25

The first public release. The interface is redesigned for current macOS, and much of the work went into document safety and print output.

### Window and navigation

- A new window layout: the system toolbar with the book title and a title menu (**Book & Print**, **Book Templates**, saving and exporting), a native inspector whose tabs follow the selection (**Page** or **Cover**, **Text**, **Photo**, **Film**), a **Photo Library** tray at the bottom of the canvas and a resizable **Pages** sidebar whose thumbnails grow with its width.
- On macOS 26 and later the panels use Liquid Glass; earlier systems use materials. The app frame follows the light or dark appearance and increased contrast; pages keep their template colors.
- New **Insert**, **Page**, **Photo** and **Arrange** menus, and more items in **View** and **File**, with keyboard shortcuts for every toolbar and canvas action.
- **Open Recent** and the welcome window show recent books with their cover.
- A floating bar under the selection offers **Crop**, **Adjust**, **Film** and **Remove from Page**. The Pages sidebar and the canvas have context menus.
- **Browse the Book** (⌥⌘↩) shows the spreads full screen.
- In the Pages sidebar, ← → step one page and ↑ ↓ one spread. When the whole page fits, scrolling or swiping turns pages. A **+** between pages appears on hover.
- **Settings** (⌘,) chooses the interface language.
- **Help › Paper & Grain Help** (⌘?) opens a short guide in English or Italian. **About Paper & Grain** shows the author, the license and the source repository.
- An app icon.

### Book templates

- Five **Photobook** templates: Monograph, Postcard, Nocturne, Kodachrome and Road Log. With the earlier seven, the twelve templates are grouped in three families (**Classics**, **Studio**, **Photobook**).
- A new book opens on the **Book Templates** chooser. The template can also be changed from **Style** in the toolbar.
- Each template scales the cover title, and a spine of 5 mm or more carries the book title.
- Swiss Grid no longer leaves empty cells with three photos.
- 21 preset photobook sizes (square, landscape and portrait) next to a custom size.

### Laying out pages

- **Layout** in the toolbar and **Page › Page Layout…** pick the page template. The **Insert** menu adds pages with page templates.
- Drop a photo from the tray on a photo on the page to replace it. It keeps the slot and the layer and is never cropped without telling you; an automatic gallery adapts to the new proportions. Drop a photo on an empty slot to fill it. A preview shows what will happen.
- **Bring to Front**, **Bring Forward**, **Send Backward** and **Send to Back** in the context menu and in the **Arrange** menu. The layer order is saved and used in the PDF.
- Photos, boxes, text and cover photos snap to the page edges and center, with a longer reach than other objects. A dragged object stays exactly where it was released.
- A warning badge marks photos whose print resolution is below the book's target: orange below the target, red below two thirds of it. The **Photo** tab shows the value.
- The **Text** tab holds font, size, color, alignment and line spacing for headings, stories, boxes and cover text. A text box can have no background, the paper color or any color, and a border from 0.5 to 12 pt. Formatting controls appear only in the Text tab.
- Photo Library thumbnails keep each photo's proportions.
- Selecting photos in large books is much faster, and canvas previews load in parallel at a size that suits the frame.

### Photos and film looks

- **Import Files…** in the Photo Library adds the chosen images to the open book.
- The album picker lists **Recents** and **Favorites** before your albums, opens on the album used last, shows a clear message for an empty library and loads faster. A click selects the thumbnail you see, even next to a portrait photo.
- Photos added while an analysis is running are analysed when it ends.
- Film for one photo and for the whole book are separate: with a photo selected, a look changes only that photo unless **Change the whole book** is ticked. With nothing selected, the **Film** tab sets the book look and offers **Match Book**.
- The bundled film-emulation LUTs have descriptive names, such as Natural Slide or Street Negative, with no film or camera trademarks.
- LUT import accepts `.cube` files with `LUT_3D_INPUT_RANGE` and HaldCLUT PNGs up to level 12. A 1D LUT is refused with a clear message.
- Sharpening and noise reduction look the same in the preview and in print.
- Story suggestions ignore short, common words read on signs.

### Documents

- Opening a book no longer rewrites it.
- A book renamed or moved in Finder while open keeps saving in its new place. A book that disappears (ejected, deleted) can be saved elsewhere with **Save As**.
- A book saved by a newer version opens read-only. A book in a read-only location opens normally and can be copied elsewhere with **Save As**.
- The welcome window lists every draft. **Delete Draft…** moves a draft to the Trash after asking. After **Save As**, the draft is moved to the Trash.
- **Save As**, imports and opening run in the background, with progress for long copies.
- The undo history no longer carries over between two copies of the same book.
- Errors name the problem in the interface language: book moved, newer format, read-only location, damaged file, image unavailable with its file name.
- Quitting saves the open book even after its window was closed.

### Printing

- Printed page numbers match the editor, also when blank pages are inserted.
- Photos that reach the trim are no longer slightly zoomed in print: the bleed is filled from the photo itself.
- PDFs are several times smaller and use far less memory. The viewing PDF is rendered at about 150 ppi.
- The preflight check lists everything that would stop the export (text that overflows, missing photo files, unreadable LUTs) before you choose a destination, and the export shows its progress.
- Exporting for print again into the same folder replaces the previous files.
- Blank compensation pages take the template's paper color.
- Pixartprinting cover: the title is fitted in the width it is printed in, and a cover band reaches the wrap.
- Full-bleed photos brought to the front no longer cover their neighbor in the PDF.

### Command line

- `build` accepts book, page and cover `typography`, `textBoxes` and `layerOrder`, rejects unknown or misspelled keys, follows symbolic links, and returns a map from spec asset IDs to photo UUIDs.
- `templates` returns the ID, name and family of each template.
- `patch` applies the same page rules as `build` and reports pages with hidden photos or text in `warnings`. A `copy` gives copied pages and text boxes new IDs.
- Errors name the failed check, the page or the file.
- `import-lut --builtin` and the `builtIn` list of `film-looks` use the descriptive look IDs.
- Editing a read-only package works and leaves no hidden copies behind.

### Release and licensing

- The app is named **Paper & Grain** and builds as a universal app for Apple silicon and Intel. Releases are a signed zip that is not notarized; the README explains how to open it.
- The source code is licensed under the PolyForm Noncommercial License 1.0.0. The bundled LUTs keep their CC BY-NC-SA 4.0 license.
- The app identifier is `me.magno.paperandgrain`. Coming from 0.9.x, macOS asks again for Photos access and the recent-books list and preferences start empty; drafts stay in `~/Library/Application Support/PaperAndGrain` and appear in the welcome window.

## 0.9.7 · 2026-11-25

- Delete or Backspace removes the page selected in the Pages sidebar; ⌘Z brings it back.

## 0.9.6 · 2026-11-25

- Library thumbnails show the photo's orientation and keep its original framing.
- A **+** between pages in the sidebar inserts a page.
- **Full Spread** is available as a page template; a photo dropped on a full spread fills both pages.

## 0.9.5 · 2026-11-24

- The photo library groups photos by date, place, subject or usage, by date of capture by default. Photos without the needed metadata are listed at the end.

## 0.9.4 · 2026-11-24

- **Show Page Numbers** in the book templates turns printed folios on or off.

## 0.9.3 · 2026-11-24

- The library shows the page, or cover face, where each photo is used, with a count and a list of other uses.
- The LUT menu shows the active LUT when closed.

## 0.9.2 · 2026-11-24

- Cover photos can be selected, moved, resized and cropped on the canvas, on the front and on the back.
- The Pages sidebar and the inspector can be hidden separately.
- Film sliders update a light preview and make a single undo step. **Book & Print** and template changes can be undone.
- Faster response when selecting objects; autosave runs off the interface thread.

## 0.9.1 · 2026-11-24

- Italian story search recognizes dunes and desert.

## 0.9.0 · 2026-11-24

- The command line imports files or photos from albums, analyses, searches and compares photos, adjusts color and film, patches projects and exports every PDF profile. See the [CLI guide](docs/cli.md).
- Photo analysis adds confidence, detections, recognized text and visual measures. The editor explains why a photo matches a story and can update older analyses.

## 0.8.1 · 2026-11-24

- Swiss Grid, Berlin Notebook and Japanese Interval get their own galleries and **Text over photo** panels. Headings are smaller and fit one line when they can.

## 0.8.0 · 2026-11-24

- Clicks select the object drawn on top. Clicking empty paper deselects. Arrow keys move objects, Delete removes photos and boxes.
- Three new templates: Swiss Grid, Berlin Notebook and Japanese Interval.
- A command line builds editable books from JSON specs.

## 0.7.1 · 2026-11-23

- A handle moves heading, story and background together.
- Images can be dragged into the book's photo library.

## 0.7.0 · 2026-11-23

- Heading, story, boxes and cover text are moved and resized directly on the page.
- A font browser with families, styles, preview, favorites and recent fonts.
- **Save Project** updates the saved package; **Save As** makes a copy.
- **Export PDF** adds the Pixartprinting 21 × 21 cm profile with hardcover and spine width from the quote.

## 0.6.0 · 2026-11-23

- More page templates, grouped with the full-bleed ones: two across, two stacked, three across, a grid of four, one large above two.
- Font, size and alignment for headings, stories, cover and boxes, with book-wide defaults that each object can override.

## 0.5.3 · 2026-11-23

- Drag a photo inside another one on the same page to swap them; hold ⌥ to overlap freely.

## 0.5.2 · 2026-11-23

- Eleven single-page templates in the Page inspector.
- Photo adjustments and film for the front and back cover photos.

## 0.5.1 · 2026-11-23

- Backspace and Delete act on the selected photo. A single click selects, a double click crops or edits a box.
- Resize handles snap photos and crops to other objects. Sliders use a light preview.

## 0.5.0 · 2026-11-23

- Thumbnails show the actual page composition, side by side; pages are reordered one at a time.
- Photo frames can extend past the trim. Double-click a text box to type on the page.
- **Adjust** with auto enhance, and adjustments shared by editor and print.

## 0.4.1 · 2026-11-23

- Photos and boxes snap to the edges and centers of other objects, with guides; hold ⌥ to ignore them.
- 14 bundled film-emulation LUTs.

## 0.4.0 · 2026-11-23

- Drag pages to reorder them, zoom the canvas, resize and crop photos on the page, free text boxes, a title page and an editable front and back cover.
- File panels open as sheets of the book window, and errors appear in the window.

## 0.3.0 · 2026-11-23

- Four book templates with previews, and page headings.

## 0.2.0 · 2026-11-23

- Book size changes, moving and copying photos between pages, text below or beside photos.
- Three film looks with grain, comparison with the original, a book look and per-photo looks, and import of 3D CUBE and HaldCLUT PNG files.
- Print settings: margin, bleed, target resolution, first page on the left or right, single pages or spreads, separate cover, sRGB output.

## 0.1.0 · 2026-11-23

- First version: pick a Photos album and a book size, or files from Finder; galleries, text, mixed, full-page and panorama pages; on-device photo analysis with story suggestions in English and Italian; a viewing PDF; projects saved as packages.
