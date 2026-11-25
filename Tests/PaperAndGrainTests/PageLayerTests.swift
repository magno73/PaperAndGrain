import AppKit
import CoreGraphics
import XCTest
@testable import PaperAndGrain

final class PageLayerTests: XCTestCase {
    private func fixture() -> (BookPhoto, BookPhoto, PageTextBox, BookPage, Book) {
        let back = BookPhoto(name: "Back", filename: "back.jpg", pixelWidth: 100, pixelHeight: 100)
        let front = BookPhoto(name: "Front", filename: "front.jpg", pixelWidth: 100, pixelHeight: 100)
        let box = PageTextBox(text: "Caption", frame: PageRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4))
        let page = BookPage(photoIDs: [back.id, front.id], photoPlacements: [
            back.id: PhotoPlacement(frame: PageRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)),
            front.id: PhotoPlacement(frame: PageRect(x: 0.4, y: 0.4, width: 0.5, height: 0.5))
        ], textBoxes: [box])
        return (back, front, box, page, Book(title: "Layers", photos: [back, front], pages: [page]))
    }

    func testDefaultOrderKeepsPhotosUnderTextAndOldProjectsDecodeWithoutLayers() throws {
        let (back, front, box, page, book) = fixture()
        XCTAssertNil(page.layerOrder)
        XCTAssertEqual(PageComposition(page: page, book: book).layers,
                       [.photo(back.id), .photo(front.id), .story, .textBox(box.id)])

        // A page saved before stacking existed has no layerOrder key.
        let data = try JSONEncoder().encode(page)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["layerOrder"])
        json.removeValue(forKey: "layerOrder")
        let decoded = try JSONDecoder().decode(BookPage.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.layerOrder)
    }

    func testMovesRestackAndSurviveSaving() throws {
        let (back, front, box, original, _) = fixture()
        var page = original
        let photos = [back.id, front.id]
        XCTAssertTrue(page.moveLayer(.photo(back.id), .front, photos: photos, boxes: [box.id]))
        XCTAssertEqual(page.stackingOrder(photos: photos, boxes: [box.id]).last, .photo(back.id))
        XCTAssertFalse(page.moveLayer(.photo(back.id), .forward, photos: photos, boxes: [box.id]))
        XCTAssertTrue(page.moveLayer(.textBox(box.id), .back, photos: photos, boxes: [box.id]))
        XCTAssertEqual(page.stackingOrder(photos: photos, boxes: [box.id]).first, .textBox(box.id))
        XCTAssertTrue(page.moveLayer(.textBox(box.id), .forward, photos: photos, boxes: [box.id]))
        XCTAssertEqual(page.stackingOrder(photos: photos, boxes: [box.id]),
                       [.photo(front.id), .textBox(box.id), .story, .photo(back.id)])

        let decoded = try JSONDecoder().decode(BookPage.self, from: JSONEncoder().encode(page))
        XCTAssertEqual(decoded.layerOrder, page.layerOrder)
    }

    func testObjectsAddedAfterARestackKeepSensibleDefaults() {
        let (back, front, box, original, _) = fixture()
        var page = original
        page.moveLayer(.photo(back.id), .front, photos: [back.id, front.id], boxes: [box.id])
        let newPhoto = UUID()
        let newBox = UUID()
        let order = page.stackingOrder(photos: [back.id, front.id, newPhoto], boxes: [box.id, newBox])
        XCTAssertEqual(order.first, .photo(newPhoto))
        XCTAssertEqual(order.last, .textBox(newBox))
    }

    func testRestackedPhotoOverTextIsHitAndDropTargetsFollowTheStack() {
        let (back, front, box, original, fixtureBook) = fixture()
        var page = original
        var book = fixtureBook
        let frame = CGRect(x: 0, y: 0, width: 400, height: 400)
        let overlap = CGPoint(x: 0.45 * 400, y: 0.45 * 400) // back photo, front photo and the box all cover it.
        XCTAssertNil(EditorPhotoHitTest.onPage(at: overlap, frame: frame,
                                               composition: PageComposition(page: page, book: book)))
        page.moveLayer(.photo(back.id), .front, photos: [back.id, front.id], boxes: [box.id])
        book.pages = [page]
        XCTAssertEqual(EditorPhotoHitTest.onPage(at: overlap, frame: frame,
                                                 composition: PageComposition(page: page, book: book)), back.id)
        XCTAssertEqual(EditorPhotoHitTest.onPage(at: overlap, frame: frame,
                                                 composition: PageComposition(page: page, book: book),
                                                 excluding: back.id), nil)
    }

    func testLayerCodingUsesReadableStrings() throws {
        let id = try XCTUnwrap(UUID(uuidString: "0D8F4B1C-0000-4000-8000-000000000001"))
        let data = try JSONEncoder().encode([PageLayer.photo(id), .story, .textBox(id)])
        XCTAssertEqual(String(decoding: data, as: UTF8.self),
                       "[\"photo:\(id.uuidString)\",\"story\",\"box:\(id.uuidString)\"]")
        XCTAssertThrowsError(try JSONDecoder().decode([PageLayer].self, from: Data("[\"shape:x\"]".utf8)))
    }
}

final class PageScrollGestureTests: XCTestCase {
    func testTrackpadSwipeTurnsOncePerGestureAndSwallowsMomentum() {
        var gesture = PageScrollGesture()
        XCTAssertEqual(gesture.handle(phase: .began, momentum: [], precise: true, dx: 0, dy: -4, allowed: true, now: 0), .consume)
        XCTAssertEqual(gesture.handle(phase: .changed, momentum: [], precise: true, dx: 0, dy: -30, allowed: true, now: 0.02), .turn(1))
        XCTAssertEqual(gesture.handle(phase: .changed, momentum: [], precise: true, dx: 0, dy: -60, allowed: true, now: 0.04), .consume)
        XCTAssertEqual(gesture.handle(phase: .ended, momentum: [], precise: true, dx: 0, dy: 0, allowed: true, now: 0.05), .consume)
        XCTAssertEqual(gesture.handle(phase: [], momentum: .changed, precise: true, dx: 0, dy: -20, allowed: true, now: 0.1), .consume)
        // Swiping right moves back, like turning a page with the finger.
        XCTAssertEqual(gesture.handle(phase: .began, momentum: [], precise: true, dx: 40, dy: 2, allowed: true, now: 1), .turn(-1))
    }

    func testZoomedCanvasKeepsItsScroll() {
        var gesture = PageScrollGesture()
        XCTAssertEqual(gesture.handle(phase: .began, momentum: [], precise: true, dx: 0, dy: -40, allowed: false, now: 0), .ignore)
        XCTAssertEqual(gesture.handle(phase: .changed, momentum: [], precise: true, dx: 0, dy: -40, allowed: true, now: 0.1), .ignore)
        XCTAssertEqual(gesture.handle(phase: [], momentum: .changed, precise: true, dx: 0, dy: -40, allowed: true, now: 0.2), .ignore)
    }

    func testMouseWheelTurnsOnePagePerNotch() {
        var gesture = PageScrollGesture()
        XCTAssertEqual(gesture.handle(phase: [], momentum: [], precise: false, dx: 0, dy: -1, allowed: true, now: 10), .turn(1))
        XCTAssertEqual(gesture.handle(phase: [], momentum: [], precise: false, dx: 0, dy: -1, allowed: true, now: 10.05), .consume)
        XCTAssertEqual(gesture.handle(phase: [], momentum: [], precise: false, dx: 0, dy: 1, allowed: true, now: 10.3), .turn(-1))
        XCTAssertEqual(gesture.handle(phase: [], momentum: [], precise: false, dx: 0, dy: 1, allowed: false, now: 11), .ignore)
    }
}

final class TextFormatTests: XCTestCase {
    func testColorAndLineSpacingInheritAndReachTheAttributedText() throws {
        let base = EditorialTextStyle(fontName: "Georgia", pointSize: 12, alignment: .left, color: 0x112233, lineSpacing: 1.4)
        let local = EditorialTextStyle(color: 0xC8102E)
        let merged = local.inheriting(base)
        XCTAssertEqual(merged.color, 0xC8102E)
        XCTAssertEqual(merged.lineSpacing, 1.4)
        XCTAssertEqual(EditorialTextStyle(lineSpacing: 9).normalizedLineSpacing, EditorialTextStyle.lineSpacingRange.upperBound)

        let style = BookTemplate.diary.style
        let text = style.typography("Uno\nDue", heading: nil, mixed: true, bodyStyle: merged)
        let attributes = text.attributes(at: 0, effectiveRange: nil)
        let paragraph = try XCTUnwrap(attributes[.paragraphStyle] as? NSParagraphStyle)
        XCTAssertEqual(paragraph.lineHeightMultiple, 1.4, accuracy: 0.001)
        let color = try XCTUnwrap(attributes[NSAttributedString.Key(kCTForegroundColorAttributeName as String)])
        XCTAssertEqual(CFGetTypeID(color as CFTypeRef), CGColor.typeID)
        XCTAssertEqual((color as! CGColor).components?.first ?? 0, CGFloat(0xC8) / 255, accuracy: 0.01)

        let plain = style.typography("Uno", heading: nil, mixed: true, bodyStyle: EditorialTextStyle())
        let plainParagraph = try XCTUnwrap(plain.attributes(at: 0, effectiveRange: nil)[.paragraphStyle] as? NSParagraphStyle)
        XCTAssertEqual(plainParagraph.lineHeightMultiple, 0)
    }
}
