import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import PaperAndGrain

/// Regression tests for the print output fixes of the release plan (section B).
final class PrintReleaseTests: XCTestCase {
    // MARK: B1 page numbers

    func testPrintedFoliosMatchTheEditorWhenImpositionInsertsBlanks() throws {
        let folder = try PrintFixtures.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = BookPage(layout: .text, text: "Alfa")
        let panorama = BookPage(layout: .fullSpread)
        let last = BookPage(layout: .text, text: "Omega")
        var book = Book(title: "Folio", pages: [first, panorama, last], template: .atlas)
        XCTAssertEqual(Book.pageNumbers(of: book.pages), [1, 2, 4])
        XCTAssertEqual(book.pageNumber(of: last), 4)

        // First page on the right: a blank opens the interior but the first page still reads 1.
        book.printSettings = PrintSettings(bleedMM: 0, spreads: false, firstPageOnRight: true)
        let right = folder.appendingPathComponent("right")
        try BookPDF.writePrint(book, directory: folder, to: right)
        let rightPages = try PrintFixtures.pageWords(right.appendingPathComponent("Interior.pdf"))
        let alfa = try XCTUnwrap(rightPages.firstIndex { $0.contains("Alfa") })
        XCTAssertTrue(rightPages[alfa].contains("1"), "\(rightPages[alfa])")
        XCTAssertFalse(rightPages[alfa].contains("2"))
        let omega = try XCTUnwrap(rightPages.firstIndex { $0.contains("Omega") })
        XCTAssertTrue(rightPages[omega].contains("4"), "\(rightPages[omega])")

        // Facing pages: a blank before the panorama must not shift the later folios.
        book.printSettings = PrintSettings(bleedMM: 0, spreads: false, firstPageOnRight: false)
        book.pages = [first, panorama, last]
        let left = folder.appendingPathComponent("left")
        try BookPDF.writePrint(book, directory: folder, to: left)
        let leftPages = try PrintFixtures.pageWords(left.appendingPathComponent("Interior.pdf"))
        XCTAssertEqual(leftPages.count, 5)
        let later = try XCTUnwrap(leftPages.firstIndex { $0.contains("Omega") })
        XCTAssertTrue(leftPages[later].contains("4"), "\(leftPages[later])")
        XCTAssertFalse(leftPages[later].contains("5"))

        // Pixart moves the imposition by one slot; the folios stay the same.
        let pixart = folder.appendingPathComponent("pixart.pdf")
        book.cover = BookCover(title: "Folio")
        try BookPDF.writePixart(book, directory: folder, spineMM: 7, to: pixart)
        let pixartPages = try PrintFixtures.pageWords(pixart)
        let pixartAlfa = try XCTUnwrap(pixartPages.firstIndex { $0.contains("Alfa") })
        XCTAssertTrue(pixartPages[pixartAlfa].contains("1"), "\(pixartPages[pixartAlfa])")
        let pixartOmega = try XCTUnwrap(pixartPages.firstIndex { $0.contains("Omega") })
        XCTAssertTrue(pixartPages[pixartOmega].contains("4"), "\(pixartPages[pixartOmega])")
    }

    func testPrintWarningsNameTheEditorPageNumber() throws {
        let folder = try PrintFixtures.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let photo = try PrintFixtures.photo(in: folder, width: 40, height: 40)
        var book = Book(title: "Warnings", photos: [photo],
                        pages: [BookPage(layout: .text, text: "Uno"), BookPage(layout: .gallery, photoIDs: [photo.id])])
        book.printSettings = PrintSettings(firstPageOnRight: true)
        let warnings = BookPDF.printWarnings(book)
        XCTAssertTrue(warnings.contains { $0.hasPrefix("p. 2 ·") && $0.contains(photo.name) }, "\(warnings)")
    }
}

enum PrintFixtures {
    static func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("assets"), withIntermediateDirectories: true)
        return folder
    }

    /// The words of each page of a PDF, in page order.
    static func pageWords(_ url: URL) throws -> [Set<String>] {
        let document = try XCTUnwrap(PDFDocument(url: url))
        return (0..<document.pageCount).map { index in
            Set((document.page(at: index)?.string ?? "").split(whereSeparator: \.isWhitespace).map(String.init))
        }
    }

    /// A synthetic photo: a horizontal gradient with a few colored bands, written as PNG.
    static func photo(in folder: URL, width: Int, height: Int, name: String = UUID().uuidString) throws -> BookPhoto {
        let photo = BookPhoto(name: name + ".png", filename: name + ".png", pixelWidth: width, pixelHeight: height)
        let image = try gradient(width: width, height: height)
        try writePNG(image, to: BookStorage.assetURL(filename: photo.filename, in: folder))
        return photo
    }

    static func gradient(width: Int, height: Int) throws -> CGImage {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: width * 4, space: space,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                pixels[i] = UInt8(255 * x / max(1, width - 1))
                pixels[i + 1] = UInt8(255 * y / max(1, height - 1))
                pixels[i + 2] = UInt8((x / max(1, width / 8)) % 2 == 0 ? 40 : 200)
                pixels[i + 3] = 255
            }
        }
        return try XCTUnwrap(context.makeImage())
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    /// Rasterizes one PDF page (1-based) into sRGB RGBA bytes at the given scale per point.
    static func raster(_ url: URL, page number: Int, scale: CGFloat, box: CGPDFBox = .mediaBox) throws
        -> (bytes: [UInt8], width: Int, height: Int, origin: CGPoint) {
        let page = try XCTUnwrap(CGPDFDocument(url as CFURL)?.page(at: number))
        let rect = page.getBoxRect(box)
        let width = Int((rect.width * scale).rounded()), height = Int((rect.height * scale).rounded())
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -rect.minX, y: -rect.minY)
        context.drawPDFPage(page)
        let data = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        return (Array(UnsafeBufferPointer(start: data, count: width * height * 4)), width, height, rect.origin)
    }
}
