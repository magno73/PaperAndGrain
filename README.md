# Paper & Grain

Paper & Grain is a native Mac app that turns a travel album into a printed photobook. It mixes photos and stories, film looks and editorial page templates. It also exports print-ready PDFs.

It is written in SwiftUI. Photo access uses PhotoKit, photo analysis uses Vision and the PDF output uses Core Graphics and Core Text. Everything runs on your Mac: photos are copied into the book and analysed locally, and nothing is uploaded. The interface is available in English and Italian.

> **Status:** a working prototype that is used to build real books. The first test book was a trip to Namibia. Expect rough edges, and check every PDF with your print shop before ordering.

## Features

- **Start from an album.** Pick an album in Photos, or files in Finder. Choose a book size from 21 common photobook formats or a custom one. A first draft is laid out in shooting order.
- **Twelve book templates in three families.** **Classics**, **Studio** and **Photobook**, the last drawn from award-winning photobooks. A template sets paper, type, margins, page rhythm, cover and spine.
- **Page layouts.** An automatic gallery, fixed layouts with margins or full bleed, full spreads and text-over-photo pages. Photos, text boxes and stories can be moved, resized, cropped, aligned with guides and stacked in front of or behind each other.
- **Stories.** Write next to your photos. **Suggested photos** finds pictures that match the text, using on-device labels in English and Italian.
- **Photo editing.** Auto enhance, light, color, black & white, detail, curves, levels and selective color. Film looks: built-in presets, 14 Fujifilm-style LUTs and your own `.cube` or HaldCLUT files, for the whole book or a single photo.
- **Print output.** A proof PDF, a generic print PDF with bleed (`Interior.pdf` and `Cover.pdf` with spine) and a Pixartprinting 21 × 21 cm profile. A preflight check flags photos below the target resolution.
- **Command line.** A CLI to build, analyse, edit and export books from JSON, so scripts and AI agents can work on a book.

## Requirements

- macOS 14 Sonoma or later. On macOS 26 and later the panels use Liquid Glass.
- Xcode, or the Swift toolchain that comes with it (Swift 5.10 or later), to build.

## Build and run

From the repository root:

```sh
./scripts/build-app.sh            # debug build
./scripts/build-app.sh release    # optimised build
open ~/Applications/"Paper & Grain Redesign.app"
```

The script builds the executable, bundles resources and translations, signs the app locally and copies it to **`~/Applications/Paper & Grain Redesign.app`**. Every build replaces that copy, so the latest one is always in the same place. A versioned copy also stays in `dist/<version>/`. Set `PAPERGRAIN_INSTALL_DIR` to install somewhere else.

The app is built as **Paper & Grain Redesign** (`local.paperandgrain.mac.redesign`) and keeps its drafts in its own folder, separate from any other Paper & Grain build. Use the bundle, not `swift run`, when you test access to Photos: macOS grants that permission to the signed app.

Run the tests with:

```sh
swift test
```

`scripts/publish-github.sh` publishes the current branch to GitHub as `main`. On a temporary copy it replaces the author email with the GitHub noreply address and drops the files listed in `removed_paths` from every commit, so the local history is left untouched. Run it with `--force` once after adding a path.

## Make your first book

1. Choose **New Book from a Photos Album** and allow access when macOS asks. Pick an album, select the pictures, set the size and press **Auto-Layout**. **New Book from Finder Files** works without Photos. **Open the Sample Book** needs no permissions at all.
2. A new book opens on the **Book Templates** chooser. **Apply** sets paper, type and margins. **Cancel** keeps the basic style. You can change the template later from **Style** in the toolbar.
3. Arrange the pages. Drag photos from the **Photo Library** tray at the bottom onto a page, drag thumbnails in the **Pages** sidebar to reorder pages, and pick a layout with **Layout** in the toolbar.
4. Select a heading, story or text box to write and format it. Select a photo to adjust it or give it a film look.
5. Choose **Save Project** to keep a `.papergrain` package, then **Export PDF** or **Export for Print**.

## The window

| Area | What it does |
|---|---|
| **Pages** (left, ⌃⌘S) | Spread thumbnails. Drag to reorder; hover between pages for **+**; right-click to insert, move or delete. After clicking a thumbnail, ← → step one page and ↑ ↓ one spread. Drag the edge to make thumbnails larger. |
| **Toolbar** | **Insert**, **Style** (book template), **Layout** (page layout), **Film**, **Export**, **Photo Library** and **Inspector**. Click the book title for **Book & Print**, templates, saving and exporting. |
| **Canvas** | One page or a spread (⌘1, ⌘2), zoom (⌘+, ⌘−, ⌘0). When the whole page fits, scroll or swipe to turn pages. **Browse the Book** (⌥⌘↩) shows the book full screen. |
| **Photo Library** (bottom, ⌥⌘L) | Thumbnails in each photo's own proportions. Filters **All**, **Unused** and **On Page**, sorting by date, place or subject, a theme filter and search. Drop files from Finder or Photos here to add them. |
| **Inspector** (right, ⌥⌘I) | Tabs follow the selection. **Page** or **Cover**. **Text** for a heading, story, box or cover text. **Photo** for a selected photo, cover photo included. **Film** for the book look when no photo is selected. |

The app frame follows the Mac's light or dark appearance. Pages always keep their template colors.

## Laying out pages

- **Select and move.** A click selects the topmost object. Click blank paper, or press Esc or ⇧⌘A, to deselect. Arrow keys nudge the selection by 1 pt, or 10 pt with ⇧. Delete removes it from the page, and ⌘Z brings it back.
- **Page layouts.** **Page → Page Template**, or **Layout** in the toolbar, is the single control for the page type. **Automatic gallery** arranges the photos for you. Fixed layouts, with margins or full bleed, place frames, and **Full Spread** fills both pages. Photos that do not fit a layout stay listed on the page until there is room.
- **Photos.** Drag a photo from the tray onto a photo on the page to replace it. It keeps the same slot and layer and is never cropped without telling you:
  - with similar proportions, it fills the same frame;
  - an automatic gallery lays the page out again for the new proportions;
  - in a fixed layout, or a frame you placed by hand, the frame shrinks to the whole photo and nothing else moves;
  - a full-bleed slot is filled, and a note says the photo was cropped.

  Drag a photo onto an empty slot to fill that slot, or onto an empty page to start its layout. Anywhere else it gets a free frame where you drop it. Use the corner handles to resize, even past the trim. Double-click to crop, then press **Done**. Drop a photo inside another one to swap them; hold ⌥ to overlap freely instead. Guides show alignment with the edges and centers of other objects and of the page. Snapping happens while you drag: the photo jumps to the guide and stays where you see it when you let go. The page edges pull a little harder, so a photo brought close to the trim lands exactly on it. Keep dragging past the pull to place it freely, or hold ⌥ to ignore all guides.
- **Layers.** Right-click, or Control-click, a photo, box or story for its own menu. It includes **Bring to Front**, **Bring Forward**, **Send Backward** and **Send to Back**. The same commands are in the **Arrange** menu (⇧⌘F, ⌥⇧⌘F, ⌥⇧⌘B, ⇧⌘B). The order is saved and used in the PDF.
- **Text.** **Insert → Text Box** adds a free text frame. **Insert → Page Heading** adds a heading to any page. Drag text to move it; use the side handles for width and the corners for height. Double-click to type on the page. Drag the story's background, or its **Move Story Group** handle, to move heading, story and background together.
- **Cover.** **Cover**, **First Page** and **Back Cover** open from the Pages sidebar. **Insert → Title Page** adds an opening page with the book title. Both cover faces take a photo and text that you can move, resize and crop.

## Book templates

Choose **Style** in the toolbar, the **Book Template** row in the Page tab, or **File › Book Templates…**:

- **Classics:** Diary, Atlas, Gallery and Essential.
- **Studio:** Swiss Grid, Berlin Notebook and Japanese Interval.
- **Photobook:** Monograph, Postcard, Nocturne, Kodachrome and Road Log. They draw on *The Americans*, *Fernweh*, Luigi Ghirri's *Kodachrome* and *American Surfaces*.

Each template sets paper color, typefaces, margins, the automatic gallery, text-over-photo panels and a cover title scaled to the template. From a spine width of 5 mm, the spine carries the book title. **Show Page Numbers** turns printed folios on or off. [Template notes](docs/templates.md).

## Formatting text

Select a heading, story or text box and the **Text** tab opens, like Keynote's Format panel:

- **Font:** choose a family and style from the fonts installed on your Mac, with a live preview. Favorites and recent fonts are kept.
- **Size:** −, + or type the size in points.
- **Color:** the template's swatches or any color.
- **Alignment** and **Line Spacing.**
- **Box:** a text box can have no background, the paper color or any color, and a border from 0.5 to 12 pt in any color.
- **Reset to Template Style** removes local changes. **Arrange** brings the object to the front or sends it to the back.

Select the cover title or the back cover text to format it in the same tab. Book-wide defaults for headings and body text are in **Book & Print → Book Typography**. The editor, thumbnails and PDF share the same Core Text layout, so what you see is what prints.

## Photo adjustments and film looks

Select a photo. The **Photo** tab groups **Adjust**, **Film** and **Analysis** in sections that start collapsed. The current look is shown next to **Film**.

- **Adjust:** **Auto Enhance** analyses the photo on your Mac and proposes values you can edit. Then come light, color and white balance, black & white, detail and sharpness, noise reduction, vignette, curves, levels and selective color. **Compare with original** shows the untouched file. Adjustments follow the photo everywhere it is used, and into the PDF.
- **Film for one photo:** with a photo selected, a film choice changes **only that photo**. Tick **Change the whole book** to change the book look instead; the photo then follows the book again. **Follow Book** removes a photo's own look.
- **Film for the whole book:** with nothing selected, the **Film** tab sets the look for every photo that follows the book. It also tells you how many photos have their own look, and **Match Book** brings them back.
- **LUTs:** **Choose LUT** lists 14 sRGB Fujifilm-style LUTs by abpy and imports your own 3D `.cube` or HaldCLUT `.png`. Imported LUTs are copied into the project.

Every look choice or slider drag is a single ⌘Z step.

## Printing

**Book & Print** sets the format, bleed, safe margin, target resolution, PDF type, the side of the first page and the cover with spine width.

- **Export for Print** writes `Interior.pdf` and, if enabled, `Cover.pdf`. It flags photos below the target resolution and the filler pages that panoramas need.
- **Export PDF** offers **Viewing PDF**, **Generic Print** and **Pixartprinting · 21 × 21 cm**. The Pixartprinting profile writes one 1:1 PDF: a flat hardcover with the spine width from your quote, then single 216 × 216 mm pages with 3 mm bleed. PDFs are sRGB.

Always use the exact dimensions and color requirements of the product you order.

## Help and about

**Help › Paper & Grain Help** (⌘?) opens a short guide in the interface language. **Paper & Grain › About Paper & Grain** shows the author, Marco Magnocavallo ([marco@magno.me](mailto:marco@magno.me)), the license and the source repository.

## Command line

The app binary includes a CLI. It can build a book from a JSON spec, list and search photos, apply patches, create variants, import LUTs and export PDFs:

```sh
swift run PaperAndGrain cli build trip.json Trip.papergrain
"Paper & Grain Redesign.app/Contents/MacOS/PaperAndGrain" cli export-pdf Trip.papergrain --profile print --output Trip.pdf
```

See the [CLI guide](docs/cli.md) for every command and the JSON formats.

## Privacy and project files

- **Photos:** selected photos are copied into the book. Photos may download originals from iCloud when they are needed.
- **Analysis:** Vision runs on the Mac on copies of up to 640 pixels. Labels and themes are stored in the project.
- **Drafts and packages:** a new book starts as a draft in your user's Application Support folder. A saved `.papergrain` package holds the images, the analysis and the document; share it only as you would share the original album.
- **This repository:** it contains only synthetic or authorised test images. Keep personal albums, local projects and private text out of Git.

## Documentation

The developer documentation is written in Italian:

- [AGENTS.md](AGENTS.md): instructions for people and coding agents working on the code. Entry points, how to work in increments and how to verify changes.
- [Architecture and document format](docs/architecture.md)
- [Testing log and feature status](docs/status.md)
- [Templates](docs/templates.md)
- [CLI](docs/cli.md), [editing commands](docs/cli-editing.md) and [media commands](docs/cli-media.md)

## Licensing

The Fujifilm-style LUTs in `Resources/FujifilmFilmLooks` come from [FujifilmCameraProfiles by abpy](https://github.com/abpy/FujifilmCameraProfiles). They are licensed under [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/), which forbids commercial use; see [CREDITS](Resources/FujifilmFilmLooks/CREDITS.md). The fonts are the ones that ship with macOS. Check their embedding license before you sell printed books.

The source code is released under the [MIT License](LICENSE). The LUTs are not covered by the MIT License and keep their own license.
