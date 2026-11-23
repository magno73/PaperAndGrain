import AppKit
import XCTest
@testable import PaperAndGrain

final class TextFrameTests: XCTestCase {
    func testDefaultUsesOriginalFlowAndBodyBaselineSurvivesMovingTitle() throws {
        let title = "One heading\nwith two lines"
        var page = BookPage(layout: .text, text: "A paragraph to place independently.", heading: title)
        let book = Book(title: "Test", template: .diary)
        let original = PageComposition(page: page, book: book)
        let legacy = try XCTUnwrap(original.storyDrawingBlocks(page: page, book: book).first)
        XCTAssertEqual(legacy.role, .combined)
        let originalBaseline = try XCTUnwrap(EditorialTypesetter.baseline(legacy.text, at: (title as NSString).length + 1, in: legacy.frame))
        let manual = PageRect(x: 0.05, y: 0.65, width: 0.9, height: 0.3)
        page.titleFrame = manual
        let composition = PageComposition(page: page, book: book)
        let blocks = composition.storyDrawingBlocks(page: page, book: book)
        XCTAssertEqual(blocks.map(\.role), [.title, .body])
        XCTAssertEqual(blocks[0].frame, manual.rect(in: composition.bounds))
        let baseline = try XCTUnwrap(EditorialTypesetter.baseline(blocks[1].text, at: 0, in: blocks[1].frame))
        XCTAssertEqual(blocks[1].frame.minY + baseline, legacy.frame.minY + originalBaseline, accuracy: 0.05)
        XCTAssertTrue(EditorialTypesetter.fits(blocks[0].text, in: blocks[0].frame))
        XCTAssertTrue(EditorialTypesetter.fits(blocks[1].text, in: blocks[1].frame))
    }

    func testFullWidthBodyAndIndependentStylesSurviveRoundTrip() throws {
        let normalized = PageRect(x: 0, y: 0.45, width: 1, height: 0.5)
        let page = BookPage(layout: .text, text: "Body", heading: "Title",
                            typography: .init(title: .init(pointSize: 33), body: .init(pointSize: 16, alignment: .right)),
                            storyFrame: normalized)
        let book = Book(title: "Example", pages: [page], template: .diary)
        XCTAssertEqual(try JSONDecoder().decode(Book.self, from: JSONEncoder().encode(book)), book)
        let composition = PageComposition(page: page, book: book)
        let blocks = composition.storyDrawingBlocks(page: page, book: book)
        XCTAssertEqual(blocks[1].frame, normalized.rect(in: composition.bounds))
        XCTAssertLessThan(blocks[0].frame.minY, blocks[1].frame.minY)
        let attrs = blocks[1].text.attributes(at: 0, effectiveRange: nil)
        XCTAssertEqual((attrs[.paragraphStyle] as? NSParagraphStyle)?.alignment, .right)
        XCTAssertEqual((attrs[.font] as? NSFont)?.pointSize, 16)
        XCTAssertEqual((blocks[0].text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize, 33)
    }

    func testTextBoxCanUseWholeFrameWhileLegacyBoxKeepsPadding() throws {
        let box = PageTextBox(text: "Full width", frame: .init(x: 0, y: 0.1, width: 1, height: 0.3))
        let legacy = try JSONDecoder().decode(PageTextBox.self, from: JSONEncoder().encode(box))
        XCTAssertNil(legacy.usesFullWidth)
        XCTAssertEqual(legacy.textInsetPoints, 9)
        var full = box
        full.usesFullWidth = true
        XCTAssertEqual(full.textInsetPoints, 0)
        XCTAssertEqual(try JSONDecoder().decode(PageTextBox.self, from: JSONEncoder().encode(full)), full)
    }

    func testOverlayBackingFollowsManuallyPlacedText() throws {
        let page = BookPage(text: "Caption", arrangement: .textOverPhoto,
                            storyFrame: PageRect(x: 0.2, y: 0.12, width: 0.46, height: 0.15))
        let book = Book(title: "Test", template: .diary)
        let composition = PageComposition(page: page, book: book)
        let blocks = composition.storyDrawingBlocks(page: page, book: book)
        let frame = try XCTUnwrap(blocks.first?.frame)
        let backing = try XCTUnwrap(composition.storyBackgroundFrames(page: page, blocks: blocks).first)
        let automatic = try XCTUnwrap(composition.storyBackground)
        XCTAssertTrue(backing.contains(frame))
        XCTAssertFalse(backing.intersects(automatic))
    }

    func testManualCoverFramesAreIndependentOfTheTemplateAndBleed() throws {
        var book = Book(title: "Cover")
        let front = PageRect(x: 0, y: 0.05, width: 1, height: 0.2)
        let back = PageRect(x: 0.3, y: 0.7, width: 0.4, height: 0.2)
        book.cover = BookCover(title: "Title", backText: "Back", frontTitleFrame: front, backTextFrame: back)
        for template in [nil] + BookTemplate.allCases.map(Optional.some) {
            book.template = template
            for (isFront, frame) in [(true, front), (false, back)] {
                let geometry = BookCoverGeometry(book: book, front: isFront, bleed: 8)
                XCTAssertEqual(geometry.titleFrame, frame.rect(in: geometry.bounds))
            }
        }
        XCTAssertEqual(try JSONDecoder().decode(Book.self, from: JSONEncoder().encode(book)), book)
    }
}
