import AppKit
import XCTest
@testable import PaperAndGrain

final class CanvasDeleteShortcutTests: XCTestCase {
    func testRecognizesBothMacDeletionKeys() {
        XCTAssertTrue(CanvasDeleteShortcut.isDeleteKey(51, modifiers: [], isRepeat: false))
        XCTAssertTrue(CanvasDeleteShortcut.isDeleteKey(117, modifiers: [.function], isRepeat: false))
        XCTAssertTrue(CanvasDeleteShortcut.isDeleteKey(51, modifiers: [.capsLock], isRepeat: false))
    }

    func testPassesThroughOtherShortcutsAndRepeats() {
        XCTAssertFalse(CanvasDeleteShortcut.isDeleteKey(0, modifiers: [], isRepeat: false))
        XCTAssertFalse(CanvasDeleteShortcut.isDeleteKey(51, modifiers: [], isRepeat: true))
        for modifier: NSEvent.ModifierFlags in [.command, .shift, .control, .option] {
            XCTAssertFalse(CanvasDeleteShortcut.isDeleteKey(51, modifiers: modifier, isRepeat: false))
            XCTAssertFalse(CanvasDeleteShortcut.isDeleteKey(117, modifiers: [.function, modifier], isRepeat: false))
        }
    }
}
