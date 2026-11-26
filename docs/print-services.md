# Print services

The print-service catalog lives in `Resources/PrintProfiles`, one JSON file per service, described in [Architecture](architecture.md). This page lists every entry, what its export writes, what the author still has to enter, and the services that cannot be supported. Every entry names the page it was read from and the day it was checked; check the printer's current requirements before ordering. Paper & Grain is not affiliated with any of these services.

Checked on 26 November 2026, from the printers' own pages.

## Entries

(One section per entry, added with the entry.)

## Not added yet

### Saal Digital

Not in the catalog. Saal publishes the numbers that a cover and spread need (spread size, cover size, spine and fold-over by page count, for each size and cover type) as tables in pixels at 300 dpi on its Professional Zone page, but the tables are filled in by a script after the page loads: the page's own text, fetched as HTML, holds none of them, and neither the product pages nor the InDesign and Photoshop guides give them. Without the tables the product cannot be described without guessing, so it is left out. What the pages do state, for when the tables are available:

- Each double page is one page of the PDF; the first page of the first spread and the last page of the last spread are the inside covers, which are printed (leave them empty for a white inside cover). The stated page count does not include the cover.
- sRGB (IEC 61966-2.1), fonts embedded, no marks. Bleed and the joint apply to each page, so double them for a spread.
- The 21 × 28 cm product page gives the closed size as 21.5 × 27.5 cm and 26 to 160 pages in steps of two.
- The standard option prints a small barcode on the back cover and the last page.

To add it: download the template PDFs of the sizes wanted from the Professional Zone, or read the tables in a browser, and give the numbers (the engine already has spreads, inside covers, a fold-over inside the board and tables by page count).

### Pixartprinting, other sizes

Waiting for the printer's cover templates for each size (and the instructions PDF of the user's own quote, which settles whether the interior wants CMYK). The 21 × 21 cm entry is the only one whose cover geometry is known; the other sizes are not scaled from it.

### Blurb

Waits for output color profiles (T12): Blurb asks for CMYK.

## Services that cannot be supported

These services take their books only through their own software or website, or take pages as pictures, so a PDF from Paper & Grain cannot be uploaded: Photobox, Albelli, Shutterfly, Mixbook, Artifact Uprising, PhotoSì (JPG pages only), MILK Books (consumer), CEWE outside the UK (its own software; in the UK through its template software), and Printique for covers (inside pages only). Authors ask about them: the answer is to use the printer's own designer, or to order from one of the services in the catalog.

Services that accept a PDF but are not in the catalog yet: Bookvault, Flyeralarm, Onlineprinters, Mimeo Photos, PrestoPhoto, ilFotoalbum, Amazon KDP and IngramSpark (trade books: a 75-page minimum for hardcover, barcodes).
