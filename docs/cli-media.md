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

`export-pdf SOURCE.papergrain --profile proof|print|pixart --output PATH [--spine-mm MM]` returns the path, the profile and the print warnings found. The profiles share the project settings and resources.

- `proof` saves the interior as a single `.pdf` for viewing.
- `print` saves `Interior.pdf` and, if the book has a cover, `Cover.pdf` in a new folder.
- `pixart` saves a single `.pdf` with the cover before the interior pages, following the 21 × 21 cm hardcover profile, and needs a 210 × 210 mm book. It uses the spine width saved in the project, or `--spine-mm` with a value greater than 0 and at most 100.

Before it creates any file, the command refuses with a specific error a book with no pages, a format with a side of 17.6 mm or less, and a page too small for its margins. `import-lut` reports a file that is not a `.cube` or a `.png`, or whose size is not between 1 byte and 50 MB.
