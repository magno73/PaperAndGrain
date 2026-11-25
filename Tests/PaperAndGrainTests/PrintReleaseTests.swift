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

    // MARK: B2 Pixart cover title

    static let coverTitles = [
        "Namibia", "Giappone 2024", "Sulle strade del Damaraland", "A Journey Through the Skeleton Coast",
        "Tra dune, canyon e oceano: diario di tre settimane", "Kolmanskop", "Fish River Canyon at Dawn",
        "Etosha", "Il lungo viaggio verso il mare di Swakopmund", "Wildlife and Wide Horizons",
        "Spitzkoppe", "Deserto del Namib", "Three Weeks in the Kalahari and Beyond", "Sossusvlei",
    ]

    func testPixartCoverFitsTheTitleInThePanelItDrawsIn() throws {
        let folder = try PrintFixtures.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let output = folder.appendingPathComponent("pixart.pdf")
        var failures: [String] = []
        for template in [nil] + BookTemplate.allCases.map(Optional.some) {
            for title in Self.coverTitles {
                var book = Book(title: title, pages: [BookPage(layout: .text)], template: template)
                book.cover = BookCover(title: title)
                // Only titles that fit in the editor's cover are expected to fit in the Pixart panel.
                let editor = BookCoverGeometry(book: book, front: true)
                guard editor.titleFrame.map({ EditorialTypesetter.fits(editor.title, in: $0) }) ?? true else { continue }
                do {
                    try BookPDF.writePixart(book, directory: folder, spineMM: 8, to: output)
                } catch {
                    failures.append("\(template?.rawValue ?? "classic") · \(title) · \(error.localizedDescription)")
                }
                let panel = CGSize(width: PixartPrintProfile.panelWidth * 72 / 25.4,
                                   height: PixartPrintProfile.panelHeight * 72 / 25.4)
                let face = BookCoverGeometry(book: book, front: true, size: panel)
                if let frame = face.titleFrame, !EditorialTypesetter.fits(face.title, in: frame) {
                    failures.append("\(template?.rawValue ?? "classic") · \(title) · panel geometry overflows")
                }
            }
        }
        XCTAssertEqual(failures, [])
    }

    func testCoverOverflowIsReportedAsCover() throws {
        let folder = try PrintFixtures.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var book = Book(title: "Overflow", pages: [BookPage(layout: .text)])
        book.cover = BookCover(title: "Overflow", backText: String(repeating: "Troppo testo sul retro. ", count: 400))
        XCTAssertThrowsError(try BookPDF.writePrint(book, directory: folder, to: folder.appendingPathComponent("print"))) {
            guard case BookPDF.ExportError.coverTextOverflow = $0 else { return XCTFail("Expected a cover overflow, got \($0)") }
            XCTAssertTrue($0.localizedDescription.contains("copertina"))
            XCTAssertTrue($0.localizedDescription.contains("cover"))
        }
    }

    // MARK: B3 bleed without re-crop

    func testPrintBleedKeepsTheEditorCropInsideTheTrim() throws {
        let folder = try PrintFixtures.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        // 900 × 600 with a blue stripe change every 112 px; the page shows the middle of it.
        let photo = try PrintFixtures.photo(in: folder, width: 900, height: 600)
        let page = BookPage(layout: .fullPage, photoIDs: [photo.id], arrangement: .fullBleed)
        var book = Book(title: "Bleed", photos: [photo], pages: [page])
        book.printSettings = PrintSettings(bleedMM: 3, targetPPI: 72)
        let editor = try XCTUnwrap(PageComposition(page: page, book: book).photos.first)
        let placement = editor.crop.imageRect(for: CGSize(width: 900, height: 600), in: editor.frame, fills: true)
        let trim = PageComposition(page: page, book: book).bounds
        let stripe = CGFloat(900 / 8) * placement.width / 900
        let stripes: [CGFloat] = (1..<8).map { CGFloat($0) * stripe + placement.minX }
        let expected = stripes
            .filter { $0 > trim.minX + 2 && $0 < trim.maxX - 2 }
        XCTAssertFalse(expected.isEmpty)
        let sourcePixel = placement.width / 900

        let package = folder.appendingPathComponent("print")
        try BookPDF.writePrint(book, directory: folder, to: package)
        let scale: CGFloat = 3
        let raster = try PrintFixtures.raster(package.appendingPathComponent("Interior.pdf"), page: 1, scale: scale)
        let bleed = 3 * 72 / 25.4
        let row = raster.height / 2
        func blue(atPagePoint x: CGFloat) -> UInt8 {
            let column = min(raster.width - 1, max(0, Int(((x + bleed) * scale).rounded(.down))))
            return raster.bytes[(row * raster.width + column) * 4 + 2]
        }
        var found: [CGFloat] = []
        var previous = blue(atPagePoint: trim.minX) > 120
        for column in Int((bleed + trim.minX) * scale)..<Int((bleed + trim.maxX) * scale) {
            let high = raster.bytes[(row * raster.width + column) * 4 + 2] > 120
            if high != previous { found.append(CGFloat(column) / scale - bleed) }
            previous = high
        }
        XCTAssertEqual(found.count, expected.count, "\(found) vs \(expected)")
        for (actual, wanted) in zip(found, expected) {
            XCTAssertEqual(actual, wanted, accuracy: sourcePixel + 1 / scale)
        }
        // The crop has spare image on the left, so the bleed shows the real continuation, not a mirror.
        let outside = raster.bytes[(row * raster.width + Int(bleed * 0.5 * scale)) * 4]
        let inside = raster.bytes[(row * raster.width + Int(bleed * 1.5 * scale)) * 4]
        XCTAssertLessThan(Int(outside), Int(inside))

        // With the photo aligned to its left edge there is no spare image: the bleed mirrors the trim edge.
        book.pages[0].photoPlacements = [photo.id: PhotoPlacement(crop: PhotoCrop(x: 0, y: 0.5))]
        let aligned = folder.appendingPathComponent("aligned")
        try BookPDF.writePrint(book, directory: folder, to: aligned)
        let mirrored = try PrintFixtures.raster(aligned.appendingPathComponent("Interior.pdf"), page: 1, scale: scale)
        let left = mirrored.bytes[(row * mirrored.width + Int(bleed * 0.5 * scale)) * 4]
        let right = mirrored.bytes[(row * mirrored.width + Int(bleed * 1.5 * scale)) * 4]
        XCTAssertEqual(Int(left), Int(right), accuracy: 3)
        XCTAssertNotEqual(mirrored.bytes[(row * mirrored.width + 1) * 4 + 1], 0, "bleed left unpainted")
    }

    // MARK: B4 JPEG images streamed to a file

    func testPhotosAreEmbeddedAsJPEGAtTheProfileResolution() throws {
        let folder = try PrintFixtures.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let photo = try PrintFixtures.photo(in: folder, width: 3000, height: 3000)
        let page = BookPage(layout: .fullPage, photoIDs: [photo.id], arrangement: .fullBleed)
        var book = Book(title: "JPEG", photos: [photo], pages: [page])
        book.printSettings = PrintSettings(bleedMM: 0, targetPPI: 300)
        let proof = folder.appendingPathComponent("proof.pdf")
        try BookPDF.write(book, directory: folder, to: proof)
        let package = folder.appendingPathComponent("print")
        try BookPDF.writePrint(book, directory: folder, to: package)
        let side = 210 / 25.4
        for (url, ppi) in [(proof, 150.0), (package.appendingPathComponent("Interior.pdf"), 300.0)] {
            let images = try PrintFixtures.images(url, page: 1)
            XCTAssertEqual(images.count, 1, url.lastPathComponent)
            XCTAssertEqual(images.first?.format, .jpegEncoded, url.lastPathComponent)
            XCTAssertEqual(Double(images.first?.width ?? 0), side * ppi, accuracy: 3, url.lastPathComponent)
        }
        // Only the finished files remain: the temporary stream is moved into place.
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted(),
                       ["assets", "print", "proof.pdf"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: package.path).sorted(), ["Interior.pdf"])

        // A failed export keeps the previous file and leaves no temporary file behind.
        let previous = try Data(contentsOf: proof)
        book.pages.append(BookPage(layout: .text, textBoxes: [PageTextBox(text: String(repeating: "Troppo ", count: 3000),
                                                                           frame: PageRect(x: 0.1, y: 0.1, width: 0.2, height: 0.1))]))
        XCTAssertThrowsError(try BookPDF.write(book, directory: folder, to: proof))
        XCTAssertEqual(try Data(contentsOf: proof), previous)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted(),
                       ["assets", "print", "proof.pdf"])
    }

    func testJPEGPrintKeepsSmoothGradientsWithoutBanding() throws {
        let folder = try PrintFixtures.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        // A slow sky-like gradient: 0.25 code values per source pixel, where banding shows first.
        let width = 1600, height = 1600
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: width * 4, space: space,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                pixels[i] = UInt8(60 + x * 100 / width)
                pixels[i + 1] = UInt8(110 + x * 60 / width)
                pixels[i + 2] = 200
                pixels[i + 3] = 255
            }
        }
        let photo = BookPhoto(name: "sky.png", filename: "sky.png", pixelWidth: width, pixelHeight: height)
        try PrintFixtures.writePNG(try XCTUnwrap(context.makeImage()), to: BookStorage.assetURL(filename: photo.filename, in: folder))
        let page = BookPage(layout: .fullPage, photoIDs: [photo.id], arrangement: .fullBleed)
        var book = Book(title: "Sky", photos: [photo], pages: [page])
        book.printSettings = PrintSettings(bleedMM: 0, targetPPI: 300)
        let package = folder.appendingPathComponent("print")
        try BookPDF.writePrint(book, directory: folder, to: package)
        let raster = try PrintFixtures.raster(package.appendingPathComponent("Interior.pdf"), page: 1, scale: 2)
        let row = raster.height / 2
        // Banding would show as steps: values that drift from the ramp or fall back behind the highest so far.
        var worst = 0
        var highest = -1
        var reversals = 0
        for column in 4..<(raster.width - 4) {
            let red = Int(raster.bytes[(row * raster.width + column) * 4])
            let expected = 60 + Int(Double(column) / Double(raster.width) * 100)
            worst = max(worst, abs(red - expected))
            if red < highest - 2 { reversals += 1 }
            highest = max(highest, red)
        }
        XCTAssertLessThanOrEqual(worst, 3)
        XCTAssertEqual(reversals, 0)
    }
}

enum PrintFixtures {
    /// Image XObjects of one page (1-based): stream encoding and pixel width.
    static func images(_ url: URL, page number: Int) throws -> [(format: CGPDFDataFormat, width: Int)] {
        // The dictionaries point into the document, which must stay alive while they are read.
        let document = try XCTUnwrap(CGPDFDocument(url as CFURL))
        defer { withExtendedLifetime(document) {} }
        let page = try XCTUnwrap(document.page(at: number)?.dictionary)
        var resources: CGPDFDictionaryRef?
        var objects: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(page, "Resources", &resources), let resources,
              CGPDFDictionaryGetDictionary(resources, "XObject", &objects), let objects else { return [] }
        final class Box {
            var found: [(CGPDFDataFormat, Int)] = []
            var nested: [CGPDFDictionaryRef] = []
        }
        let box = Box()
        box.nested = [objects]
        while let objects = box.nested.popLast() {
        CGPDFDictionaryApplyBlock(objects, { _, value, info in
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(value, .stream, &stream), let stream, let dictionary = CGPDFStreamGetDictionary(stream)
            else { return true }
            var subtype: UnsafePointer<CChar>?
            guard CGPDFDictionaryGetName(dictionary, "Subtype", &subtype), let subtype else { return true }
            if String(cString: subtype) == "Form" {
                // Quartz wraps clipped images in form XObjects; look inside them too.
                var resources: CGPDFDictionaryRef?
                var objects: CGPDFDictionaryRef?
                if CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources), let resources,
                   CGPDFDictionaryGetDictionary(resources, "XObject", &objects), let objects {
                    Unmanaged<Box>.fromOpaque(info!).takeUnretainedValue().nested.append(objects)
                }
                return true
            }
            guard String(cString: subtype) == "Image" else { return true }
            var width: CGPDFInteger = 0
            CGPDFDictionaryGetInteger(dictionary, "Width", &width)
            var format = CGPDFDataFormat.raw
            _ = CGPDFStreamCopyData(stream, &format)
            Unmanaged<Box>.fromOpaque(info!).takeUnretainedValue().found.append((format, Int(width)))
            return true
        }, Unmanaged.passUnretained(box).toOpaque())
        }
        return box.found.map { (format: $0.0, width: $0.1) }
    }


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
