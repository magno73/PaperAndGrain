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
        XCTAssertEqual(profile.separateFiles, true)
        let cover = profile.cover
        XCTAssertTrue(cover.panel?.widthMM.isTyped == true && cover.panel?.heightMM.isTyped == true)
        XCTAssertTrue(cover.spine?.isTyped == true && cover.wrap?.isTyped == true && cover.hinge?.isTyped == true)
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
        XCTAssertEqual(profile.cover.hinge?.nominal ?? 0, 5.08, accuracy: 0.001)
        XCTAssertEqual(profile.cover.bleed?.fixedValues, PrintProfile.EdgeValues(top: 20.32, bottom: 20.32, outer: 20.32, inner: 20.32))
        XCTAssertTrue(profile.cover.spine?.isTyped == true, "the spine is in the cart")
        XCTAssertEqual(profile.separateFiles, true)
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
