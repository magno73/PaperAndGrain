import XCTest
@testable import PaperAndGrain

final class PageDuplicationTests: XCTestCase {
    private func sample() -> BookPage {
        let photo = UUID(), other = UUID()
        let first = PageTextBox(text: "One", frame: PageRect(x: 0.1, y: 0.1, width: 0.3, height: 0.2))
        let second = PageTextBox(text: "Two", frame: PageRect(x: 0.5, y: 0.5, width: 0.3, height: 0.2), borderWidth: 1)
        return BookPage(layout: .mixed, photoIDs: [photo, other], text: "Story", framing: 0.3,
                        heading: "Heading",
                        photoPlacements: [photo: PhotoPlacement(frame: PageRect(x: 0, y: 0, width: 0.5, height: 0.5))],
                        textBoxes: [first, second],
                        arrangement: nil,
                        layerOrder: [.textBox(second.id), .photo(photo), .story, .photo(other), .textBox(first.id)],
                        titleFrame: PageRect(x: 0.1, y: 0.7, width: 0.8, height: 0.1))
    }

    func testCopyDiffersOnlyInPageAndBoxIDs() throws {
        let original = sample()
        let copy = original.duplicated()
        XCTAssertNotEqual(copy.id, original.id)
        let boxes = try XCTUnwrap(copy.textBoxes), originals = try XCTUnwrap(original.textBoxes)
        XCTAssertEqual(boxes.count, 2)
        XCTAssertTrue(Set(boxes.map(\.id)).isDisjoint(with: originals.map(\.id)))

        // Put the ids back and the two pages must be equal in every other field.
        var normalized = copy
        normalized.id = original.id
        normalized.textBoxes = zip(boxes, originals).map { new, old in var box = new; box.id = old.id; return box }
        normalized.layerOrder = original.layerOrder
        XCTAssertEqual(normalized, original)
        XCTAssertEqual(copy.photoIDs, original.photoIDs)
        XCTAssertEqual(copy.photoPlacements, original.photoPlacements)
    }

    func testLayerOrderRefersOnlyToIDsOnTheCopyAndKeepsItsOrder() throws {
        let original = sample()
        let copy = original.duplicated()
        let ids = Set(try XCTUnwrap(copy.textBoxes).map(\.id))
        let layers = try XCTUnwrap(copy.layerOrder)
        XCTAssertEqual(layers.count, try XCTUnwrap(original.layerOrder).count)
        for case let .textBox(id) in layers { XCTAssertTrue(ids.contains(id)) }
        // The box that was at the bottom is still at the bottom, now with the copy's id.
        XCTAssertEqual(layers.first, .textBox(try XCTUnwrap(copy.textBoxes)[1].id))
        XCTAssertEqual(layers.last, .textBox(try XCTUnwrap(copy.textBoxes)[0].id))
    }

    func testPageWithoutBoxesOrLayersCopiesCleanly() {
        let plain = BookPage(photoIDs: [UUID()])
        let copy = plain.duplicated()
        XCTAssertNil(copy.textBoxes)
        XCTAssertNil(copy.layerOrder)
        XCTAssertNotEqual(copy.id, plain.id)
    }
}
