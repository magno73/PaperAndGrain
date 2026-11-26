import CoreGraphics
import PDFKit
import XCTest
@testable import PaperAndGrain

/// The rules of the planning research that need more than a fixed length (sizes, boards and bleeds per order, a
/// fold-over inside the board, page limits per paper, endpapers), the binding margin in the safe-margin
/// check, and a catalog that survives a broken file.
final class PrintProfileStructureTests: XCTestCase {
    private let points = 72.0 / 25.4

    private var fixtures: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/PrintProfiles", isDirectory: true)
    }

    private func fixture(_ id: String) throws -> PrintProfile {
        try XCTUnwrap(PrintProfileCatalog.load(from: fixtures).profile(id))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("print-structure-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testAStaleSizeChoiceFallsBackToTheSizeWithTheBooksTrim() throws {
        let trim = try fixture("test-trimonly")
        var book = Book(title: "T", format: BookFormat(widthMM: 210, heightMM: 210), pages: [BookPage(layout: .text)])
        book.printSettings = PrintSettings()
        book.printSettings?.choose(trim, size: trim.size("a4-landscape"))
        let plan = PrintPlan(profile: trim, sizeID: "a4-landscape")
        XCTAssertEqual(plan.size(for: book)?.id, "210x210")
        let report = BookPDF.preflight(book, directory: nil, profile: .service(plan))
        XCTAssertFalse(report.blockers.contains { $0.problem.kind == "sizeNotOffered" })
    }

    func testSizesBoardsHingeWrapAndBleedsGivenPerOrder() throws {
        let order = try fixture("test-perorder")
        var book = Book(title: "T", format: BookFormat(widthMM: 288, heightMM: 291),
                        pages: (0..<28).map { _ in BookPage(layout: .text, text: "x") })
        book.cover = BookCover(title: "T")
        var plan = PrintPlan(profile: order)
        XCTAssertEqual(plan.size(for: book)?.id, "29x29", "any size inside the range is this size")
        XCTAssertEqual(plan.profile.size("29x29")?.format, BookFormat(widthMM: 290, heightMM: 290))
        let pages = BookPDF.interiorPageCount(book, plan: plan)
        XCTAssertEqual(Set(plan.missingMeasures(for: book, interiorPages: pages).map(\.measure)),
                       Set(PrintMeasure.allCases))
        XCTAssertEqual(Set(plan.editableMeasures(for: book)), Set(PrintMeasure.allCases))
        let report = BookPDF.preflight(book, directory: nil, profile: .service(plan))
        XCTAssertTrue(report.blockers.contains { $0.message(language: "en") == "Cover · Board width missing: enter it from the printer’s quote" },
                      "\(report.blockers.map { $0.message(language: "en") })")
        // A quote that starts at 0 accepts 0; the spine excludes it.
        XCTAssertTrue(try XCTUnwrap(plan.rule(.hinge, for: book)).accepts(0))
        XCTAssertFalse(try XCTUnwrap(plan.rule(.spine, for: book)).accepts(0))
        plan.measures = PrintMeasures(spineMM: 12, hingeMM: 0, wrapMM: 15, panelWidthMM: 296, panelHeightMM: 302,
                                      coverBleedMM: 2, interiorBleedMM: 4)
        XCTAssertTrue(plan.missingMeasures(for: book, interiorPages: pages).isEmpty)
        XCTAssertEqual(plan.interiorBleed(for: book), PrintProfile.EdgeValues(top: 4, bottom: 4, outer: 4, inner: 0))
        let directory = try temporaryDirectory()
        let output = directory.appendingPathComponent("Out")
        try BookPDF.write(book, directory: directory, plan: plan, to: output)
        let cover = try XCTUnwrap(CGPDFDocument(output.appendingPathComponent("Cover.pdf") as CFURL)?.page(at: 1))
        XCTAssertEqual(cover.getBoxRect(.trimBox).width, (2 * 296 + 12) * points, accuracy: 0.02)
        XCTAssertEqual(cover.getBoxRect(.mediaBox).height, (302 + 2 * 17) * points, accuracy: 0.02)
        let interior = try XCTUnwrap(CGPDFDocument(output.appendingPathComponent("Interior.pdf") as CFURL))
        // 28 pages, one blank so page 1 stays on the left of a right-first product, three more to a step of 4.
        XCTAssertEqual(interior.numberOfPages, 32)
        let first = try XCTUnwrap(interior.page(at: 1))
        XCTAssertEqual(first.getBoxRect(.mediaBox).width, (288 + 4) * points, accuracy: 0.02, "no bleed at the binding")
    }

    func testAFoldOverInsideTheBoardKeepsTheOuterWidthAndTheHingeZone() throws {
        let spreads = try fixture("test-spreads")
        let plan = PrintPlan(profile: spreads)
        var book = Book(title: "T", format: BookFormat(widthMM: 210, heightMM: 280), pages: [])
        book.cover = BookCover(title: "T")
        func coverWidth(pages: Int) throws -> (trim: CGFloat, hinge: Double?) {
            book.pages = (0..<pages).map { _ in BookPage(layout: .text, text: "x") }
            let directory = try temporaryDirectory()
            let output = directory.appendingPathComponent("Out")
            try BookPDF.write(book, directory: directory, plan: plan, to: output)
            let cover = try XCTUnwrap(CGPDFDocument(output.appendingPathComponent("Cover.pdf") as CFURL)?.page(at: 1))
            let interior = BookPDF.interiorPageCount(book, plan: plan)
            return (cover.getBoxRect(.trimBox).width, plan.zones(for: book, interiorPages: interior).coverHingeMM)
        }
        let thin = try coverWidth(pages: 26)
        let thick = try coverWidth(pages: 100)
        let spineDifference = (plan.value(.spine, for: book, interiorPages: 100)! - plan.value(.spine, for: book, interiorPages: 26)!)
        XCTAssertEqual(thick.trim - thin.trim, spineDifference * points, accuracy: 0.02, "only the spine grows")
        XCTAssertEqual(thin.hinge, 8.975)
        XCTAssertEqual(thick.hinge, 17.018)
    }

    func testEndpapersArePrintedBlank() throws {
        let profile = try fixture("test-endpapers")
        let directory = try temporaryDirectory()
        for right in [false, true] {
            var book = Book(title: "T", pages: ["Alfa", "Beta", "Gamma"].map { BookPage(layout: .text, text: $0) })
            book.printSettings = PrintSettings(firstPageOnRight: right)
            let output = directory.appendingPathComponent("Out-\(right).pdf")
            try BookPDF.write(book, directory: directory, plan: PrintPlan(profile: profile), to: output)
            let pdf = try XCTUnwrap(PDFDocument(url: output))
            let texts = (0..<pdf.pageCount).map { pdf.page(at: $0)?.string ?? "" }
            XCTAssertEqual(texts.first?.trimmingCharacters(in: .whitespacesAndNewlines), "", "\(texts)")
            XCTAssertEqual(texts.last?.trimmingCharacters(in: .whitespacesAndNewlines), "", "\(texts)")
            XCTAssertTrue(pdf.pageCount.isMultiple(of: 2))
            // The first PDF page is a right page: Alfa stays on its side, the left (odd index) or the right.
            let alfa = try XCTUnwrap(texts.firstIndex { $0.contains("Alfa") })
            XCTAssertEqual(alfa.isMultiple(of: 2), right, "\(texts)")
        }
    }

    func testTextNearTheBindingIsCheckedAgainstTheProductsInnerMargin() throws {
        // Page 1 is a left page: its binding is the right edge. The box ends 7 mm from it, 20 mm from the outer edge.
        func book(_ format: BookFormat) -> Book {
            let box = PageTextBox(text: "Near the binding",
                                  frame: PageRect(x: 20 / format.widthMM, y: 0.3, width: 1 - 27 / format.widthMM, height: 0.1))
            var book = Book(title: "T", format: format, pages: [BookPage(layout: .text, textBoxes: [box])])
            book.printSettings = PrintSettings(bleedMM: 3, safeMM: 5)
            return book
        }
        func flagged(_ book: Book, _ profile: BookPDF.Profile) -> Bool {
            BookPDF.preflight(book, directory: nil, profile: profile).warnings.contains { $0.problem.kind == "textOutsideSafeMargin" }
        }
        let square = book(.square)
        XCTAssertFalse(flagged(square, .print), "7 mm is inside a 5 mm safe margin")
        XCTAssertTrue(flagged(square, .service(.pixart(spineMM: 5))), "Pixartprinting keeps text 15 mm from the binding")
        let blurb = try fixture("test-imagewrap")
        let landscape = book(BookFormat(widthMM: 241.3, heightMM: 203.2))
        XCTAssertTrue(flagged(landscape, .service(PrintPlan(profile: blurb))), "45 pt from the binding")
        // The same box mirrored on the outer side is fine.
        var outer = square
        outer.pages[0].textBoxes?[0].frame.x = 7 / 210
        outer.pages[0].textBoxes?[0].frame.width = 1 - 27 / 210
        XCTAssertFalse(flagged(outer, .service(.pixart(spineMM: 5))))
        // The guides draw the dashed line where the check falls.
        let zones = PrintPlan.pixart().guideZones(pageSize: CGSize(width: 595.276, height: 595.276), onRight: false,
                                                  spread: false, safeMM: 5)
        let guides = PrintGuides.frames(pageSize: CGSize(width: 595.276, height: 595.276), settings: PrintSettings(safeMM: 5),
                                        zones: zones)
        XCTAssertEqual(guides.textSafe.maxX, 595.276 - 15 * points, accuracy: 0.01)
        XCTAssertEqual(guides.textSafe.minX, 5 * points, accuracy: 0.01)
        XCTAssertEqual(BookPDF.rightPageIDs(square), [])
    }

    func testOneBrokenFileLeavesTheRestOfTheCatalog() throws {
        let directory = try temporaryDirectory()
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/PrintProfiles/pixartprinting.json")
        try FileManager.default.copyItem(at: repository, to: directory.appendingPathComponent("a-pixart.json"))
        try Data("{ not json".utf8).write(to: directory.appendingPathComponent("b-broken.json"))
        let partial = #"{"id":"x","service":"X","product":"X","binding":"softcover","regions":[],"sourceURL":"https://x.example","#
            + #""verifiedOn":"2026-11-26","interior":{"layout":"single","bleed":{"top":3,"bottom":3},"safe":5,"#
            + #""firstPage":"right","pages":{}},"cover":{},"files":{"arrangement":"single"},"color":{"accepts":["srgb"]},"#
            + #""sizes":[{"id":"a","widthMM":100,"heightMM":100}]}"#
        try Data(partial.utf8).write(to: directory.appendingPathComponent("c-partial.json"))
        try Data(#"[{"id":"y"}]"#.utf8).write(to: directory.appendingPathComponent("d-array.json"))
        let catalog = try PrintProfileCatalog.read(directory)
        XCTAssertEqual(catalog.profiles.map(\.id), [PrintProfileCatalog.pixartID])
        XCTAssertEqual(catalog.skipped.map(\.file), ["b-broken.json", "c-partial.json", "d-array.json"])
        let partialReason = try XCTUnwrap(catalog.skipped.first { $0.file == "c-partial.json" }?.reason)
        XCTAssertTrue(partialReason.contains("interior.bleed") && partialReason.contains("missing: outer, inner"), partialReason)
        let arrayReason = try XCTUnwrap(catalog.skipped.first { $0.file == "d-array.json" }?.reason)
        XCTAssertTrue(arrayReason.hasPrefix("[0]"), arrayReason)
        XCTAssertThrowsError(try PrintProfileCatalog.load(from: directory))
    }

    @MainActor
    func testMeasuresTypedAtExportAreKeptAsOneUndoStep() async throws {
        let directory = try temporaryDirectory()
        let package = directory.appendingPathComponent("Book.papergrain", isDirectory: true)
        var book = Book(title: "T", pages: [BookPage(layout: .text)])
        book.printSettings = PrintSettings()
        book.printSettings?.choose(try fixture("test-perorder"), size: nil)
        try BookStorage.write(book, to: package)
        let workspace = Workspace(defaults: DocumentReleaseTests.MemoryDefaults())
        await workspace.openProject(at: package).value
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        workspace.savePrintMeasures(PrintMeasures(hingeMM: 4, wrapMM: 0), undoManager: undo, actionName: "Measures")
        undo.endUndoGrouping()
        XCTAssertEqual(workspace.book.printSettings?.profileMeasures, PrintMeasures(hingeMM: 4, wrapMM: 0))
        undo.undo()
        XCTAssertNil(workspace.book.printSettings?.profileMeasures)
    }
}
