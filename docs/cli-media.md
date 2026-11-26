# Photos, development and export from the CLI

The commands use the same import, color development and export engine as the app. Argument paths are absolute or relative to the current directory. Editing commands create a new `.papergrain` package, and the source project stays available for other variants. Destinations need an existing parent folder and a free name.

## Apple Photos

Run the commands that access Photos with the binary inside the signed Paper & Grain bundle, for example `"/Applications/Paper & Grain.app/Contents/MacOS/PaperAndGrain" cli albums`. Use `--request-access` to ask the system for the initial permission. With limited access, the results include only the albums and photos visible to Paper & Grain.

- `albums [--request-access]` returns the accessible albums with ID, title and number of images.
- `album-assets ALBUM_ID [--request-access]` returns the IDs of the images in the album, their dimensions and the ISO 8601 capture date when available.
- `album-preview ALBUM_ID --asset ID --output FILE.png [--request-access]` saves a preview of the chosen image, if it is available locally. It returns the path and the dimensions.

## Import

`import-photos SOURCE.papergrain --spec IMPORT.json --output OUTPUT.papergrain [--request-access]` adds images to the project library, so that the new UUIDs can be used in layout operations. It returns the project path, its ID and the new library entries in import order. If a photo is missing or fails, the command stops the import and does not publish the package; the error names the file.

The spec holds `version: 1` and one or both of the selections below. Local files are relative to the spec and come before the Photos selection. macOS may download originals from iCloud. Choose the IDs after looking at the album. To import a whole album, list every ID you want explicitly.

The spec accepts only `version`, `files` and `photos`, and `photos` only `albumID` and `assetIDs`. An unknown key stops the command with an error that names it together with the valid keys.

```json
{
  "version": 1,
  "files": ["./photos/departure.jpg", "./photos/return.heic"],
  "photos": {
    "albumID": "<album ID>",
    "assetIDs": ["<first photo ID>", "<second photo ID>"]
  }
}
```

## Development and previews

- `photo-preview SOURCE.papergrain --photo UUID --output FILE.png [--max-pixels N] [--original]` exports a PNG of the photo with its actual adjustments and look. The long side is limited to 1600 pixels by default and accepts values from 1 to 8192. Use `--original` to see the photo without adjustments and look. The result includes the path and the actual dimensions.
- `auto-enhance SOURCE.papergrain --photo UUID --output OUTPUT.papergrain` applies the app's automatic adjustment to the given photo. It returns the path, the project ID and the updated photo data.
- `film-looks` lists the presets and the bundled LUTs (field `builtIn`: `id`, English name and the expected starting development, `linear` or `slide`).
- `import-lut SOURCE.papergrain (--file PATH | --builtin LOOK_ID) [--photo UUID] --output OUTPUT.papergrain` installs and applies a 3D `.cube` LUT, a Hald CLUT `.png` or a LUT bundled with the app (`LOOK_ID` from `film-looks`, for example `natural-slide`). Without `--photo`, it applies the LUT to the book. It returns the path, the project ID and the name of the new LUT file in the package.

## PDF

`export-pdf SOURCE.papergrain --profile proof|print|pixart|PROFILE_ID --output PATH [--size SIZE_ID] [--paper PAPER_ID] [--spine-mm MM] [--hinge-mm MM] [--wrap-mm MM] [--panel-width-mm MM] [--panel-height-mm MM] [--cover-bleed-mm MM] [--interior-bleed-mm MM] [--color srgb|cmyk] [--icc PATH|ID]` returns the path, the profile as given, the product size (`size`, for a print service) and the print warnings found, in English (for example `p. 3 · Missing photo` or `Needs at least 24 pages (has 18)`). The profiles share the project settings and resources.

- `--color` and `--icc` replace the book's color output for one print export (`print` or a print service); the viewing PDF is always sRGB. `--color srgb` writes sRGB. `--color cmyk` (or `--icc` alone) writes CMYK with the profile `--icc` names: a file path, `eci:PSOcoated_v3` (the copy downloaded in the app), a bundled profile id (`bundled:GRACoL2006_Coated1v2.icc` or `bundled:Coated_Fogra39L_VIGC_300.icc`), or the name or file name of a CMYK output profile installed on the Mac; without `--icc` it uses the book's CMYK profile. The result's `color` gives the color written: `sRGB IEC61966-2.1` or the CMYK profile's name (its ICC description). A print service that takes only the other color mode (Blurb CMYK only; Peecho and Saal Digital sRGB only) is refused before anything is written, with the option that fixes it; the warnings read the color of this export, `--color` included.
- `proof` saves the interior as a single `.pdf` for viewing.
- `print` saves `Interior.pdf` and, if the book has a cover, `Cover.pdf` in a new folder.
- `PROFILE_ID` is an `id` from `print-profiles`: a printer's product. It saves what the product asks for: one `.pdf` (`files.arrangement` `single`), or a new folder with the interior and cover files under the names the printer expects (`separate`). The book must have one of the product's trims; `--size` chooses among them, otherwise the size whose trim matches the book, or the one in `printSettings.profileSizeID` when the book chose this profile. `--paper` chooses the paper for spine tables. A spine given in the printer's quote comes from `--spine-mm`, `printSettings.profileMeasures.spineMM` or `cover.spineMM`, in that order; a spine from a formula or table is computed from the interior page count and `--spine-mm` replaces it. `--hinge-mm`, `--wrap-mm`, `--panel-width-mm`, `--panel-height-mm`, `--cover-bleed-mm` and `--interior-bleed-mm` do the same for the other measures, and give the ones a printer states only per order; without them the command reads `printSettings.profileMeasures`. Blanks are added at the end so the count the printer takes reaches the product's step, and glued endpapers are printed blank.
- `pixart` is the catalog entry `pixartprinting-photobook-hardcover`: a single `.pdf` with the flat hardcover before single 216 × 216 mm interior pages, for a 210 × 210 mm book, with a spine greater than 0 and at most 100 mm.

`print-profiles` lists the catalog as JSON: `profiles`, each with `id`, `service`, `product` (English and Italian), `binding`, `regions`, `sourceURL`, `verifiedOn`, `interior` (layout, bleed and safe margin per edge, first page side, page rules), `cover`, `files`, `color` and `sizes`. Lengths are millimetres; a length written as `{"mm": …, "source": …}` keeps the printer's own value and unit.

Before it creates any file, the command refuses with a specific error a book with no pages, a format with a side of 17.6 mm or less, a page too small for its margins, a book whose size the product does not offer (naming both sizes), an unknown size or paper, and a missing spine width. `import-lut` reports a file that is not a `.cube` or a `.png`, or whose size is not between 1 byte and 50 MB.
