import AppKit
import CoreGraphics
import Foundation
import XCTest
@testable import PaperAndGrain

@MainActor
final class CanvasClipboardTests: XCTestCase {
    private func sample() -> (book: Book, source: BookPage, photo: BookPhoto, box: PageTextBox) {
        let photo = BookPhoto(name: "a", filename: "a.jpg", pixelWidth: 600, pixelHeight: 400)
        let box = PageTextBox(text: "Etosha, 6 am", frame: PageRect(x: 0.1, y: 0.7, width: 0.3, height: 0.1))
        var source = BookPage(layout: .mixed, photoIDs: [photo.id], text: "We crossed the pan.", heading: "Etosha")
        source.textBoxes = [box]
        source.photoPlacements = [photo.id: PhotoPlacement(frame: PageRect(x: 0.2, y: 0.1, width: 0.5, height: 0.3),
                                                           crop: PhotoCrop(x: 0.3, y: 0.5, zoom: 1.4), captionPosition: .above)]
        let book = Book(title: "T", photos: [photo], pages: [source, BookPage()], template: .atlas)
        return (book, source, photo, box)
    }

    private func clip(_ book: Book, _ page: BookPage, _ layers: [PageLayer]) throws -> CanvasClipboard {
        try XCTUnwrap(CanvasClipboard(layers: layers, page: page, book: book))
    }

    // MARK: Encoding

    func testEncodeAndDecodeEveryKind() throws {
        let (book, source, photo, box) = sample()
        let copied = try clip(book, source, [.textBox(box.id), .photo(photo.id), .story])
        XCTAssertEqual(copied.objects.count, 3)
        // Drawing order, not selection order: photo, story, box.
        guard case .photo = copied.objects[0], case .story = copied.objects[1], case .textBox = copied.objects[2] else {
            return XCTFail("objects out of drawing order")
        }
        let data = try JSONEncoder().encode(copied)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"kind\":\"photo\"") && json.contains("\"kind\":\"story\""))
        XCTAssertEqual(try JSONDecoder().decode(CanvasClipboard.self, from: data), copied)
        XCTAssertEqual(copied.plainText, "Etosha\n\nWe crossed the pan.\n\nEtosha, 6 am")
        let unknown = Data(#"{"version":1,"bookID":"\#(UUID())","pageID":"\#(UUID())","pageWidth":1,"pageHeight":1,"objects":[{"kind":"map"}]}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(CanvasClipboard.self, from: unknown))
        XCTAssertNil(CanvasClipboard(layers: [.textBox(UUID())], page: source, book: book))
    }

    func testThePasteboardCarriesObjectsAndPlainText() throws {
        let (book, source, _, box) = sample()
        let copied = try clip(book, source, [.textBox(box.id)])
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("test-" + UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        try copied.write(to: pasteboard)
        XCTAssertEqual(CanvasClipboard.read(from: pasteboard), .objects(copied))
        XCTAssertEqual(pasteboard.string(forType: .string), "Etosha, 6 am")
        pasteboard.clearContents()
        pasteboard.setString("From another app", forType: .string)
        XCTAssertEqual(CanvasClipboard.read(from: pasteboard), .text("From another app"))
        XCTAssertTrue(CanvasClipboard.canRead(from: pasteboard))
        pasteboard.clearContents()
        XCTAssertNil(CanvasClipboard.read(from: pasteboard))
    }

    // MARK: Paste rules

    func testPasteOnAnotherPageKeepsFramesAndOrderWithNewBoxIds() throws {
        let (book, source, photo, box) = sample()
        let copied = try clip(book, source, [.photo(photo.id), .textBox(box.id)])
        let target = book.pages[1]
        let pasted = copied.paste(into: target, book: book)
        XCTAssertEqual(pasted.skipped, [])
        XCTAssertEqual(pasted.page.id, target.id)
        XCTAssertEqual(pasted.page.photoIDs, [photo.id])
        let placement = try XCTUnwrap(pasted.page.photoPlacements?[photo.id])
        XCTAssertEqual(placement.crop, PhotoCrop(x: 0.3, y: 0.5, zoom: 1.4))
        XCTAssertEqual(placement.captionPosition, .above)
        let bounds = PageComposition(page: target, book: book).bounds
        XCTAssertEqual(try XCTUnwrap(placement.frame).rect(in: bounds), source.photoPlacements?[photo.id]?.frame?.rect(in: bounds))
        let newBox = try XCTUnwrap(pasted.page.textBoxes?.first)
        XCTAssertNotEqual(newBox.id, box.id)
        XCTAssertEqual(newBox.text, box.text)
        XCTAssertEqual(newBox.frame.rect(in: bounds).minX, box.frame.rect(in: bounds).minX, accuracy: 0.001)
        XCTAssertEqual(pasted.layers, [.photo(photo.id), .textBox(newBox.id)])
        XCTAssertEqual(pasted.page.layerOrder?.suffix(2), [.photo(photo.id), .textBox(newBox.id)])
    }

    func testPasteOnTheSamePageOffsetsBoxesAndSkipsPhotos() throws {
        let (book, source, photo, box) = sample()
        let copied = try clip(book, source, [.photo(photo.id), .textBox(box.id)])
        let pasted = copied.paste(into: source, book: book)
        XCTAssertEqual(pasted.skipped, [.alreadyOnPage])
        XCTAssertEqual(pasted.page.photoIDs, [photo.id])
        XCTAssertEqual(pasted.page.textBoxes?.count, 2)
        let bounds = PageComposition(page: source, book: book).bounds
        let copy = try XCTUnwrap(pasted.page.textBoxes?.last).frame.rect(in: bounds)
        let original = box.frame.rect(in: bounds)
        XCTAssertEqual(copy.minX - original.minX, 12, accuracy: 0.001)
        XCTAssertEqual(copy.minY - original.minY, 12, accuracy: 0.001)
    }

    func testAnotherBookTakesTextButNotPhotos() throws {
        let (book, source, photo, box) = sample()
        let copied = try clip(book, source, [.photo(photo.id), .textBox(box.id), .story])
        let other = Book(title: "Other", photos: [photo], pages: [BookPage()])
        let pasted = copied.paste(into: other.pages[0], book: other)
        XCTAssertEqual(pasted.skipped, [.otherBook])
        XCTAssertTrue(pasted.page.photoIDs.isEmpty)
        XCTAssertEqual(pasted.page.textBoxes?.count, 1)
        XCTAssertEqual(pasted.page.heading, "Etosha")
        XCTAssertEqual(pasted.page.text, "We crossed the pan.")
        XCTAssertEqual(pasted.layers.count, 2)
    }

    func testAStoryBecomesTheStoryOrATextBox() throws {
        let (book, source, _, _) = sample()
        let copied = try clip(book, source, [.story])
        // A page without a story takes it as its story, with frames so it shows on any layout.
        let empty = copied.paste(into: book.pages[1], book: book)
        XCTAssertEqual(empty.layers, [.story])
        XCTAssertEqual(empty.page.heading, "Etosha")
        XCTAssertNotNil(empty.page.titleFrame)
        XCTAssertNotNil(empty.page.storyFrame)
        XCTAssertFalse(PageComposition(page: empty.page, book: book).storyBlocks(page: empty.page, book: book).isEmpty)
        // A page with a story gets a text box with the same text, and keeps its own story.
        let full = copied.paste(into: source, book: book)
        XCTAssertEqual(full.page.heading, "Etosha")
        XCTAssertEqual(full.page.text, "We crossed the pan.")
        let added = try XCTUnwrap(full.page.textBoxes?.last)
        XCTAssertEqual(added.text, "Etosha\n\nWe crossed the pan.")
        XCTAssertEqual(full.layers, [.textBox(added.id)])
    }

    func testPlainTextBecomesABoxInTheMiddle() {
        let bounds = CGRect(x: 0, y: 0, width: 600, height: 600)
        let box = CanvasClipboard.textBox(for: "Hello", in: bounds, safe: bounds.insetBy(dx: 40, dy: 40))
        let frame = box.frame.rect(in: bounds)
        XCTAssertEqual(frame.midX, 300, accuracy: 0.001)
        XCTAssertEqual(frame.midY, 300, accuracy: 0.001)
        XCTAssertEqual(box.text, "Hello")
    }

    func testCutTakesTheObjectsOffAndPastingThreeOnAnEmptyPageCanBeRemoved() throws {
        let (book, source, photo, box) = sample()
        let layers: [PageLayer] = [.photo(photo.id), .textBox(box.id), .story]
        let copied = try clip(book, source, layers)
        var cut = source
        cut.removeObjects(layers)
        XCTAssertTrue(cut.photoIDs.isEmpty)
        XCTAssertNil(cut.textBoxes)
        XCTAssertFalse(cut.hasStoryText)
        XCTAssertNil(cut.titleFrame)
        // Undo restores the page as it was: pasting then removing what was pasted gives the empty page back.
        let empty = book.pages[1]
        let pasted = copied.paste(into: empty, book: book)
        XCTAssertEqual(pasted.layers.count, 3)
        var removed = pasted.page
        removed.removeObjects(pasted.layers)
        XCTAssertTrue(removed.photoIDs.isEmpty)
        XCTAssertNil(removed.textBoxes)
        XCTAssertFalse(removed.hasStoryText)
        XCTAssertEqual(empty.photoIDs, [], "the page pasted onto is a value; the editor's undo restores it")
    }

    // MARK: Responder chain

    func testEditCommandsComeAfterTextViewsInTheResponderChain() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let content = NSView(frame: window.contentLayoutRect)
        window.contentView = content
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 40))
        content.addSubview(text)
        let anchor = CanvasDeleteShortcut.Anchor(frame: .zero)
        var copied = 0
        anchor.editResponder.commands = CanvasEditCommands(canCopy: { true }, canPaste: { false }, copy: { copied += 1 })
        content.addSubview(anchor)
        XCTAssertTrue(window.nextResponder === anchor.editResponder)
        // A text view that is first responder answers copy: itself; the canvas only comes after the window.
        XCTAssertTrue(window.makeFirstResponder(text))
        var responder: NSResponder? = window.firstResponder
        var first: NSResponder?
        while let current = responder {
            if current.responds(to: #selector(NSText.copy(_:))) { first = current; break }
            responder = current.nextResponder
        }
        XCTAssertTrue(first === text)
        // With no text first responder, the canvas answers and validates.
        XCTAssertTrue(window.makeFirstResponder(nil))
        let item = NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        XCTAssertTrue(anchor.editResponder.validateMenuItem(item))
        item.action = #selector(NSText.paste(_:))
        XCTAssertFalse(anchor.editResponder.validateMenuItem(item))
        anchor.editResponder.copy(nil)
        XCTAssertEqual(copied, 1)
        // Joining again does not insert it twice; leaving restores the chain.
        anchor.joinResponderChain()
        XCTAssertTrue(window.nextResponder === anchor.editResponder)
        XCTAssertFalse(anchor.editResponder.nextResponder === anchor.editResponder)
        anchor.removeFromSuperview()
        XCTAssertFalse(window.nextResponder === anchor.editResponder)
        window.close()
    }
}
