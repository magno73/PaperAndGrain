import CoreGraphics
import XCTest
@testable import PaperAndGrain

final class PhotoDropTests: XCTestCase {
    private func photo(_ name: String, _ width: Int = 300, _ height: Int = 200) -> BookPhoto {
        BookPhoto(name: name, filename: name + ".jpg", pixelWidth: width, pixelHeight: height)
    }

    private func frame(_ id: UUID, _ page: BookPage, _ photos: [BookPhoto]) throws -> CGRect {
        let composition = PageComposition(page: page, book: Book(title: "Drop", photos: photos, pages: [page]))
        return try XCTUnwrap(composition.photos.first { $0.id == id }?.frame)
    }

    func testSameProportionsKeepTheFrame() throws {
        let a = photo("a"), b = photo("b"), c = photo("c"), twin = photo("twin", 310, 200)
        let photos = [a, b, c, twin]
        var page = BookPage(layout: .gallery, photoIDs: [a.id, b.id, c.id])
        let before = PageComposition(page: page, book: Book(title: "Drop", photos: photos, pages: [page]))
        XCTAssertEqual(page.replacePhoto(b.id, with: twin, in: before), .sameFrame)
        XCTAssertEqual(page.photoIDs, [a.id, twin.id, c.id])
        XCTAssertEqual(try frame(twin.id, page, photos).integral, try XCTUnwrap(before.photos.first { $0.id == b.id }?.frame).integral)
        XCTAssertNil(page.photoPlacements?[twin.id]?.crop)
    }

    func testAnAutomaticGalleryReflowsSoNothingIsCropped() throws {
        let a = photo("a"), b = photo("b"), tall = photo("tall", 200, 600)
        let photos = [a, b, tall]
        var page = BookPage(layout: .gallery, photoIDs: [a.id, b.id])
        let before = PageComposition(page: page, book: Book(title: "Drop", photos: photos, pages: [page]))
        XCTAssertEqual(page.replacePhoto(b.id, with: tall, in: before), .reflowed)
        XCTAssertNil(page.photoPlacements)
        let placed = try frame(tall.id, page, photos)
        XCTAssertEqual(placed.width / placed.height, 200.0 / 600.0, accuracy: 0.02)
    }

    func testFixedLayoutsFitTheWholePhotoInsideTheSlot() throws {
        let a = photo("a"), b = photo("b"), tall = photo("tall", 200, 600)
        let photos = [a, b, tall]
        var page = BookPage(photoIDs: [a.id, b.id], arrangement: .twoStacked)
        page.layerOrder = [.photo(b.id), .photo(a.id), .story]
        let before = PageComposition(page: page, book: Book(title: "Drop", photos: photos, pages: [page]))
        let slot = try XCTUnwrap(before.photos.first { $0.id == a.id }?.frame)
        XCTAssertEqual(page.replacePhoto(a.id, with: tall, in: before), .fitted)
        XCTAssertEqual(page.photoIDs, [tall.id, b.id])
        XCTAssertEqual(page.layerOrder, [.photo(b.id), .photo(tall.id), .story])
        let placed = try frame(tall.id, page, photos)
        XCTAssertEqual(placed.width / placed.height, 200.0 / 600.0, accuracy: 0.01)
        XCTAssertTrue(slot.insetBy(dx: -0.5, dy: -0.5).contains(placed))
        XCTAssertEqual(placed.midX, slot.midX, accuracy: 0.5)
        XCTAssertEqual(try frame(b.id, page, photos).integral, try XCTUnwrap(before.photos.first { $0.id == b.id }?.frame).integral)
        let after = PageComposition(page: page, book: Book(title: "Drop", photos: photos, pages: [page]))
        XCTAssertTrue(after.emptySlots.isEmpty, "A fitted photo still occupies its slot")
        XCTAssertNil(page.replacePhoto(b.id, with: tall, in: after), "A photo already on the page swaps instead")
    }

    func testTemplateGalleriesWithFixedFramesFitInsteadOfCropping() throws {
        let a = photo("a"), b = photo("b"), tall = photo("tall", 200, 600)
        let photos = [a, b, tall]
        var page = BookPage(layout: .gallery, photoIDs: [a.id, b.id])
        var book = Book(title: "Drop", photos: photos, pages: [page])
        book.template = .slide
        let before = PageComposition(page: page, book: book)
        XCTAssertTrue(before.photos.allSatisfy(\.fills), "Slide lays pairs out in fixed frames")
        XCTAssertEqual(page.replacePhoto(a.id, with: tall, in: before), .fitted)
        book.pages = [page]
        let placed = try XCTUnwrap(PageComposition(page: page, book: book).photos.first { $0.id == tall.id }?.frame)
        XCTAssertEqual(placed.width / placed.height, 200.0 / 600.0, accuracy: 0.01)
    }

    func testManualFramesKeepTheirPlaceAndFullBleedReportsTheCrop() throws {
        let a = photo("a"), b = photo("b"), tall = photo("tall", 200, 600)
        let photos = [a, b, tall]
        var manual = BookPage(layout: .gallery, photoIDs: [a.id, b.id], photoPlacements: [
            a.id: PhotoPlacement(frame: PageRect(x: 0.1, y: 0.1, width: 0.6, height: 0.4))
        ])
        let composition = PageComposition(page: manual, book: Book(title: "Drop", photos: photos, pages: [manual]))
        let bBefore = try XCTUnwrap(composition.photos.first { $0.id == b.id }?.frame)
        XCTAssertEqual(manual.replacePhoto(a.id, with: tall, in: composition), .fitted)
        XCTAssertEqual(try frame(b.id, manual, photos).integral, bBefore.integral, "Other photos are pinned")

        var bleed = BookPage(photoIDs: [a.id, b.id], arrangement: .bleedTwoAcross)
        let bleedComposition = PageComposition(page: bleed, book: Book(title: "Drop", photos: photos, pages: [bleed]))
        XCTAssertEqual(bleed.replacePhoto(a.id, with: tall, in: bleedComposition), .croppedToBleed)
        XCTAssertNil(bleed.photoPlacements, "Full bleed keeps the slot")
    }

    func testFillingAnEmptySlotUsesThatSlot() throws {
        let a = photo("a"), b = photo("b"), c = photo("c")
        var page = BookPage(photoIDs: [a.id], arrangement: .fourGrid)
        var book = Book(title: "Drop", photos: [a, b, c], pages: [page])
        var composition = PageComposition(page: page, book: book)
        XCTAssertEqual(composition.emptySlots.map(\.index), [1, 2, 3])

        // The next slot in order stays automatic.
        XCTAssertTrue(page.fillSlot(1, with: b.id, in: composition))
        XCTAssertNil(page.photoPlacements?[b.id]?.frame)
        book.pages = [page]
        composition = PageComposition(page: page, book: book)
        XCTAssertEqual(composition.emptySlots.map(\.index), [2, 3])

        // A later slot gets the slot itself as the frame.
        XCTAssertTrue(page.fillSlot(3, with: c.id, in: composition))
        book.pages = [page]
        let filled = PageComposition(page: page, book: book)
        XCTAssertEqual(filled.emptySlots.map(\.index), [2])
        let frame = try XCTUnwrap(filled.photos.first { $0.id == c.id }?.frame)
        XCTAssertEqual(frame.integral, filled.arrangementPhotoSlots[3].integral)
    }

    func testOnlyEmptyAutomaticPagesAcceptAFirstPhoto() {
        let a = photo("a")
        let empty = BookPage(layout: .gallery)
        let text = BookPage(layout: .text)
        let book = Book(title: "Drop", photos: [a], pages: [empty, text])
        XCTAssertTrue(PageComposition(page: empty, book: book).acceptsFirstPhoto(on: empty))
        XCTAssertFalse(PageComposition(page: text, book: book).acceptsFirstPhoto(on: text))
    }
}

final class TextBoxFrameTests: XCTestCase {
    func testBoxFillAndBorderDefaultsAndDecodeFromOlderProjects() throws {
        var box = PageTextBox(text: "Caption", frame: PageRect(x: 0.1, y: 0.1, width: 0.3, height: 0.2))
        XCTAssertEqual(box.fill(paper: 0xF6F3EC), 0xF6F3EC)
        XCTAssertNil(box.border(ink: 0x222222))
        box.hidesBackground = true
        box.borderWidth = 40
        XCTAssertNil(box.fill(paper: 0xF6F3EC))
        XCTAssertEqual(box.border(ink: 0x222222)?.width, PageTextBox.borderWidthRange.upperBound)
        XCTAssertEqual(box.border(ink: 0x222222)?.color, 0x222222)

        let saved = try JSONDecoder().decode(PageTextBox.self, from: JSONEncoder().encode(box))
        XCTAssertEqual(saved, box)
        let old = #"{"id":"0D8F4B1C-0000-4000-8000-000000000002","text":"Old","frame":{"x":0.1,"y":0.1,"width":0.3,"height":0.2}}"#
        let decoded = try JSONDecoder().decode(PageTextBox.self, from: Data(old.utf8))
        XCTAssertNil(decoded.backgroundColor)
        XCTAssertNil(decoded.borderWidth)
    }
}

final class PhotoResolutionTests: XCTestCase {
    func testResolutionLevelsFollowTheTarget() throws {
        let photo = BookPhoto(name: "p", filename: "p.jpg", pixelWidth: 3000, pixelHeight: 2000)
        // 3000 px over 10 inches (720 pt) is 300 ppi.
        let ten = CGRect(x: 0, y: 0, width: 720, height: 480)
        let exact = try XCTUnwrap(PhotoResolution.ppi(of: photo, in: ten, fills: true, crop: PhotoCrop()))
        XCTAssertEqual(exact, 300, accuracy: 0.001)
        XCTAssertEqual(PhotoResolution.level(exact, target: 300), .good)
        XCTAssertEqual(PhotoResolution.level(299.6, target: 300), .good, "Rounds like the preflight text")
        XCTAssertEqual(PhotoResolution.level(250, target: 300), .low)
        XCTAssertEqual(PhotoResolution.level(150, target: 300), .poor)
        // A 2x crop zoom halves the resolution.
        var zoomed = PhotoCrop()
        zoomed.zoom = 2
        let half = try XCTUnwrap(PhotoResolution.ppi(of: photo, in: ten, fills: true, crop: zoomed))
        XCTAssertEqual(half, 150, accuracy: 0.001)
    }
}
