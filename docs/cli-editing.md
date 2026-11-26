# Editing a project from the terminal

The command works on a copy of the package and publishes the variant only after reading it back. Every variant has a new book UUID. The copy holds the original images, the LUTs and the other project files. The destination path must be new, with the `.papergrain` extension, in an existing folder outside the source project.

```sh
PaperAndGrain cli inspect original.papergrain > manifest.json
PaperAndGrain cli patch original.papergrain changes.json variant.papergrain
PaperAndGrain cli inspect variant.papergrain
```

## Patch format

The file holds an array of JSON Patch operations, run in the given order. JSON Pointer paths start with `/` and identify a field or an element of the native manifest. Array indices start at zero. `~1` stands for a slash in a field name and `~0` for a tilde. The document root is reserved.

| Operation | Fields | Effect |
| --- | --- | --- |
| `test` | `path`, `value` | Requires the value to match. A failed test cancels the whole patch. |
| `add` | `path`, `value` | Sets a field or inserts an element into the array. The `/-` suffix appends. |
| `replace` | `path`, `value` | Replaces an existing value. |
| `remove` | `path` | Deletes an optional field or an element. |
| `move` | `from`, `path` | Removes a value and inserts it at the destination, evaluated after the removal. |
| `copy` | `from`, `path` | Copies the value to the destination. Every copied object with an `id` field (a page, a text box and those it contains) gets a new UUID; references to those IDs inside the copy, such as `box:<UUID>` in `layerOrder`, follow it. Photo references stay unchanged. |

This patch requires a first page whose text is "Departure", changes the story, sets the body style and moves the page to the end.

```json
[
  {"op":"test","path":"/pages/0/text","value":"Departure"},
  {"op":"replace","path":"/pages/0/text","value":"We left before dawn."},
  {"op":"add","path":"/pages/0/typography","value":{"body":{"pointSize":15,"alignment":"left"}}},
  {"op":"move","from":"/pages/0","path":"/pages/-"}
]
```

## Page rules and result

`patch` and `build` share the page rules. These are errors: a `layout` different from the one `arrangement` requires (for example `gallery` for `twoAcross`), a photo repeated on the same page, and a patch that leaves the book without pages. As in the app, photos beyond the capacity of the page template and text on a layout that does not show it (`gallery`, `fullPage`, `fullSpread`) stay stored but do not appear: `build` rejects them, `patch` accepts them and reports them.

On success `patch` returns `project`, `id` and `warnings`, an array of English messages about the pages that the patch added or changed only, for example `Page 1 (pages[0]) has 3 photos; arrangement "twoAcross" shows 2. The others stay stored but are not shown`.

Before positional changes, use `test` on `/pages/0/id` or `/photos/0/id` with the matching UUID from `inspect`. Run `inspect` again on the variant before you generate the next patch.

## Model paths

- `/pages` sets the page order. To insert a page, give at least `id` (a new UUID), `layout`, `photoIDs` and `text`. To change the layout you can change `layout` and `arrangement` together. `photoIDs` holds UUIDs from the book library in slot order.
- `/pages/0/photoPlacements` follows the native Swift representation of maps with UUID keys. It is an alternating array `["UUID", {"frame": {...}, "crop": {...}, "captionPosition": "below"}, ...]`. Use `inspect` to read the order and `test` on the key before you change the entry that follows it. Every key must also appear in `photoIDs`. `crop` holds `x` and `y` between 0 and 1 and `zoom` between 1 and 12. `captionPosition` is `below`, `above`, `inside` (a band on the photo) or `hidden`; remove it for automatic placement.
- `/photos/0/caption` is the photo's caption, printed on every page where the photo appears. Remove it, or set an empty string, for no caption.
- Frames have `x`, `y`, `width` and `height` as fractions of the page, with the origin at the top left. The same coordinates apply to `titleFrame`, `storyFrame`, `storyBackdropFrames`, the `textBoxes` and the two cover frames. Each text box has `id`, `text` and `frame`, with an optional local type style.
- `/typography`, `/pages/0/typography` and `/cover/typography` accept `title` and `body`. `/typography/caption` is the book's caption style; pages and the cover have none, and the patch refuses one there. Each style can set `fontName`, `pointSize`, `alignment` (`left`, `center`, `right`, `justified`), `color` and `lineSpacing` (a multiple of the line height, from 0.8 to 2).
- A text box in `/pages/0/textBoxes` has `id`, `text`, `frame` and the optional fields `typography` (one style), `usesFullWidth` (text with no inner margin), `backgroundColor`, `hidesBackground` (transparent box), `borderColor` and `borderWidth` in points from 0 to 12.
- Colors are `0xRRGGBB` integers written in decimal, from 0 to 16777215 (`0xFFFFFF`). Without a color, the template's ink and paper apply. The patch rejects colors, `borderWidth` and `lineSpacing` out of range.
- `/pages/0/layerOrder` lists the objects on the page from bottom to top as the strings `story`, `photo:<UUID>` and `box:<UUID>`. Entries that do not match an object on the page are ignored. Objects not listed keep their default position: photos below, boxes above.
- `/cover` holds `title`, `spineMM`, `frontPhotoID`, `backPhotoID`, `backText`, `typography`, `frontTitleFrame` and `backTextFrame`. Photo references must belong to the book.
- `/cover/frontPhotoPlacement` and `/cover/backPhotoPlacement` can set `frame` (normalized coordinates `x`, `y`, `width`, `height`) and `crop` (`x` and `y` from 0 to 1, `zoom` from 1 to 12). When the field is missing, the template's placement for that face is used.
- `/film` and `/photos/0/film` hold `preset`, `strength`, `grain`, `grainSize` and the optional `lutFilename` already present in `looks`. `/photos/0/adjustments` holds the development values. To change a single parameter that is already present, use for example `replace /photos/0/adjustments/exposure`.
- `/format` sets `widthMM` and `heightMM`. `/printSettings` holds `bleedMM`, `safeMM`, `targetPPI`, `spreads` and the optional `firstPageOnRight`. `/template` accepts the IDs from the `templates` catalog. `/showPageNumbers` accepts a boolean. Remove the field to restore the template's setting.

The `templates` catalog includes the starting values in `defaults.film`, `defaults.adjustments` and `defaults.printSettings`. You can copy the whole object and change the values you need. To create a missing optional object, use `add` on the whole object with the fields the model requires. To restore inheritance, use `remove` on the optional field. The patch checks fields and references before publishing. The import commands handle images and LUTs. Photo IDs, file names, original dimensions, capture dates, source Photos IDs and the schema version are reserved. On reading, `pixelWidth` and `pixelHeight` must be between 1 and 1,000,000.
