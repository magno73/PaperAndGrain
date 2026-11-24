import AppKit
import XCTest
@testable import PaperAndGrain

final class CanvasPointerShortcutTests: XCTestCase {
    func testOnlySinglePrimaryPressesAreEligible() {
        XCTAssertTrue(CanvasDeleteShortcut.isPrimaryMousePress(clickCount: 1, modifiers: []))
        XCTAssertTrue(CanvasDeleteShortcut.isPrimaryMousePress(clickCount: 1, modifiers: [.shift, .option]))
        XCTAssertFalse(CanvasDeleteShortcut.isPrimaryMousePress(clickCount: 1, modifiers: [.control]))
        XCTAssertFalse(CanvasDeleteShortcut.isPrimaryMousePress(clickCount: 2, modifiers: []))
    }

    func testClicksUseTheSameMovementThresholdAsCanvasDragging() {
        let origin = CGPoint(x: 20, y: 30)

        XCTAssertTrue(CanvasDeleteShortcut.isWithinClickDistance(from: origin, to: CGPoint(x: 22, y: 32)))
        XCTAssertFalse(CanvasDeleteShortcut.isWithinClickDistance(from: origin, to: CGPoint(x: 23, y: 30)))
        XCTAssertFalse(CanvasDeleteShortcut.isWithinClickDistance(from: origin, to: CGPoint(x: 22.5, y: 32.5)))
    }

    func testEscapeAndKeynoteDeselectShortcutLeaveOtherCombinationsAvailable() {
        XCTAssertTrue(CanvasDeleteShortcut.isDeselectKey(53, modifiers: [], isRepeat: false))
        XCTAssertTrue(CanvasDeleteShortcut.isDeselectKey(0, modifiers: [.command, .shift], isRepeat: false))
        XCTAssertFalse(CanvasDeleteShortcut.isDeselectKey(53, modifiers: [.option], isRepeat: false))
        XCTAssertFalse(CanvasDeleteShortcut.isDeselectKey(0, modifiers: [.command], isRepeat: false))
        XCTAssertFalse(CanvasDeleteShortcut.isDeselectKey(53, modifiers: [], isRepeat: true))
    }

    func testArrowKeysNudgeByOneOrTenPoints() {
        XCTAssertEqual(CanvasDeleteShortcut.nudgeOffset(123, modifiers: []), CGSize(width: -1, height: 0))
        XCTAssertEqual(CanvasDeleteShortcut.nudgeOffset(126, modifiers: [.shift]), CGSize(width: 0, height: -10))
        XCTAssertNil(CanvasDeleteShortcut.nudgeOffset(124, modifiers: [.command]))
        XCTAssertNil(CanvasDeleteShortcut.nudgeOffset(0, modifiers: [.shift]))
    }

    func testDetachedAnchorConvertsCoordinatesAndDoesNotInterceptHitTesting() async {
        await MainActor.run {
            let root = NSView(frame: CGRect(x: 0, y: 0, width: 480, height: 360))
            let anchor = CanvasDeleteShortcut.Anchor(frame: CGRect(x: 40, y: 50, width: 300, height: 220))
            root.addSubview(anchor)

            let click = CGPoint(x: 61, y: 239)
            XCTAssertNil(anchor.window)
            XCTAssertNil(anchor.hitTest(click))
            XCTAssertEqual(anchor.convert(click, from: nil), CGPoint(x: 21, y: 31))
        }
    }
}
