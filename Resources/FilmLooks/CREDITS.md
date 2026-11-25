# Bundled film looks

The 14 sRGB CUBE LUTs in this folder come from [FujifilmCameraProfiles by abpy (Aaron)](https://github.com/abpy/FujifilmCameraProfiles), revision [b5a1f16](https://github.com/abpy/FujifilmCameraProfiles/tree/b5a1f16abfb2759b337c83d69d9dc49470e7e518), taken from the upstream `cube lut` and `provia conversion luts` directories.

They are licensed under [Creative Commons Attribution–NonCommercial–ShareAlike 4.0 International](https://creativecommons.org/licenses/by-nc-sa/4.0/); see the [upstream licensing notes](https://github.com/abpy/FujifilmCameraProfiles#licensing). The content of every file is unchanged. Paper & Grain renamed the files and gives the looks descriptive names, so the app does not use film or camera trademarks; this does not imply any endorsement by abpy or by any manufacturer.

| File in this folder | Name in the app | Upstream file |
|---|---|---|
| `natural-slide.cube` | Natural Slide | `cube lut/provia_sRGB.cube` |
| `vivid-slide.cube` | Vivid Slide | `cube lut/velvia_sRGB.cube` |
| `soft-slide.cube` | Soft Slide | `cube lut/astia_sRGB.cube` |
| `muted-chrome.cube` | Muted Chrome | `cube lut/classic chrome_sRGB.cube` |
| `street-negative.cube` | Street Negative | `cube lut/classic neg_sRGB.cube` |
| `portrait-standard.cube` | Portrait Standard | `cube lut/pro neg std_sRGB.cube` |
| `portrait-contrast.cube` | Portrait Contrast | `cube lut/pro neg hi_sRGB.cube` |
| `soft-cinema.cube` | Soft Cinema | `cube lut/eterna_sRGB.cube` |
| `bleach-bypass.cube` | Bleach Bypass | `cube lut/bleach bypass_sRGB.cube` |
| `vintage-negative.cube` | Vintage Negative | `cube lut/nostalgic neg_sRGB.cube` |
| `true-color.cube` | True Color | `cube lut/reala ace_sRGB.cube` |
| `slide-to-street-negative.cube` | Street Negative (from standard slide film) | `provia conversion luts/Provia to Classic Neg sRGB.cube` |
| `slide-to-bleach-bypass.cube` | Bleach Bypass (from standard slide film) | `provia conversion luts/Provia to Bleach Bypass sRGB.cube` |
| `slide-to-vintage-negative.cube` | Vintage Negative (from standard slide film) | `provia conversion luts/Provia to Nostalgic Neg sRGB.cube` |

The files in the first group expect a development with linear contrast. The last three expect an image already rendered with a standard slide-film look, such as an in-camera JPEG.
