import CoreGraphics
import Foundation
import PDFKit
import XCTest
@testable import PaperAndGrain

final class CaptionTests: XCTestCase {
    private let templates: [BookTemplate?] = BookTemplate.allCases.map(Optional.some) + [nil]

    private func photos(_ count: Int, captions: [String?] = []) -> [BookPhoto] {
        (0..<count).map { index in
            var photo = BookPhoto(name: "Photo \(index)", filename: "photo-\(index).jpg",
                                  pixelWidth: index == 1 ? 400 : 600, pixelHeight: index == 1 ? 600 : 400)
            photo.caption = index < captions.count ? captions[index] : nil
            return photo
        }
    }

    private func frames(_ composition: PageComposition) -> [CGRect] { composition.photos.map(\.frame) }

    // MARK: Saved books

    func testABookWithoutCaptionsEncodesAndDecodesAsBefore() throws {
        // A 0.10 manifest has none of the new fields.
        let id = UUID(), photoID = UUID(), pageID = UUID()
        let manifest = """
        {"id":"\(id)","title":"Old","format":{"widthMM":210,"heightMM":210},"schemaVersion":1,
         "photos":[{"id":"\(photoID)","name":"a","filename":"a.jpg","pixelWidth":600,"pixelHeight":400}],
         "pages":[{"id":"\(pageID)","layout":"gallery","photoIDs":["\(photoID)"],"text":"",
                   "photoPlacements":["\(photoID)",{"crop":{"x":0.2,"y":0.5,"zoom":1.5}}]}],
         "typography":{"body":{"pointSize":12}}}
        """
        let book = try JSONDecoder().decode(Book.self, from: Data(manifest.utf8))
        XCTAssertNil(book.photos[0].caption)
        XCTAssertNil(book.pages[0].photoPlacements?[photoID]?.captionPosition)
        XCTAssertNil(book.typography?.caption)
        let encoded = try XCTUnwrap(String(data: JSONEncoder().encode(book), encoding: .utf8))
        XCTAssertFalse(encoded.contains("caption"), "nil caption fields must not be written")
        XCTAssertTrue(PageComposition(page: book.pages[0], book: book).captions.isEmpty)
    }

    func testPagesWithoutPrintedCaptionsKeepTheirGeometry() {
        let pages: [(BookPage, Int)] = [
            (BookPage(), 3), (BookPage(), 5), (BookPage(layout: .mixed, text: "Story"), 2),
            (BookPage(layout: .fullPage), 1), (BookPage(layout: .fullSpread), 1),
        ] + PageArrangement.allCases.map { (BookPage(layout: $0.layout, arrangement: $0), max(1, $0.photoCapacity)) }
        for template in templates {
            for (page, count) in pages {
                let plain = photos(count)
                var page = page
                page.photoIDs = plain.map(\.id)
                let book = Book(title: "T", photos: plain, template: template)
                let reference = PageComposition(page: page, book: book)
                for variant in ["", "  \n ", "Hidden caption"] {
                    var captioned = book
                    captioned.photos = plain.map { var photo = $0; photo.caption = variant; return photo }
                    var hiddenPage = page
                    if !variant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        hiddenPage.photoPlacements = Dictionary(uniqueKeysWithValues: plain.map {
                            ($0.id, PhotoPlacement(captionPosition: .hidden))
                        })
                    }
                    let composition = PageComposition(page: hiddenPage, book: captioned)
                    XCTAssertEqual(frames(composition), frames(reference), "\(String(describing: template)) \(page.effectiveLayout)")
                    XCTAssertTrue(composition.captions.isEmpty)
                    XCTAssertEqual(composition.captionBand, 0)
                }
            }
        }
    }

    // MARK: Layout

    func testGalleryOfThreeWithOneCaptionGivesUpACommonBand() throws {
        for template in [nil, BookTemplate.swissGrid, .kodachrome, .postcard, .diary] {
            let plain = photos(3)
            let captioned = photos(3, captions: ["Etosha, 12 May 2024"]).enumerated().map { index, photo -> BookPhoto in
                var copy = photo; copy.id = plain[index].id; return copy
            }
            let page = BookPage(photoIDs: plain.map(\.id))
            let before = PageComposition(page: page, book: Book(title: "T", photos: plain, template: template))
            let after = PageComposition(page: page, book: Book(title: "T", photos: captioned, template: template))
            XCTAssertEqual(after.captions.count, 1)
            let caption = try XCTUnwrap(after.captions.first)
            XCTAssertEqual(caption.position, .below)
            XCTAssertTrue(caption.fits)
            XCTAssertGreaterThan(after.captionBand, 0)
            let gap = (template?.style ?? .classic).captionGap(override: EditorialTextStyle())
            XCTAssertEqual(caption.frame.minY, after.photos[0].frame.maxY + gap, accuracy: 0.01)
            for (old, new) in zip(frames(before), frames(after)) {
                XCTAssertLessThanOrEqual(new.height, old.height + 0.01)
                XCTAssertFalse(new.intersects(caption.frame), "a photo covers the caption")
            }
            // Every slot gives up the same band: photos that shared a size still do.
            if template != nil, template != .diary {
                for index in 0..<3 {
                    XCTAssertEqual(before.photos[index].frame.height - after.photos[index].frame.height, after.captionBand,
                                   accuracy: 0.01)
                }
            }
        }
    }

    func testFixedFourPhotoLayoutSharesBaselinesPerRow() throws {
        let list = photos(4, captions: ["Left top", "Right top, a longer caption that wraps onto a second line", nil, "Right bottom"])
        let page = BookPage(layout: .gallery, photoIDs: list.map(\.id), arrangement: .fourGrid)
        for template in templates {
            let book = Book(title: "T", photos: list, template: template)
            let composition = PageComposition(page: page, book: book)
            let slots = composition.arrangementPhotoSlots
            XCTAssertEqual(composition.captions.map(\.position), [.below, .below, .below])
            for (frame, slot) in zip(frames(composition), slots) {
                XCTAssertEqual(frame.minY, slot.minY, accuracy: 0.01)
                XCTAssertEqual(frame.height, slot.height - composition.captionBand, accuracy: 0.01)
            }
            let top = composition.captions.filter { $0.frame.minY < composition.bounds.midY }
            XCTAssertEqual(top.count, 2)
            XCTAssertEqual(top[0].frame.minY, top[1].frame.minY, accuracy: 0.01)
            XCTAssertTrue(composition.captions.allSatisfy(\.fits))
            // The longest caption sets the band.
            XCTAssertGreaterThanOrEqual(composition.captionBand, top[1].frame.height)
        }
    }

    func testAManualFrameStaysAndItsCaptionMovesWithIt() throws {
        let list = photos(1, captions: ["Sossusvlei"])
        var page = BookPage(photoIDs: list.map(\.id))
        let rect = PageRect(x: 0.2, y: 0.2, width: 0.4, height: 0.3)
        page.photoPlacements = [list[0].id: PhotoPlacement(frame: rect)]
        let book = Book(title: "T", photos: list, template: .atlas)
        let first = PageComposition(page: page, book: book)
        XCTAssertEqual(first.photos[0].frame, rect.photoRect(in: first.bounds))
        let caption = try XCTUnwrap(first.captions.first)
        XCTAssertEqual(caption.position, .below)
        XCTAssertEqual(caption.frame.minX, first.photos[0].frame.minX, accuracy: 0.01)
        XCTAssertEqual(caption.frame.width, first.photos[0].frame.width, accuracy: 0.01)
        page.photoPlacements?[list[0].id]?.frame = PageRect(x: 0.3, y: 0.1, width: 0.4, height: 0.3)
        let moved = PageComposition(page: page, book: book)
        let next = try XCTUnwrap(moved.captions.first)
        XCTAssertEqual(next.frame.minX - caption.frame.minX, moved.photos[0].frame.minX - first.photos[0].frame.minX, accuracy: 0.01)
        XCTAssertEqual(next.frame.minY - caption.frame.minY, moved.photos[0].frame.minY - first.photos[0].frame.minY, accuracy: 0.01)
        // Near the bottom there is no room under the safe line: automatic falls back to the photo.
        page.photoPlacements?[list[0].id]?.frame = PageRect(x: 0.3, y: 0.6, width: 0.4, height: 0.38)
        XCTAssertEqual(PageComposition(page: page, book: book).captions.first?.position, .inside)
    }

    func testFullBleedAndFullSpreadResolveToTheBandOnThePhoto() throws {
        let list = photos(1, captions: ["Dune 45 at first light"])
        for page in [BookPage(layout: .fullPage, photoIDs: list.map(\.id), arrangement: .fullBleed),
                     BookPage(layout: .fullSpread, photoIDs: list.map(\.id))] {
            for template in templates {
                let book = Book(title: "T", photos: list, template: template)
                let composition = PageComposition(page: page, book: book)
                let caption = try XCTUnwrap(composition.captions.first)
                XCTAssertEqual(caption.position, .inside)
                let band = try XCTUnwrap(caption.band)
                XCTAssertEqual(band.maxY, composition.bounds.maxY, accuracy: 0.01)
                XCTAssertTrue(band.contains(caption.frame))
                // The text stays inside the print safe line and, on a spread, off the gutter.
                let safe = composition.bounds.insetBy(dx: 10 * 72 / 25.4, dy: 10 * 72 / 25.4)
                XCTAssertTrue(safe.insetBy(dx: -0.5, dy: -0.5).contains(caption.frame))
                if page.effectiveLayout == .fullSpread {
                    XCTAssertLessThan(caption.frame.maxX, composition.bounds.midX)
                }
                XCTAssertTrue(caption.fits)
            }
        }
    }

    func testAPhotoOnTwoPagesShowsItsCaptionOnBothUnlessHiddenOnOne() {
        let list = photos(1, captions: ["Etosha"])
        var first = BookPage(photoIDs: list.map(\.id))
        let second = BookPage(layout: .gallery, photoIDs: list.map(\.id), arrangement: .twoAcross)
        var book = Book(title: "T", photos: list, pages: [first, second], template: .monograph)
        XCTAssertEqual(book.pages.map { PageComposition(page: $0, book: book).captions.count }, [1, 1])
        first.photoPlacements = [list[0].id: PhotoPlacement(captionPosition: .hidden)]
        book.pages[0] = first
        XCTAssertEqual(book.pages.map { PageComposition(page: $0, book: book).captions.count }, [0, 1])
        // Resetting a page's frames keeps the caption position.
        XCTAssertEqual(PhotoPlacement(frame: PageRect(x: 0, y: 0, width: 1, height: 1), captionPosition: .above).withoutFrame,
                       PhotoPlacement(captionPosition: .above))
        XCTAssertNil(PhotoPlacement(frame: PageRect(x: 0, y: 0, width: 1, height: 1)).withoutFrame)
    }

    func testExplicitPositionsAboveAndInside() throws {
        let list = photos(2, captions: ["Above", "On the photo"])
        var page = BookPage(layout: .gallery, photoIDs: list.map(\.id), arrangement: .twoStacked)
        page.photoPlacements = [list[0].id: PhotoPlacement(captionPosition: .above),
                                list[1].id: PhotoPlacement(captionPosition: .inside)]
        let composition = PageComposition(page: page, book: Book(title: "T", photos: list, template: .essential))
        let above = try XCTUnwrap(composition.caption(for: list[0].id))
        XCTAssertEqual(above.position, .above)
        XCTAssertLessThan(above.frame.maxY, composition.photos[0].frame.minY)
        XCTAssertGreaterThanOrEqual(above.frame.minY, composition.arrangementPhotoSlots[0].minY - 0.01)
        let inside = try XCTUnwrap(composition.caption(for: list[1].id))
        XCTAssertEqual(inside.position, .inside)
        XCTAssertTrue(composition.photos[1].frame.contains(try XCTUnwrap(inside.band)))
    }

    func testLayoutIsDeterministic() {
        let list = photos(5, captions: ["One", nil, "Three, with more words to wrap the line", "Four", nil])
        let page = BookPage(photoIDs: list.map(\.id))
        let book = Book(title: "T", photos: list, template: .roadLog)
        let a = PageComposition(page: page, book: book), b = PageComposition(page: page, book: book)
        XCTAssertEqual(frames(a), frames(b))
        XCTAssertEqual(a.captions.map(\.frame), b.captions.map(\.frame))
    }

    // MARK: Issues

    func testCaptionThatDoesNotFitIsAWarningOnTheCaption() throws {
        var list = photos(1, captions: [String(repeating: "A very long caption about the trip. ", count: 12)])
        var page = BookPage(photoIDs: list.map(\.id))
        page.photoPlacements = [list[0].id: PhotoPlacement(frame: PageRect(x: 0.3, y: 0.3, width: 0.25, height: 0.12),
                                                           captionPosition: .inside)]
        var book = Book(title: "T", photos: list, pages: [page], template: .atlas)
        var report = BookPDF.preflight(book, directory: nil, profile: .print)
        let issue = try XCTUnwrap(report.warnings.first { $0.problem == .captionDoesNotFit })
        XCTAssertEqual(issue.target, .caption(list[0].id))
        XCTAssertEqual(issue.destination(in: book), .page(page.id))
        XCTAssertTrue(issue.message(language: "en").hasSuffix("Caption does not fit"))
        // Below a frame at the bottom edge, the caption crosses the trim.
        list[0].caption = "Short"
        book.photos = list
        book.pages[0].photoPlacements = [list[0].id: PhotoPlacement(frame: PageRect(x: 0.1, y: 0.7, width: 0.5, height: 0.3),
                                                                    captionPosition: .below)]
        report = BookPDF.preflight(book, directory: nil, profile: .print)
        XCTAssertTrue(report.warnings.contains { $0.problem == .captionDoesNotFit })
        book.pages[0].photoPlacements = nil
        report = BookPDF.preflight(book, directory: nil, profile: .print)
        XCTAssertFalse(report.warnings.contains { $0.problem == .captionDoesNotFit })
    }

    func testACaptionOutsideTheSafeLineIsASafeMarginWarning() throws {
        let list = photos(1, captions: ["Above the frame"])
        var page = BookPage(photoIDs: list.map(\.id))
        // Above a frame 12.6 mm from the top: inside the trim, outside the 10 mm safe line.
        page.photoPlacements = [list[0].id: PhotoPlacement(frame: PageRect(x: 0.2, y: 0.06, width: 0.5, height: 0.3),
                                                           captionPosition: .above)]
        var book = Book(title: "T", photos: list, pages: [page], template: .atlas)
        let caption = try XCTUnwrap(PageComposition(page: page, book: book).captions.first)
        XCTAssertTrue(caption.fits)
        var report = BookPDF.preflight(book, directory: nil, profile: .print)
        let issue = try XCTUnwrap(report.warnings.first { $0.problem == .textOutsideSafeMargin })
        XCTAssertEqual(issue.target, .caption(list[0].id))
        XCTAssertTrue(issue.message(language: "en").contains("Caption “Above the frame”"))
        book.pages[0].photoPlacements?[list[0].id]?.captionPosition = nil
        report = BookPDF.preflight(book, directory: nil, profile: .print)
        XCTAssertFalse(report.warnings.contains { $0.problem == .textOutsideSafeMargin })
    }

    func testAPastedLongCaptionIsCutAndReported() throws {
        let list = photos(2, captions: [String(repeating: "word ", count: 2000), "Short"])
        let page = BookPage(photoIDs: list.map(\.id))
        let book = Book(title: "T", photos: list, pages: [page], template: .diary)
        let composition = PageComposition(page: page, book: book)
        let long = try XCTUnwrap(composition.caption(for: list[0].id))
        XCTAssertLessThanOrEqual(long.text.length, CaptionSetter.maximumCharacters + 1)
        XCTAssertTrue(long.text.string.hasSuffix("…"))
        XCTAssertFalse(long.fits)
        XCTAssertEqual(composition.caption(for: list[1].id)?.fits, true)
        XCTAssertTrue(BookPDF.preflight(book, directory: nil, profile: .print).warnings.contains {
            $0.problem == .captionDoesNotFit && $0.target == .caption(list[0].id)
        })
        let lines = CaptionSetter.printable((1...40).map(String.init).joined(separator: "\n"))
        XCTAssertTrue(lines.cut)
        XCTAssertEqual(lines.text.split(separator: "\n").count, CaptionSetter.maximumLines)
        XCTAssertFalse(CaptionSetter.printable("Etosha").cut)
    }

    func testAFrameAcrossTheGutterKeepsAReadableCaption() throws {
        let list = photos(1, captions: ["Across the fold"])
        var page = BookPage(layout: .fullSpread, photoIDs: list.map(\.id))
        // Mostly on the right page: the caption moves to the right of the gutter.
        page.photoPlacements = [list[0].id: PhotoPlacement(frame: PageRect(x: 0.48, y: 0.2, width: 0.3, height: 0.3),
                                                           captionPosition: .below)]
        let book = Book(title: "T", photos: list, pages: [page], template: .atlas)
        var composition = PageComposition(page: page, book: book)
        var caption = try XCTUnwrap(composition.captions.first)
        XCTAssertGreaterThan(caption.frame.minX, composition.bounds.midX)
        XCTAssertGreaterThan(caption.frame.width, 36)
        XCTAssertTrue(caption.fits)
        // Straddling it evenly with no room on either side: the full width, and a warning.
        page.photoPlacements?[list[0].id]?.frame = PageRect(x: 0.47, y: 0.2, width: 0.06, height: 0.3)
        composition = PageComposition(page: page, book: book)
        caption = try XCTUnwrap(composition.captions.first)
        XCTAssertEqual(caption.frame.width, composition.photos[0].frame.width, accuracy: 0.01)
        XCTAssertFalse(caption.fits)
    }

    func testAPageWithoutCaptionsDoesNoCaptionWork() {
        let list = photos(3)
        let page = BookPage(photoIDs: list.map(\.id))
        let book = Book(title: "T", photos: list, template: .diary)
        XCTAssertNil(CaptionSetter(book: book, page: page, bounds: CGRect(x: 0, y: 0, width: 500, height: 500),
                                   storyPanel: nil, lookup: book.photo))
    }

    func testUseThisOneCarriesTheCaptionOver() {
        var chosen = BookPhoto(name: "a", filename: "a.jpg", pixelWidth: 10, pixelHeight: 10)
        var first = BookPhoto(name: "b", filename: "b.jpg", pixelWidth: 10, pixelHeight: 10)
        var second = BookPhoto(name: "c", filename: "c.jpg", pixelWidth: 10, pixelHeight: 10)
        XCTAssertEqual(SimilarPhotos.captionCarry(chosen: chosen, replaced: [first, second]), .none)
        second.caption = "Etosha"
        first.caption = "  "
        XCTAssertEqual(SimilarPhotos.captionCarry(chosen: chosen, replaced: [first, second]), .copy("Etosha"))
        chosen.caption = "Etosha"
        XCTAssertEqual(SimilarPhotos.captionCarry(chosen: chosen, replaced: [first, second]), .none)
        chosen.caption = "Okaukuejo"
        XCTAssertEqual(SimilarPhotos.captionCarry(chosen: chosen, replaced: [first, second]), .keepsOwn)
    }

    // MARK: Text

    func testAutomaticCaptionFromPlaceAndDate() {
        var components = DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(identifier: "UTC"),
                                        year: 2024, month: 5, day: 12, hour: 9)
        let date = components.date
        let utc = TimeZone(identifier: "UTC")!
        XCTAssertEqual(CaptionText.automatic(place: "Etosha", date: date, language: "en", timeZone: utc), "Etosha, 12 May 2024")
        XCTAssertEqual(CaptionText.automatic(place: "Etosha", date: date, language: "it", timeZone: utc), "Etosha, 12 maggio 2024")
        XCTAssertEqual(CaptionText.automatic(place: " ", date: date, language: "en", timeZone: utc), "12 May 2024")
        XCTAssertEqual(CaptionText.automatic(place: "Etosha", date: nil, language: "it"), "Etosha")
        XCTAssertNil(CaptionText.automatic(place: nil, date: nil, language: "en"))
        components.day = 1
        XCTAssertEqual(CaptionText.automatic(place: nil, date: components.date, language: "en", timeZone: utc), "1 May 2024")
    }

    func testDefaultCaptionStyleForEveryTemplate() {
        for template in templates {
            let style = template?.style ?? .classic
            let caption = style.defaultCaptionStyle
            XCTAssertNotNil(caption.fontName.flatMap { NSFont(name: $0, size: 10) }, "\(String(describing: template))")
            XCTAssertEqual(caption.pointSize ?? 0, max(8.5, style.bodySize * 0.8), accuracy: 0.13)
            XCTAssertNotEqual(style.captionInk, style.ink)
            XCTAssertNotEqual(style.captionInk, style.paper)
        }
        // The book's caption style overrides the template's.
        var book = Book(title: "T", template: .atlas)
        book.typography = EditorialTypography(title: nil, body: nil, caption: EditorialTextStyle(pointSize: 14, color: 0xFF0000))
        let text = book.editorialStyle.captionTypography("Hi", override: book.captionStyle, overPhoto: false)
        let font = text.attribute(NSAttributedString.Key(kCTFontAttributeName as String), at: 0, effectiveRange: nil)
        XCTAssertEqual(CTFontGetSize(font as! CTFont), 14)
    }

    // MARK: PDF and command line

    func testThePDFHasEachCaptionAsTextInEveryTemplate() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let image = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aHukAAAAASUVORK5CYII="))
        try image.write(to: root.appendingPathComponent("pixel.png"))
        for template in templates {
            let name = template?.rawValue ?? "classic"
            let spec = root.appendingPathComponent(name + ".json")
            let template = template.map { "\"template\":\"\($0.rawValue)\"," } ?? ""
            try Data("""
            {"version":1,"title":"Captions",\(template)
             "assets":[{"id":"a","path":"pixel.png","caption":"Etosha waterhole"},{"id":"b","path":"pixel.png","caption":"Dune at dawn"}],
             "pages":[{"photos":["a","b"]},{"arrangement":"fullBleed","layout":"fullPage","photos":["b"]}]}
            """.utf8).write(to: spec)
            let project = root.appendingPathComponent(name + ".papergrain")
            _ = try BookCLI.execute(["build", spec.path, project.path])
            let book = try BookStorage.read(from: project)
            let pdfURL = root.appendingPathComponent(name + ".pdf")
            try BookPDF.write(book, directory: project, to: pdfURL)
            let pdf = try XCTUnwrap(PDFDocument(url: pdfURL))
            let first = try XCTUnwrap(pdf.page(at: 0)?.attributedString)
            XCTAssertTrue(first.string.contains("Etosha waterhole"), name)
            XCTAssertTrue(first.string.contains("Dune at dawn"), name)
            XCTAssertTrue(pdf.page(at: 1)?.string?.contains("Dune at dawn") == true, name)
            let range = (first.string as NSString).range(of: "Etosha waterhole")
            let font = first.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
            let expected = try XCTUnwrap(NSFont(name: book.editorialStyle.defaultCaptionStyle.fontName ?? "", size: 10))
            XCTAssertEqual(font?.familyName, expected.familyName, name)
        }
    }

    func testCommandLineCaptionsAndPositions() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let image = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aHukAAAAASUVORK5CYII="))
        try image.write(to: root.appendingPathComponent("pixel.png"))
        let spec = root.appendingPathComponent("spec.json")
        try Data("""
        {"version":1,"title":"T","typography":{"caption":{"pointSize":9}},
         "assets":[{"id":"a","path":"pixel.png","caption":"Etosha"}],
         "pages":[{"photos":["a"],"photoPlacements":{"a":{"captionPosition":"above"}}}]}
        """.utf8).write(to: spec)
        let project = root.appendingPathComponent("a.papergrain")
        _ = try BookCLI.execute(["build", spec.path, project.path])
        var book = try BookStorage.read(from: project)
        XCTAssertEqual(book.photos[0].caption, "Etosha")
        XCTAssertEqual(book.pages[0].photoPlacements?[book.photos[0].id]?.captionPosition, .above)
        XCTAssertEqual(book.typography?.caption?.pointSize, 9)
        let output = try await BookCLI.executeExtended(["photos", project.path])
        let listed = try XCTUnwrap(JSONSerialization.jsonObject(with: output) as? [[String: Any]])
        XCTAssertEqual(listed.first?["caption"] as? String, "Etosha")

        let patch = root.appendingPathComponent("patch.json")
        try Data("""
        [{"op":"replace","path":"/photos/0/caption","value":"Etosha, 12 May 2024"},
         {"op":"replace","path":"/pages/0/photoPlacements/1/captionPosition","value":"inside"}]
        """.utf8).write(to: patch)
        book = try BookCLIEditing.patch(source: project, patchURL: patch, output: root.appendingPathComponent("b.papergrain"))
        XCTAssertEqual(book.photos[0].caption, "Etosha, 12 May 2024")
        XCTAssertEqual(book.pages[0].photoPlacements?[book.photos[0].id]?.captionPosition, .inside)

        // Captions have one style per book; a page caption style and an unknown position are refused.
        for bad in [#"{"version":1,"title":"T","assets":[],"pages":[{"typography":{"caption":{"pointSize":9}}}]}"#,
                    #"{"version":1,"title":"T","assets":[{"id":"a","path":"pixel.png"}],"pages":[{"photos":["a"],"photoPlacements":{"a":{"captionPosition":"left"}}}]}"#,
                    #"{"version":1,"title":"T","assets":[{"id":"a","path":"pixel.png"}],"pages":[{"photos":[],"photoPlacements":{"a":{"captionPosition":"below"}}}]}"#] {
            try Data(bad.utf8).write(to: spec)
            XCTAssertThrowsError(try BookCLI.execute(["build", spec.path, root.appendingPathComponent(UUID().uuidString + ".papergrain").path]))
        }
    }
}
