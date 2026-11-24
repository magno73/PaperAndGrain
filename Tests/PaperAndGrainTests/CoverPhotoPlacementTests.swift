import AppKit
import XCTest
@testable import PaperAndGrain

final class CoverPhotoPlacementTests: XCTestCase {
    func testLegacyAndEditedFacesRoundTripIndependently() throws {
        var book = Book(title: "Legacy")
        book.template = .atlas
        book.cover = try JSONDecoder().decode(BookCover.self, from: Data(#"{"title":"Legacy","spineMM":0,"backText":"Rear caption"}"#.utf8))
        let oldFront = BookCoverGeometry(book: book, front: true)
        let oldBack = BookCoverGeometry(book: book, front: false)
        XCTAssertFalse(oldBack.fills)
        let frame = PageRect(x: 0.2, y: 0.35, width: 0.53, height: 0.31)
        let crop = PhotoCrop(x: 0.12, y: 0.79, zoom: 2.4)
        book.cover?.backPhotoPlacement = PhotoPlacement(frame: frame)
        XCTAssertFalse(BookCoverGeometry(book: book, front: false).fills)
        book.cover?.backPhotoPlacement?.crop = crop
        let decoded = try JSONDecoder().decode(Book.self, from: JSONEncoder().encode(book))
        let back = BookCoverGeometry(book: decoded, front: false, bleed: 9)
        XCTAssertEqual(back.photoFrame, frame.photoRect(in: back.bounds))
        XCTAssertEqual(back.photoCrop, crop)
        XCTAssertTrue(back.fills)
        XCTAssertEqual(back.titleFrame, oldBack.titleFrame)
        XCTAssertEqual(BookCoverGeometry(book: decoded, front: true).photoFrame, oldFront.photoFrame)
    }

    func testPrintWarningsAccountForCoverCropZoom() {
        let photo = BookPhoto(name: "Square", filename: "square.jpg", pixelWidth: 3200, pixelHeight: 3200)
        var book = Book(title: "", photos: [photo], pages: [BookPage(layout: .text)])
        book.cover = BookCover(frontPhotoID: photo.id)
        for pixart in [false, true] {
            book.cover?.frontPhotoPlacement = nil
            XCTAssertFalse(BookPDF.printWarnings(book, pixart: pixart).contains { $0.contains(photo.name) })
            book.cover?.frontPhotoPlacement = PhotoPlacement(crop: PhotoCrop(zoom: 2))
            XCTAssertTrue(BookPDF.printWarnings(book, pixart: pixart).contains { $0.contains(photo.name) })
        }
    }

    func testBothPrintProfilesDrawSelectedEdgeAndRespectManualFrame() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("assets"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let photo = BookPhoto(name: "Bands", filename: "bands.tiff", pixelWidth: 300, pixelHeight: 100)
        let sample = NSImage(size: CGSize(width: 300, height: 100), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            NSColor.blue.setFill()
            CGRect(x: 150, y: 0, width: 150, height: 100).fill()
            return true
        }
        try XCTUnwrap(sample.tiffRepresentation).write(to: BookStorage.assetURL(filename: photo.filename, in: directory))
        var book = Book(title: "", photos: [photo], pages: [BookPage(layout: .text)])
        let frame = PageRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        book.cover = BookCover(frontPhotoID: photo.id, backPhotoID: photo.id, spineMM: 7,
                               frontPhotoPlacement: PhotoPlacement(frame: frame, crop: PhotoCrop(x: 1, zoom: 2)),
                               backPhotoPlacement: PhotoPlacement(frame: frame, crop: PhotoCrop(x: 0, zoom: 2)))
        let generic = directory.appendingPathComponent("print")
        try BookPDF.writePrint(book, directory: directory, to: generic)
        let pixart = directory.appendingPathComponent("pixart.pdf")
        try BookPDF.writePixart(book, directory: directory, spineMM: 7, to: pixart)
        for file in [generic.appendingPathComponent("Cover.pdf"), pixart] {
            let document = try XCTUnwrap(CGPDFDocument(file as CFURL))
            let page = try XCTUnwrap(document.page(at: 1))
            let media = page.getBoxRect(.mediaBox)
            let width = 500, height = 250
            let bitmap = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            bitmap.scaleBy(x: CGFloat(width) / media.width, y: CGFloat(height) / media.height)
            bitmap.drawPDFPage(page)
            let pixels = try XCTUnwrap(bitmap.data).assumingMemoryBound(to: UInt8.self)
            func rgb(_ x: Int) -> [UInt8] {
                let base = (width * (height / 2) + x) * 4
                return Array(UnsafeBufferPointer(start: pixels + base, count: 3))
            }
            XCTAssertGreaterThan(rgb(125)[0], 200)
            XCTAssertLessThan(rgb(125)[2], 50)
            XCTAssertGreaterThan(rgb(375)[2], 200)
            XCTAssertLessThan(rgb(375)[0], 50)
            XCTAssertLessThan(rgb(24).max()!, 100)
            XCTAssertLessThan(rgb(476).max()!, 100)
        }
    }
}
