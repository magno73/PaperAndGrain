import Foundation
import XCTest
@testable import PaperAndGrain

final class BookCLIEditingTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return url
    }

    func testPatchReopensWithIndependentIdentityAndOriginalAssets() throws {
        let root = try temporaryDirectory()
        let source = root.appendingPathComponent("original.papergrain")
        let output = root.appendingPathComponent("edited.papergrain")
        let patch = root.appendingPathComponent("patch.json")
        let photo = BookPhoto(name: "pixel", filename: "pixel.png", pixelWidth: 1, pixelHeight: 1, adjustments: PhotoAdjustments())
        let page = BookPage(layout: .mixed, photoIDs: [photo.id], text: "Prima")
        let book = Book(title: "Libro", photos: [photo], pages: [page, BookPage(layout: .text)])
        try BookStorage.write(book, to: source)
        let bytes = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aHukAAAAASUVORK5CYII="))
        try bytes.write(to: BookStorage.assetURL(filename: photo.filename, in: source))
        let boxID = UUID()
        try Data("""
        [
          {"op":"test","path":"/pages/0/id","value":"\(page.id.uuidString)"},
          {"op":"move","from":"/pages/0","path":"/pages/-"},
          {"op":"replace","path":"/pages/1/text","value":"Dopo"},
          {"op":"add","path":"/pages/1/textBoxes","value":[{"id":"\(boxID.uuidString)","text":"Didascalia","frame":{"x":0.1,"y":0.2,"width":0.5,"height":0.2}}]},
          {"op":"add","path":"/pages/1/photoPlacements","value":["\(photo.id.uuidString)",{"crop":{"x":0.3,"y":0.4,"zoom":2}}]},
          {"op":"add","path":"/typography","value":{"body":{"pointSize":18,"alignment":"right"}}},
          {"op":"add","path":"/cover","value":{"title":"Copertina","spineMM":4,"frontPhotoID":"\(photo.id.uuidString)"}},
          {"op":"replace","path":"/photos/0/adjustments/exposure","value":0.35},
          {"op":"add","path":"/photos/0/film","value":{"preset":"documentary","grain":0.1,"strength":1,"grainSize":0.5}},
          {"op":"add","path":"/printSettings","value":{"bleedMM":3,"safeMM":10,"targetPPI":240,"spreads":true}}
        ]
        """.utf8).write(to: patch)
        let result = try BookCLIEditing.patch(source: source, patchURL: patch, output: output)
        XCTAssertEqual(try BookStorage.read(from: output), result)
        XCTAssertNotEqual(result.id, book.id)
        XCTAssertEqual(result.pages.map(\.id), book.pages.reversed().map(\.id))
        XCTAssertEqual(result.pages[1].photoPlacements?[photo.id]?.crop?.zoom, 2)
        XCTAssertEqual(result.pages[1].textBoxes?.first?.id, boxID)
        XCTAssertEqual(result.cover?.frontPhotoID, photo.id)
        XCTAssertEqual(result.printSettings?.targetPPI, 240)
        XCTAssertEqual(result.typography?.body?.pointSize, 18)
        XCTAssertEqual(result.photos[0].film?.preset, .documentary)
        XCTAssertEqual(result.photos[0].adjustments?.exposure, 0.35)
        XCTAssertEqual(try Data(contentsOf: BookStorage.assetURL(filename: photo.filename, in: output)), bytes)
        XCTAssertEqual(try BookStorage.read(from: source), book)
        XCTAssertThrowsError(try BookCLIEditing.patch(source: source, patchURL: patch, output: output))
        XCTAssertEqual(try BookStorage.read(from: output), result)
    }

    func testLateOutputCreationWinsPublicationRace() throws {
        let root = try temporaryDirectory()
        let source = root.appendingPathComponent("source.papergrain")
        let target = root.appendingPathComponent("copy.papergrain")
        let original = Book(title: "Original")
        let contender = Book(title: "Concurrent output")
        try BookStorage.write(original, to: source)
        XCTAssertThrowsError(try BookCLIEditing.derive(source: source, output: target) { book, _ in
            book.title = "Must not overwrite"
            try BookStorage.write(contender, to: target)
        })
        XCTAssertEqual(try BookStorage.read(from: target), contender)
        XCTAssertEqual(try BookStorage.read(from: source), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted(), ["copy.papergrain", "source.papergrain"])
    }

    func testFailuresLeaveSourceAndDestinationAlone() throws {
        let root = try temporaryDirectory()
        let source = root.appendingPathComponent("source.papergrain")
        let target = root.appendingPathComponent("copy.papergrain")
        let patch = root.appendingPathComponent("patch.json")
        let original = Book(title: "Book", pages: [BookPage()])
        try BookStorage.write(original, to: source)
        for operation in [
            #"{"op":"add","path":"/pages/0/typo","value":1}"#,
            #"{"op":"test","path":"/title","value":true}"#,
            #"{"op":"remove","path":"/pages/01"}"#,
            #"{"op":"add","path":"/format/widthMM","value":-1}"#,
            #"{"op":"replace","path":"/pages/0/id","value":"00000000-0000-0000-0000-000000000000"}"#,
            #"{"op":"add","path":"/film","value":{"preset":"custom","strength":1,"grain":0,"grainSize":0.5,"lutFilename":"missing.cube"}}"#
        ] {
            try Data("[\(operation)]".utf8).write(to: patch)
            XCTAssertThrowsError(try BookCLIEditing.patch(source: source, patchURL: patch, output: target), operation)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted(), ["patch.json", "source.papergrain"])
        }
        XCTAssertEqual(try BookStorage.read(from: source), original)
        try FileManager.default.createSymbolicLink(at: source.appendingPathComponent("link"), withDestinationURL: root)
        XCTAssertThrowsError(try BookCLIEditing.derive(source: source, output: target) { _, _ in })
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
    }
}
