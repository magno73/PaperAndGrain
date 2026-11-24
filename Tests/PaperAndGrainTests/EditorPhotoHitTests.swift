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

        let photo = UUID()
        let map = CanvasHitMap.cover(geometry, photoID: photo)
        XCTAssertEqual(map.target(at: CGPoint(x: 420, y: 250), in: frame), .photo(photo))
        XCTAssertNotEqual(map.target(at: CGPoint(x: 420, y: 340), in: frame), .photo(photo))
        XCTAssertNil(map.target(at: CGPoint(x: 269, y: 250), in: frame))
    }

    func testCanvasRoutesEachClickToTheTopVisibleObjectOrPaper() {
        let photo = UUID()
        let box = UUID()
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
        let frame = CGRect(x: 50, y: 20, width: 100, height: 100)
        let map = CanvasHitMap(bounds: bounds, regions: [
            .init(frame: CGRect(x: 0, y: 0, width: 200, height: 130), target: .photo(photo)),
            .init(frame: CGRect(x: 20, y: 20, width: 110, height: 80), target: .storyGroup),
            .init(frame: CGRect(x: 30, y: 30, width: 90, height: 20), target: .story(.title)),
            .init(frame: CGRect(x: 40, y: 40, width: 20, height: 20), target: .textBox(box)),
        ])
        XCTAssertEqual(map.target(at: CGPoint(x: 130, y: 60), in: frame), .photo(photo))
        XCTAssertEqual(map.target(at: CGPoint(x: 65, y: 62), in: frame), .storyGroup)
        XCTAssertEqual(map.target(at: CGPoint(x: 98, y: 41), in: frame), .story(.title))
        XCTAssertEqual(map.target(at: CGPoint(x: 75, y: 43), in: frame), .textBox(box))
        XCTAssertEqual(map.target(at: CGPoint(x: 73, y: 99), in: frame), .paper)
        XCTAssertNil(map.target(at: CGPoint(x: 72, y: 121), in: frame))
    }

    func testPhotoHitUsesTheMovedTextFrame() {
        let photo = BookPhoto(name: "Page", filename: "page.jpg", pixelWidth: 100, pixelHeight: 100)
        let page = BookPage(photoIDs: [photo.id], heading: "Title", arrangement: .textOverPhoto,
                            titleFrame: PageRect(x: 0.21, y: 0.12, width: 0.42, height: 0.18))
        let book = Book(title: "Test", photos: [photo])
        let composition = PageComposition(page: page, book: book)
        let frame = CGRect(x: 130, y: 70, width: 360, height: 360)
        let text = composition.storyBlocks(page: page, book: book).map(\.frame)

        XCTAssertNil(EditorPhotoHitTest.onPage(at: CGPoint(x: 270, y: 142), frame: frame, composition: composition,
                                               storyFrames: text))
        XCTAssertEqual(EditorPhotoHitTest.onPage(at: CGPoint(x: 260, y: 364), frame: frame, composition: composition,
                                                 storyFrames: text), photo.id)
    }

    func testLibraryTileCannotBeSelectedOutsideTheScrollViewport() {
        let id = UUID()
        let frames = LibraryPhotoFrames(viewport: CGRect(x: 600, y: 180, width: 260, height: 350),
                                        tiles: [id: CGRect(x: 650, y: 157, width: 72, height: 56)])
        XCTAssertEqual(frames.photo(at: CGPoint(x: 680, y: 200)), id)
        XCTAssertNil(frames.photo(at: CGPoint(x: 680, y: 165)))
        XCTAssertNil(frames.photo(at: CGPoint(x: 740, y: 200)))
    }
}
