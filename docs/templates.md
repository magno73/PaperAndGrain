# Book templates

Open a book and choose **File › Book Templates…**, **Style** in the toolbar, the **Book Template** row in the Page tab, or the title menu in the toolbar. A new book opens on the same chooser. The window shows the twelve templates in three families (**Classics**, **Studio**, **Photobook**), each with a photo from the project. **Apply** saves the choice for the book. **Show Page Numbers** turns the folios on the interior pages with margins on or off, in the editor and in the PDF. The choice made in the window takes precedence over the template's default. A template changes paper, headings, body type, margins and the gaps between photos. The order of pages and images, the framing and the texts are kept. A page heading is optional; **Insert › Page Heading** adds one to any page.

| Template | ID | Composition | When to choose it |
|---|---|---|---|
| Journal | `diary` | Warm ivory, headings in Didot and text in Baskerville | The story leads the spreads and a photo answers it on the facing page. |
| Atlas | `atlas` | Light paper, Avenir Next, grid with a rule and a page number | The trip reads as a sequence of stages, with images and notes on the same spread. |
| Gallery | `gallery` | Charcoal, headings in Baskerville Italic, text in Optima and wide margins | The book leaves room for single photos and panoramas. |
| Essential | `essential` | White, Helvetica Neue Light for headings, text in Helvetica Neue and a full-bleed photo on the cover | The composition echoes the restraint of Apple presentations. It suits spreads with a short text next to a full-page photo. |
| Swiss Grid | `swissGrid` | Compact headings in Helvetica Neue Bold, a red bar and folios. The text takes five columns out of six. The cover photo takes the four right-hand columns. | An itinerary in stages, with short texts and images read in sequence. |
| Berlin Notebook | `berlinQuarter` | Midnight blue, citron headings in Avenir Next Condensed Heavy and light body text in Georgia. The photo takes almost two thirds of the cover above the masthead. The story starts in the second third of the page. | Alternates close-up photos with narrative pages, at the pace of an independent magazine. |
| Japanese Interval | `japaneseInterval` | Warm paper, heading in Hiragino Mincho and text in Palatino. A small print sits on the right side. The reading block also moves to the right and leaves the top fifth of the page empty. | Images that call for a pause, with short texts of observation. |
| Monograph | `monograph` | Warm paper #F6F3EC, Iowan Old Style for headings and text, an oxblood accent. One photo per page in a constant frame with 13% margins. The text is in a centered column a third of the way down the page. On the cover, a print mounted in the middle. | Photos that stand on their own, calm sequences. Inspired by *The Americans* and *American Prospects*. |
| Postcard | `postcard` | Warm white, red Futura Bold headings, Avenir Next text, no page numbers. The photo frame stays in the same place on every page, and two or three photos stack inside it. On the cover, a poster title and a photo over three quarters of the face. | Graphic, sunny trips. Inspired by Teju Cole's *Fernweh* (MACK). |
| Nocturne | `nocturne` | Black pages #141414, light Didot headings, Avenir Next text. Floating photos with a medium border; the text starts halfway down the page. | Nights, cities, low light, or a dark chapter inside another book. |
| Kodachrome | `kodachrome` | Ivory #F2EDE3, Gill Sans SemiBold for headings, text in Palatino, sky blue and folios. Framed prints, never full bleed, in pairs: with three photos, one large above and two below. | Pairs that answer each other in color or shape. Inspired by Luigi Ghirri's *Kodachrome*. |
| Road Log | `roadLog` | Manila paper #EFE6D2, American Typewriter headings, Georgia text, a rust rule and page numbers. The gallery is a dense contact sheet in travel order. | Dense, chronological diaries. Inspired by Stephen Shore's *American Surfaces*. |

In automatic galleries, Swiss Grid aligns the photos in modular cells. If the last row would be incomplete, the first photo widens over the empty cells. Berlin Notebook gives weight to the first photo with a side strip of smaller images. Japanese Interval places up to three staggered prints with wide space between them.

On **Text over photo** pages, Swiss Grid uses a light panel with a vertical red bar, Berlin Notebook a midnight-blue masthead with a citron edge, and Japanese Interval a paper-colored panel with a short moss-green rule. The chooser shows these three treatments on the same cover photo.

For these three templates, the automatic heading shrinks its size slightly when that is enough to keep a short phrase on one line. A line break typed by the author, a long heading or a point size chosen in the inspector keeps its own layout.

Swiss Grid draws on the typographic tradition of Zurich. [Museum für Gestaltung Zürich](https://eshop.museum-gestaltung.ch/?lang=en&nr=780030&op=productnr)

Berlin Notebook interprets working within constraints through the contrast between a condensed masthead, literary text and a band of photos. [Hort workshops](https://hort.org.uk/wp-content/uploads/2014/11/Hort-Workshops.pdf)

Japanese Interval uses empty space as an invitation to interpretation. [Kenya Hara, *White*](https://www.lars-mueller-publishers.com/white)

`Book.template` and `BookPage.heading` are optional fields in schema v1. A project with no template uses the basic style. `BookTemplate.swift` holds the colors, typefaces and rules shared by the editor and the PDF. Core Text draws and measures text with the same parameters on both paths. The template margin also respects the minimum print margin. Cover PDFs use the template's composition.

## Cover and spine

Each template has a scale for the cover title (`EditorialStyle.coverTitleScale`). A title that does not fit the band at full scale falls back to the page heading size. If the spine is at least 5 mm wide, the print PDF and the Pixartprinting PDF carry the title on it, reading top to bottom with the foot towards the front, in the template's heading typeface and color.

## Sources of the Photobook templates

The five templates interpret the choices of award-winning or reference books: the jury statements of the Deutscher Fotobuchpreis 25|26, the Paris Photo–Aperture PhotoBook Awards 2024 and 2025, interviews with Morgan Crowcroft-Brown (MACK), Hans Gremmen and Sybren Kuiper, and Aperture's guide to making a photobook. They are not reproductions of those books. The typefaces are those that ship with macOS; check their PDF embedding license before you sell printed books.
