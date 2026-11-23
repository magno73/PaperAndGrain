import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import PaperAndGrain

final class CoreRegressionTests: XCTestCase {
    func testVersionOneOpensWithNewDefaults() throws {
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (book, _) = try fixture(in: folder)
        try BookStorage.write(book, to: folder)

        let manifest = folder.appendingPathComponent("manifest.json")
        let old = try Data(contentsOf: manifest)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: old) as? [String: Any])
        XCTAssertNil(json["film"])
        XCTAssertNil(json["cover"])
        XCTAssertNil(json["printSettings"])
        let reopened = try BookStorage.read(from: folder)
        XCTAssertEqual(reopened, book)
        XCTAssertEqual(reopened.effectiveFilm(for: reopened.photos[0]), FilmSettings())
    }

    func testImported13CubeSurvivesMovingProject() throws {
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var (book, photo) = try fixture(in: folder)
        let cube = folder.appendingPathComponent("identity13.cube")
        try identityCube().write(to: cube, atomically: true, encoding: .utf8)
        let stored = try BookStorage.importLUT(cube, in: folder)
        XCTAssertEqual(try BookStorage.importLUT(cube, in: folder), stored)
        var look = FilmSettings(preset: .custom, lutFilename: stored)
        book.film = look
        XCTAssertEqual(book.effectiveFilm(for: photo), look)
        photo.film = FilmSettings(preset: .monochrome)
        book.photos[0] = photo
        XCTAssertEqual(book.effectiveFilm(for: photo).preset, .monochrome)
        try BookStorage.write(book, to: folder)

        let migrated = folder.appendingPathComponent("moved.papergrain", isDirectory: true)
        try FileManager.default.createDirectory(at: migrated, withIntermediateDirectories: false)
        for name in ["manifest.json", "assets", "looks"] {
            try FileManager.default.copyItem(at: folder.appendingPathComponent(name), to: migrated.appendingPathComponent(name))
        }
        try FileManager.default.removeItem(at: cube)
        let reopened = try BookStorage.read(from: migrated)
        XCTAssertEqual(reopened, book)
        let image = BookStorage.assetURL(filename: photo.filename, in: migrated)
        let lut = BookStorage.lutURL(filename: stored, in: migrated)
        try FilmRenderer.validateLUT(at: lut)
        let original = try XCTUnwrap(FilmRenderer.image(from: image, maxPixelSize: 16, settings: FilmSettings(), lutURL: nil))
        let identity = try XCTUnwrap(FilmRenderer.image(from: image, maxPixelSize: 16, settings: look, lutURL: lut))
        XCTAssertEqual(rgba(original), rgba(identity))
        look.grain = 0.7
        let grain = try XCTUnwrap(FilmRenderer.image(from: image, maxPixelSize: 16, settings: look, lutURL: lut))
        let second = try XCTUnwrap(FilmRenderer.image(from: image, maxPixelSize: 16, settings: look, lutURL: lut))
        XCTAssertEqual(rgba(grain), rgba(second))
    }

    func testPrintKeepsPanoramaOnFacingPagesAndUsesTrimBox() throws {
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var (book, photo) = try fixture(in: folder)
        book.pages = [
            BookPage(layout: .gallery, photoIDs: [photo.id]),
            BookPage(layout: .fullSpread, photoIDs: [photo.id], framing: 0.7),
        ]
        book.printSettings = PrintSettings(bleedMM: 3, spreads: true)
        book.cover = BookCover(title: "Namibia", frontPhotoID: photo.id, spineMM: 10)
        let package = folder.appendingPathComponent("print", isDirectory: true)
        try BookPDF.writePrint(book, directory: folder, to: package)
        let inside = try pdf(package, "Interior.pdf")
        let cover = try pdf(package, "Cover.pdf")
        XCTAssertEqual(inside.numberOfPages, 2)
        XCTAssertEqual(cover.numberOfPages, 1)
        for number in 1...inside.numberOfPages {
            let page = try XCTUnwrap(inside.page(at: number))
            XCTAssertEqual(page.getBoxRect(.trimBox).width * 25.4 / 72, 420, accuracy: 0.02)
            XCTAssertEqual(page.getBoxRect(.bleedBox).width * 25.4 / 72, 426, accuracy: 0.02)
        }
        let coverPage = try XCTUnwrap(cover.page(at: 1))
        XCTAssertEqual(coverPage.getBoxRect(.trimBox).width * 25.4 / 72, 430, accuracy: 0.02)
        XCTAssertFalse(BookPDF.printWarnings(book).isEmpty)

        book.printSettings?.spreads = false
        let singles = folder.appendingPathComponent("singles", isDirectory: true)
        try BookPDF.writePrint(book, directory: folder, to: singles)
        XCTAssertEqual(try pdf(singles, "Interior.pdf").numberOfPages, 4)
        try BookPDF.write(book, directory: folder, to: folder.appendingPathComponent("proof.pdf"))
        XCTAssertEqual(try pdf(folder, "proof.pdf").numberOfPages, 3)
    }

    func testMixedAreaSupportsAnAdjacentTextBox() throws {
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var (book, photo) = try fixture(in: folder)
        book.pages = [BookPage(layout: .mixed, photoIDs: [photo.id], text: "Road to the coast.", textPlacement: .beside)]
        try BookStorage.write(book, to: folder)
        XCTAssertEqual(try BookStorage.read(from: folder).pages.first?.textPlacement, .beside)
        let safe = CGRect(x: 12, y: 12, width: 200, height: 150)
        for placement in [PageTextPlacement.beside, .below] {
            let parts = BookLayoutGeometry.mixedArea(in: safe, placement: placement, spacing: 10)
            XCTAssertTrue(safe.contains(parts.photo))
            XCTAssertTrue(safe.contains(parts.text))
            XCTAssertFalse(parts.photo.intersects(parts.text))
        }
        try BookPDF.write(book, directory: folder, to: folder.appendingPathComponent("mixed.pdf"))
        XCTAssertEqual(try pdf(folder, "mixed.pdf").numberOfPages, 1)
    }

    private func fixture(in folder: URL) throws -> (Book, BookPhoto) {
        var book = Book(title: "Fixture")
        try BookStorage.write(book, to: folder)
        let photo = BookPhoto(name: "colors.png", filename: "colors.png", pixelWidth: 16, pixelHeight: 8)
        let cs = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: 16, height: 8, bitsPerComponent: 8,
                                               bytesPerRow: 64, space: cs,
                                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 0.1, green: 0.35, blue: 0.75, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        context.setFillColor(red: 0.8, green: 0.44, blue: 0.15, alpha: 1)
        context.fill(CGRect(x: 8, y: 0, width: 8, height: 8))
        let url = BookStorage.assetURL(filename: photo.filename, in: folder)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        book.photos = [photo]
        book.autoLayout()
        return (book, photo)
    }

    private func rgba(_ image: CGImage) -> Data? {
        guard let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let data = context.data else { return nil }
        return Data(bytes: data, count: context.bytesPerRow * context.height)
    }

    private func identityCube() -> String {
        var lines = ["TITLE \"Identity\"", "LUT_3D_SIZE 13", "DOMAIN_MIN 0 0 0", "DOMAIN_MAX 1 1 1"]
        for blue in 0..<13 {
            for green in 0..<13 {
                for red in 0..<13 {
                    lines.append("\(Double(red)/12) \(Double(green)/12) \(Double(blue)/12)")
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    private func pdf(_ directory: URL, _ name: String) throws -> CGPDFDocument {
        try XCTUnwrap(CGPDFDocument(directory.appendingPathComponent(name) as CFURL))
    }

    private func scratchFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        return folder
    }
}
