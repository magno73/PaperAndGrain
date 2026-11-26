import XCTest
@testable import PaperAndGrain

final class PrintGuidesTests: XCTestCase {
    private let mm = PrintGuides.pointsPerMM
    private var settings: PrintSettings { PrintSettings(bleedMM: 3, safeMM: 10) }

    private func guides() -> PrintGuides {
        PrintGuides.frames(pageSize: CGSize(width: 210 * mm, height: 210 * mm), settings: settings)
    }

    func testFramesAt210By210WithThreeBleedAndTenSafe() {
        let g = guides()
        XCTAssertEqual(g.trim, CGRect(x: 0, y: 0, width: 210 * mm, height: 210 * mm))
        XCTAssertEqual(g.safe.minX, 10 * mm, accuracy: 0.001)
        XCTAssertEqual(g.safe.width, 190 * mm, accuracy: 0.001)
        XCTAssertEqual(g.safe.height, 190 * mm, accuracy: 0.001)
        XCTAssertEqual(g.bleed.minX, -3 * mm, accuracy: 0.001)
        XCTAssertEqual(g.bleed.width, 216 * mm, accuracy: 0.001)
        XCTAssertTrue(g.zones.isEmpty)
        let hinge = PrintGuides.Zone(kind: .hinge, rect: CGRect(x: 0, y: 0, width: 10, height: 10))
        let extra = PrintGuides.frames(pageSize: g.trim.size, settings: settings, zones: [hinge])
        XCTAssertEqual(extra.zones, [hinge])
    }

    func testPhotoEdgeNearTheTrim() {
        let g = guides()
        func frame(insetMM: Double) -> CGRect {
            CGRect(x: insetMM * mm, y: -5, width: 100 * mm, height: 100 * mm)
        }
        XCTAssertTrue(g.edgesNearTrim(of: frame(insetMM: 0)).isEmpty, "on the trim")
        XCTAssertTrue(g.edgesNearTrim(of: frame(insetMM: -2)).isEmpty, "bleeding")
        XCTAssertTrue(g.edgesNearTrim(of: frame(insetMM: 0.2)).isEmpty, "within the tolerance")
        let near = g.edgesNearTrim(of: frame(insetMM: 1.5))
        XCTAssertEqual(near.map(\.edge), [.left])
        XCTAssertEqual(near[0].distanceMM, 1.5, accuracy: 0.001)
        XCTAssertTrue(g.edgesNearTrim(of: frame(insetMM: 5)).isEmpty, "safely inside")
        XCTAssertTrue(g.edgesNearTrim(of: frame(insetMM: 1.5), ignoring: [.left]).isEmpty, "binding edge")
    }

    func testSafeLine() {
        let g = guides()
        XCTAssertTrue(g.keepsInsideSafe(g.safe))
        XCTAssertFalse(g.keepsInsideSafe(g.safe.insetBy(dx: -1, dy: 0)))
        XCTAssertFalse(g.keepsInsideSafe(CGRect(x: 0, y: 50, width: 100, height: 20)))
    }

    // MARK: Warnings

    private func book(photoFrame: PageRect? = nil, boxFrame: PageRect? = nil, safeMM: Double = 10) -> Book {
        let photo = BookPhoto(name: "wide.jpg", filename: "wide.jpg", pixelWidth: 8000, pixelHeight: 8000)
        var page = BookPage(layout: .gallery, photoIDs: [photo.id])
        if let photoFrame { page.photoPlacements = [photo.id: PhotoPlacement(frame: photoFrame)] }
        if let boxFrame { page.textBoxes = [PageTextBox(text: "Hello", frame: boxFrame)] }
        var book = Book(title: "Guides", photos: [photo], pages: [page])
        book.printSettings = PrintSettings(bleedMM: 3, safeMM: safeMM, targetPPI: 300)
        return book
    }

    private func kinds(_ book: Book) -> [String] {
        BookPDF.preflight(book, directory: nil, profile: .print).warnings.map(\.problem.kind)
    }

    func testPhotoNearEdgeWarning() throws {
        let w = 210.0
        func photo(left mm: Double) -> Book {
            // Right edge beyond the page: only the left edge can be near the trim.
            book(photoFrame: PageRect(x: mm / w, y: 0.2, width: 1, height: 0.5))
        }
        XCTAssertFalse(kinds(photo(left: 0)).contains("photoNearEdge"))
        XCTAssertFalse(kinds(photo(left: 5)).contains("photoNearEdge"))
        let near = photo(left: 1.5)
        let issues = BookPDF.preflight(near, directory: nil, profile: .print).warnings
            .filter { $0.problem.kind == "photoNearEdge" }
        let issue = try XCTUnwrap(issues.first)
        XCTAssertEqual(issues.count, 1)
        guard case let .photoNearEdge(name, distance) = issue.problem else { return XCTFail() }
        XCTAssertEqual(name, "wide.jpg")
        XCTAssertEqual(distance, 1.5, accuracy: 0.05)
        XCTAssertEqual(issue.pageID, near.pages[0].id)
        let message = issue.message(language: "en")
        XCTAssertTrue(message.contains("1.5 mm"), message)
        XCTAssertTrue(message.contains("wide.jpg"), message)
    }

    func testTextOutsideTheSafeMarginWarning() {
        let inside = PageRect(x: 0.1, y: 0.1, width: 0.3, height: 0.1)
        let crossing = PageRect(x: 0.02, y: 0.1, width: 0.3, height: 0.1)
        XCTAssertFalse(kinds(book(boxFrame: inside)).contains("textOutsideSafeMargin"))
        XCTAssertTrue(kinds(book(boxFrame: crossing)).contains("textOutsideSafeMargin"))
        // The same box is fine when the safe margin shrinks, and a larger margin makes `inside` cross it.
        XCTAssertFalse(kinds(book(boxFrame: crossing, safeMM: 3)).contains("textOutsideSafeMargin"))
        XCTAssertTrue(kinds(book(boxFrame: inside, safeMM: 30)).contains("textOutsideSafeMargin"))
    }

    func testStandardPagesOfEveryTemplateRaiseNoGuideWarnings() {
        for template in BookTemplate.allCases {
            for arrangement in PageArrangement.allCases {
                let photo = BookPhoto(name: "p.jpg", filename: "p.jpg", pixelWidth: 8000, pixelHeight: 6000)
                var page = BookPage(layout: arrangement.layout, photoIDs: [photo.id, photo.id, photo.id, photo.id],
                                    text: "Un racconto breve.", heading: "Titolo")
                page.arrangement = arrangement
                var book = Book(title: "T", photos: [photo], pages: [page])
                book.template = template
                book.printSettings = PrintSettings(bleedMM: 3, safeMM: 10, targetPPI: 300)
                let found = kinds(book).filter { $0 == "photoNearEdge" || $0 == "textOutsideSafeMargin" }
                XCTAssertTrue(found.isEmpty, "\(template) \(arrangement): \(found)")
            }
        }
    }

    func testWarningIdsAreStableAndTheViewingProfileSkipsThem() {
        let b = book(photoFrame: PageRect(x: 0.007, y: 0.2, width: 1, height: 0.5),
                     boxFrame: PageRect(x: 0.02, y: 0.1, width: 0.3, height: 0.1))
        let first = BookPDF.preflight(b, directory: nil, profile: .print).warnings.map(\.id)
        XCTAssertEqual(first, BookPDF.preflight(b, directory: nil, profile: .print).warnings.map(\.id))
        XCTAssertEqual(Set(first).count, first.count)
        XCTAssertTrue(BookPDF.preflight(b, directory: nil, profile: .proof).isClean)
    }

    func testBindingEdgeOfASinglePageDoesNotWarn() {
        // Page 1 sits on the left (firstPageOnRight is off): its right edge is the binding edge.
        var b = book(photoFrame: PageRect(x: -1, y: 0.2, width: 1 + (210 - 1.5) / 210, height: 0.5))
        XCTAssertFalse(kinds(b).contains("photoNearEdge"))
        b.printSettings?.firstPageOnRight = true
        XCTAssertTrue(kinds(b).contains("photoNearEdge"))
    }
}
