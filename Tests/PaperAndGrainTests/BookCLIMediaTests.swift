import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import PaperAndGrain

final class BookCLIMediaTests: XCTestCase {
    func testImportsLocalFilesInOrderAndLeavesSourceIntact() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try makeBook(in: directory)
        let manifest = source.appendingPathComponent("manifest.json")
        let original = try Data(contentsOf: manifest)
        let image = directory.appendingPathComponent("second.png")
        try Data(contentsOf: repositoryImage).write(to: image)
        let spec = directory.appendingPathComponent("selection.json")
        try Data(#"{"version":1,"files":["second.png","second.png"]}"#.utf8).write(to: spec)

        _ = try await run("import-photos", ["Source.papergrain", "--spec", "selection.json",
                                           "--output", "Imported.papergrain"], in: directory)
        let destination = directory.appendingPathComponent("Imported.papergrain")
        let book = try BookStorage.read(from: destination)
        XCTAssertEqual(book.photos.dropFirst().map(\.name), ["second.png", "second.png"])
        XCTAssertEqual(book.photos.count, Set(book.photos.map(\.filename)).count)
        XCTAssertEqual(try Data(contentsOf: manifest), original)
        for photo in book.photos {
            XCTAssertTrue(FileManager.default.fileExists(atPath:
                BookStorage.assetURL(filename: photo.filename, in: destination).path))
        }

        try Data(#"{"version":1,"files":["second.png","missing.png"]}"#.utf8).write(to: spec)
        do {
            _ = try await run("import-photos", ["Source.papergrain", "--spec", "selection.json",
                                               "--output", "Failed.papergrain"], in: directory)
            XCTFail("Import unexpectedly succeeded")
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("Failed.papergrain").path))
        }
    }

    func testPreviewEnhancementAndLUTShareProjectRendering() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try makeBook(in: directory)
        let book = try BookStorage.read(from: source)
        let photo = try XCTUnwrap(book.photos.first)
        let id = photo.id.uuidString
        _ = try await run("auto-enhance", ["Source.papergrain", "--photo", id,
                                          "--output", "Enhanced.papergrain"], in: directory)
        let enhanced = try BookStorage.read(from: directory.appendingPathComponent("Enhanced.papergrain"))
        let imageURL = BookStorage.assetURL(filename: photo.filename, in: source)
        let suggestion = try XCTUnwrap(PhotoAdjustments.automatic(from: imageURL))
        let expected = PhotoAdjustments().applyingAutomatic(suggestion)
        XCTAssertEqual(enhanced.photos.first?.adjustments, expected == PhotoAdjustments() ? nil : expected)
        XCTAssertNil(book.photos.first?.adjustments)

        let cube = """
        LUT_3D_SIZE 2
        1 1 1
        0 1 1
        1 0 1
        0 0 1
        1 1 0
        0 1 0
        1 0 0
        0 0 0
        """
        try Data(cube.utf8).write(to: directory.appendingPathComponent("invert.cube"))
        _ = try await run("import-lut", ["Enhanced.papergrain", "--file", "invert.cube", "--photo", id,
                                        "--output", "Look.papergrain"], in: directory)
        let lookDirectory = directory.appendingPathComponent("Look.papergrain")
        let look = try BookStorage.read(from: lookDirectory)
        let film = try XCTUnwrap(look.photos.first?.film)
        XCTAssertEqual(film.preset, .custom)
        let filename = try XCTUnwrap(film.lutFilename)
        XCTAssertTrue(FileManager.default.fileExists(atPath: BookStorage.lutURL(filename: filename, in: lookDirectory).path))

        for (name, flags) in [("developed.png", []), ("original.png", ["--original"])] {
            _ = try await run("photo-preview", ["Look.papergrain", "--photo", id, "--output", name,
                                               "--max-pixels", "64"] + flags, in: directory)
            let output = directory.appendingPathComponent(name)
            let png = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(png, 0, nil))
            XCTAssertEqual(max(image.width, image.height), 64)
        }
        XCTAssertNotEqual(try Data(contentsOf: directory.appendingPathComponent("developed.png")),
                          try Data(contentsOf: directory.appendingPathComponent("original.png")))
    }

    func testExportsPDFProfilesAndPreservesExistingDestination() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try makeBook(in: directory)
        for (profile, path) in [("proof", "Proof.pdf"), ("print", "Press"), ("pixart", "Pixart.pdf")] {
            _ = try await run("export-pdf", ["Source.papergrain", "--profile", profile, "--output", path], in: directory)
        }
        let proofPath = directory.appendingPathComponent("Proof.pdf")
        let bytes = try Data(contentsOf: proofPath)
        let proof = try XCTUnwrap(CGPDFDocument(proofPath as CFURL))
        XCTAssertEqual(proof.numberOfPages, 3)
        let spreadLeft = try XCTUnwrap(proof.page(at: 2)).getBoxRect(.mediaBox)
        let spreadRight = try XCTUnwrap(proof.page(at: 3)).getBoxRect(.mediaBox)
        XCTAssertEqual(spreadLeft.width, 210 * 72 / 25.4, accuracy: 0.01)
        XCTAssertEqual(spreadLeft, spreadRight)
        let press = directory.appendingPathComponent("Press")
        XCTAssertNotNil(CGPDFDocument(press.appendingPathComponent("Interior.pdf") as CFURL))
        XCTAssertNotNil(CGPDFDocument(press.appendingPathComponent("Cover.pdf") as CFURL))
        let pixart = try XCTUnwrap(CGPDFDocument(directory.appendingPathComponent("Pixart.pdf") as CFURL))
        let cover = try XCTUnwrap(pixart.page(at: 1)).getBoxRect(.mediaBox)
        XCTAssertEqual(cover.width, (2 * (207 + 11 + 19) + 4) * 72 / 25.4, accuracy: 0.01)
        XCTAssertEqual(cover.height, (220 + 2 * 19) * 72 / 25.4, accuracy: 0.01)
        do {
            _ = try await run("export-pdf", ["Source.papergrain", "--profile", "proof", "--output", "Proof.pdf"],
                              in: directory)
            XCTFail("Export unexpectedly replaced the existing PDF")
        } catch {
            XCTAssertEqual(try Data(contentsOf: proofPath), bytes)
        }
    }

    func testStandaloneBinaryRejectsApplePhotosBeforeRequestingAccess() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        guard Bundle.main.bundleURL.pathExtension != "app" else { return }
        do {
            _ = try await run("albums", ["--request-access"], in: directory)
            XCTFail("Unbundled CLI accessed Photos")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("signed Paper & Grain.app bundle"))
        }
    }

    private var repositoryImage: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/Demo.png")
    }

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("papergrain-media-test-\(UUID())",
                                                                               isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private func makeBook(in directory: URL) throws -> URL {
        let spec = directory.appendingPathComponent("book.json")
        let content: [String: Any] = [
            "version": 1, "title": "Synthetic media test",
            "assets": [["id": "demo", "path": repositoryImage.path]],
            "pages": [
                ["layout": "text", "heading": "Passaggio", "text": String(repeating: "Luce e paesaggio. ", count: 20)],
                ["layout": "fullSpread", "photos": ["demo"]],
            ],
            "cover": ["frontPhoto": "demo", "title": "Synthetic", "spineMM": 4],
        ]
        try JSONSerialization.data(withJSONObject: content).write(to: spec)
        let project = directory.appendingPathComponent("Source.papergrain", isDirectory: true)
        _ = try BookCLI.build(specURL: spec, output: project)
        return project
    }

    private func run(_ command: String, _ arguments: [String], in directory: URL) async throws -> Data {
        let result = try await BookCLIMedia.run(command: command, arguments: arguments, currentDirectory: directory)
        return try XCTUnwrap(result)
    }
}
