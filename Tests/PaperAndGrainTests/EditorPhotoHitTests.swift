import CoreGraphics
import XCTest
@testable import PaperAndGrain

final class EditorPhotoHitTests: XCTestCase {
    func testScaledPageHitUsesStackingOrderAndClipsOversizedPhotos() {
        let bottom = BookPhoto(name: "Bottom", filename: "bottom.jpg", pixelWidth: 100, pixelHeight: 100)
        let top = BookPhoto(name: "Top", filename: "top.jpg", pixelWidth: 100, pixelHeight: 100)
        let page = BookPage(photoIDs: [bottom.id, top.id], photoPlacements: [
            bottom.id: PhotoPlacement(frame: PageRect(x: 0.2, y: 0.15, width: 0.55, height: 0.6)),
            top.id: PhotoPlacement(frame: PageRect(x: 0.5, y: 0.3, width: 0.65, height: 0.65))
        ], textBoxes: [PageTextBox(text: "Caption", frame: PageRect(x: 0.55, y: 0.55, width: 0.15, height: 0.1))])
        let book = Book(title: "Test", photos: [bottom, top], pages: [page])
        let composition = PageComposition(page: page, book: book)
        let frame = CGRect(x: 130, y: 70, width: 360, height: 360)

        func hit(_ x: Double, _ y: Double) -> UUID? {
            let point = CGPoint(x: frame.minX + x * frame.width, y: frame.minY + y * frame.height)
            return EditorPhotoHitTest.onPage(at: point, frame: frame, composition: composition)
        }

        XCTAssertEqual(hit(0.35, 0.35), bottom.id)
        XCTAssertEqual(hit(0.6, 0.4), top.id)
        XCTAssertNil(hit(0.62, 0.6))
        XCTAssertNil(hit(1.05, 0.4))
    }

    func testCoverHitExcludesTheTitleBand() {
        let book = Book(title: "Title")
        let geometry = BookCoverGeometry(book: book, front: true)
        let frame = CGRect(x: 270, y: 120, width: 300, height: 300)

        XCTAssertTrue(EditorPhotoHitTest.onCover(at: CGPoint(x: 420, y: 250), frame: frame, geometry: geometry))
        XCTAssertFalse(EditorPhotoHitTest.onCover(at: CGPoint(x: 420, y: 340), frame: frame, geometry: geometry))
        XCTAssertFalse(EditorPhotoHitTest.onCover(at: CGPoint(x: 269, y: 250), frame: frame, geometry: geometry))
    }
}
