import CoreGraphics
import Foundation
import XCTest
@testable import PaperAndGrain

final class PhotoOverflowGeometryTests: XCTestCase {
    private let trim = CGRect(x: 0, y: 0, width: 200, height: 100)

    func testPhotoPlacementRoundTripsOutsideTrimWhileTextClamps() throws {
        let bounds = trim.offsetBy(dx: 25, dy: 35)
        let frame = CGRect(x: -25, y: -15, width: 350, height: 200)
        let placement = PhotoPlacement(frame: PageRect(frame, in: bounds))

        let data = try JSONEncoder().encode(placement)
        let reopened = try JSONDecoder().decode(PhotoPlacement.self, from: data)
        let rectangle = try XCTUnwrap(reopened.frame)

        XCTAssertEqual(rectangle.photoRect(in: bounds), frame)
        XCTAssertEqual(rectangle.rect(in: bounds), bounds)
        let legacy = PageRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        XCTAssertEqual(legacy.photoRect(in: bounds), legacy.rect(in: bounds))
    }

    func testPlacementCapsDimensionsAndKeepsThePhotoReachable() {
        let frame = PageRect(x: -99, y: 99, width: 99, height: 99).photoRect(in: trim)
        let visible = frame.intersection(trim)

        XCTAssertEqual(frame.size, CGSize(width: 800, height: 400))
        XCTAssertEqual(visible.width, 10, accuracy: 0.000001)
        XCTAssertEqual(visible.height, 5, accuracy: 0.000001)
        let limits = CanvasPhotoGeometry.movementBounds(for: frame.size, in: trim)
        XCTAssertEqual(limits.minX, frame.minX, accuracy: 0.000001)
        XCTAssertEqual(limits.maxY, frame.maxY, accuracy: 0.000001)
    }

    func testBleedAddsOnlyThePartNotAlreadyCoveredByThePhoto() {
        let frame = PageRect(x: -0.1, y: 0, width: 1.125, height: 0.75)

        XCTAssertEqual(frame.photoRect(in: trim, bleed: 10), CGRect(x: -20, y: -10, width: 230, height: 85))
    }

    func testPhotoCornerResizesPastTrimWithoutMovingTheOppositeAnchor() {
        let frame = CGRect(x: 50, y: 25, width: 100, height: 50)
        let drag = CGSize(width: 200, height: 100)
        let minimum = CGSize(width: 20, height: 20)
        let photo = CanvasCorner.bottomRight.resized(frame, by: drag, in: trim, minimumSize: minimum,
                                                       preservesAspectRatio: true, allowsPhotoOverflow: true)
        let box = CanvasCorner.bottomRight.resized(frame, by: drag, in: trim, minimumSize: minimum)

        XCTAssertEqual(photo, CGRect(x: 50, y: 25, width: 300, height: 150))
        XCTAssertEqual(box, CGRect(x: 50, y: 25, width: 150, height: 75))

        let far = CanvasCorner.bottomRight.resized(frame, by: CGSize(width: 1000, height: 1000), in: trim,
                                                      minimumSize: minimum, preservesAspectRatio: true, allowsPhotoOverflow: true)
        XCTAssertEqual(far, CGRect(x: 50, y: 25, width: 800, height: 400))
    }

    func testResizingTowardAnOffPageAnchorRetainsTheVisiblePart() {
        let frame = CGRect(x: -240, y: -120, width: 400, height: 200)
        let resized = CanvasCorner.bottomRight.resized(frame, by: CGSize(width: -500, height: -500), in: trim,
                                                          minimumSize: CGSize(width: 20, height: 20),
                                                          preservesAspectRatio: true, allowsPhotoOverflow: true)

        XCTAssertEqual(resized, CGRect(x: -240, y: -120, width: 250, height: 125))
        XCTAssertEqual(resized.intersection(trim).size, CGSize(width: 10, height: 5))
    }

    func testPartlyOutsidePhotoCanStillSnapToAnObjectOnThePage() {
        let photo = CGRect(x: -85, y: 20, width: 180, height: 70)
        let target = CGRect(x: 100, y: 70, width: 20, height: 28)
        let allowedArea = CanvasPhotoGeometry.movementBounds(for: photo.size, in: trim)
        let aligned = CanvasAlignment.snap(photo, to: [target], within: allowedArea)

        XCTAssertEqual(aligned.frame, photo.offsetBy(dx: 5, dy: 0))
        XCTAssertEqual(aligned.guides, [.vertical(x: 100, span: 20...98)])
    }
}
