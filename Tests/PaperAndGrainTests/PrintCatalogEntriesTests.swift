import CoreGraphics
import PDFKit
import XCTest
@testable import PaperAndGrain

/// The numbers of the bundled services, as read from each printer's own page (T11), and the layout of
/// every size of every entry against the product's safe margin. T10's `PrintProfileTests` render the
/// boxes; these tests pin what each entry says and check that text keeps inside the margin.
final class PrintCatalogEntriesTests: XCTestCase {
    private let points = 72.0 / 25.4

    private var catalog: PrintProfileCatalog {
        get throws {
            try PrintProfileCatalog.load(from: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/PrintProfiles"))
        }
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("print-entries-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// What an entry must say, from the printer's page.
    private struct Facts {
        var id: String
        var service: String
        var binding: PrintProfile.Binding
        var layout: PrintProfile.Interior.Layout = .single
        var minimum: Int?
        var maximum: Int?
        var multiple: Int?
        var coverCounted: Int?
        var coverKind: PrintProfile.Cover.Kind
        var interiorBleed: PrintProfile.EdgeValues
        var sizes: [String]
        var colors: [PrintProfile.ColorMode]
    }

    private func verify(_ facts: [Facts], file: StaticString = #filePath, line: UInt = #line) throws {
        let catalog = try catalog
        for fact in facts {
            let profile = try XCTUnwrap(catalog.profile(fact.id), fact.id, file: file, line: line)
            XCTAssertEqual(profile.service, fact.service, fact.id, file: file, line: line)
            XCTAssertEqual(profile.binding, fact.binding, fact.id, file: file, line: line)
            XCTAssertEqual(profile.interior.layout, fact.layout, fact.id, file: file, line: line)
            let rules = profile.interior.pages
            XCTAssertEqual(rules.minimum, fact.minimum, fact.id, file: file, line: line)
            XCTAssertEqual(rules.maximum, fact.maximum, fact.id, file: file, line: line)
            XCTAssertEqual(rules.multiple, fact.multiple, fact.id, file: file, line: line)
            XCTAssertEqual(rules.coverPagesCounted, fact.coverCounted, fact.id, file: file, line: line)
            XCTAssertEqual(profile.cover.kind, fact.coverKind, fact.id, file: file, line: line)
            XCTAssertEqual(profile.interior.bleed.fixedValues, fact.interiorBleed, fact.id, file: file, line: line)
            XCTAssertEqual(profile.sizes.map(\.id), fact.sizes, fact.id, file: file, line: line)
            XCTAssertEqual(profile.color.accepts, fact.colors, fact.id, file: file, line: line)
            XCTAssertEqual(profile.verifiedDate != nil, true, fact.id, file: file, line: line)
        }
    }

    // MARK: Services

    func testPeechoEntriesSayWhatThePrintersPagesSay() throws {
        let none = PrintProfile.EdgeValues.zero
        try verify([
            Facts(id: "peecho-hardcover", service: "Peecho", binding: .hardcover, minimum: 24, maximum: 500, multiple: 2,
                  coverCounted: 2, coverKind: .interiorPages, interiorBleed: none,
                  sizes: ["148x210", "210x148", "210x297", "297x210", "216x280", "280x216", "210x210", "294x294"], colors: [.srgb]),
            Facts(id: "peecho-layflat", service: "Peecho", binding: .layflat, minimum: 18, maximum: 122, multiple: 2,
                  coverCounted: 2, coverKind: .interiorPages, interiorBleed: none,
                  sizes: ["297x210", "210x210", "294x294"], colors: [.srgb]),
            Facts(id: "peecho-softcover", service: "Peecho", binding: .softcover, minimum: 20, maximum: 300, multiple: 2,
                  coverCounted: 2, coverKind: .interiorPages, interiorBleed: none,
                  sizes: ["148x210", "210x148", "210x297", "297x210", "210x210"], colors: [.srgb]),
        ])
        let layflat = try XCTUnwrap(catalog.profile("peecho-layflat"))
        XCTAssertEqual(layflat.interior.safe.fixedValues, PrintProfile.EdgeValues(top: 10, bottom: 10, outer: 10, inner: 0),
                       "no margin on the binding edge of a layflat page")
        XCTAssertEqual(try XCTUnwrap(catalog.profile("peecho-hardcover")).interior.safe.fixedValues.largest, 10)
        XCTAssertNil(try XCTUnwrap(catalog.profile("peecho-hardcover")).cover.spine, "Peecho draws no spine")
    }

    func testWhiteWallTakesEveryMeasureFromTheOrder() throws {
        try verify([Facts(id: "whitewall-coffee-table-book", service: "WhiteWall", binding: .hardcover, minimum: 28, maximum: 200,
                          multiple: 4, coverKind: .flat, interiorBleed: .zero,
                          sizes: ["27x35.6", "38.2x29", "29x29", "20.5x27", "27x20.5", "20.5x20.5"], colors: [.srgb])])
        let profile = try XCTUnwrap(catalog.profile("whitewall-coffee-table-book"))
        XCTAssertEqual(profile.interior.safe.fixedValues, PrintProfile.EdgeValues(top: 5, bottom: 5, outer: 5, inner: 5))
        XCTAssertTrue(profile.interior.bleed.top.isTyped && profile.interior.bleed.bottom.isTyped && profile.interior.bleed.outer.isTyped)
        XCTAssertEqual(profile.interior.bleed.inner, .fixed(PrintProfile.Length(0)), "no bleed on the binding edge")
        XCTAssertEqual(profile.files.arrangement, .separate)
        let cover = profile.cover
        XCTAssertTrue(cover.panel?.widthMM.isTyped == true && cover.panel?.heightMM.isTyped == true)
        XCTAssertTrue(cover.spine?.isTyped == true && cover.wrap?.isTyped == true && cover.hinge?.isTyped == true)
        XCTAssertEqual(cover.hingeWithinPanel, true, "the fold lies inside each cover face")
        XCTAssertEqual(cover.hinge?.nominal, 11, "the fold takes 10 to 12 mm from the spine")
        XCTAssertTrue(cover.hinge?.accepts(10) == true && cover.hinge?.accepts(12) == true && cover.hinge?.accepts(13) == false)
        // Every size is a range around the printer's nominal size, and the nominal size is what a menu proposes.
        let size = try XCTUnwrap(profile.size("20.5x27"))
        XCTAssertEqual(size.format, BookFormat(widthMM: 205, heightMM: 270))
        XCTAssertTrue(size.matches(BookFormat(widthMM: 207, heightMM: 272)))
        XCTAssertFalse(size.matches(BookFormat(widthMM: 220, heightMM: 270)))
        // Photo papers stop at 112 pages, inkjet papers at 200.
        for paper in profile.papers ?? [] {
            XCTAssertEqual(profile.pageRules(for: size, paper: paper).maximum, paper.id.hasPrefix("photo") ? 112 : 200, paper.id)
        }
        XCTAssertEqual(profile.papers?.count, 6)
    }

    func testLuluSpineTableAndFormulaFollowTheGuide() throws {
        let bleed = PrintProfile.EdgeValues(top: 3.175, bottom: 3.175, outer: 3.175, inner: 3.175)
        let sizes = ["small-square", "square", "small-landscape", "us-letter", "us-letter-landscape", "a4", "a4-landscape"]
        try verify([
            Facts(id: "lulu-hardcover-casewrap", service: "Lulu", binding: .hardcover, minimum: 24, maximum: 800, multiple: 2,
                  coverKind: .flat, interiorBleed: bleed, sizes: sizes, colors: [.srgb, .cmyk]),
            Facts(id: "lulu-paperback", service: "Lulu", binding: .softcover, minimum: 32, maximum: 800, multiple: 2,
                  coverKind: .flat, interiorBleed: bleed, sizes: sizes, colors: [.srgb, .cmyk]),
        ])
        let hardcover = try XCTUnwrap(catalog.profile("lulu-hardcover-casewrap"))
        let spine = try XCTUnwrap(hardcover.cover.spine)
        for (pages, mm) in [(24, 6.0), (84, 6), (85, 13), (140, 13), (141, 16), (169, 17), (195, 19), (223, 21), (251, 22),
                            (500, 35), (501, 37), (799, 52), (800, 54)] {
            XCTAssertEqual(spine.value(pages: pages, paper: nil), mm, "\(pages) pages")
        }
        XCTAssertNil(spine.value(pages: 801, paper: nil), "past the printer's table")
        XCTAssertEqual(spine.tableLimit(paper: nil), 800)
        XCTAssertTrue(hardcover.cover.wrap?.isTyped == true && hardcover.cover.panel?.widthMM.isTyped == true,
                      "the casewrap wrap and board come from Lulu's cover template")
        XCTAssertEqual(hardcover.cover.safe?.mm, 19.05)
        let paperback = try XCTUnwrap(catalog.profile("lulu-paperback"))
        let formula = try XCTUnwrap(paperback.cover.spine)
        XCTAssertEqual(try XCTUnwrap(formula.value(pages: 100, paper: nil)), 100 / 17.48 + 1.524, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(formula.value(pages: 32, paper: nil)), 3.354, accuracy: 0.001)
        XCTAssertEqual(paperback.interior.safe.fixedValues.largest, 12.7)
        XCTAssertEqual(try XCTUnwrap(paperback.size("small-square")).format.widthMM, 190.5, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(paperback.size("a4")).format, BookFormat(widthMM: 210, heightMM: 297))
    }

    func testMixamHardcoverFollowsItsCoverFormula() throws {
        let profile = try XCTUnwrap(catalog.profile("mixam-hardcover"))
        XCTAssertEqual(profile.binding, .hardcover)
        XCTAssertEqual(profile.sizes.count, 24)
        XCTAssertEqual(profile.interior.bleed.fixedValues, PrintProfile.EdgeValues(top: 3.175, bottom: 3.175, outer: 3.175, inner: 3.175))
        XCTAssertEqual(profile.interior.safe.fixedValues, PrintProfile.EdgeValues(top: 6.35, bottom: 6.35, outer: 6.35, inner: 12.7))
        XCTAssertEqual(profile.interior.pages.coverPagesCounted, 2)
        XCTAssertNil(profile.interior.pages.minimum, "page limits are shown per order")
        XCTAssertEqual(profile.interior.pages.multiple, 2, "a sheet has two sides")
        XCTAssertEqual(profile.size("a4-portrait")?.format, BookFormat(widthMM: 210, heightMM: 297))
        XCTAssertEqual(profile.size("a5-landscape")?.format, BookFormat(widthMM: 210, heightMM: 148))
        XCTAssertTrue(profile.size(matching: BookFormat(widthMM: 210, heightMM: 297)) != nil, "an A4 book matches")
        XCTAssertEqual(profile.cover.hinge?.nominal ?? 0, 5.08, accuracy: 0.001)
        XCTAssertEqual(profile.cover.bleed?.fixedValues, PrintProfile.EdgeValues(top: 20.32, bottom: 20.32, outer: 20.32, inner: 20.32))
        XCTAssertTrue(profile.cover.spine?.isTyped == true, "the spine is in the cart")
        XCTAssertEqual(profile.files.arrangement, .separate)
        // Page 1 is on the right, so a blank leads it (Mixam's blank page 2) and the count is made even at the end.
        var even = Book(title: "Even", format: try XCTUnwrap(profile.size("digest-portrait")).format,
                        pages: (0..<32).map { _ in BookPage(layout: .text, text: "x") })
        even.cover = BookCover(title: "Even")
        var evenPlan = PrintPlan(profile: profile, sizeID: "digest-portrait")
        evenPlan.measures[.spine] = 10
        XCTAssertEqual(BookPDF.interiorPageCount(even, plan: evenPlan), 34)
        even.pages.removeLast()
        XCTAssertEqual(BookPDF.interiorPageCount(even, plan: evenPlan) % 2, 0)

        // The printer's worked example: a 5.5 x 8.5 in digest with a 0.35 in spine is 11.75 x 8.5 in without bleed and
        // 13.35 x 10.1 in with it.
        var book = Book(title: "Digest", format: try XCTUnwrap(profile.size("digest-portrait")).format, pages: [BookPage(layout: .text, text: "x")])
        book.cover = BookCover(title: "Digest", spineMM: 0.35 * 25.4)
        var plan = PrintPlan(profile: profile, sizeID: "digest-portrait")
        plan.measures[.spine] = 0.35 * 25.4
        let directory = try temporaryDirectory()
        let output = directory.appendingPathComponent("Out")
        try BookPDF.write(book, directory: directory, plan: plan, to: output)
        let cover = try XCTUnwrap(CGPDFDocument(output.appendingPathComponent("Cover.pdf") as CFURL)?.page(at: 1))
        let inch = 72.0
        XCTAssertEqual(cover.getBoxRect(.trimBox).width, 11.75 * inch, accuracy: 0.1)
        XCTAssertEqual(cover.getBoxRect(.trimBox).height, 8.5 * inch, accuracy: 0.1)
        XCTAssertEqual(cover.getBoxRect(.mediaBox).width, 13.35 * inch, accuracy: 0.1)
        XCTAssertEqual(cover.getBoxRect(.mediaBox).height, 10.1 * inch, accuracy: 0.1)
    }

    // MARK: Saal Digital

    private struct Pinned {
        var size: String
        var spreadPX: (Int, Int)
        var spreadDPI: Double
        var coverDPI: Double
        var coverHeightPX: Int
        /// Pages, cover width, spine and fold-over in pixels, as Saal's Professional Zone tables give them.
        var rows: [(Int, Int, Int, Int)]
    }

    private var saalPins: [Pinned] { [
        Pinned(size: "8.5x11", spreadPX: (5031, 3260), spreadDPI: 300, coverDPI: 300, coverHeightPX: 3402,
               rows: [(26, 5415, 142, 106), (56, 5463, 213, 130), (86, 5520, 283, 154), (160, 5702, 425, 201)]),
        Pinned(size: "11x11", spreadPX: (6449, 3260), spreadDPI: 300, coverDPI: 300, coverHeightPX: 3402,
               rows: [(26, 6833, 142, 106), (56, 6880, 213, 130), (86, 6938, 283, 154), (160, 7120, 425, 201)]),
        Pinned(size: "11x7.5", spreadPX: (6730, 2307), spreadDPI: 302, coverDPI: 302, coverHeightPX: 2449,
               rows: [(26, 7115, 143, 107), (56, 7174, 214, 131), (86, 7222, 285, 155), (160, 7405, 428, 202)]),
        Pinned(size: "16.5x11", spreadPX: (9992, 3260), spreadDPI: 300, coverDPI: 300, coverHeightPX: 3402,
               rows: [(26, 10382, 142, 106), (56, 10429, 213, 130), (86, 10487, 283, 154), (130, 10557, 366, 177)]),
        Pinned(size: "7.5x7.5", spreadPX: (4527, 2299), spreadDPI: 301, coverDPI: 302, coverHeightPX: 2449,
               rows: [(26, 4927, 143, 107), (56, 4987, 202, 131), (86, 5034, 285, 155), (130, 5104, 369, 178)]),
    ] }

    /// Rows of Saal's tables (default cover and paper) render to the cover width, spine and fold-over the table gives,
    /// and every size's spreads match the spread size.
    func testSaalTablesRenderTheDimensionsOfTheProfessionalZone() throws {
        let profile = try XCTUnwrap(catalog.profile("saal-digital-photobook-hardcover"))
        XCTAssertEqual(profile.binding, .hardcover)
        XCTAssertEqual(profile.interior.layout, .spread)
        XCTAssertEqual(profile.interior.ends, .insideCovers)
        XCTAssertEqual(profile.interior.pages.minimum, 26)
        XCTAssertEqual(profile.interior.pages.multiple, 2)
        XCTAssertEqual(profile.interior.pages.coverPagesCounted, 0, "the stated page count does not include the cover")
        XCTAssertEqual(profile.files.arrangement, .separate)
        XCTAssertEqual(profile.color.accepts, [.srgb])
        XCTAssertEqual(profile.sizes.map(\.id), ["8.5x11", "11x11", "11x7.5", "16.5x11", "7.5x7.5"])
        XCTAssertEqual(try XCTUnwrap(profile.size("16.5x11")).pages?.maximum, 130)
        XCTAssertEqual(try XCTUnwrap(profile.size("7.5x7.5")).pages?.maximum, 130)
        XCTAssertNil(try XCTUnwrap(profile.size("8.5x11")).pages?.maximum)
        XCTAssertEqual(profile.size("8.5x11")?.format, BookFormat(widthMM: 210, heightMM: 270),
                       "the trim is read from the spread: (5031 - 2 x 35) / 2 px at 300 dpi")
        for pin in saalPins {
            let size = try XCTUnwrap(profile.size(pin.size), pin.size)
            XCTAssertEqual(profile.pageRules(for: size).maximum ?? 160, pin.rows.last?.0, pin.size)
            for (pages, coverPX, spinePX, foldPX) in pin.rows {
                let context = "\(pin.size) \(pages) pages"
                var book = Book(title: "Saal", format: size.format, pages: (0..<pages).map { _ in BookPage(layout: .text, text: "x") })
                book.cover = BookCover(title: "Saal")
                let plan = PrintPlan(profile: profile, sizeID: pin.size)
                XCTAssertEqual(BookPDF.interiorPageCount(book, plan: plan), pages, context)
                let spine = try XCTUnwrap(plan.value(.spine, for: book, interiorPages: pages), context)
                let fold = try XCTUnwrap(plan.value(.hinge, for: book, interiorPages: pages), context)
                XCTAssertEqual(spine, Double(spinePX) * 25.4 / pin.coverDPI, accuracy: 0.002, context + " spine")
                XCTAssertEqual(fold, Double(foldPX) * 25.4 / pin.coverDPI, accuracy: 0.002, context + " fold-over")
                let directory = try temporaryDirectory()
                let output = directory.appendingPathComponent("Out")
                try BookPDF.write(book, directory: directory, plan: plan, to: output)
                let cover = try XCTUnwrap(CGPDFDocument(output.appendingPathComponent("Cover.pdf") as CFURL)?.page(at: 1), context)
                let media = cover.getBoxRect(.mediaBox)
                XCTAssertEqual(media.width / points, Double(coverPX) * 25.4 / pin.coverDPI, accuracy: 0.05, context + " cover width")
                XCTAssertEqual(media.height / points, Double(pin.coverHeightPX) * 25.4 / pin.coverDPI, accuracy: 0.05, context + " cover height")
                let interior = try XCTUnwrap(CGPDFDocument(output.appendingPathComponent("Interior.pdf") as CFURL), context)
                XCTAssertEqual(interior.numberOfPages, pages / 2, context + " one PDF page per double page")
                let spread = try XCTUnwrap(interior.page(at: 1)).getBoxRect(.mediaBox)
                XCTAssertEqual(spread.width / points, Double(pin.spreadPX.0) * 25.4 / pin.spreadDPI, accuracy: 0.2, context + " spread width")
                XCTAssertEqual(spread.height / points, Double(pin.spreadPX.1) * 25.4 / pin.spreadDPI, accuracy: 0.2, context + " spread height")
            }
        }
    }

    // MARK: Blurb

    func testBlurbEntriesFollowTheSpecificationAndTheStandardLandscapeTable() throws {
        let sizes = ["small-square", "standard-portrait", "standard-landscape", "large-landscape", "large-square"]
        let bleed = PrintProfile.EdgeValues(top: 3.175, bottom: 3.175, outer: 3.175, inner: 0)
        try verify([
            Facts(id: "blurb-imagewrap-hardcover", service: "Blurb", binding: .hardcover, minimum: 20, maximum: 240, multiple: 2,
                  coverCounted: 0, coverKind: .flat, interiorBleed: bleed, sizes: sizes, colors: [.cmyk]),
            Facts(id: "blurb-softcover", service: "Blurb", binding: .softcover, minimum: 20, maximum: 240, multiple: 2,
                  coverCounted: 0, coverKind: .flat, interiorBleed: bleed, sizes: Array(sizes.prefix(3)), colors: [.cmyk]),
        ])
        let imagewrap = try XCTUnwrap(catalog.profile("blurb-imagewrap-hardcover"))
        let safe = imagewrap.interior.safe.fixedValues
        for (value, expected) in zip(safe.all, [6.35, 6.35, 6.35, 15.875]) {
            XCTAssertEqual(value, expected, accuracy: 0.001, "18 pt outside, 45 pt at the binding")
        }
        XCTAssertEqual(imagewrap.cover.bleed?.fixedValues.largest ?? 0, 22 * 25.4 / 72, accuracy: 0.001)
        XCTAssertEqual(imagewrap.cover.safe?.mm ?? 0, 18 * 25.4 / 72, accuracy: 0.001)
        XCTAssertEqual(imagewrap.color.standard, "PDF/X-3:2002")
        XCTAssertNil(imagewrap.color.iccProfile, "Blurb names no ICC profile")
        XCTAssertEqual(imagewrap.papers?.map(\.id), ["premium", "standard", "prophoto-pearl", "layflat-pearl"])
        XCTAssertEqual(imagewrap.pageRules(for: imagewrap.size("large-square"), paper: imagewrap.papers?.last).maximum, 110)
        XCTAssertEqual(imagewrap.pageRules(for: imagewrap.size("large-square"), paper: imagewrap.papers?.first).maximum, 240)
        // Trims, in points, as Blurb's calculator gave them during planning.
        for (id, w, h) in [("small-square", 486.0, 477.0), ("standard-portrait", 576, 720), ("standard-landscape", 684, 576),
                           ("large-landscape", 900, 765), ("large-square", 846, 846)] {
            let format = try XCTUnwrap(imagewrap.size(id)).format
            XCTAssertEqual(format.widthMM, w * 25.4 / 72, accuracy: 0.001, id)
            XCTAssertEqual(format.heightMM, h * 25.4 / 72, accuracy: 0.001, id)
        }
        // Only Standard Landscape has a confirmed spine table; the others are typed from Blurb's calculator.
        for id in sizes where id != "standard-landscape" {
            XCTAssertTrue(imagewrap.coverRules(for: try XCTUnwrap(imagewrap.size(id))).spine?.isTyped == true, id)
        }
        let landscape = try XCTUnwrap(imagewrap.size("standard-landscape"))
        let spine = try XCTUnwrap(imagewrap.coverRules(for: landscape).spine)
        func points(_ pages: Int, _ paper: String) -> Double? { spine.value(pages: pages, paper: paper).map { ($0 * 72 / 25.4).rounded() } }
        for (pages, paper, pt) in [(20, "premium", 33.0), (40, "premium", 33), (60, "premium", 41), (120, "premium", 54), (240, "premium", 79),
                                   (20, "standard", 33), (80, "standard", 41), (240, "standard", 66),
                                   (100, "prophoto-pearl", 54), (240, "prophoto-pearl", 89),
                                   (20, "layflat-pearl", 40), (100, "layflat-pearl", 144)] {
            XCTAssertEqual(points(pages, paper), pt, "\(paper) \(pages) pages")
        }
        XCTAssertNil(points(110, "layflat-pearl"), "past the table: the author types it")
        let softcover = try XCTUnwrap(catalog.profile("blurb-softcover"))
        let softSpine = try XCTUnwrap(softcover.coverRules(for: try XCTUnwrap(softcover.size("standard-landscape"))).spine)
        XCTAssertEqual(softSpine.value(pages: 20, paper: "premium").map { ($0 * 72 / 25.4).rounded() }, 4)
        XCTAssertEqual(softSpine.value(pages: 240, paper: "premium").map { ($0 * 72 / 25.4).rounded() }, 54)
    }

    /// Blurb's 20-page examples for Standard Landscape: ImageWrap cover 1483 x 648 pt (trim line 1439 x 604, spine 33) and
    /// softcover cover 1390 x 594 pt (spine 4); the inside page is 693 x 594 pt.
    func testBlurbStandardLandscapeRendersTheDocumentedPageAndCoverSizes() throws {
        for (id, coverW, coverH, spinePT) in [("blurb-imagewrap-hardcover", 1483.0, 648.0, 33.0), ("blurb-softcover", 1390, 594, 4)] {
            let profile = try XCTUnwrap(catalog.profile(id))
            let size = try XCTUnwrap(profile.size("standard-landscape"))
            var book = Book(title: "Blurb", format: size.format, pages: (0..<20).map { _ in BookPage(layout: .text, text: "x") })
            book.cover = BookCover(title: "Blurb")
            // Blurb's file starts with a single page, page 1 on the right, so the first page of the book is on the right.
            book.printSettings = PrintSettings(firstPageOnRight: true)
            let plan = PrintPlan(profile: profile, sizeID: "standard-landscape", paperID: "premium")
            XCTAssertEqual(BookPDF.interiorPageCount(book, plan: plan), 20, id)
            let spineMM = try XCTUnwrap(plan.value(.spine, for: book, interiorPages: 20), id)
            XCTAssertEqual(spineMM * 72 / 25.4, spinePT, accuracy: 0.6, id)
            let directory = try temporaryDirectory()
            let output = directory.appendingPathComponent("Out")
            try BookPDF.write(book, directory: directory, plan: plan, to: output)
            let cover = try XCTUnwrap(CGPDFDocument(output.appendingPathComponent("Cover.pdf") as CFURL)?.page(at: 1), id)
            XCTAssertEqual(cover.getBoxRect(.mediaBox).width, coverW, accuracy: 1.5, id + " cover width")
            XCTAssertEqual(cover.getBoxRect(.mediaBox).height, coverH, accuracy: 1.5, id + " cover height")
            let interior = try XCTUnwrap(CGPDFDocument(output.appendingPathComponent("Interior.pdf") as CFURL), id)
            let widths = Set((1...interior.numberOfPages).compactMap { interior.page(at: $0)?.getBoxRect(.mediaBox).width.rounded() })
            XCTAssertEqual(widths, [693], "every inside page is the trim plus 9 pt on the outer edge, none at the binding")
        }
    }

    // MARK: Text keeps inside the safe margin

    /// A page of text in every size of every entry stays inside the product's margin on the edges that are cut.
    func testTextStaysInsideTheProductsSafeMargin() throws {
        var checked = 0
        for profile in try catalog.profiles {
            for size in profile.sizes {
                var book = Book(title: "Margins", format: size.format, pages: [
                    BookPage(layout: .text, text: String(repeating: "Margin check on a line of text. ", count: 14)),
                ])
                book.cover = BookCover(title: "Margins", spineMM: 8)
                book.printSettings = PrintSettings()
                book.printSettings?.choose(profile, size: size)
                var plan = try XCTUnwrap(PrintPlan(book: book), profile.id)
                for measure in plan.editableMeasures(for: book) {
                    if case let .quote(quote)? = plan.rule(measure, for: book) {
                        plan.measures[measure] = measure == .spine ? 8 : (quote.typicalMM ?? quote.minMM)
                    }
                }
                let directory = try temporaryDirectory()
                let separate = profile.files.arrangement == .separate
                let output = directory.appendingPathComponent(separate ? "Out" : "Out.pdf")
                try BookPDF.write(book, directory: directory, plan: plan, to: output)
                let interior = separate ? output.appendingPathComponent(profile.files.interiorName) : output
                let pdf = try XCTUnwrap(PDFDocument(url: interior), profile.id)
                let safe = (book.printSettings?.safeMM ?? 0) * points
                var found = false
                for index in 0..<pdf.pageCount {
                    guard let page = pdf.page(at: index), page.string?.contains("Margin check") == true,
                          let cg = page.pageRef else { continue }
                    let trim = cg.getBoxRect(.trimBox)
                    for line in (page.selection(for: page.bounds(for: .mediaBox))?.selectionsByLine() ?? []) {
                        let bounds = line.bounds(for: page)
                        guard !bounds.isEmpty, line.string?.contains("Margin") == true || line.string?.contains("line") == true
                        else { continue }
                        let context = "\(profile.id) \(size.id) page \(index)"
                        XCTAssertGreaterThanOrEqual(bounds.minY - trim.minY, safe - 1, context + " bottom")
                        XCTAssertGreaterThanOrEqual(trim.maxY - bounds.maxY, safe - 1, context + " top")
                        XCTAssertGreaterThanOrEqual(bounds.minX - trim.minX, safe - 1, context + " left")
                        XCTAssertGreaterThanOrEqual(trim.maxX - bounds.maxX, safe - 1, context + " right")
                        found = true
                    }
                }
                XCTAssertTrue(found, "\(profile.id) \(size.id) has text to check")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 10)
    }
}
