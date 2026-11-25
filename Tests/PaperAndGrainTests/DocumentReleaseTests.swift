import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import PaperAndGrain

/// Regression tests for the documents, saving and import work of the release plan (section A).
@MainActor
final class DocumentReleaseTests: XCTestCase {
    private var scratch: URL!

    override func setUp() async throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocumentReleaseTests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    // A1
    func testTrayImportAddsFilesToTheOpenBookAndKeepsItsPages() async throws {
        let package = scratch.appendingPathComponent("Trip.papergrain", isDirectory: true)
        let pages = [BookPage(text: "Day one"), BookPage(text: "Day two")]
        let original = Book(title: "Trip", pages: pages)
        try BookStorage.write(original, to: package)
        let files = try (1...3).map { index in
            let url = scratch.appendingPathComponent("Photo \(index).png")
            try Self.png(width: 40 + index, height: 30).write(to: url)
            return url
        }

        let workspace = Workspace(defaults: MemoryDefaults())
        workspace.openProject(at: package)
        var revealed: UUID?
        XCTAssertTrue(workspace.addPhotoFiles(files, language: "en") { revealed = $0 })
        try await waitUntil { !workspace.importing }

        XCTAssertNil(workspace.problem)
        XCTAssertEqual(workspace.book.id, original.id)
        XCTAssertTrue(BookStorage.sameLocation(try XCTUnwrap(workspace.directory), package))
        XCTAssertEqual(workspace.book.pages, pages)
        XCTAssertEqual(workspace.book.photos.map(\.name), ["Photo 1.png", "Photo 2.png", "Photo 3.png"])
        XCTAssertEqual(revealed, workspace.book.photos.first?.id)
        let saved = try BookStorage.read(from: package)
        XCTAssertEqual(saved.photos.count, 3)
        XCTAssertEqual(saved.pages, pages)
        for photo in saved.photos {
            XCTAssertTrue(FileManager.default.fileExists(atPath: BookStorage.assetURL(filename: photo.filename, in: package).path))
        }
    }

    // MARK: - Helpers

    func waitUntil(timeout: TimeInterval = 10, _ condition: @escaping @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return XCTFail("Timed out waiting for the workspace") }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    static func png(width: Int, height: Int) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.8, green: 0.5, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    final class MemoryDefaults: UserDefaults {
        private var values: [String: Any] = [:]

        override func set(_ value: Any?, forKey defaultName: String) { values[defaultName] = value }
        override func string(forKey defaultName: String) -> String? { values[defaultName] as? String }
        override func data(forKey defaultName: String) -> Data? { values[defaultName] as? Data }
        override func object(forKey defaultName: String) -> Any? { values[defaultName] }
        override func removeObject(forKey defaultName: String) { values.removeValue(forKey: defaultName) }
    }
}
