import AppKit
import CoreGraphics
import Foundation
import XCTest
@testable import PaperAndGrain

final class GroupSelectionTests: XCTestCase {
    private let a = PageLayer.photo(UUID()), b = PageLayer.textBox(UUID()), story = PageLayer.story

    // MARK: Selecting

    func testModifierClicksAddAndRemoveOnOnePage() {
        let page = UUID(), other = UUID()
        XCTAssertEqual(CanvasGroupSelection.toggling(b, on: page, current: [a], currentPage: page), [a, b])
        XCTAssertEqual(CanvasGroupSelection.toggling(a, on: page, current: [a, b], currentPage: page), [b])
        // An object of the other page of the spread starts a new selection there.
        XCTAssertEqual(CanvasGroupSelection.toggling(b, on: other, current: [a, story], currentPage: page), [b])
        XCTAssertEqual(CanvasGroupSelection.toggling(a, on: page, current: [], currentPage: nil), [a])
        var group = CanvasGroupSelection(pageID: page, layers: [a])
        XCTAssertFalse(group.isActive, "one object is the single selection")
        group.layers.append(b)
        XCTAssertTrue(group.contains(b, on: page))
        XCTAssertFalse(group.contains(b, on: other))
        XCTAssertTrue(CanvasDeleteShortcut.extendsSelection([.shift]))
        XCTAssertTrue(CanvasDeleteShortcut.extendsSelection([.command]))
        XCTAssertFalse(CanvasDeleteShortcut.extendsSelection([.option]))
        XCTAssertTrue(CanvasDeleteShortcut.isSelectAllKey(0, modifiers: [.command], isRepeat: false))
        XCTAssertFalse(CanvasDeleteShortcut.isSelectAllKey(0, modifiers: [.command, .shift], isRepeat: false))
    }

    func testSelectionRectangleSelectsEveryObjectItTouches() {
        let objects: [(layer: PageLayer, frame: CGRect)] = [
            (a, CGRect(x: 10, y: 10, width: 100, height: 80)),
            (story, CGRect(x: 200, y: 10, width: 100, height: 200)),
            (b, CGRect(x: 10, y: 300, width: 100, height: 50)),
        ]
        // Touching is enough; the corner of the story counts.
        XCTAssertEqual(CanvasGroupSelection.touched(by: CGRect(x: 50, y: 50, width: 151, height: 10), objects: objects), [a, story])
        // Drawn from bottom right to top left.
        XCTAssertEqual(CanvasGroupSelection.touched(by: CGRect(x: 400, y: 400, width: -395, height: -395), objects: objects),
                       [a, story, b])
        XCTAssertEqual(CanvasGroupSelection.touched(by: CGRect(x: 120, y: 120, width: 60, height: 60), objects: objects), [])
        XCTAssertEqual(CanvasGroupSelection.touched(by: CGRect(x: 50, y: 50, width: 0, height: 0), objects: objects), [])
    }

    // MARK: Moving

    func testGroupMoveStopsAtEachPageEdgeAsAWhole() {
        let bounds = CGRect(x: 0, y: 0, width: 600, height: 600)
        let extent = CGRect(x: 100, y: 200, width: 300, height: 100)
        func clamp(_ dx: CGFloat, _ dy: CGFloat) -> CGSize {
            CanvasGroupGeometry.clampedTranslation(CGSize(width: dx, height: dy), extent: extent, bounds: bounds)
        }
        XCTAssertEqual(clamp(-500, 0), CGSize(width: -100, height: 0))
        XCTAssertEqual(clamp(500, 0), CGSize(width: 200, height: 0))
        XCTAssertEqual(clamp(0, -500), CGSize(width: 0, height: -200))
        XCTAssertEqual(clamp(0, 500), CGSize(width: 0, height: 300))
        XCTAssertEqual(clamp(20, -30), CGSize(width: 20, height: -30))
        // A bleeding photo already past the left edge: the group cannot go further out, only back in.
        let bleeding = CGRect(x: -9, y: 0, width: 300, height: 600)
        XCTAssertEqual(CanvasGroupGeometry.clampedTranslation(CGSize(width: -10, height: 0), extent: bleeding, bounds: bounds).width, 0)
        XCTAssertEqual(CanvasGroupGeometry.clampedTranslation(CGSize(width: 40, height: 5), extent: bleeding, bounds: bounds),
                       CGSize(width: 40, height: 0))
        XCTAssertEqual(CanvasGroupGeometry.movementArea(extent: extent, bounds: bounds), bounds)
    }

    func testMovingAGroupOnAPageKeepsIdsAndFixesAutomaticFrames() throws {
        let photos = (0..<2).map { BookPhoto(name: "p\($0)", filename: "p\($0).jpg", pixelWidth: 600, pixelHeight: 400) }
        let box = PageTextBox(text: "Etosha", frame: PageRect(x: 0.1, y: 0.7, width: 0.3, height: 0.1))
        var page = BookPage(photoIDs: photos.map(\.id))
        page.textBoxes = [box]
        let book = Book(title: "T", photos: photos, pages: [page], template: .atlas)
        let before = PageComposition(page: page, book: book)
        var moved = page
        let delta = CGSize(width: 12, height: -8)
        moved.applyFrames([.photo(photos[0].id): before.photos[0].frame.offsetBy(dx: delta.width, dy: delta.height),
                           .textBox(box.id): box.frame.rect(in: before.bounds).offsetBy(dx: delta.width, dy: delta.height)],
                          book: book)
        let after = PageComposition(page: moved, book: book)
        XCTAssertEqual(moved.id, page.id)
        XCTAssertEqual(moved.textBoxes?.map(\.id), [box.id])
        XCTAssertEqual(after.photos[0].frame.minX, before.photos[0].frame.minX + delta.width, accuracy: 0.01)
        XCTAssertEqual(after.photos[0].frame.minY, before.photos[0].frame.minY + delta.height, accuracy: 0.01)
        // The photo left out of the move kept its place: the gallery was fixed first.
        XCTAssertEqual(after.photos[1].frame.minX, before.photos[1].frame.minX, accuracy: 0.01)
        XCTAssertNotNil(moved.photoPlacements?[photos[1].id]?.frame)
        XCTAssertEqual(after.textBoxes[0].frame.rect(in: after.bounds).minX,
                       box.frame.rect(in: before.bounds).minX + delta.width, accuracy: 0.01)
    }

    func testAStoryInAGroupMovesAsOne() throws {
        var page = BookPage(layout: .text, text: "We crossed the pan at dawn.", heading: "Etosha")
        page.arrangement = .textOnly
        let book = Book(title: "T", pages: [page], template: .diary)
        let composition = PageComposition(page: page, book: book)
        let extent = try XCTUnwrap(BookPage.storyExtent(of: page, book: book, in: composition))
        var moved = page
        moved.applyFrames([.story: extent.offsetBy(dx: 0, dy: 30)], book: book)
        let after = try XCTUnwrap(BookPage.storyExtent(of: moved, book: book, in: PageComposition(page: moved, book: book)))
        XCTAssertEqual(after.minY, extent.minY + 30, accuracy: 0.5)
        XCTAssertEqual(after.minX, extent.minX, accuracy: 0.5)
    }

    // MARK: Align, distribute, size

    func testEachAlignment() {
        let frames = [CGRect(x: 10, y: 20, width: 50, height: 30), CGRect(x: 100, y: 80, width: 20, height: 60)]
        let box = CanvasGroupGeometry.extent(frames)
        XCTAssertEqual(box, CGRect(x: 10, y: 20, width: 110, height: 120))
        func run(_ alignment: CanvasGroupGeometry.Alignment) -> [CGRect] {
            CanvasGroupGeometry.align(frames, alignment, to: box)
        }
        XCTAssertEqual(run(.left).map(\.minX), [10, 10])
        XCTAssertEqual(run(.right).map(\.maxX), [120, 120])
        XCTAssertEqual(run(.center).map(\.midX), [65, 65])
        XCTAssertEqual(run(.top).map(\.minY), [20, 20])
        XCTAssertEqual(run(.bottom).map(\.maxY), [140, 140])
        XCTAssertEqual(run(.middle).map(\.midY), [80, 80])
        // Only one axis moves, and sizes stay.
        XCTAssertEqual(run(.top).map(\.minX), [10, 100])
        XCTAssertEqual(run(.left).map(\.size), frames.map(\.size))
        // One object aligns to the safe area it is given.
        let safe = CGRect(x: 28, y: 28, width: 539, height: 539)
        XCTAssertEqual(CanvasGroupGeometry.align([frames[0]], .right, to: safe)[0].maxX, safe.maxX)
    }

    func testDistributionWithUnequalSizesKeepsTheOuterTwo() {
        let frames = [CGRect(x: 0, y: 0, width: 50, height: 10), CGRect(x: 300, y: 0, width: 100, height: 10),
                      CGRect(x: 60, y: 0, width: 10, height: 10), CGRect(x: 200, y: 0, width: 20, height: 10)]
        let spread = CanvasGroupGeometry.distribute(frames, horizontally: true)
        XCTAssertEqual(spread[0], frames[0])
        XCTAssertEqual(spread[1], frames[1])
        let ordered = spread.sorted { $0.minX < $1.minX }
        let gaps = zip(ordered, ordered.dropFirst()).map { $1.minX - $0.maxX }
        XCTAssertEqual(gaps.count, 3)
        for gap in gaps { XCTAssertEqual(gap, gaps[0], accuracy: 0.0001) }
        XCTAssertEqual(gaps[0], (400 - 180) / 3, accuracy: 0.0001)
        XCTAssertEqual(spread.map(\.size), frames.map(\.size))
        let vertical = CanvasGroupGeometry.distribute(frames.map { CGRect(x: $0.minY, y: $0.minX, width: $0.height, height: $0.width) },
                                                      horizontally: false)
        XCTAssertEqual(vertical.map(\.minY), spread.map(\.minX))
        XCTAssertEqual(CanvasGroupGeometry.distribute(Array(frames.prefix(2)), horizontally: true), Array(frames.prefix(2)))
    }

    func testSameSizeTakesTheLastSelected() {
        let frames = [CGRect(x: 0, y: 0, width: 100, height: 50), CGRect(x: 200, y: 10, width: 40, height: 40),
                      CGRect(x: 300, y: 20, width: 80, height: 20)]
        let reference = frames[2]
        let boxes = CanvasGroupGeometry.sameSize(frames, width: true, as: reference, keepingProportions: false)
        XCTAssertEqual(boxes.map(\.width), [80, 80, 80])
        XCTAssertEqual(boxes.map(\.height), [50, 40, 20])
        XCTAssertEqual(boxes.map(\.origin), frames.map(\.origin))
        let photos = CanvasGroupGeometry.sameSize(frames, width: false, as: reference, keepingProportions: true)
        XCTAssertEqual(photos.map(\.height), [20, 20, 20])
        XCTAssertEqual(photos[0].width, 40, accuracy: 0.0001)
        XCTAssertEqual(photos[1].width, 20, accuracy: 0.0001)
    }

    // MARK: Layers

    func testLayerMovesKeepTheSelectionsOrder() {
        let photos = (0..<3).map { _ in UUID() }, boxes = [UUID(), UUID()]
        var page = BookPage(photoIDs: photos)
        // Back to front: p0 p1 p2 story b0 b1
        let p = photos.map(PageLayer.photo), bx = boxes.map(PageLayer.textBox)
        let selected = [bx[0], p[0]]
        var front = page
        XCTAssertTrue(front.moveLayers(selected, .front, photos: photos, boxes: boxes))
        XCTAssertEqual(front.layerOrder, [p[1], p[2], .story, bx[1], p[0], bx[0]])
        var back = page
        XCTAssertTrue(back.moveLayers(selected, .back, photos: photos, boxes: boxes))
        XCTAssertEqual(back.layerOrder, [p[0], bx[0], p[1], p[2], .story, bx[1]])
        var forward = page
        XCTAssertTrue(forward.moveLayers([p[0], p[1]], .forward, photos: photos, boxes: boxes))
        XCTAssertEqual(forward.layerOrder, [p[2], p[0], p[1], .story, bx[0], bx[1]])
        var backward = page
        XCTAssertTrue(backward.moveLayers([.story, bx[1]], .backward, photos: photos, boxes: boxes))
        XCTAssertEqual(backward.layerOrder, [p[0], p[1], .story, p[2], bx[1], bx[0]])
        // Already at the front, nothing to do.
        XCTAssertFalse(page.canMoveLayers([bx[0], bx[1]], .forward, photos: photos, boxes: boxes))
        XCTAssertTrue(page.canMoveLayers([bx[0], bx[1]], .backward, photos: photos, boxes: boxes))
        XCTAssertFalse(page.moveLayers([bx[0], bx[1]], .front, photos: photos, boxes: boxes))
        XCTAssertNil(page.layerOrder)
    }
}
