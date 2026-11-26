import AppKit
import CoreGraphics
import XCTest
@testable import PaperAndGrain

/// T13: the soft proof and the out-of-gamut warning, with the bundled FOGRA39 profile (coated offset).
final class SoftProofTests: XCTestCase {
    private func fogra39() throws -> CMYKConverter {
        let bundled = try XCTUnwrap(ICCProfileSources.bundled.first { $0.filename == "Coated_Fogra39L_VIGC_300.icc" })
        return try PrintColor.converter(for: try XCTUnwrap(ICCProfileSources.bundledData(bundled)))
    }

    /// A 160 × 120 sRGB image drawn by `fill`.
    private func image(_ fill: (CGContext) -> Void) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 160, height: 120, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        fill(context)
        return try XCTUnwrap(context.makeImage())
    }

    private var saturated: (CGContext) -> Void {
        { context in
            let colors: [(CGFloat, CGFloat, CGFloat)] = [(0, 0, 1), (0, 1, 0), (1, 0, 1), (0, 1, 1), (0.1, 0.2, 1), (1, 0, 0), (0.5, 0, 1), (0, 0.9, 0.4)]
            for (index, color) in colors.enumerated() {
                context.setFillColor(CGColor(srgbRed: color.0, green: color.1, blue: color.2, alpha: 1))
                context.fill(CGRect(x: index * 20, y: 0, width: 20, height: 120))
            }
        }
    }

    private var grayRamp: (CGContext) -> Void {
        { context in
            for x in 0..<160 {
                let value = CGFloat(x) / 159
                context.setFillColor(CGColor(srgbRed: value, green: value, blue: value, alpha: 1))
                context.fill(CGRect(x: x, y: 0, width: 1, height: 120))
            }
        }
    }

    func testASaturatedImageIsOutOfGamutAndAGrayRampIsNot() throws {
        let converter = try fogra39()
        let vivid = converter.outOfGamutShare(try image(saturated))
        let gray = converter.outOfGamutShare(try image(grayRamp))
        XCTAssertGreaterThan(vivid, GamutEstimate.warningShare, "saturated: \(vivid)")
        XCTAssertLessThan(gray, 0.01, "gray ramp: \(gray)")
        // Skin and sky tones of an ordinary photo stay inside a coated press's range.
        let ordinary = converter.outOfGamutShare(try image { context in
            context.setFillColor(CGColor(srgbRed: 0.88, green: 0.67, blue: 0.54, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 120))
            context.setFillColor(CGColor(srgbRed: 0.45, green: 0.62, blue: 0.80, alpha: 1))
            context.fill(CGRect(x: 80, y: 0, width: 80, height: 120))
        })
        XCTAssertLessThan(ordinary, 0.01, "ordinary: \(ordinary)")
    }

    func testTheProofKeepsPrintableColorsAndDullsTheOthers() throws {
        let converter = try fogra39()
        func proofed(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) throws -> [Int] {
            let source = try image { context in
                context.setFillColor(CGColor(srgbRed: r, green: g, blue: b, alpha: 1))
                context.fill(CGRect(x: 0, y: 0, width: 160, height: 120))
            }
            let result = try XCTUnwrap(converter.proof(source))
            XCTAssertEqual(result.colorSpace?.model, .rgb)
            let data = try XCTUnwrap(result.dataProvider?.data as Data?)
            return Array(data.prefix(3)).map(Int.init)
        }
        let gray = try proofed(0.5, 0.5, 0.5)
        for value in gray { XCTAssertEqual(value, 128, accuracy: 4, "\(gray)") }
        let blue = try proofed(0, 0, 1)
        XCTAssertGreaterThan(blue[0] + blue[1], 40, "pure sRGB blue prints duller: \(blue)")
    }

    func testThePreflightWarnsOnlyForCMYKBooksWithSaturatedPhotos() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("soft-proof-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("assets"), withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        func write(_ name: String, _ fill: (CGContext) -> Void) throws -> BookPhoto {
            let photo = BookPhoto(name: name, filename: name + ".png", pixelWidth: 160, pixelHeight: 120)
            let rep = NSBitmapImageRep(cgImage: try image(fill))
            try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                .write(to: BookStorage.assetURL(filename: photo.filename, in: directory))
            return photo
        }
        let vivid = try write("vivid", saturated)
        let gray = try write("ramp", grayRamp)
        var book = Book(title: "Proof", photos: [vivid, gray],
                        pages: [BookPage(layout: .gallery, photoIDs: [vivid.id, gray.id])])
        book.printSettings = PrintSettings()
        func gamutRows() -> [String] {
            BookPDF.preflight(book, directory: directory, profile: .print).warnings
                .filter { $0.problem.kind == "outOfGamut" }.map { $0.message(language: "en") }
        }
        XCTAssertEqual(gamutRows(), [], "an sRGB book has no gamut warning")
        let bundled = try XCTUnwrap(ICCProfileSources.bundled.first { $0.filename == "Coated_Fogra39L_VIGC_300.icc" })
        let reference = try BookStorage.importICCProfile(try XCTUnwrap(ICCProfileSources.bundledData(bundled)),
                                                         named: bundled.filename, id: bundled.id, in: directory)
        book.printSettings?.colorOutput = .cmyk(reference)
        let rows = gamutRows()
        XCTAssertEqual(rows.count, 1, "\(rows)")
        XCTAssertTrue(rows.first?.hasPrefix("p. 1 · vivid · Colors will be duller in print (") == true, "\(rows)")
        XCTAssertTrue(rows.first?.hasSuffix("% of the photo is outside the printer’s range)") == true, "\(rows)")
        // A second run reads the cache.
        let start = Date()
        _ = gamutRows()
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
    }
}
