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
}
