# Print services

The print-service catalog lives in `Resources/PrintProfiles`, one JSON file per service, described in [Architecture](architecture.md). This page lists every entry, what its export writes, what the author still has to enter, and the services that cannot be supported. Every entry names the page it was read from and the day it was checked; check the printer's current requirements before ordering. Paper & Grain is not affiliated with any of these services.

Checked on 26 November 2026, from the printers' own pages.

## Entries

### Pixartprinting · photo book, hardcover

21 × 21 cm only. One 1:1 PDF: a flat hardcover (back, spine, front, with the printer's 11 mm hinge and 19 mm wrap) then single pages with 3 mm bleed, starting on the right; the count includes the four cover sides. The spine is typed from the quote. The product page asks for CMYK (FOGRA 39): with CMYK in **Book & Print › Color** the app proposes the bundled FOGRA39 profile; check the instructions for your quote. [Source](https://www.pixartprinting.it/stampa-riviste-cataloghi-libri/copertina-rigida-nobilitata/).

### Peecho · hardcover, layflat, softcover

Three entries (`peecho-hardcover`, `peecho-layflat`, `peecho-softcover`), file `peecho.json`.

- **Sizes (mm).** Hardcover 148 × 210, 210 × 148, 210 × 297, 297 × 210, 216 × 280, 280 × 216, 210 × 210, 294 × 294. Layflat 297 × 210, 210 × 210, 294 × 294. Softcover 148 × 210, 210 × 148, 210 × 297, 297 × 210, 210 × 210. Choosing one sets the book's size to it.
- **Pages.** An even number, covers included: hardcover 24 to 500, layflat 18 to 122, softcover 20 to 300.
- **What the export writes.** One PDF of single pages: front cover, content, back cover, each at the trim size with no bleed and no marks (Peecho adds them). The inside covers are blank and not in the PDF. sRGB, 300 dpi, fonts embedded; transparency is flattened, as the page asks; the page recommends a PDF/X-4 (FOGRA 39) check, which the export does not certify. A CMYK book is blocked for Peecho, which takes sRGB only.
- **Margins.** 10 mm on every side; on layflat content pages none on the inner (binding) edge.
- **What the author enters.** Nothing: Peecho works the spine out from the page count, the paper and the destination, and prints it only for a merchant account, so no spine is drawn.
- **Differences from the planning research of 26 November 2026.** Layflat content pages need no margin on the inner (binding) edge (the planning research said 10 mm on every side); the page's orientation labels (for example "A5 Landscape 148 × 210") do not agree with the dimensions, so the entry uses the dimensions as written. The numbers of the three products otherwise agree.
- Sources: [hardcover](https://support.peecho.com/hc/en-us/articles/19730953142428), [layflat](https://support.peecho.com/hc/en-us/articles/19732208244252), [softcover](https://support.peecho.com/hc/en-us/articles/19731377793564) (help articles updated 9 September, 24 November and 22 October 2026).

### Saal Digital · photo book, hardcover (default options)

File `saal-digital.json`; one entry, five sizes, **for the default cover and paper options only** (glossy unpadded cover, matte photo paper, standard barcode, no finishing). The tables were read in a real browser on 26 November 2026 from the Professional Zone page and saved as a text file by the lead (`reports/saal-professional-zone-2026-11-26.txt` in the integration checkout, not part of the repository).

| Id | Saal's size | Trim per page | Pages |
|---|---|---|---|
| `8.5x11` | 21 × 28 cm (8.5 × 11 in) | 210 × 270 mm | 26 to 160 |
| `11x11` | 28 × 28 cm (11 × 11 in) | 270 × 270 mm | 26 to 160 |
| `11x7.5` | 28 × 19 cm (11 × 7.5 in) | 280 × 188 mm | 26 to 160 |
| `16.5x11` | 42 × 28 cm (16.5 × 11 in) | 420 × 270 mm | 26 to 130 |
| `7.5x7.5` | 19 × 19 cm (7.5 × 7.5 in) | 188 × 188 mm | 26 to 130 |

- **Trim.** Read from the spread, not from the size's name: (spread − 2 × 35 px bleed) ÷ 2 at 300 dpi, so the "21 × 28" book is 210 × 270 mm per page (4961 px = 420 mm; 3190 px = 270.1 mm).
- **What the export writes.** Two files in a folder. `Interior.pdf` has one PDF page per double page, the first spread starting on the left; the first page of the first spread and the last page of the last spread are the printed inside covers (leave them empty for white). `Cover.pdf` is one flat spread. sRGB, fonts embedded, no marks. The stated page count does not include the cover; counts run in twos.
- **Tables.** Every size has its own table by page count (they differ between sizes: the spine at 30 pages is 154 px for 21 × 28 and 142 px for 28 × 28). The spine and the fold-over are Saal's own columns. Saal's cover width is not a constant board plus the spine (the side panel is 2526.5 px at 26 pages, 2515 at 56 and 2528.5 at 160 for 21 × 28), so each size's **board width, fold-over included**, is a table worked out from the cover width: (width − 2 × side bleed − spine) ÷ 2, with the fold-over lying inside the board (`hingeWithinPanel`). That makes the cover exactly as wide as Saal's table at every page count. The engine needed one change: a board width may be a table (it was a length or a quote). Values are kept in millimetres with the pixels in `source`.
- **Cover.** Bleed on the sides and the top and bottom as Saal gives it (110 and 83 px at 300 dpi, for example); no wrap.
- **Bleed of the interior.** 35 px (2.96 mm) for every size. The two smaller sizes are tabled at 302 dpi with 36 px (3.03 mm), so their spreads come out up to 0.1 mm narrower than Saal's.
- **Margins.** About 1 cm from the trim (Saal's advice for content that does not cover the page).
- **What the author enters.** Nothing; the spine and fold come from the tables.
- **Not read.** Other cover and paper options (glossy, matte, leatherette, padded covers, silk and other papers; they may change the spine and the fold-over), the three smaller sizes (8.5 × 6, 6 × 8.5 and 6 × 6 in: their tables have other columns), XT books, Professional Line and softcover. The standard option prints a small barcode (92 × 66 px) on the back cover and the last page.
- **Difference from the planning research.** The trim: the planning research's example spread of 5031 × 3260 px is 210 × 270 mm per page, not 280 mm. The EU product page's "exact size 21.5 × 27.5 cm" is a different figure and is not used.
- Source: [Professional Zone](https://www.saal-digital.com/photo-book/professional-zone/).

### WhiteWall · Coffee Table Book, hardcover

File `whitewall.json`; one entry, six sizes (cm): Portfolio A3 portrait 27 × 35.6 and landscape 38.2 × 29, Gallery square 29 × 29, Exhibition A4 portrait 20.5 × 27 and landscape 27 × 20.5, Story square 20.5 × 20.5. Six papers: three inkjet (up to 200 pages) and three Fuji Crystal Archive photo papers (up to 112).

- **Pages.** 28 to 200 in steps of 4, covers not counted.
- **What the export writes.** Two files in a folder: `Interior.pdf`, single pages with bleed on the top, bottom and outer edge and none on the binding edge, and `Cover.pdf`, one flat spread (back, spine, front with the fold, wrap and bleed). sRGB, 300 ppi target, fonts embedded, no marks.
- **Margins.** 5 mm inside the page and cover edges; text at least 2 mm from the spine edges, 11 pt or larger recommended.
- **Quote-typed.** WhiteWall shows the exact page and cover sizes, the bleed, the spine and the fold only after the book is configured on its site (Create now › PDF upload) or in its InDesign template, so the author types them in the export sheet: the page sizes (the entry accepts 8 mm either way of the nominal size and proposes the nominal one; the 8 mm tolerance is ours, WhiteWall states none), the interior bleed, the cover board, the fold (10 to 12 mm from the spine onto the front and back, the one range the page states), the wrap, the cover bleed and the spine. They map as follows: the cover board of each face includes the fold (`hingeWithinPanel`), so the hinge lies inside the board next to the spine; the wrap is the material beyond the board, and the bleed beyond the wrap.
- **Limits.** The cover file is at most 250 MB. The content file is 1 GB on two WhiteWall pages and 1.5 GB on the upload page: keep it under 1 GB.
- **Differences from the planning research.** None in the numbers; the pages say the safety area is 5 mm and the spine margin 2 mm, as the planning research did. The article "Setting the correct dimensions" confirms bleed on three edges only.
- Sources: [PDF upload](https://www.whitewall.com/eu/coffee-table-book/pdf-upload), [file requirements](https://service.whitewall.com/hc/en-us/articles/4411222658321), [dimensions](https://service.whitewall.com/hc/en-us/articles/4411250911377), [design notes](https://service.whitewall.com/hc/en-us/articles/4411236486929), [formats and papers](https://www.whitewall.com/eu/coffee-table-book).

### Lulu · hardcover casewrap, paperback

File `lulu.json`; two entries, seven trims each: Small Square 7.5 × 7.5 in, Square 8.5 × 8.5 in, Small Landscape 9 × 7 in, US Letter 8.5 × 11 in and its landscape, A4 210 × 297 mm and its landscape (the trims useful for photo books, from the guide's table of 20; inch sizes are kept exactly, so 7.5 in is 190.5 mm).

- **Pages.** Hardcover 24 to 800, paperback 32 to 800, an even number, covers not counted. (Hardcover's 800 is the end of Lulu's spine table; paperback's from the products page.)
- **What the export writes.** Two files in a folder: `Interior.pdf`, single pages at trim plus 0.125 in (3.175 mm) bleed on every side, and `Cover.pdf`, one flat spread (back, spine, front) with the same bleed. sRGB or CMYK, as **Book & Print › Color** says (Lulu's printers use sRGB IEC61966-2.1; a CMYK file stays CMYK at Lulu, which names Coated GRACoL 2006, the entry's ICC profile and a bundled one, and a total ink of at most 270 %). 300 to 600 ppi, fonts embedded, no marks, no password. Transparency is flattened, as Lulu asks.
- **Margins.** Text 0.5 in (12.7 mm) inside the trim (0.75 in on hardcover covers). The gutter should grow with the page count (the guide's table is in the entry's notes); the entry checks 12.7 mm.
- **Spine.** Paperback: pages ÷ 17.48 + 1.524 mm. Hardcover: Lulu's table of 27 steps from 24 to 800 pages (6 mm up to 84 pages, 13 mm to 140, 16 mm to 168, and so on to 54 mm at 800), taken whole. No spine text at 80 pages or fewer.
- **Quote-typed.** The hardcover casewrap's board size, fold (about 6 mm from the spine) and wrap come from the cover template Lulu generates after the interior is uploaded; the author types them. Casewrap covers are bound 0.75 in from each edge and have overhang of 0.125 to 0.25 in on three sides.
- **Differences from the planning research.** Lulu's guide is newer than the one read during planning: the safety margin on both the interior and the cover is 0.5 in; the help page asks for 0.25 in minimum and 0.75 in on casewrap covers, so the hardcover entry uses 0.75 in for its cover. The guide's gutter text says "0.2 in/2.08 mm" (0.2 in is 5.08 mm): not used. The hardcover spine table runs to 800 pages (the planning research stops at 250). The bleed applies to every edge, the binding edge included.
- **Not confirmed.** Which of the seven trims Lulu offers for hardcover casewrap: the guide lists trims for all bindings, and the products page does not list casewrap sizes. Check Lulu's pricing calculator before ordering; see `docs/status.md`.
- Sources: [Book Creation Guide](https://assets.lulu.com/media/guides/en/lulu-book-creation-guide.pdf), [PDF settings](https://help.lulu.com/en/support/solutions/articles/64000255519), [casewrap cover](https://help.lulu.com/en/support/solutions/articles/64000308572-creating-your-hardcover-casewrap-cover), [products](https://www.lulu.com/products).

### Mixam · hardcover book (casebound)

File `mixam.json`; one entry, 24 sizes: the 11 book sizes of the hardcover page's table (Digest 5.5 × 8.5 in, US Trade 6 × 9, Letter 8.5 × 11, 7.25 × 9.5, 7 × 9, Pocket Book, Royal, Executive, Crown Quarto, A5, A4) in portrait and landscape, and the 8.5 in and 7.5 in squares. Inch values are kept exactly as Mixam writes them.

- **What the export writes.** Two files in a folder: `Interior.pdf`, single pages with 0.125 in (3.175 mm) bleed on all four sides, and `Cover.pdf`, one flat spread (back, 0.2 in hinge, spine, 0.2 in hinge, front) with 0.8 in (20.32 mm) of bleed on all four edges, which Mixam wraps around the boards. Mixam's worked example (a 5.5 × 8.5 in digest with a 0.35 in spine: 11.75 × 8.5 in, 13.35 × 10.1 in with bleed) is a test.
- **Margins.** Interior: 0.25 in from the outer edges, 0.5 in from the binding. Cover: 0.25 in from the outer edges; 0.6 in from the spine edge (the structure has one safe distance for a cover, so the 0.6 in is in the notes).
- **Pages.** Mixam counts two pages for the cover in the total you enter in its calculator; hardcovers have free endpapers and no inside covers; the first printed page is page 3, on the right. Page limits are shown by the calculator per order, so the entry sets none.
- **Quote-typed.** The spine, from your Mixam cart or the order's Artwork tab (it depends on the page count and the paper).
- **Color.** Mixam prefers CMYK (GRACoL2006_Coated1v2) and converts RGB files itself; with CMYK in **Book & Print › Color** the app proposes the bundled GRACoL2006_Coated1v2.
- **Differences from the planning research.** The cover bleed (0.8 in on all four edges), the hinge and the interior bleed agree. The interior binding margin is 0.5 in on the hardcover binding page, and 0.6 in applies to the cover spread, from the spine edge (the planning research gave 0.6 in for the interior). The binding-types page gives 0.4 in for the cover's binding edge and the file-setup page 0.6 in: the stricter is used. The UK site's millimetre values were not read (the UK pages could not be fetched as text), so none is used.
- **Not added.** Mixam layflat: its binding page gives the margins (bleed 0.125 in, no quiet area at the binding, cover bleed 0.8 in) but the sizes and page limits are not on any page that could be read.
- Sources: [hardcover setup](https://mixam.com/support/hardcoversetup), [print file setup](https://mixam.com/support/filesetup), [binding types](https://mixam.com/support/binding), [page counts](https://mixam.com/support/pagecount), [CMYK vs RGB](https://mixam.com/support/cmykvsrgb).

### Blurb · ImageWrap hardcover, softcover (PDF to Book)

File `blurb.json`; two entries. ImageWrap hardcover (`blurb-imagewrap-hardcover`) in five formats and softcover (`blurb-softcover`) in the three smaller ones (Blurb offers no softcover for the two large formats). Papers of the ImageWrap entry: Premium, Standard and ProPhoto Pearl (up to 240 pages) and Layflat Pearl (up to 110).

| Id | Blurb's name | Trim (pt) | Trim (in) |
|---|---|---|---|
| `small-square` | Small Square "7 × 7" | 486 × 477 | 6.75 × 6.625 |
| `standard-portrait` | Standard Portrait "8 × 10" | 576 × 720 | 8 × 10 |
| `standard-landscape` | Standard Landscape "10 × 8" | 684 × 576 | 9.5 × 8 |
| `large-landscape` | Large Landscape "13 × 11" | 900 × 765 | 12.5 × 10.625 |
| `large-square` | Large Square "12 × 12" | 846 × 846 | 11.75 × 11.75 |

- **What the export writes.** Two files in a folder: `Cover.pdf`, one page (back, spine, front), and `Interior.pdf`, single pages (Blurb's file starts with a single page, then spreads, and ends with a single page: page 1 is on the right, so tick the first page on the right in **Book & Print**). CMYK with body text in black only; the export sheet says the file is not a certified PDF/X-3:2002 and that Blurb's upload check may refuse it (decision D6). Blurb names no ICC profile, so the author chooses the CMYK profile. An sRGB book is blocked for Blurb until **Book & Print › Color** is set to CMYK, and transparency is flattened because PDF/X-3 allows none.
- **Pages.** An even number, at least 20 (24 for Blurb's trade formats, which are not in the catalog).
- **Inside pages.** 9 pt (0.125 in) bleed on the top, bottom and outer edge and none on the binding edge, so the PDF page is the trim plus 9 pt in width and 18 pt in height (Standard Landscape: 693 × 594 pt). Text 18 pt from the outer edges and 45 pt from the binding (the calculator table says 36 pt, its text 45 pt; 45 pt is used).
- **ImageWrap cover.** The cover wraps around the board, so each panel is larger than the page (Standard Landscape: 703 × 604 pt against a 684 × 576 pt page) and the bleed is 22 pt on every edge. At 20 pages the Standard Landscape cover is 1483 × 648 pt with a 33 pt spine; the trim line is 1439 × 604 pt. The panel heights of the other formats come from the trim-line heights of the table (505, 747, 793 and 874 pt). Text 18 pt from the trim line.
- **Softcover cover.** Panel = page, 9 pt bleed on every edge, no wrap: Standard Landscape at 20 pages is 1390 × 594 pt with a 4 pt spine.
- **Spine, tabled.** Standard Landscape only, from the table read during planning in points at 20, 40, 60, 80, 100, 120, 160, 200 and 240 pages: Premium, Standard and ProPhoto Pearl ImageWrap, Layflat Pearl ImageWrap (to 100 pages), Premium softcover (4 to 54 pt). Between two columns the next column's value is used, which can be wider than Blurb's real value; the exact page counts where each step changes were not readable, so check the spine in Blurb's calculator and type it if it differs (any tabled value can be overridden). Layflat Pearl from 101 to 110 pages is past the table: the export asks for the spine.
- **Quote-typed.** For the other four ImageWrap formats and for the Small Square and Standard Portrait softcovers, the spine; for the other four ImageWrap formats, the panel width: both come from Blurb's book-size calculator (<https://www.blurb.com/make/pdf_to_book/booksize_calculator>), which gives the cover and page sizes of the chosen book.
- **Differences from the planning research and the page.** Blurb's PDF-to-Book page states the bleed as 0.125 in on all sides and the safe margin as 0.25 in; the calculator's page sizes show bleed on the outer edge only and the planning research's 18 pt and 45 pt margins, which are used. The page gives 24 pages as the minimum for trade (paperback and hardcover) books and 20 for photo books. The page's list of paper limits is ambiguous (440 and 480 pages for some papers, 240 for Premium and Proline, and "over 80" for a case it does not name), so the maximums are the ones the spine table reaches: 240 pages (110 for layflat).
- **Not added.** Mini Square (5 × 5 in; its table was not captured), the trade formats, magazines, dust-jacket and plain hardcover covers, and every number of the calculator that is not in the planning table.
- Sources: [PDF to Book](https://www.blurb.com/pdf-to-book), [book size calculator](https://www.blurb.com/make/pdf_to_book/booksize_calculator) (its tables load by script; the numbers are those recorded in the planning research of 26 November 2026).

## Not added yet

### Pixartprinting, other sizes

Waiting for the printer's cover templates for each size (and the instructions PDF of the user's own quote, which settles whether the interior wants CMYK). The 21 × 21 cm entry is the only one whose cover geometry is known; the other sizes are not scaled from it.

## Services that cannot be supported

These services take their books only through their own software or website, or take pages as pictures, so a PDF from Paper & Grain cannot be uploaded: Photobox, Albelli, Shutterfly, Mixbook, Artifact Uprising, PhotoSì (JPG pages only), MILK Books (consumer), CEWE outside the UK (its own software; in the UK through its template software), and Printique for covers (inside pages only). Authors ask about them: the answer is to use the printer's own designer, or to order from one of the services in the catalog.

Services that accept a PDF but are not in the catalog yet: Bookvault, Flyeralarm, Onlineprinters, Mimeo Photos, PrestoPhoto, ilFotoalbum, Amazon KDP and IngramSpark (trade books: a 75-page minimum for hardcover, barcodes).
