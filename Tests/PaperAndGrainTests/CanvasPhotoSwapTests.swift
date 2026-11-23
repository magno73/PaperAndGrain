import CoreGraphics
import Foundation
import XCTest
@testable import PaperAndGrain

final class CanvasPhotoSwapTests: XCTestCase {
    private let landscape = BookPhoto(name: "Landscape", filename: "one.jpg", pixelWidth: 480, pixelHeight: 240)
    private let portrait = BookPhoto(name: "Portrait", filename: "two.jpg", pixelWidth: 150, pixelHeight: 200)
    private let square = BookPhoto(name: "Square", filename: "three.jpg", pixelWidth: 300, pixelHeight: 300)

    func testAutomaticRowSwapsExactFramesAndKeepsOtherPhotosStill() throws {
        var page = BookPage(photoIDs: [landscape.id, portrait.id, square.id])
        let book = Book(title: "Test", photos: [landscape, portrait, square])
        let original = PageComposition(page: page, book: book)

        XCTAssertTrue(page.swapPhotos(landscape.id, portrait.id, in: original))
        XCTAssertEqual(page.photoIDs, [portrait.id, landscape.id, square.id])
        try assertFramesSwapped(landscape.id, portrait.id, before: original, after: PageComposition(page: page, book: book))
    }

    func testPresetSwapsAnAutomaticAndManualFrameAndKeepsCrops() throws {
        let landscapeCrop = PhotoCrop(x: 0.15, y: 0.3, zoom: 1.25)
        let portraitCrop = PhotoCrop(x: 0.8, y: 0.45, zoom: 1.6)
        let portraitFrame = PageRect(x: 0.15, y: 0.39, width: 0.5, height: 0.58)
        var page = BookPage(photoIDs: [landscape.id, portrait.id, square.id], photoPlacements: [
            landscape.id: PhotoPlacement(crop: landscapeCrop),
            portrait.id: PhotoPlacement(frame: portraitFrame, crop: portraitCrop)
        ], arrangement: .heroAboveTwo)
        let book = Book(title: "Test", photos: [landscape, portrait, square])
        let original = PageComposition(page: page, book: book)

        XCTAssertTrue(page.swapPhotos(landscape.id, portrait.id, in: original))
        let saved = try JSONEncoder().encode(page)
        let reopened = try JSONDecoder().decode(BookPage.self, from: saved)
        XCTAssertEqual(reopened.arrangement, .heroAboveTwo)
        XCTAssertEqual(reopened.photoPlacements?[landscape.id], PhotoPlacement(frame: portraitFrame, crop: landscapeCrop))
        XCTAssertEqual(reopened.photoPlacements?[portrait.id], PhotoPlacement(crop: portraitCrop))
        try assertFramesSwapped(landscape.id, portrait.id, before: original, after: PageComposition(page: reopened, book: book))
    }

    func testTargetFollowsPointerWithZoomAndIgnoresTheEdgeAndText() {
        let page = BookPage(photoIDs: [landscape.id, portrait.id, square.id], photoPlacements: [
            landscape.id: PhotoPlacement(frame: PageRect(x: 0.03, y: 0.05, width: 0.3, height: 0.3)),
            portrait.id: PhotoPlacement(frame: PageRect(x: 0.4, y: 0.2, width: 0.4, height: 0.6)),
            square.id: PhotoPlacement(frame: PageRect(x: 0.5, y: 0.3, width: 0.4, height: 0.4))
        ], textBoxes: [PageTextBox(text: "Caption", frame: PageRect(x: 0.68, y: 0.58, width: 0.14, height: 0.12))])
        let book = Book(title: "Test", photos: [landscape, portrait, square])
        let composition = PageComposition(page: page, book: book)
        let bounds = CGRect(x: 25, y: 90, width: 370, height: 370)

        func target(_ x: Double, _ y: Double, moving id: UUID? = nil) -> UUID? {
            let point = CGPoint(x: bounds.minX + x * bounds.width, y: bounds.minY + y * bounds.height)
            return CanvasPhotoSwap.target(moving: id ?? landscape.id, at: point, in: bounds, composition: composition)?.id
        }

        XCTAssertEqual(target(0.46, 0.4), portrait.id)
        XCTAssertEqual(target(0.62, 0.48), square.id)
        XCTAssertNil(target(0.41, 0.4))
        XCTAssertNil(target(0.72, 0.63))
        XCTAssertNil(target(0.15, 0.15))
        XCTAssertNil(target(0.62, 0.48, moving: UUID()))
    }

    func testHiddenPhotoCannotBeSwapped() {
        var page = BookPage(photoIDs: [landscape.id, portrait.id, square.id], arrangement: .twoAcross)
        let original = page
        let book = Book(title: "Test", photos: [landscape, portrait, square])
        let composition = PageComposition(page: page, book: book)
        XCTAssertFalse(page.swapPhotos(landscape.id, square.id, in: composition))
        XCTAssertEqual(page, original)
    }

    private func assertFramesSwapped(_ first: UUID, _ second: UUID, before: PageComposition, after: PageComposition,
                                     file: StaticString = #filePath, line: UInt = #line) throws {
        for original in before.photos {
            let target = original.id == first ? second : (original.id == second ? first : original.id)
            let new = try XCTUnwrap(after.photos.first { $0.id == target }, file: file, line: line)
            XCTAssertEqual(new.frame.minX, original.frame.minX, accuracy: 0.00001, file: file, line: line)
            XCTAssertEqual(new.frame.minY, original.frame.minY, accuracy: 0.00001, file: file, line: line)
            XCTAssertEqual(new.frame.width, original.frame.width, accuracy: 0.00001, file: file, line: line)
            XCTAssertEqual(new.frame.height, original.frame.height, accuracy: 0.00001, file: file, line: line)
        }
    }
}
