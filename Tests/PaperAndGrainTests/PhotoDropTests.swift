import CoreGraphics
import XCTest
@testable import PaperAndGrain

final class PhotoDropTests: XCTestCase {
    private func photo(_ name: String, _ width: Int = 300, _ height: Int = 200) -> BookPhoto {
        BookPhoto(name: name, filename: name + ".jpg", pixelWidth: width, pixelHeight: height)
    }

    func testReplacingInAGalleryKeepsEveryFrame() throws {
        let a = photo("a"), b = photo("b"), c = photo("c"), tall = photo("tall", 200, 600)
        let page = BookPage(layout: .gallery, photoIDs: [a.id, b.id, c.id])
        let book = Book(title: "Drop", photos: [a, b, c, tall], pages: [page])
        let before = PageComposition(page: page, book: book)
        var updated = page
        XCTAssertTrue(updated.replacePhoto(b.id, with: tall.id, in: before))
        XCTAssertEqual(updated.photoIDs, [a.id, tall.id, c.id])
        let after = PageComposition(page: updated, book: Book(title: "Drop", photos: [a, b, c, tall], pages: [updated]))
        func frame(_ id: UUID, _ composition: PageComposition) throws -> CGRect {
            try XCTUnwrap(composition.photos.first { $0.id == id }?.frame)
        }
        // A portrait photo in a landscape slot fills the same frame instead of reflowing the page.
        XCTAssertEqual(try frame(tall.id, after).integral, try frame(b.id, before).integral)
        XCTAssertEqual(try frame(a.id, after).integral, try frame(a.id, before).integral)
        XCTAssertEqual(try frame(c.id, after).integral, try frame(c.id, before).integral)
        XCTAssertNil(updated.photoPlacements?[b.id])
        XCTAssertNil(updated.photoPlacements?[tall.id]?.crop)
    }

    func testReplacingInAFixedLayoutKeepsTheSlotAndTheStackingOrder() {
        let a = photo("a"), b = photo("b"), new = photo("new")
        var page = BookPage(photoIDs: [a.id, b.id], arrangement: .twoAcross)
        page.layerOrder = [.photo(b.id), .photo(a.id), .story]
        let book = Book(title: "Drop", photos: [a, b, new], pages: [page])
        let composition = PageComposition(page: page, book: book)
        XCTAssertTrue(page.replacePhoto(a.id, with: new.id, in: composition))
        XCTAssertEqual(page.photoIDs, [new.id, b.id])
        XCTAssertNil(page.photoPlacements)
        XCTAssertEqual(page.layerOrder, [.photo(b.id), .photo(new.id), .story])
        XCTAssertFalse(page.replacePhoto(b.id, with: new.id, in: composition), "A photo already on the page swaps instead")
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
