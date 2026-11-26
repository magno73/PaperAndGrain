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
