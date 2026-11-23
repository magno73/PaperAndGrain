import AppKit
import XCTest
@testable import PaperAndGrain

final class StoryGroupTests: XCTestCase {
    let book = Book(title: "Example", template: .diary)

    func testWholeOverlayTranslatesBySameClampedDistance() throws {
        var page = BookPage(text: "A caption", heading: "Heading", arrangement: .textOverPhoto)
        let original = PageComposition(page: page, book: book)
        let blocks = original.storyBlocks(page: page, book: book)
        let backdrops = original.storyBackgroundFrames(page: page, blocks: blocks)
        XCTAssertEqual(backdrops.count, 1)
        let delta = CGSize(width: 8, height: -20)
        page.moveStoryGroup(by: delta, blocks: blocks, backdrops: backdrops, in: original.bounds)
        let moved = PageComposition(page: page, book: book)
        let newBlocks = moved.storyBlocks(page: page, book: book)
        for (before, after) in zip(blocks, newBlocks) {
            equalRect(after.frame, before.frame.offsetBy(dx: 8, dy: -20))
        }
        let newBackdrops = moved.storyBackgroundFrames(page: page, blocks: newBlocks)
        equalRect(try XCTUnwrap(newBackdrops.first), backdrops[0].offsetBy(dx: 8, dy: -20))
        page.moveStoryGroup(by: CGSize(width: 9999, height: 0), blocks: newBlocks, backdrops: newBackdrops, in: moved.bounds)
        let final = PageComposition(page: page, book: book)
        let finalBlocks = final.storyBlocks(page: page, book: book)
        let rightmostBacking = try XCTUnwrap(final.storyBackgroundFrames(page: page, blocks: finalBlocks).first)
        XCTAssertEqual(rightmostBacking.maxX, final.bounds.maxX, accuracy: 0.00001)
        let limit = moved.bounds.maxX - newBackdrops[0].maxX
        for (before, after) in zip(newBlocks, finalBlocks) {
            equalRect(after.frame, before.frame.offsetBy(dx: limit, dy: 0))
        }
    }

    func testIndividualMovementKeepsBothLegacyBackingPanelsFixed() throws {
        var page = BookPage(text: "Body", heading: "Title", arrangement: .textOverPhoto,
                            titleFrame: .init(x: 0.15, y: 0.18, width: 0.3, height: 0.1),
                            storyFrame: .init(x: 0.45, y: 0.52, width: 0.4, height: 0.17))
        let legacyData = try JSONEncoder().encode(page)
        XCTAssertNil((try JSONSerialization.jsonObject(with: legacyData) as? [String: Any])?["storyBackdropFrames"])
        page = try JSONDecoder().decode(BookPage.self, from: legacyData)
        let original = PageComposition(page: page, book: book)
        let before = original.storyBackgroundFrames(page: page, blocks: original.storyBlocks(page: page, book: book))
        XCTAssertEqual(before.count, 2)
        page.freezeStoryBackdrop(before, in: original.bounds)
        page.titleFrame?.y = 0.1
        let moved = PageComposition(page: page, book: book)
        let after = moved.storyBackgroundFrames(page: page, blocks: moved.storyBlocks(page: page, book: book))
        XCTAssertEqual(after.count, before.count)
        for (original, current) in zip(before, after) { equalRect(original, current) }
        XCTAssertEqual(try JSONDecoder().decode(BookPage.self, from: JSONEncoder().encode(page)), page)
        page.arrangement = .textOnly
        let plain = PageComposition(page: page, book: book)
        XCTAssertTrue(plain.storyBackgroundFrames(page: page, blocks: []).isEmpty)
    }

    func testNoMovementKeepsLegacyGeometryImplicit() {
        var page = BookPage(text: "Only body", arrangement: .textOverPhoto)
        let original = page
        let composition = PageComposition(page: page, book: book)
        let blocks = composition.storyBlocks(page: page, book: book)
        page.moveStoryGroup(by: .zero, blocks: blocks, backdrops: [], in: composition.bounds)
        page.moveStoryGroup(by: CGSize(width: 5, height: 8), blocks: [], backdrops: [], in: composition.bounds)
        XCTAssertEqual(page, original)
    }

    private func equalRect(_ actual: CGRect, _ expected: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.00001, file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.00001, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.00001, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.00001, file: file, line: line)
    }
}
