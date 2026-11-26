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
- **What the export writes.** One PDF of single pages: front cover, content, back cover, each at the trim size with no bleed and no marks (Peecho adds them). The inside covers are blank and not in the PDF. sRGB, 300 dpi, fonts embedded; the page also asks for transparency flattened, which this export does not do until the colour-output work (T12) is merged; the page recommends a PDF/X-4 (FOGRA 39) check, which this export does not certify.
- **Margins.** 10 mm on every side; on layflat content pages none on the inner (binding) edge.
- **What the author enters.** Nothing: Peecho works the spine out from the page count, the paper and the destination, and prints it only for a merchant account, so no spine is drawn.
- **Differences from the PRD's Appendix A.** Layflat content pages need no margin on the inner (binding) edge (Appendix A says 10 mm on every side); the page's orientation labels (for example "A5 Landscape 148 × 210") do not agree with the dimensions, so the entry uses the dimensions as written. The numbers of the three products otherwise agree.
- Sources: [hardcover](https://support.peecho.com/hc/en-us/articles/19730953142428), [layflat](https://support.peecho.com/hc/en-us/articles/19732208244252), [softcover](https://support.peecho.com/hc/en-us/articles/19731377793564) (help articles updated 9 September, 24 November and 22 October 2026).

### WhiteWall · Coffee Table Book, hardcover

File `whitewall.json`; one entry, six sizes (cm): Portfolio A3 portrait 27 × 35.6 and landscape 38.2 × 29, Gallery square 29 × 29, Exhibition A4 portrait 20.5 × 27 and landscape 27 × 20.5, Story square 20.5 × 20.5. Six papers: three inkjet (up to 200 pages) and three Fuji Crystal Archive photo papers (up to 112).

- **Pages.** 28 to 200 in steps of 4, covers not counted.
- **What the export writes.** Two files in a folder: `Interior.pdf`, single pages with bleed on the top, bottom and outer edge and none on the binding edge, and `Cover.pdf`, one flat spread (back, spine, front with the fold, wrap and bleed). sRGB, 300 ppi target, fonts embedded, no marks.
- **Margins.** 5 mm inside the page and cover edges; text at least 2 mm from the spine edges, 11 pt or larger recommended.
- **Quote-typed.** WhiteWall shows the exact page and cover sizes, the bleed, the spine and the fold only after the book is configured on its site (Create now › PDF upload) or in its InDesign template, so the author types them in the export sheet: the page sizes (the entry accepts 8 mm either way of the nominal size and proposes the nominal one; the 8 mm tolerance is ours, WhiteWall states none), the interior bleed, the cover board, the fold (10 to 12 mm from the spine onto the front and back, the one range the page states), the wrap, the cover bleed and the spine. They map as follows: the cover board of each face includes the fold (`hingeWithinPanel`), so the hinge lies inside the board next to the spine; the wrap is the material beyond the board, and the bleed beyond the wrap.
- **Limits.** The cover file is at most 250 MB. The content file is 1 GB on two WhiteWall pages and 1.5 GB on the upload page: keep it under 1 GB.
- **Differences from Appendix A.** None in the numbers; the pages say the safety area is 5 mm and the spine margin 2 mm, as Appendix A does. The article "Setting the correct dimensions" confirms bleed on three edges only.
- Sources: [PDF upload](https://www.whitewall.com/eu/coffee-table-book/pdf-upload), [file requirements](https://service.whitewall.com/hc/en-us/articles/4411222658321), [dimensions](https://service.whitewall.com/hc/en-us/articles/4411250911377), [design notes](https://service.whitewall.com/hc/en-us/articles/4411236486929), [formats and papers](https://www.whitewall.com/eu/coffee-table-book).

### Lulu · hardcover casewrap, paperback

File `lulu.json`; two entries, seven trims each: Small Square 7.5 × 7.5 in, Square 8.5 × 8.5 in, Small Landscape 9 × 7 in, US Letter 8.5 × 11 in and its landscape, A4 210 × 297 mm and its landscape (the trims useful for photo books, from the guide's table of 20; inch sizes are kept exactly, so 7.5 in is 190.5 mm).

- **Pages.** Hardcover 24 to 800, paperback 32 to 800, an even number, covers not counted. (Hardcover's 800 is the end of Lulu's spine table; paperback's from the products page.)
- **What the export writes.** Two files in a folder: `Interior.pdf`, single pages at trim plus 0.125 in (3.175 mm) bleed on every side, and `Cover.pdf`, one flat spread (back, spine, front) with the same bleed. sRGB (Lulu's printers use sRGB IEC61966-2.1); a CMYK file stays CMYK at Lulu, which names Coated GRACoL 2006 (the entry's ICC profile; sRGB needs none) and a total ink of at most 270 %. 300 to 600 ppi, fonts embedded, no marks, no password. Lulu asks for transparency flattened; this export does not do that until the colour-output work (T12) is merged.
- **Margins.** Text 0.5 in (12.7 mm) inside the trim (0.75 in on hardcover covers). The gutter should grow with the page count (the guide's table is in the entry's notes); the entry checks 12.7 mm.
- **Spine.** Paperback: pages ÷ 17.48 + 1.524 mm. Hardcover: Lulu's table of 27 steps from 24 to 800 pages (6 mm up to 84 pages, 13 mm to 140, 16 mm to 168, and so on to 54 mm at 800), taken whole. No spine text at 80 pages or fewer.
- **Quote-typed.** The hardcover casewrap's board size, fold (about 6 mm from the spine) and wrap come from the cover template Lulu generates after the interior is uploaded; the author types them. Casewrap covers are bound 0.75 in from each edge and have overhang of 0.125 to 0.25 in on three sides.
- **Differences from Appendix A.** Lulu's guide is newer than the PRD's reading: the safety margin on both the interior and the cover is 0.5 in; the help page asks for 0.25 in minimum and 0.75 in on casewrap covers, so the hardcover entry uses 0.75 in for its cover. The guide's gutter text says "0.2 in/2.08 mm" (0.2 in is 5.08 mm): not used. The hardcover spine table runs to 800 pages (Appendix A stops at 250). The bleed applies to every edge, the binding edge included.
- **Not confirmed.** Which of the seven trims Lulu offers for hardcover casewrap: the guide lists trims for all bindings, and the products page does not list casewrap sizes. Check Lulu's pricing calculator before ordering; see `docs/status.md`.
- Sources: [Book Creation Guide](https://assets.lulu.com/media/guides/en/lulu-book-creation-guide.pdf), [PDF settings](https://help.lulu.com/en/support/solutions/articles/64000255519), [casewrap cover](https://help.lulu.com/en/support/solutions/articles/64000308572-creating-your-hardcover-casewrap-cover), [products](https://www.lulu.com/products).

### Mixam · hardcover book (casebound)

File `mixam.json`; one entry, 24 sizes: the 11 book sizes of the hardcover page's table (Digest 5.5 × 8.5 in, US Trade 6 × 9, Letter 8.5 × 11, 7.25 × 9.5, 7 × 9, Pocket Book, Royal, Executive, Crown Quarto, A5, A4) in portrait and landscape, and the 8.5 in and 7.5 in squares. Inch values are kept exactly as Mixam writes them.

- **What the export writes.** Two files in a folder: `Interior.pdf`, single pages with 0.125 in (3.175 mm) bleed on all four sides, and `Cover.pdf`, one flat spread (back, 0.2 in hinge, spine, 0.2 in hinge, front) with 0.8 in (20.32 mm) of bleed on all four edges, which Mixam wraps around the boards. Mixam's worked example (a 5.5 × 8.5 in digest with a 0.35 in spine: 11.75 × 8.5 in, 13.35 × 10.1 in with bleed) is a test.
- **Margins.** Interior: 0.25 in from the outer edges, 0.5 in from the binding. Cover: 0.25 in from the outer edges; 0.6 in from the spine edge (the structure has one safe distance for a cover, so the 0.6 in is in the notes).
- **Pages.** Mixam counts two pages for the cover in the total you enter in its calculator; hardcovers have free endpapers and no inside covers; the first printed page is page 3, on the right. Page limits are shown by the calculator per order, so the entry sets none.
- **Quote-typed.** The spine, from your Mixam cart or the order's Artwork tab (it depends on the page count and the paper).
- **Color.** Mixam prefers CMYK (GRACoL2006_Coated1v2) and converts RGB files itself; this export is sRGB.
- **Differences from Appendix A.** The cover bleed (0.8 in on all four edges), the hinge and the interior bleed agree. The interior binding margin is 0.5 in on the hardcover binding page, and 0.6 in applies to the cover spread, from the spine edge (Appendix A gave 0.6 in for the interior). The binding-types page gives 0.4 in for the cover's binding edge and the file-setup page 0.6 in: the stricter is used. The UK site's millimetre values were not read (the UK pages could not be fetched as text), so none is used.
- **Not added.** Mixam layflat: its binding page gives the margins (bleed 0.125 in, no quiet area at the binding, cover bleed 0.8 in) but the sizes and page limits are not on any page that could be read.
- Sources: [hardcover setup](https://mixam.com/support/hardcoversetup), [print file setup](https://mixam.com/support/filesetup), [binding types](https://mixam.com/support/binding), [page counts](https://mixam.com/support/pagecount), [CMYK vs RGB](https://mixam.com/support/cmykvsrgb).

## Not added yet

### Saal Digital

Not in the catalog. Saal publishes the numbers that a cover and spread need (spread size, cover size, spine and fold-over by page count, for each size and cover type) as tables in pixels at 300 dpi on its Professional Zone page, but the tables are filled in by a script after the page loads: the page's own text, fetched as HTML, holds none of them, and neither the product pages nor the InDesign and Photoshop guides give them. Without the tables the product cannot be described without guessing, so it is left out. What the pages do state, for when the tables are available:

- Each double page is one page of the PDF; the first page of the first spread and the last page of the last spread are the inside covers, which are printed (leave them empty for a white inside cover). The stated page count does not include the cover.
- sRGB (IEC 61966-2.1), fonts embedded, no marks. Bleed and the joint apply to each page, so double them for a spread.
- The 21 × 28 cm product page gives the closed size as 21.5 × 27.5 cm and 26 to 160 pages in steps of two.
- The standard option prints a small barcode on the back cover and the last page.

To add it: download the template PDFs of the sizes wanted from the Professional Zone, or read the tables in a browser, and give the numbers (the engine already has spreads, inside covers, a fold-over inside the board and tables by page count).

### Mixam layflat

Not in the catalog. The binding page gives the margins (bleed 0.125 in, no quiet area at the binding, 0.25 in elsewhere, cover bleed 0.8 in), but no page states the layflat sizes or page limits, and the spine is per order. Add it with the sizes from Mixam's calculator.

### Pixartprinting, other sizes

Waiting for the printer's cover templates for each size (and the instructions PDF of the user's own quote, which settles whether the interior wants CMYK). The 21 × 21 cm entry is the only one whose cover geometry is known; the other sizes are not scaled from it.

### Blurb

Waits for output color profiles (T12): Blurb asks for CMYK.

## Services that cannot be supported

These services take their books only through their own software or website, or take pages as pictures, so a PDF from Paper & Grain cannot be uploaded: Photobox, Albelli, Shutterfly, Mixbook, Artifact Uprising, PhotoSì (JPG pages only), MILK Books (consumer), CEWE outside the UK (its own software; in the UK through its template software), and Printique for covers (inside pages only). Authors ask about them: the answer is to use the printer's own designer, or to order from one of the services in the catalog.

Services that accept a PDF but are not in the catalog yet: Bookvault, Flyeralarm, Onlineprinters, Mimeo Photos, PrestoPhoto, ilFotoalbum, Amazon KDP and IngramSpark (trade books: a 75-page minimum for hardcover, barcodes).
