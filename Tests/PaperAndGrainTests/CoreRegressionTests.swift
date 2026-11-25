import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import PaperAndGrain

final class CoreRegressionTests: XCTestCase {
    func testPhotoResizeKeepsItsAspectRatioWhileCropCornersCanChangeTheMask() {
        let bounds = CGRect(x: 0, y: 0, width: 600, height: 400)
        let frame = CGRect(x: 80, y: 90, width: 200, height: 100)
        let drag = CGSize(width: 100, height: 100)
        let minimum = CGSize(width: 40, height: 40)

        let photo = CanvasCorner.bottomRight.resized(frame, by: drag, in: bounds, minimumSize: minimum,
                                                       preservesAspectRatio: true)
        XCTAssertEqual(photo.origin, frame.origin)
        XCTAssertEqual(photo.width / photo.height, frame.width / frame.height, accuracy: 0.0001)
        XCTAssertGreaterThan(photo.width, frame.width)

        let mask = CanvasCorner.bottomRight.resized(frame, by: drag, in: bounds, minimumSize: minimum)
        XCTAssertEqual(mask, CGRect(x: 80, y: 90, width: 300, height: 200))
        XCTAssertTrue(bounds.contains(mask))
    }

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
        let oldPage = try XCTUnwrap((json["pages"] as? [[String: Any]])?.first)
        XCTAssertNil(oldPage["photoPlacements"])
        XCTAssertNil(oldPage["storyFrame"])
        XCTAssertNil(oldPage["textBoxes"])
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
            BookPage(layout: .fullSpread, photoIDs: [photo.id], framing: 0.7, arrangement: .fullSpread),
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

    func testEditorialTemplateSurvivesAnExistingProjectAndExports() throws {
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var (book, photo) = try fixture(in: folder)
        book.pages = [BookPage(layout: .mixed, photoIDs: [photo.id], text: "Al tramonto le dune sembravano un mare.",
                               textPlacement: .beside, heading: "Il mare di dune")]
        book.cover = BookCover(title: "Namibia", frontPhotoID: photo.id, spineMM: 10)
        let originalPages = book.pages
        let styles = BookTemplate.allCases.map { $0.style.paper }
        XCTAssertEqual(Set(styles).count, BookTemplate.allCases.count)
        for template in BookTemplate.allCases {
            book.template = template
            try BookStorage.write(book, to: folder)
            let reopened = try BookStorage.read(from: folder)
            XCTAssertEqual(reopened.template, template)
            XCTAssertEqual(reopened.pages, originalPages)
            let destination = folder.appendingPathComponent(template.rawValue)
            try BookPDF.writePrint(reopened, directory: folder, to: destination)
            XCTAssertEqual(try pdf(destination, "Interior.pdf").numberOfPages, 1)
            XCTAssertEqual(try pdf(destination, "Cover.pdf").numberOfPages, 1)
        }
        let missingPhoto = UUID()
        book.cover?.frontPhotoID = missingPhoto
        let destination = folder.appendingPathComponent("missing-cover")
        XCTAssertThrowsError(try BookPDF.writePrint(book, directory: folder, to: destination)) { error in
            guard case BookPDF.ExportError.missingImage(let id) = error else {
                return XCTFail("Expected an unavailable cover photo, got \(error)")
            }
            XCTAssertEqual(id, missingPhoto.uuidString)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testManualPlacementsPreserveAutomaticRowsAndUseBothCropAxes() throws {
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var (book, photo) = try fixture(in: folder)
        let initial = try XCTUnwrap(PageComposition(page: book.pages[0], book: book).photos.first)
        var second = photo
        second.id = UUID()
        book.photos.append(second)
        let frame = PageRect(x: 0.7, y: 0, width: 0.3, height: 0.25)
        let crop = PhotoCrop(x: 1, y: 0, zoom: 2)
        book.pages[0].photoIDs.append(second.id)
        book.pages[0].photoPlacements = [second.id: PhotoPlacement(frame: frame, crop: crop)]
        let composition = PageComposition(page: book.pages[0], book: book)
        XCTAssertEqual(composition.photos.map(\.id), [photo.id, second.id])
        XCTAssertEqual(composition.photos[0].frame, initial.frame)
        XCTAssertEqual(composition.photos[1].frame, frame.rect(in: composition.bounds))
        let bleed = PageComposition(page: book.pages[0], book: book, bleed: 8)
        XCTAssertEqual(bleed.photos[1].frame.minX, composition.photos[1].frame.minX, accuracy: 0.0001)
        XCTAssertEqual(bleed.photos[1].frame.minY, -8)
        XCTAssertEqual(bleed.photos[1].frame.maxX, composition.bounds.maxX + 8, accuracy: 0.0001)
        let sample = CGRect(x: 10, y: 20, width: 60, height: 60)
        XCTAssertEqual(crop.imageRect(for: CGSize(width: 120, height: 60), in: sample, fills: true),
                       CGRect(x: -170, y: 20, width: 240, height: 120))
        book.pages[0].photoPlacements = [photo.id: PhotoPlacement(crop: crop)]
        XCTAssertTrue(PageComposition(page: book.pages[0], book: book).photos[0].fills)

        book.pages[0] = BookPage(layout: .fullSpread, photoIDs: [photo.id], framing: 0.8)
        let panorama = PageComposition(page: book.pages[0], book: book, bleed: 5)
        XCTAssertEqual(panorama.photos[0].crop, PhotoCrop(x: 0.8, y: 0.8))
        XCTAssertEqual(panorama.photos[0].frame, panorama.bounds.insetBy(dx: -5, dy: -5))
        XCTAssertEqual(panorama.bounds.width, 2 * book.format.pageSize.width)
    }

    func testPPIWarningUsesEnlargedContentAndEmptyTextBoxesDoNotPrint() throws {
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var (book, photo) = try fixture(in: folder)
        book.printSettings = PrintSettings(bleedMM: 0, targetPPI: 1.5)
        let centered = PageRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let edge = PageRect(x: 0, y: 0, width: 1, height: 1)
        book.pages = [BookPage(layout: .gallery, photoIDs: [photo.id],
                               photoPlacements: [photo.id: PhotoPlacement(frame: centered)],
                               textBoxes: [PageTextBox(text: "   ", frame: edge)])]
        XCTAssertTrue(BookPDF.printWarnings(book).isEmpty)
        book.pages[0].photoPlacements?[photo.id]?.crop = PhotoCrop(zoom: 3)
        XCTAssertEqual(BookPDF.printWarnings(book).count, 1)

        let first = folder.appendingPathComponent("empty-box.pdf")
        try BookPDF.write(book, directory: folder, to: first)
        book.pages[0].textBoxes = nil
        let second = folder.appendingPathComponent("no-box.pdf")
        try BookPDF.write(book, directory: folder, to: second)
        func pixels(_ url: URL) throws -> Data {
            let page = try XCTUnwrap(CGPDFDocument(url as CFURL)?.page(at: 1))
            let bitmap = try XCTUnwrap(CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8,
                                                 bytesPerRow: 400, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            let size = book.format.pageSize
            bitmap.scaleBy(x: 100 / size.width, y: 100 / size.height)
            bitmap.drawPDFPage(page)
            return Data(bytes: try XCTUnwrap(bitmap.data), count: 40_000)
        }
        XCTAssertEqual(try pixels(first), try pixels(second))
    }

    func testManualPhotoAndMovableTypeRoundTripAndRenderInPlace() throws {
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var (book, photo) = try fixture(in: folder)
        let box = PageTextBox(text: "Separate caption", frame: PageRect(x: 0.55, y: 0.15, width: 0.40, height: 0.2))
        let photoFrame = PageRect(x: 0.15, y: 0.35, width: 0.30, height: 0.30)
        let bounds = CGRect(origin: .zero, size: book.format.pageSize)
        let story = bounds.insetBy(dx: book.contentInsetPoints, dy: book.contentInsetPoints)
        book.pages = [BookPage(layout: .text, photoIDs: [photo.id], text: "Main story",
                               photoPlacements: [photo.id: PhotoPlacement(frame: photoFrame, crop: PhotoCrop(x: 1, zoom: 2))],
                               textBoxes: [box])]
        book.cover = BookCover(title: "Front", backPhotoID: photo.id, backText: "Back cover blurb")
        try BookStorage.write(book, to: folder)
        XCTAssertEqual(try BookStorage.read(from: folder), book)
        let output = folder.appendingPathComponent("proof.pdf")
        try BookPDF.write(book, directory: folder, to: output)
        let proof = try XCTUnwrap(PDFDocument(url: output))
        let page = try XCTUnwrap(proof.page(at: 0))
        for (phrase, expected) in [("Main story", story), ("Separate caption", box.frame.rect(in: bounds))] {
            let match = try XCTUnwrap(proof.findString(phrase).first)
            let quartz = match.bounds(for: page)
            let topLeft = CGPoint(x: quartz.midX, y: book.format.pageSize.height - quartz.midY)
            XCTAssertTrue(expected.contains(topLeft), phrase)
        }
        let rendered = try XCTUnwrap(try pdf(folder, "proof.pdf").page(at: 1))
        let bitmap = try XCTUnwrap(CGContext(data: nil, width: 100, height: 100,
                                             bitsPerComponent: 8, bytesPerRow: 400,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let size = book.format.pageSize
        bitmap.scaleBy(x: 100 / size.width, y: 100 / size.height)
        bitmap.drawPDFPage(rendered)
        let bytes = try XCTUnwrap(bitmap.data).assumingMemoryBound(to: UInt8.self)
        let inside = (50 * 100 + 30) * 4
        XCTAssertGreaterThan(Int(bytes[inside]) - Int(bytes[inside + 2]), 80)
        XCTAssertGreaterThan(bytes[(50 * 100 + 8) * 4], 220)
        let package = folder.appendingPathComponent("manual-print")
        try BookPDF.writePrint(book, directory: folder, to: package)
        let cover = try XCTUnwrap(PDFDocument(url: package.appendingPathComponent("Cover.pdf")))
        XCTAssertEqual(cover.findString("Back cover blurb").count, 1)

        let previous = try Data(contentsOf: output)
        book.pages[0].textBoxes?[0].text = String(repeating: "Too long ", count: 1000)
        XCTAssertThrowsError(try BookPDF.write(book, directory: folder, to: output)) { error in
            guard case BookPDF.ExportError.textOverflow(1) = error else { return XCTFail("Expected text overflow") }
        }
        XCTAssertEqual(try Data(contentsOf: output), previous)
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
