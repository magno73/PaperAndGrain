import PDFKit
import XCTest
@testable import PaperAndGrain

final class PixartPrintTests: XCTestCase {
    private let points = 72.0 / 25.4

    func testCoverInteriorBoxesSpinePaginationAndManualFrames() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let frame = PageRect(x: 0.20, y: 0.24, width: 0.7, height: 0.16)
        let page = BookPage(layout: .fullPage, text: "Interior", storyFrame: frame)
        var book = Book(title: "Example", pages: [page, BookPage(layout: .fullSpread)])
        book.cover = BookCover(title: "Front", backText: "Rear", frontTitleFrame: frame, backTextFrame: frame)
        for right in [false, true] {
            for spine in [7.0, 15.0] {
                book.printSettings = PrintSettings(spreads: true, firstPageOnRight: right)
                let file = dir.appendingPathComponent("book.pdf")
                try BookPDF.write(book, directory: dir, plan: .pixart(spineMM: spine), to: file)
                let pdf = try XCTUnwrap(PDFDocument(url: file))
                // The count with the four cover pages is even: an odd interior gets a trailing blank.
                XCTAssertEqual(pdf.pageCount, right ? 5 : 7)
                let cover = try XCTUnwrap(pdf.page(at: 0))
                checkBoxes(cover, width: 474 + spine, height: 258, inset: 19)
                let backText = try XCTUnwrap(pdf.findString("Rear", withOptions: []).first)
                // The spine repeats the title; the front cover's title is the rightmost occurrence.
                let frontText = try XCTUnwrap(pdf.findString("Front", withOptions: [])
                    .max { $0.bounds(for: cover).minX < $1.bounds(for: cover).minX })
                let x = (19 + 0.20 * 207) * points
                XCTAssertEqual(backText.bounds(for: cover).minX, x, accuracy: 2)
                XCTAssertEqual(frontText.bounds(for: cover).minX, x + (229 + spine)*points, accuracy: 2)
                let interior = try XCTUnwrap(pdf.page(at: right ? 1 : 2))
                let text = try XCTUnwrap(pdf.findString("Interior", withOptions: []).first)
                XCTAssertEqual(text.bounds(for: interior).minX, (3 + 0.20 * 210)*points, accuracy: 2)
                for index in 1..<pdf.pageCount {
                    checkBoxes(try XCTUnwrap(pdf.page(at: index)), width: 216, height: 216, inset: 3)
                }
            }
        }
        book.pages = [page]
        book.printSettings = PrintSettings(firstPageOnRight: true)
        let file = dir.appendingPathComponent("short.pdf")
        try BookPDF.write(book, directory: dir, plan: .pixart(spineMM: 5), to: file)
        XCTAssertEqual(PDFDocument(url: file)?.pageCount, 3)
        let spine = try XCTUnwrap(PrintPlan.pixart().rule(.spine, for: book))
        XCTAssertFalse(spine.accepts(.nan))
        XCTAssertFalse(spine.accepts(0))
        XCTAssertTrue(spine.accepts(100))
        XCTAssertFalse(spine.accepts(100.5))
        book.format = .landscape
        XCTAssertNil(PrintPlan.pixart().size(for: book))
        XCTAssertThrowsError(try BookPDF.write(book, directory: dir, plan: .pixart(spineMM: 5), to: file))
    }

    func testCoverPhotographContinuesIntoWrapAndHingeButLeavesSpineClear() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("assets"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let photo = BookPhoto(name: "Red", filename: "red.tiff", pixelWidth: 100, pixelHeight: 100)
        let sample = NSImage(size: CGSize(width: 100, height: 100), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        try XCTUnwrap(sample.tiffRepresentation).write(to: BookStorage.assetURL(filename: photo.filename, in: dir))
        var book = Book(title: "", photos: [photo], pages: [BookPage(layout: .text)])
        book.cover = BookCover(frontPhotoID: photo.id)
        let url = dir.appendingPathComponent("cover.pdf")
        try BookPDF.write(book, directory: dir, plan: .pixart(spineMM: 7), to: url)
        let document = try XCTUnwrap(CGPDFDocument(url as CFURL))
        let cover = try XCTUnwrap(document.page(at: 1))
        let bitmap = try XCTUnwrap(CGContext(data: nil, width: 481, height: 258, bitsPerComponent: 8,
                                             bytesPerRow: 481 * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        bitmap.scaleBy(x: 1 / points, y: 1 / points)
        bitmap.drawPDFPage(cover)
        let pixels = try XCTUnwrap(bitmap.data).assumingMemoryBound(to: UInt8.self)
        for (x,y) in [(250,125),(300,125),(475,125),(475,5),(350,254)] {
            let i = 4*(481*y+x)
            XCTAssertGreaterThan(pixels[i], 220)
            XCTAssertLessThan(pixels[i+1], 40)
        }
        XCTAssertLessThan(pixels[4*(481*125+240)], 100)
    }

    private func checkBoxes(_ page: PDFPage, width: Double, height: Double, inset: Double) {
        let media = page.bounds(for: .mediaBox)
        XCTAssertEqual(media.width, width*points, accuracy: 0.01)
        XCTAssertEqual(media.height, height*points, accuracy: 0.01)
        XCTAssertEqual(media, page.bounds(for: .bleedBox))
        let trim = page.bounds(for: .trimBox)
        XCTAssertEqual(trim.minX, inset*points, accuracy: 0.01)
        XCTAssertEqual(trim.minY, inset*points, accuracy: 0.01)
        XCTAssertEqual(trim.width, (width - 2*inset)*points, accuracy: 0.01)
        XCTAssertEqual(trim.height, (height - 2*inset)*points, accuracy: 0.01)
    }
}

extension PrintPlan {
    /// The Pixartprinting 21 × 21 cm hardcover from the bundled catalog, with a spine from the quote.
    static func pixart(spineMM: Double? = nil) -> PrintPlan {
        guard let profile = PrintProfileCatalog.bundled.profile(PrintProfileCatalog.pixartID) else {
            preconditionFailure("The Pixartprinting entry is missing from Resources/PrintProfiles")
        }
        return PrintPlan(profile: profile, sizeID: "21x21", measures: PrintMeasures(spineMM: spineMM))
    }
}
