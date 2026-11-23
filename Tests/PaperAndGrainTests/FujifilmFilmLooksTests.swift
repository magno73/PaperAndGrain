import CryptoKit
import Foundation
import XCTest
@testable import PaperAndGrain

final class FujifilmFilmLooksTests: XCTestCase {
    private let resources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources", isDirectory: true)

    func testCatalogCoversTheBundledSRGBCubesAndLoadsEachOne() throws {
        let catalog = FujifilmFilmLook.all
        XCTAssertEqual(catalog.filter { $0.input == .linear }.count, 11)
        XCTAssertEqual(catalog.filter { $0.input == .provia }.count, 3)
        XCTAssertEqual(Set(catalog.map(\.id)).count, catalog.count)
        let assets = try FileManager.default.contentsOfDirectory(at: resources.appendingPathComponent("FujifilmFilmLooks"),
                                                                 includingPropertiesForKeys: nil)
        XCTAssertEqual(Set(assets.filter { $0.pathExtension == "cube" }.map(\.lastPathComponent)),
                       Set(catalog.map(\.filename)))

        for look in catalog {
            let url = look.url(in: resources)
            XCTAssertNoThrow(try FilmRenderer.validateLUT(at: url), look.filename)
            let bytes = try Data(contentsOf: url)
            let digest = SHA256.hash(data: bytes).prefix(8).map { String(format: "%02x", $0) }.joined()
            let imported = "\(url.deletingPathExtension().lastPathComponent)-\(digest).cube"
            XCTAssertEqual(FujifilmFilmLook.importedLook(filename: imported), look, look.filename)
        }
    }

    func testProjectImportRetainsLookIdentityAndOriginalBytes() throws {
        let look = try XCTUnwrap(FujifilmFilmLook.all.first { $0.input == .provia })
        let source = look.url(in: resources)
        let project = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: project) }
        let imported = try BookStorage.importBuiltInLUT(look, resources: resources, in: project)
        XCTAssertEqual(try BookStorage.importLUT(source, in: project), imported)
        let book = Book(title: "Film sample", film: FilmSettings(preset: .custom, lutFilename: imported))
        try BookStorage.write(book, to: project)
        let reopened = try BookStorage.read(from: project)
        let filename = try XCTUnwrap(reopened.film?.lutFilename)
        XCTAssertEqual(FujifilmFilmLook.importedLook(filename: filename), look)
        XCTAssertEqual(try Data(contentsOf: BookStorage.lutURL(filename: filename, in: project)),
                       try Data(contentsOf: source))
        XCTAssertNil(FujifilmFilmLook.importedLook(filename: "\(source.deletingPathExtension().lastPathComponent)-0000000000000000.cube"))
        XCTAssertNil(FujifilmFilmLook.importedLook(filename: "personal-look.cube"))
    }
}
