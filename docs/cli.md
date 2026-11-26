# Building a photobook from the terminal

On macOS 14 or later, an agent can create a book, import and analyse images, change the layout, look at previews and export a PDF. The commands use the same editable package as the editor.

From the repository root:

```sh
swift run PaperAndGrain cli templates
swift run PaperAndGrain cli build trip.json Trip.papergrain
swift run PaperAndGrain cli inspect Trip.papergrain
swift run PaperAndGrain cli help
```

With the app installed you can call the binary directly, from any directory. A build from `scripts/build-app.sh` is in `~/Applications`; a downloaded release is usually in `/Applications`:

```sh
"/Applications/Paper & Grain.app/Contents/MacOS/PaperAndGrain" cli templates
```

## Workflow for agents

1. Use `templates` to read templates, layouts, capacities and the starting values of film, crop, adjustments and print. Use `build` with a JSON spec, or start from an existing project.
2. If the photos are in Apple Photos, use the binary inside the signed bundle. `albums` lists the albums, `album-assets` the images. `import-photos` adds an explicit selection to the project library. You can create a starting project with `assets: []` and `pages: [{"layout":"gallery"}]`. [Import and media commands](cli-media.md)
3. Use `analyze` to get the visual data, `rank` to find photos that relate to a passage of text, and `similar` to compare two scenes or find near-duplicates. `photo-preview` lets you look at the candidates.
4. Use `auto-layout SOURCE.papergrain OUTPUT.papergrain` to rebuild the pages from capture day and photo order. When the book already has a layout to keep, start from `inspect` and use `patch` to change the fields you want. [Editing and coordinates](cli-editing.md)
5. Use `auto-enhance`, `film-looks` and `import-lut` for color development. Use `export-pdf` with the `proof` or `print` profile, or a print-service id from `print-profiles` (`pixart` is the Pixartprinting 21 × 21 cm hardcover). [Development and export commands](cli-media.md)

Editing commands write to a new `.papergrain` destination. The UUIDs of existing images and pages identify the same items in the variants, unless an item is removed or the pages are rebuilt with `auto-layout`. The book ID changes.

## Photo catalog and search

```sh
PaperAndGrain cli analyze Trip.papergrain --output Trip-analysed.papergrain
PaperAndGrain cli photos Trip-analysed.papergrain --details --limit 10
PaperAndGrain cli rank Trip-analysed.papergrain "elephants at the Etosha waterhole" --unused --limit 8
PaperAndGrain cli similar Trip-analysed.papergrain UUID --by near-duplicate --limit 5
```

- `photos` returns UUID, local path, ISO 8601 date, dimensions, caption, pages, cover assignments, labels and themes. `--photo UUID` selects one image and returns its full data. `--details` returns the full data for the whole list. `--filter QUERY` searches the name and the analysis data.
- `analyze` processes on the Mac the images that have no recent analysis. It accepts `--photo UUID` several times and `--force` to repeat the analysis. The result holds the outcome, the data and any error per photo. To store the results in the project, use `--output`: the destination is checked before the analysis starts. With the report alone, you can keep the data in the process that ran the command.
- `rank` returns only candidates with a match and includes `evidence` with the recognized term, its source (`subject`, `text` or `concept`) and its contribution to the score. The score orders the candidates. `--unused` excludes photos assigned to pages or the cover. The same filter works for `photos` and `similar`.
- `similar --by subjects` compares labels weighted by confidence. `--by near-duplicate` orders by the distance between visual fingerprints. The results show both values when available. Use the previews to judge close shots.

Revision 2 of the analysis includes up to 48 classifications with confidence, detected people, faces and animals, recognized text with confidence and bounding box, sRGB palette, orientation, brightness, contrast, detail and a visual fingerprint. Vision bounding boxes are normalized and start from the bottom left. `unavailableSignals` tells an unavailable module apart from an empty detection. Brightness, contrast and detail are measured on the reduced sample. Detail approximates local variation and is also affected by grain. Candidates and detections are estimates. Face detection records presence and position.

The Apple Vision animal detector locates dogs and cats. For wildlife, `rank` uses the labels of the whole-image classifier and the related themes. [Apple Vision · VNAnimalIdentifier](https://developer.apple.com/documentation/vision/vnanimalidentifier)

## Spec version 1

```json
{
  "version": 1,
  "title": "Travel Notebook",
  "format": { "widthMM": 210, "heightMM": 210 },
  "template": "atlas",
  "typography": { "body": { "fontName": "Georgia", "pointSize": 11, "lineSpacing": 1.3 } },
  "assets": [{ "id": "horizon", "path": "photos/horizon.jpg", "caption": "Etosha, 12 May 2024" }],
  "pages": [
    { "arrangement": "textBesidePhoto", "photos": ["horizon"], "heading": "Departure", "text": "We cross the plain in the morning.",
      "typography": { "title": { "color": 9109504, "alignment": "left" } },
      "photoPlacements": { "horizon": { "captionPosition": "inside" } } },
    { "layout": "fullSpread", "photos": ["horizon"],
      "textBoxes": [{ "id": "6F1C2A4E-1B7D-4C55-9F0A-3C2E8D1B5A77", "text": "Etosha, 6 am",
                      "frame": { "x": 0.06, "y": 0.82, "width": 0.3, "height": 0.1 },
                      "backgroundColor": 16777215, "borderColor": 0, "borderWidth": 1 }],
      "layerOrder": ["photo:horizon", "story", "box:6F1C2A4E-1B7D-4C55-9F0A-3C2E8D1B5A77"] }
  ],
  "cover": { "frontPhoto": "horizon", "title": "Travel Notebook", "backText": "Field notes", "spineMM": 4,
             "typography": { "title": { "color": 16777215 } } }
}
```

- `version`, a non-empty `title`, `assets` (possibly empty) and at least one entry in `pages` are required. The default size is 210 × 210 mm. Without `template`, the app's classic style is used. `ignoredSpellings` is an optional list of words the app's spelling check leaves alone in this book (`Book.ignoredSpellings`, also set with `patch`). `showPageNumbers` is an optional boolean that turns the numbering on the interior pages with margins on or off. When it is missing, the template's setting applies.
- Each asset has a unique ID and a file path, absolute or relative to the spec. `caption` is optional: the text printed with the photo on every page where it appears. A symbolic link is resolved. The command copies the originals into the package. The spec IDs are valid during the build. The app assigns UUIDs to the imported photos.
- The order of `pages` is the book order. The order of `photos` assigns the slots on the page. A photo can appear on several pages and on the cover. Each page accepts only one occurrence of the same ID.
- `templates` lists the book template IDs, page types and page templates with their capacity and matching layout. A page with neither `layout` nor `arrangement` uses `gallery`. The arrangement determines the layout. `mixed` and `text` can include `heading` and `text`. `fullSpread` places one photo across two pages. It can also be given as `arrangement` to select it as the page template.
- The cover is optional. It accepts `title`, `frontPhoto`, `backPhoto`, `backText`, a spine width `spineMM` in millimeters and `typography` for the title on the front and the text on the back.
- `printService` is optional and chooses a printer's product, as **Book & Print › Print service** does: `profile` (an `id` from `print-profiles`, or `pixart`), `size` (a size `id`; it can be left out when the product has one size or when `format` matches one) and `paper`. It records `printSettings.profileID`, `profileSizeID` and `profilePaperID`, and takes bleed and safe margin from the product. Without `format` the book takes the size's trim; a `format` that differs from it is an error. With `patch`, the same fields are `/printSettings/profileID`, `/printSettings/profileSizeID`, `/printSettings/profilePaperID` and `/printSettings/colorOutput` (`{"mode": "srgb"}` or `{"mode": "cmyk", "profile": {…}}` with the `id`, `name`, `filename` and `sha256` of a profile already in the package's `profiles/` folder; the app's **Book & Print › Color** writes it) and `/printSettings/profileMeasures` (`spineMM`, `hingeMM`, `wrapMM`, `panelWidthMM`, `panelHeightMM`, `coverBleedMM`, `interiorBleedMM`: typed over the product's values, or given per order); an id that is not in the catalog is refused.
- `typography` applies to the book (the root of the spec), to a page and to the cover, with the same fields as the manifest: `title` and `body`, each with `fontName`, `pointSize`, `alignment` (`left`, `center`, `right`, `justified`), `color` and `lineSpacing` (a multiple of the line height, from 0.8 to 2). A page style inherits the missing fields from the book style.
- `textBoxes` adds text boxes to the page with the manifest fields: a required `frame` (`x`, `y`, `width`, `height` as fractions of the page, origin at the top left, width and height greater than 0), `text`, `typography` (one style with the fields above), `usesFullWidth` (the text fills the box with no inner margin), `backgroundColor`, `hidesBackground` (transparent box), `borderColor` and `borderWidth` in points from 0 to 12. `id` is optional: a UUID chosen by the agent, useful for `layerOrder`; when it is missing, the command assigns a new one.
- Colors are `0xRRGGBB` integers written in decimal in the JSON, from 0 (black) to 16777215 (`0xFFFFFF`, white); for example `0x8B0000` is `9109504`. Without a color, the template's ink and paper apply.
- `photoPlacements` maps an asset ID placed on the page to the manifest's placement: `captionPosition` (`below`, `above`, `inside` for a band on the photo, `hidden`; without it the caption is placed automatically), and optionally `frame` (fractions of the page) and `crop` (`x`, `y` from 0 to 1, `zoom` from 1 to 12). An asset not on the page is an error.
- The caption style is one per book: `typography.caption` at the root of the spec, with the same fields as `title` and `body`. Pages and the cover do not accept `caption` in their `typography`.
- `layerOrder` lists the objects on the page from bottom to top: `story` (heading, story and background together), `photo:<asset ID>` for a photo on the same page and `box:<UUID>` for a box on the same page. In the manifest, photos become `photo:<UUID>`. An entry that does not match an object on the page is an error in `build`. Objects not listed keep their default position: photos below, boxes above.
- Each object accepts only the keys listed. An unknown or misspelled key stops the command with an error that names the key, the object (for example `pages[0]`) and the valid keys.

## Command contract

`build` needs an existing parent folder and a new path with the `.papergrain` extension. It prepares everything in a temporary sibling folder and publishes the result with an exclusive rename. An import error or an occupied destination leaves existing projects untouched. To regenerate a variant, choose a new name.

On success the process exits with code 0 and writes one JSON document to stdout. `build` returns `project` (absolute path), `id` and `photos`, a map from the spec asset ID to the photo UUID in the book, for use in later patches. `patch` returns `project`, `id` and `warnings`. `templates` returns in `templates` one object per template with `id` (the value to use in `template`), `name` with `it` and `en`, and `family` (`classic`, `studio` or `photobook`), plus `layouts`, `arrangements` and `defaults`. `inspect` validates and returns the original manifest, keeping the exact indices that `patch` needs. Command errors exit with code 1 and write to stderr a JSON object with an `error` field. The message is in English and names the failed check, for example `Page 2 (pages[1]) references unknown photo <UUID> in photoIDs`, `format.widthMM must be greater than 0` or `Output parent directory does not exist: <path>`. The app shows the same messages when a package is damaged. Partial analysis outcomes appear in the report. To keep SwiftPM build messages apart from the CLI output, call the already built binary.
