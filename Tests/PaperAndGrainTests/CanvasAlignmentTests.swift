import CoreGraphics
import XCTest
@testable import PaperAndGrain

final class CanvasAlignmentTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 300, height: 300)

    func testSnapsBothAxesIndependentlyAndDrawsGuidesFromTheAlignedFrame() {
        let frame = CGRect(x: 44, y: 62, width: 40, height: 24)
        let verticalTarget = CGRect(x: 88, y: 120, width: 44, height: 33)
        let horizontalTarget = CGRect(x: 155, y: 90, width: 65, height: 33)

        let result = CanvasAlignment.snap(frame, to: [verticalTarget, horizontalTarget], within: bounds)

        XCTAssertEqual(result.frame, CGRect(x: 48, y: 66, width: 40, height: 24))
        XCTAssertEqual(result.guides, [.vertical(x: 88, span: 66...153), .horizontal(y: 90, span: 48...220)])
    }

    func testAttractionReleasesWhenTheRawDragLeavesTheThreshold() {
        let target = CGRect(x: 85, y: 100, width: 20, height: 20)
        let near = CGRect(x: 59, y: 18, width: 20, height: 20)
        let beyond = near.offsetBy(dx: -1, dy: 0)

        let attracted = CanvasAlignment.snap(near, to: [target], within: bounds)
        XCTAssertEqual(attracted.frame.minX, 65)
        XCTAssertEqual(attracted.guides, [.vertical(x: 85, span: 18...120)])

        let released = CanvasAlignment.snap(beyond, to: [target], within: bounds)
        XCTAssertEqual(released.frame, beyond)
        XCTAssertTrue(released.guides.isEmpty)
    }

    func testNearestCenterWinsOverOtherEligibleEdges() {
        let frame = CGRect(x: 88, y: 20, width: 20, height: 20)
        let edgeTarget = CGRect(x: 112, y: 90, width: 20, height: 20)
        let centerTarget = CGRect(x: 93, y: 130, width: 12, height: 20)

        let result = CanvasAlignment.snap(frame, to: [edgeTarget, centerTarget], within: bounds)

        XCTAssertEqual(result.frame.midX, centerTarget.midX)
        XCTAssertEqual(result.guides, [.vertical(x: 99, span: 20...150)])
    }

    func testDoesNotAlignACenterToAnEdge() {
        let frame = CGRect(x: 88, y: 20, width: 20, height: 20)
        let target = CGRect(x: 98, y: 100, width: 30, height: 30)

        let result = CanvasAlignment.snap(frame, to: [target], within: bounds)

        XCTAssertEqual(result.frame, frame)
        XCTAssertTrue(result.guides.isEmpty)
    }

    func testKeepsFrameInsideBoundsAndDoesNothingWithNoTargets() {
        let frame = CGRect(x: 1, y: 18, width: 35, height: 24)
        let target = CGRect(x: 30, y: 90, width: 45, height: 50)

        let bounded = CanvasAlignment.snap(frame, to: [target], within: bounds)
        XCTAssertEqual(bounded.frame, frame)
        XCTAssertTrue(bounded.guides.isEmpty)

        let empty = CanvasAlignment.snap(frame, to: [], within: bounds)
        XCTAssertEqual(empty.frame, frame)
        XCTAssertTrue(empty.guides.isEmpty)
    }

    func testPhotoCornerSnapPreservesAspectAndShowsOnlyTheAlignedGuide() {
        let frame = CGRect(x: 30, y: 40, width: 80, height: 40)
        let vertical = CGRect(x: 140, y: 150, width: 60, height: 40)
        let competing = CGRect(x: 200, y: 96, width: 50, height: 30)
        let result = CanvasCorner.bottomRight.resizeResult(frame, by: CGSize(width: 26, height: 13),
            in: bounds, minimumSize: CGSize(width: 10, height: 10), preservesAspectRatio: true,
            allowsPhotoOverflow: true, alignmentTargets: [vertical, competing])

        XCTAssertEqual(result.frame.origin, frame.origin)
        XCTAssertEqual(result.frame.maxX, 140, accuracy: 0.000001)
        XCTAssertEqual(result.frame.height, 55, accuracy: 0.000001)
        XCTAssertEqual(result.guides, [.vertical(x: 140, span: 40...190)])
    }

    func testCropCornerSnapResizesBothAxesAndKeepsTheOppositeCornerFixed() {
        let frame = CGRect(x: 40, y: 42, width: 50, height: 48)
        let vertical = CGRect(x: 24, y: 120, width: 20, height: 30)
        let horizontal = CGRect(x: 150, y: 18, width: 40, height: 30)
        let result = CanvasCorner.topLeft.resizeResult(frame, by: CGSize(width: -13, height: -20),
            in: bounds, minimumSize: CGSize(width: 10, height: 10), allowsPhotoOverflow: true,
            alignmentTargets: [vertical, horizontal])

        XCTAssertEqual(result.frame, CGRect(x: 24, y: 18, width: 66, height: 72))
        XCTAssertEqual(result.frame.maxX, frame.maxX)
        XCTAssertEqual(result.frame.maxY, frame.maxY)
        XCTAssertEqual(result.guides, [.vertical(x: 24, span: 18...150), .horizontal(y: 18, span: 24...190)])
    }

    func testCropSnapReleasesAsTheFreeProposalMovesOutsideTheTolerance() {
        let frame = CGRect(x: 40, y: 42, width: 50, height: 48)
        let target = CGRect(x: 24, y: 120, width: 20, height: 30)
        func resize(_ dx: CGFloat) -> CanvasAlignment.Result {
            CanvasCorner.topLeft.resizeResult(frame, by: CGSize(width: dx, height: 0), in: bounds,
                minimumSize: CGSize(width: 10, height: 10), allowsPhotoOverflow: true, alignmentTargets: [target])
        }

        let snapped = resize(-10)
        XCTAssertEqual(snapped.frame.minX, 24)
        XCTAssertEqual(snapped.guides, [.vertical(x: 24, span: 42...150)])

        let released = resize(-9)
        XCTAssertEqual(released.frame.minX, 31)
        XCTAssertEqual(released.frame.maxX, frame.maxX)
        XCTAssertTrue(released.guides.isEmpty)
    }

    func testResizeCenterSnapDoesNotMoveItsAnchorOrShowAnUnreachableGuide() {
        let frame = CGRect(x: 200, y: 40, width: 40, height: 30)
        let center = CGRect(x: 218, y: 150, width: 16, height: 20)
        let unreachable = CGRect(x: 302, y: 150, width: 40, height: 20)
        func resize(_ dx: CGFloat, to target: CGRect) -> CanvasAlignment.Result {
            CanvasCorner.bottomRight.resizeResult(frame, by: CGSize(width: dx, height: 0), in: bounds,
                minimumSize: CGSize(width: 10, height: 10), alignmentTargets: [target])
        }

        let centered = resize(8, to: center)
        XCTAssertEqual(centered.frame.minX, frame.minX)
        XCTAssertEqual(centered.frame.midX, center.midX)
        XCTAssertEqual(centered.guides, [.vertical(x: 226, span: 40...170)])

        let bounded = resize(64, to: unreachable)
        XCTAssertEqual(bounded.frame.maxX, bounds.maxX)
        XCTAssertTrue(bounded.guides.isEmpty)
    }
}

final class PageEdgeSnappingTests: XCTestCase {
    private let page = CGRect(x: 0, y: 0, width: 400, height: 400)

    func testAPhotoMovedNearTheTrimLandsExactlyOnIt() {
        let nearLeft = CGRect(x: 4.5, y: 120, width: 180, height: 120)
        let moved = CanvasAlignment.snap(nearLeft, to: [page], within: page.insetBy(dx: -200, dy: -200))
        XCTAssertEqual(moved.frame.minX, 0)
        XCTAssertEqual(moved.guides.first, .vertical(x: 0, span: 0...400))

        let nearBottomRight = CGRect(x: 216, y: 277, width: 180, height: 120)
        let corner = CanvasAlignment.snap(nearBottomRight, to: [page], within: page.insetBy(dx: -200, dy: -200))
        XCTAssertEqual(corner.frame.maxX, 400)
        XCTAssertEqual(corner.frame.maxY, 400)
    }

    func testThePageEdgeReachesFurtherThanOtherObjects() {
        let nine = CGRect(x: 9, y: 150, width: 120, height: 80)
        let neighbour = CGRect(x: 0, y: 0, width: 50, height: 50)
        XCTAssertEqual(CanvasAlignment.snap(nine, to: [neighbour], within: page).frame.minX, 9, "6 pt reach for objects")
        XCTAssertEqual(CanvasAlignment.snap(nine, to: [], edges: page, within: page).frame.minX, 0, "10.5 pt reach for the page")
        let far = CGRect(x: 14, y: 150, width: 120, height: 80)
        XCTAssertEqual(CanvasAlignment.snap(far, to: [], edges: page, within: page).frame.minX, 14)

        let photo = CGRect(x: 100, y: 100, width: 150, height: 100)
        let result = CanvasCorner.bottomRight.resizeResult(photo, by: CGSize(width: 142, height: 95), in: page,
                                                           minimumSize: CGSize(width: 20, height: 20),
                                                           preservesAspectRatio: true, allowsPhotoOverflow: true,
                                                           alignmentTargets: [], edges: page)
        XCTAssertEqual(result.frame.maxX, 400, accuracy: 0.0001, "8 pt short of the trim still reaches it")
    }

    func testResizingTowardTheTrimReachesItWithoutAGap() {
        let photo = CGRect(x: 100, y: 100, width: 150, height: 100)
        // Dragging the bottom-right handle to 3 pt short of the right edge.
        let result = CanvasCorner.bottomRight.resizeResult(photo, by: CGSize(width: 147, height: 98), in: page,
                                                           minimumSize: CGSize(width: 20, height: 20),
                                                           preservesAspectRatio: true, allowsPhotoOverflow: true,
                                                           alignmentTargets: [page])
        XCTAssertEqual(result.frame.maxX, 400, accuracy: 0.0001)
        XCTAssertEqual(result.frame.width / result.frame.height, 1.5, accuracy: 0.0001)
    }
}
