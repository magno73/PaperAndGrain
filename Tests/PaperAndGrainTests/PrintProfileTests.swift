import CoreGraphics
import XCTest
@testable import PaperAndGrain

/// The print-service catalog: every entry is valid, and every entry renders the boxes it describes. The
/// test-only entries in `Tests/Fixtures/PrintProfiles` are plain JSON: a new printer needs no Swift change.
final class PrintProfileTests: XCTestCase {
    private let points = 72.0 / 25.4

    private var fixtures: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/PrintProfiles", isDirectory: true)
    }

    private var repositoryCatalog: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/PrintProfiles", isDirectory: true)
    }

    private func allProfiles() throws -> [PrintProfile] {
        try PrintProfileCatalog.load(from: repositoryCatalog).profiles + PrintProfileCatalog.load(from: fixtures).profiles
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("print-profile-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    // MARK: Catalog rules

    func testEveryEntryDecodesAndFollowsTheCatalogRules() throws {
        let bundled = try PrintProfileCatalog.load(from: repositoryCatalog)
        XCTAssertNotNil(bundled.profile(PrintProfileCatalog.pixartID))
        XCTAssertEqual(PrintProfileCatalog.bundled.profiles.map(\.id), bundled.profiles.map(\.id))
        let profiles = try allProfiles()
        XCTAssertEqual(Set(profiles.map(\.id)).count, profiles.count, "ids are unique")
        for profile in profiles {
            XCTAssertEqual(profile.problems, [], profile.id)
            XCTAssertEqual(profile.sourceURL.scheme, "https", profile.id)
            XCTAssertNotNil(profile.verifiedDate, profile.id)
            var lengths = profile.interior.bleed.fixedValues.all + profile.interior.safe.fixedValues.all
            for size in profile.sizes {
                XCTAssertGreaterThan(size.format.widthMM, 0)
                XCTAssertGreaterThan(size.format.heightMM, 0)
                XCTAssertTrue(size.matches(size.format), "\(profile.id) \(size.id)")
                let cover = profile.coverRules(for: size)
                lengths += (cover.bleed?.fixedValues.all ?? []) + [cover.panel?.widthMM.nominal, cover.panel?.heightMM.nominal,
                                                                  cover.safe?.mm].compactMap { $0 }
            }
            for length in lengths { XCTAssertTrue(length.isFinite && length >= 0, profile.id) }
            // Encoding and decoding again gives the same entry.
            let data = try JSONEncoder().encode(profile)
            XCTAssertEqual(try JSONDecoder().decode(PrintProfile.self, from: data), profile, profile.id)
        }
    }

    func testBrokenEntriesAreRefusedWithTheFileAndTheReason() throws {
        let directory = try temporaryDirectory()
        let source = try String(contentsOf: fixtures.appendingPathComponent("test-trimonly.json"), encoding: .utf8)
        let cases = [
            ("http.json", source.replacingOccurrences(of: "https://", with: "http://"), "https"),
            ("date.json", source.replacingOccurrences(of: "2026-11-26", with: "2026-13-40"), "verifiedOn"),
            ("bleed.json", source.replacingOccurrences(of: "\"bleed\": 0", with: "\"bleed\": -1"), "interior.bleed"),
            ("missing.json", source.replacingOccurrences(of: "\"firstPage\": \"right\",", with: ""), "firstPage"),
        ]
        for (name, text, reason) in cases {
            let folder = directory.appendingPathComponent(name + "-dir")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try text.write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
            XCTAssertThrowsError(try PrintProfileCatalog.load(from: folder)) { error in
                let message = error.localizedDescription
                XCTAssertTrue(message.contains(name) && message.contains(reason), message)
            }
        }
        let twice = directory.appendingPathComponent("twice")
        try FileManager.default.createDirectory(at: twice, withIntermediateDirectories: true)
        for name in ["a.json", "b.json"] { try source.write(to: twice.appendingPathComponent(name), atomically: true, encoding: .utf8) }
        XCTAssertThrowsError(try PrintProfileCatalog.load(from: twice)) { error in
            XCTAssertTrue(error.localizedDescription.contains("Duplicate profile id test-trimonly"))
        }
    }

    // MARK: Measures and rules

    func testMeasuresComeFromTablesFormulasQuotesAndTheAuthor() throws {
        let catalog = try PrintProfileCatalog.load(from: fixtures)
        let wrap = try XCTUnwrap(catalog.profile("test-imagewrap"))
        var book = Book(title: "T", format: wrap.sizes[0].format, pages: [BookPage(layout: .text)])
        book.cover = BookCover(title: "T")
        var plan = PrintPlan(profile: wrap)
        XCTAssertEqual(plan.paper?.id, "premium", "the first paper is the default")
        XCTAssertEqual(plan.value(.spine, for: book, interiorPages: 20), 11.64)
        XCTAssertEqual(plan.value(.spine, for: book, interiorPages: 41), 27.87)
        XCTAssertNil(plan.value(.spine, for: book, interiorPages: 300), "outside the table")
        plan.paperID = "standard"
        XCTAssertEqual(plan.value(.spine, for: book, interiorPages: 41), 11.64)
        XCTAssertEqual(plan.value(.hinge, for: book, interiorPages: 41), 5)
        plan.measures.spineMM = 30
        XCTAssertEqual(plan.value(.spine, for: book, interiorPages: 41), 30, "the author's value wins")

        let spreads = try XCTUnwrap(catalog.profile("test-spreads"))
        let layflat = PrintPlan(profile: spreads)
        book.format = spreads.sizes[0].format
        XCTAssertEqual(try XCTUnwrap(layflat.value(.spine, for: book, interiorPages: 100)), 1.524 + 5.72, accuracy: 1e-9)
        XCTAssertEqual(layflat.value(.hinge, for: book, interiorPages: 26), 8.975)
        XCTAssertEqual(layflat.value(.hinge, for: book, interiorPages: 27), 17.018)
        XCTAssertEqual(layflat.value(.wrap, for: book, interiorPages: 27), 0)

        // A spine from the quote: the cover's saved width, then the sheet's typed value; out of range is missing.
        var pixart = PrintPlan.pixart()
        book.format = .square
        XCTAssertNil(pixart.value(.spine, for: book, interiorPages: 10))
        book.cover?.spineMM = 9
        XCTAssertEqual(pixart.value(.spine, for: book, interiorPages: 10), 9)
        pixart.measures.spineMM = 12
        XCTAssertEqual(pixart.value(.spine, for: book, interiorPages: 10), 12)
        pixart.measures.spineMM = 140
        XCTAssertEqual(pixart.value(.spine, for: book, interiorPages: 10), 9)
        XCTAssertEqual(pixart.value(.hinge, for: book, interiorPages: 10), 11)
        XCTAssertEqual(pixart.value(.wrap, for: book, interiorPages: 10), 19)
    }

    func testProductIssuesNameSizePageCountAndMissingSpine() throws {
        let catalog = try PrintProfileCatalog.load(from: fixtures)
        let trim = try XCTUnwrap(catalog.profile("test-trimonly"))
        var book = Book(title: "T", format: BookFormat(widthMM: 200, heightMM: 200),
                        pages: (0..<9).map { _ in BookPage(layout: .text, text: "x") })
        var report = BookPDF.preflight(book, directory: nil, profile: .service(PrintPlan(profile: trim)))
        XCTAssertTrue(report.blockers.contains { if case .sizeNotOffered = $0.problem { true } else { false } })
        let sizeMessage = try XCTUnwrap(report.blockers.first { $0.id.hasPrefix("sizeNotOffered") }).message(language: "en")
        XCTAssertTrue(sizeMessage.contains("20 × 20 cm") && sizeMessage.contains("Sizes: 21 × 21 cm, 29.7 × 21 cm"), sizeMessage)
        book.format = trim.sizes[0].format
        report = BookPDF.preflight(book, directory: nil, profile: .service(PrintPlan(profile: trim)))
        XCTAssertEqual(report.blockers, [])
        // 9 pages, one blank so page 1 is on the left of a right-first product: 10 interior + 2 cover pages.
        let messages = report.warnings.map { $0.message(language: "en") }
        XCTAssertTrue(messages.contains("Needs at least 24 pages; the printer counts 12 (9 in the book)"), "\(messages)")

        let wrap = try XCTUnwrap(catalog.profile("test-imagewrap"))
        book.format = wrap.sizes[1].format
        book.cover = BookCover(title: "T")
        // This entry takes CMYK only: the book writes CMYK, so the color mode is not among the blockers.
        book.printSettings = PrintSettings()
        book.printSettings?.colorOutput = .cmyk(ICCProfileReference(id: "test", name: "Test CMYK", filename: "t.icc", sha256: "0"))
        book.pages = (0..<241).map { _ in BookPage(layout: .text, text: "x") }
        report = BookPDF.preflight(book, directory: nil, profile: .service(PrintPlan(profile: wrap)))
        let warnings = report.warnings.map { $0.message(language: "en") }
        XCTAssertTrue(warnings.contains("Takes at most 200 pages; the printer counts 242 (241 in the book)"), "\(warnings)")
        XCTAssertEqual(report.blockers.map(\.problem), [.missingMeasure(.spine, tableLimit: 240)], "beyond the spine table")
        XCTAssertEqual(report.blockers.first?.message(language: "en"),
                       "Cover · Spine width: the printer’s table stops at 240 pages. Enter the value from the quote")
        // An odd count is padded with a trailing blank to the product's step, so no page-count warning.
        book.pages.removeLast(43)
        report = BookPDF.preflight(book, directory: nil, profile: .service(PrintPlan(profile: wrap)))
        XCTAssertEqual(BookPDF.interiorPageCount(book, plan: PrintPlan(profile: wrap)), 200)
        XCTAssertFalse(report.warnings.contains { $0.problem.kind.hasPrefix("pageCount") }, "\(report.warnings)")
        XCTAssertTrue(report.warnings.contains { $0.problem == .blankPages([1, 200]) }, "\(report.warnings)")
        XCTAssertEqual(report.blockers, [])
        // Page limits per paper: the standard paper takes at most 120 pages.
        report = BookPDF.preflight(book, directory: nil, profile: .service(PrintPlan(profile: wrap, paperID: "standard")))
        XCTAssertTrue(report.warnings.contains {
            $0.message(language: "en") == "Takes at most 120 pages; the printer counts 200 (198 in the book)"
        }, "\(report.warnings.map { $0.message(language: "en") })")
    }

    func testTheBookChoosesItsProfileAndOlderBooksStayGeneric() throws {
        // A 0.10 manifest has none of the profile fields.
        let old = #"{"bleedMM":3,"safeMM":10,"targetPPI":300,"spreads":false}"#
        let settings = try JSONDecoder().decode(PrintSettings.self, from: Data(old.utf8))
        XCTAssertNil(settings.profileID)
        XCTAssertNil(settings.profileSizeID)
        XCTAssertNil(settings.profilePaperID)
        XCTAssertNil(settings.profileMeasures)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(settings), as: UTF8.self).contains("profile"))
        var book = Book(title: "Old", pages: [BookPage(layout: .text)])
        book.printSettings = settings
        XCTAssertNil(PrintPlan(book: book))
        XCTAssertEqual(BookPDF.preflight(book, directory: nil, profile: .print),
                       BookPDF.preflight(book, directory: nil, profile: .print))
        book.printSettings?.profileID = PrintProfileCatalog.pixartID
        book.printSettings?.profileMeasures = PrintMeasures(spineMM: 6)
        let plan = try XCTUnwrap(PrintPlan(book: book))
        XCTAssertEqual(plan.profile.id, PrintProfileCatalog.pixartID)
        XCTAssertEqual(plan.size(for: book)?.id, "21x21")
        XCTAssertEqual(plan.value(.spine, for: book, interiorPages: 2), 6)
        book.printSettings?.profileID = "no-such-printer"
        XCTAssertNil(PrintPlan(book: book), "an unknown profile falls back to generic print")
        let round = try JSONDecoder().decode(Book.self, from: JSONEncoder().encode(book))
        XCTAssertEqual(round.printSettings, book.printSettings)
    }

    func testPixartZonesForTheGuides() {
        var book = Book(title: "T", pages: [BookPage(layout: .text)])
        book.cover = BookCover(spineMM: 7)
        let zones = PrintPlan.pixart().zones(for: book, interiorPages: 2)
        XCTAssertEqual(zones.safe.inner, 15)
        XCTAssertEqual(zones.safe.outer, 5)
        XCTAssertEqual(zones.bleed.inner, 3)
        XCTAssertEqual(zones.coverHingeMM, 11)
        // The binding strip for T2's guides: on the left of a right page, 15 mm wide, none on a spread.
        let size = CGSize(width: 595.276, height: 595.276)
        let right = PrintPlan.pixart().guideZones(pageSize: size, onRight: true, spread: false, safeMM: 5)
        XCTAssertEqual(right.map(\.kind), [.innerMargin])
        XCTAssertEqual(right.first?.rect.minX, 0)
        XCTAssertEqual(try XCTUnwrap(right.first?.rect.width), 15 * points, accuracy: 0.001)
        let left = PrintPlan.pixart().guideZones(pageSize: size, onRight: false, spread: false, safeMM: 5)
        XCTAssertEqual(try XCTUnwrap(left.first?.rect.maxX), size.width, accuracy: 0.001)
        XCTAssertEqual(PrintPlan.pixart().guideZones(pageSize: size, onRight: true, spread: true, safeMM: 5), [])
        XCTAssertEqual(PrintPlan.pixart().guideZones(pageSize: size, onRight: true, spread: false, safeMM: 20), [])
    }

    // MARK: Rendering every entry

    /// Renders a short synthetic book at every size of every entry and checks the media, trim and bleed
    /// boxes of each PDF page against the entry.
    func testEveryEntryRendersTheBoxesItDescribes() throws {
        var checked = 0
        let profiles = try allProfiles()
        for profile in profiles {
            for size in profile.sizes {
                checked += 1
                let directory = try temporaryDirectory()
                var book = Book(title: "Boxes", format: size.format,
                                pages: [BookPage(layout: .text, text: "First"), BookPage(layout: .fullSpread),
                                        BookPage(layout: .text, text: "Last")])
                book.cover = BookCover(title: "Boxes", spineMM: 8)
                var plan = PrintPlan(profile: profile, sizeID: size.id)
                // Measures given per order get their typical value, as an author would type it.
                for measure in plan.editableMeasures(for: book) {
                    if case let .quote(quote)? = plan.rule(measure, for: book), measure != .spine {
                        plan.measures[measure] = quote.typicalMM ?? quote.minMM
                    }
                }
                let separate = profile.files.arrangement == .separate
                let output = directory.appendingPathComponent(separate ? "Out" : "Out.pdf")
                try BookPDF.write(book, directory: directory, plan: plan, to: output)
                let context = "\(profile.id) \(size.id)"
                let interiorPages = BookPDF.interiorPageCount(book, plan: plan)
                let kind = plan.coverKind(for: book)
                var pages = [CGPDFPage]()
                var coverSheet: CGPDFPage?
                if separate {
                    let names = try FileManager.default.contentsOfDirectory(atPath: output.path).sorted()
                    XCTAssertEqual(names, ([profile.files.interiorName] + (kind == .flat ? [profile.files.coverName] : [])).sorted(),
                                   context)
                    let interior = try XCTUnwrap(CGPDFDocument(output.appendingPathComponent(profile.files.interiorName) as CFURL))
                    pages = (1...interior.numberOfPages).compactMap { interior.page(at: $0) }
                    if kind == .flat {
                        let cover = try XCTUnwrap(CGPDFDocument(output.appendingPathComponent(profile.files.coverName) as CFURL))
                        XCTAssertEqual(cover.numberOfPages, 1, context)
                        coverSheet = cover.page(at: 1)
                    }
                } else {
                    let document = try XCTUnwrap(CGPDFDocument(output as CFURL))
                    pages = (1...document.numberOfPages).compactMap { document.page(at: $0) }
                    if kind == .flat { coverSheet = pages.removeFirst() }
                }
                if let coverSheet {
                    let rules = plan.coverRules(for: book)
                    let hinge = try XCTUnwrap(plan.value(.hinge, for: book, interiorPages: interiorPages))
                    let panelW = try XCTUnwrap(plan.value(.panelWidth, for: book, interiorPages: interiorPages))
                        - (rules.hingeWithinPanel == true ? hinge : 0)
                    let panelH = try XCTUnwrap(plan.value(.panelHeight, for: book, interiorPages: interiorPages))
                    let spine = try XCTUnwrap(plan.value(.spine, for: book, interiorPages: interiorPages))
                    let wrap = try XCTUnwrap(plan.value(.wrap, for: book, interiorPages: interiorPages))
                    let bleed = try XCTUnwrap(plan.coverBleed(for: book))
                    check(coverSheet, trimWidth: 2 * (panelW + hinge) + spine, trimHeight: panelH,
                          left: wrap + bleed.outer, right: wrap + bleed.outer,
                          top: wrap + bleed.top, bottom: wrap + bleed.bottom, context + " cover")
                }
                let bleed = try XCTUnwrap(plan.interiorBleed(for: book), context)
                let trimW = book.format.widthMM, trimH = book.format.heightMM
                if kind == .interiorPages {
                    let front = pages.removeFirst(), back = pages.removeLast()
                    check(front, trimWidth: trimW, trimHeight: trimH, left: bleed.inner,
                          right: bleed.outer, top: bleed.top, bottom: bleed.bottom, context + " front")
                    check(back, trimWidth: trimW, trimHeight: trimH, left: bleed.outer,
                          right: bleed.inner, top: bleed.top, bottom: bleed.bottom, context + " back")
                }
                let spread = profile.interior.layout == .spread
                XCTAssertEqual(pages.count, spread ? interiorPages / 2 : interiorPages, context)
                for (index, page) in pages.enumerated() {
                    if spread {
                        check(page, trimWidth: 2 * trimW, trimHeight: trimH, left: bleed.outer,
                              right: bleed.outer, top: bleed.top, bottom: bleed.bottom, context + " spread \(index)")
                    } else {
                        let right = !(index + (profile.interior.firstPage == .right ? 1 : 0)).isMultiple(of: 2)
                        check(page, trimWidth: trimW, trimHeight: trimH,
                              left: right ? bleed.inner : bleed.outer, right: right ? bleed.outer : bleed.inner,
                              top: bleed.top, bottom: bleed.bottom, context + " page \(index)")
                    }
                }
            }
        }
        XCTAssertEqual(checked, profiles.map(\.sizes.count).reduce(0, +))
        XCTAssertGreaterThanOrEqual(checked, 11, "the Pixart size and two sizes of each test-only entry")
    }

    func testABookOfTheWrongSizeOrWithoutSpineIsRefused() throws {
        let directory = try temporaryDirectory()
        var book = Book(title: "T", format: .landscape, pages: [BookPage(layout: .text)])
        book.cover = BookCover(title: "T")
        let output = directory.appendingPathComponent("Out.pdf")
        XCTAssertThrowsError(try BookPDF.write(book, directory: directory, plan: .pixart(spineMM: 5), to: output)) {
            guard case .sizeNotOffered? = $0 as? BookPDF.ExportError else { return XCTFail("\($0)") }
        }
        book.format = .square
        XCTAssertThrowsError(try BookPDF.write(book, directory: directory, plan: .pixart(), to: output)) {
            guard case .missingMeasure(.spine)? = $0 as? BookPDF.ExportError else { return XCTFail("\($0)") }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    private func check(_ page: CGPDFPage, trimWidth: Double, trimHeight: Double, left: Double, right: Double,
                       top: Double, bottom: Double, _ context: String, file: StaticString = #filePath, line: UInt = #line) {
        let media = page.getBoxRect(.mediaBox)
        let trim = page.getBoxRect(.trimBox)
        XCTAssertEqual(page.getBoxRect(.bleedBox), media, context, file: file, line: line)
        XCTAssertEqual(media.minX, 0, accuracy: 0.01, context, file: file, line: line)
        XCTAssertEqual(media.minY, 0, accuracy: 0.01, context, file: file, line: line)
        XCTAssertEqual(media.width, (trimWidth + left + right) * points, accuracy: 0.02, context, file: file, line: line)
        XCTAssertEqual(media.height, (trimHeight + top + bottom) * points, accuracy: 0.02, context, file: file, line: line)
        XCTAssertEqual(trim.minX, left * points, accuracy: 0.02, context, file: file, line: line)
        XCTAssertEqual(trim.minY, bottom * points, accuracy: 0.02, context, file: file, line: line)
        XCTAssertEqual(trim.width, trimWidth * points, accuracy: 0.02, context, file: file, line: line)
        XCTAssertEqual(trim.height, trimHeight * points, accuracy: 0.02, context, file: file, line: line)
    }
}
