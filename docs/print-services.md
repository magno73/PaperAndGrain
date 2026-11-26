# Print services

The print-service catalog lives in `Resources/PrintProfiles`, one JSON file per service, described in [Architecture](architecture.md). This page lists every entry, what its export writes, what the author still has to enter, and the services that cannot be supported. Every entry names the page it was read from and the day it was checked; check the printer's current requirements before ordering. Paper & Grain is not affiliated with any of these services.

Checked on 26 November 2026, from the printers' own pages.

## Entries

### Pixartprinting · photo book, hardcover

21 × 21 cm only. One 1:1 PDF: a flat hardcover (back, spine, front, with the printer's 11 mm hinge and 19 mm wrap) then single pages with 3 mm bleed, starting on the right; the count includes the four cover sides. The spine is typed from the quote. sRGB written; the product page asks for CMYK (FOGRA 39), so check the instructions for your quote. [Source](https://www.pixartprinting.it/stampa-riviste-cataloghi-libri/copertina-rigida-nobilitata/).

### Peecho · hardcover, layflat, softcover

Three entries (`peecho-hardcover`, `peecho-layflat`, `peecho-softcover`), file `peecho.json`.

- **Sizes (mm).** Hardcover 148 × 210, 210 × 148, 210 × 297, 297 × 210, 216 × 280, 280 × 216, 210 × 210, 294 × 294. Layflat 297 × 210, 210 × 210, 294 × 294. Softcover 148 × 210, 210 × 148, 210 × 297, 297 × 210, 210 × 210. Choosing one sets the book's size to it.
- **Pages.** An even number, covers included: hardcover 24 to 500, layflat 18 to 122, softcover 20 to 300.
- **What the export writes.** One PDF of single pages: front cover, content, back cover, each at the trim size with no bleed and no marks (Peecho adds them). The inside covers are blank and not in the PDF. sRGB, 300 dpi, fonts embedded, transparency flattened; the page recommends a PDF/X-4 (FOGRA 39) check, which this export does not certify.
- **Margins.** 10 mm on every side; on layflat content pages none on the inner (binding) edge.
- **What the author enters.** Nothing: Peecho works the spine out from the page count, the paper and the destination, and prints it only for a merchant account, so no spine is drawn.
- **Differences from the PRD's Appendix A.** Layflat content pages need no margin on the inner (binding) edge (Appendix A says 10 mm on every side); the page's orientation labels (for example "A5 Landscape 148 × 210") do not agree with the dimensions, so the entry uses the dimensions as written. The numbers of the three products otherwise agree.
- Sources: [hardcover](https://support.peecho.com/hc/en-us/articles/19730953142428), [layflat](https://support.peecho.com/hc/en-us/articles/19732208244252), [softcover](https://support.peecho.com/hc/en-us/articles/19731377793564) (help articles updated 9 September, 24 November and 22 October 2026).

### WhiteWall · Coffee Table Book, hardcover

File `whitewall.json`; one entry, six sizes (cm): Portfolio A3 portrait 27 × 35.6 and landscape 38.2 × 29, Gallery square 29 × 29, Exhibition A4 portrait 20.5 × 27 and landscape 27 × 20.5, Story square 20.5 × 20.5. Six papers: three inkjet (up to 200 pages) and three Fuji Crystal Archive photo papers (up to 112).

- **Pages.** 28 to 200 in steps of 4, covers not counted.
- **What the export writes.** Two files in a folder: `Interior.pdf`, single pages with bleed on the top, bottom and outer edge and none on the binding edge, and `Cover.pdf`, one flat spread (back, spine, front with the fold, wrap and bleed). sRGB, 300 ppi target, fonts embedded, no marks.
- **Margins.** 5 mm inside the page and cover edges; text at least 2 mm from the spine edges, 11 pt or larger recommended.
- **Quote-typed.** WhiteWall shows the exact page and cover sizes, the bleed, the spine and the fold only after the book is configured on its site (Create now › PDF upload) or in its InDesign template, so the author types them in the export sheet: the page sizes (the entry accepts 8 mm either way of the nominal size and proposes the nominal one), the interior bleed, the cover board, the fold (10 to 12 mm from the spine onto the front and back, the one range the page states), the wrap, the cover bleed and the spine.
- **Limits.** The cover file is at most 250 MB. The content file is 1 GB on two WhiteWall pages and 1.5 GB on the upload page: keep it under 1 GB.
- **Differences from Appendix A.** None in the numbers; the pages say the safety area is 5 mm and the spine margin 2 mm, as Appendix A does. The article "Setting the correct dimensions" confirms bleed on three edges only.
- Sources: [PDF upload](https://www.whitewall.com/eu/coffee-table-book/pdf-upload), [file requirements](https://service.whitewall.com/hc/en-us/articles/4411222658321), [dimensions](https://service.whitewall.com/hc/en-us/articles/4411250911377), [design notes](https://service.whitewall.com/hc/en-us/articles/4411236486929), [formats and papers](https://www.whitewall.com/eu/coffee-table-book).

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
