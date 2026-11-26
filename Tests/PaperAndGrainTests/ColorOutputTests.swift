import AppKit
import ColorSync
import CoreGraphics
import PDFKit
import XCTest
@testable import PaperAndGrain

/// CMYK output (T12): conversion of known patches, the PDF it writes, the profile in the package, the
/// preflight, flattened transparency, and sRGB books that do not change.
final class ColorOutputTests: XCTestCase {
    private static let genericCMYK = URL(fileURLWithPath: "/System/Library/ColorSync/Profiles/Generic CMYK Profile.icc")

    private func converter() throws -> CMYKConverter {
        try PrintColor.converter(for: Data(contentsOf: Self.genericCMYK))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("color-output-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: url.appendingPathComponent("assets"), withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// ColorSync's own relative colorimetric conversion of one 8-bit sRGB color.
    private func colorSync(_ rgb: [UInt8]) throws -> [Int] {
        let data = try Data(contentsOf: Self.genericCMYK)
        let srgb = try XCTUnwrap(ColorSyncProfileCreateWithName(kColorSyncSRGBProfile.takeUnretainedValue())?.takeRetainedValue())
        let cmyk = try XCTUnwrap(ColorSyncProfileCreate(data as CFData, nil)?.takeRetainedValue())
        let key = { (k: Unmanaged<CFString>) in k.takeUnretainedValue() as String }
        let intent = kColorSyncRenderingIntentRelative.takeUnretainedValue()
        let sequence: [[String: Any]] = [
            [key(kColorSyncProfile): srgb, key(kColorSyncRenderingIntent): intent,
             key(kColorSyncTransformTag): kColorSyncTransformDeviceToPCS.takeUnretainedValue()],
            [key(kColorSyncProfile): cmyk, key(kColorSyncRenderingIntent): intent,
             key(kColorSyncTransformTag): kColorSyncTransformPCSToDevice.takeUnretainedValue()],
        ]
        let transform = try XCTUnwrap(ColorSyncTransformCreate(sequence as CFArray, nil)?.takeRetainedValue())
        var source = rgb
        var output = [UInt8](repeating: 0, count: 4)
        let layout = ColorSyncDataLayout(UInt32(kColorSyncByteOrderDefault) | kColorSyncAlphaNone.rawValue)
        XCTAssertTrue(ColorSyncTransformConvert(transform, 1, 1, &output, kColorSync8BitInteger, layout, 4,
                                                &source, kColorSync8BitInteger, layout, 3, nil))
        return output.map(Int.init)
    }

    func testKnownPatchesMatchColorSyncAndTheBlackPointCompensatedReference() throws {
        let converter = try converter()
        // Little CMS 2 (ImageMagick 7.1.1, -intent relative -black-point-compensation), same two profiles.
        let reference: [([UInt8], [Int])] = [
            ([255, 255, 255], [0, 1, 1, 0]), ([0, 0, 0], [190, 181, 167, 204]), ([128, 128, 128], [128, 109, 100, 5]),
            ([255, 0, 0], [1, 214, 236, 2]), ([224, 172, 138], [20, 83, 107, 1]),
        ]
        for (rgb, expected) in reference {
            let ours = converter.cmyk(red: Double(rgb[0]) / 255, green: Double(rgb[1]) / 255, blue: Double(rgb[2]) / 255)
                .map { Int(($0 * 255).rounded()) }
            for (a, b) in zip(ours, expected) { XCTAssertLessThanOrEqual(abs(a - b), 4, "\(rgb): \(ours) vs \(expected)") }
            // Away from black, black point compensation changes little: ColorSync's own conversion agrees.
            if rgb != [0, 0, 0] {
                for (a, b) in zip(ours, try colorSync(rgb)) { XCTAssertLessThanOrEqual(abs(a - b), 4, "\(rgb) vs ColorSync") }
            }
        }
        XCTAssertEqual(converter.name, "Generic CMYK Profile")
    }

    func testImagesUseTheSameConversionAsSolidColors() throws {
        let converter = try converter()
        let colors: [[UInt8]] = [[255, 255, 255], [0, 0, 0], [32, 32, 32], [128, 128, 128], [255, 0, 0], [224, 172, 138], [10, 120, 230]]
        let context = try XCTUnwrap(CGContext(data: nil, width: colors.count, height: 1, bitsPerComponent: 8, bytesPerRow: colors.count * 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        for (index, color) in colors.enumerated() {
            pixels[index * 4] = color[0]; pixels[index * 4 + 1] = color[1]; pixels[index * 4 + 2] = color[2]; pixels[index * 4 + 3] = 255
        }
        let image = try XCTUnwrap(converter.convert(try XCTUnwrap(context.makeImage())))
        XCTAssertEqual(image.colorSpace?.model, .cmyk)
        let data = try XCTUnwrap(image.dataProvider?.data as Data?)
        for (index, color) in colors.enumerated() {
            let exact = converter.cmyk(red: Double(color[0]) / 255, green: Double(color[1]) / 255, blue: Double(color[2]) / 255)
            for channel in 0..<4 {
                XCTAssertLessThanOrEqual(abs(Int(data[index * 4 + channel]) - Int((exact[channel] * 255).rounded())), 3, "\(color)")
            }
        }
    }

    func testNeutralGraysUseBlackInkOnly() throws {
        let converter = try converter()
        let black = converter.color(red: 0, green: 0, blue: 0, blackOnly: true)
        XCTAssertEqual(black.components?.prefix(3).map { Double($0) }, [0, 0, 0])
        XCTAssertEqual(Double(black.components?[3] ?? 0), 1, accuracy: 0.001)
        let gray = converter.color(red: 0.5, green: 0.5, blue: 0.5, blackOnly: true)
        XCTAssertEqual(gray.components?.prefix(3).map { Double($0) }, [0, 0, 0])
        XCTAssertGreaterThan(Double(gray.components?[3] ?? 0), 0.3)
        XCTAssertEqual(converter.color(red: 1, green: 1, blue: 1, blackOnly: true).components?.prefix(4).map { Double($0) }, [0, 0, 0, 0])
        // A warm ink is not neutral and uses all four inks; an area fill never uses black alone.
        XCTAssertGreaterThan(Double(converter.color(red: 0.2, green: 0.15, blue: 0.1, blackOnly: true).components?[0] ?? 0), 0)
        XCTAssertGreaterThan(Double(converter.color(red: 0.1, green: 0.1, blue: 0.1, blackOnly: false).components?[0] ?? 0), 0)
    }

    // MARK: PDF

    private func book(in directory: URL, template: BookTemplate? = nil) throws -> Book {
        var photo = BookPhoto(name: "Field", filename: "field.tiff", pixelWidth: 400, pixelHeight: 300)
        photo.caption = "Etosha at noon"
        let sample = NSImage(size: CGSize(width: 400, height: 300), flipped: false) { rect in
            NSColor(srgbRed: 0.8, green: 0.3, blue: 0.2, alpha: 1).setFill()
            rect.fill()
            NSColor(srgbRed: 0.1, green: 0.5, blue: 0.9, alpha: 1).setFill()
            rect.insetBy(dx: 100, dy: 80).fill()
            return true
        }
        try XCTUnwrap(sample.tiffRepresentation).write(to: BookStorage.assetURL(filename: photo.filename, in: directory))
        var book = Book(title: "Color", photos: [photo],
                        pages: [BookPage(photoIDs: [photo.id], text: "Black text on the page", heading: "Heading",
                                         arrangement: .textOverPhoto),
                                BookPage(layout: .text, text: "Only black words here")])
        book.template = template
        book.cover = BookCover(title: "Color", frontPhotoID: photo.id, spineMM: 6)
        book.printSettings = PrintSettings()
        return book
    }

    /// The color operators of a page's content: operator name and operands.
    private func colorOperators(_ page: CGPDFPage) -> [(String, [Double])] {
        final class Recorder { var operands = [[Double]]() }
        var found = [(String, [Double])]()
        for name in ["sc", "scn", "rg", "k", "g"] {
            let recorder = Recorder()
            let table = CGPDFOperatorTableCreate()!
            CGPDFOperatorTableSetCallback(table, name) { scanner, info in
                guard let info else { return }
                var values = [Double]()
                var number: CGPDFReal = 0
                while CGPDFScannerPopNumber(scanner, &number) { values.insert(Double(number), at: 0) }
                Unmanaged<Recorder>.fromOpaque(info).takeUnretainedValue().operands.append(values)
            }
            let stream = CGPDFContentStreamCreateWithPage(page)
            let scanner = CGPDFScannerCreate(stream, table, Unmanaged.passUnretained(recorder).toOpaque())
            CGPDFScannerScan(scanner)
            CGPDFScannerRelease(scanner)
            CGPDFContentStreamRelease(stream)
            CGPDFOperatorTableRelease(table)
            found += recorder.operands.map { (name, $0) }
        }
        return found
    }

    func testCMYKPrintPDFHasFourComponentImagesBlackOnlyTextAndTheOutputIntent() throws {
        let directory = try temporaryDirectory()
        let book = try book(in: directory)
        let output = directory.appendingPathComponent("Press")
        try BookPDF.writePrint(book, directory: directory, to: output, color: .cmyk(try converter()))
        let raw = try Data(contentsOf: output.appendingPathComponent("Interior.pdf"))
        let text = String(decoding: raw, as: UTF8.self)
        XCTAssertTrue(text.contains("/OutputConditionIdentifier (Generic CMYK Profile)"), "output intent names the profile")
        XCTAssertTrue(text.contains("/DCTDecode"))
        XCTAssertFalse(text.contains("DeviceRGB"))
        let document = try XCTUnwrap(CGPDFDocument(output.appendingPathComponent("Interior.pdf") as CFURL))
        var images = 0
        for index in 1...document.numberOfPages {
            let page = try XCTUnwrap(document.page(at: index))
            guard let resources = page.dictionary.flatMap({ dictionary -> CGPDFDictionaryRef? in
                var value: CGPDFDictionaryRef?
                return CGPDFDictionaryGetDictionary(dictionary, "Resources", &value) ? value : nil
            }) else { continue }
            var objects: CGPDFDictionaryRef?
            guard CGPDFDictionaryGetDictionary(resources, "XObject", &objects), let objects else { continue }
            CGPDFDictionaryApplyBlock(objects, { _, object, _ in
                var stream: CGPDFStreamRef?
                guard CGPDFObjectGetValue(object, .stream, &stream), let stream,
                      let dictionary = CGPDFStreamGetDictionary(stream) else { return true }
                var space: CGPDFArrayRef?
                var name: UnsafePointer<CChar>?
                if CGPDFDictionaryGetArray(dictionary, "ColorSpace", &space), let space,
                   CGPDFArrayGetName(space, 0, &name), let name, String(cString: name) == "ICCBased" {
                    var icc: CGPDFStreamRef?
                    if CGPDFArrayGetStream(space, 1, &icc), let icc, let info = CGPDFStreamGetDictionary(icc) {
                        var components: CGPDFInteger = 0
                        if CGPDFDictionaryGetInteger(info, "N", &components), components == 4 { images += 1 }
                    }
                }
                return true
            }, nil)
            // Text is black ink only: every four-component color with no C, M or Y has some K, and no RGB fill.
            let operators = colorOperators(page)
            XCTAssertFalse(operators.contains { $0.0 == "rg" }, "no RGB colors")
            if index == 2 || index == 3 {
                XCTAssertTrue(operators.contains { $0.1.count == 4 && $0.1[0] == 0 && $0.1[1] == 0 && $0.1[2] == 0 && $0.1[3] > 0.5 },
                              "page \(index): \(operators)")
            }
        }
        XCTAssertGreaterThanOrEqual(images, 1, "the photograph is a four-component ICC-based image")
        // Captions go through the same colors: the caption is text in the CMYK file, with no RGB anywhere.
        XCTAssertTrue(PDFDocument(url: output.appendingPathComponent("Interior.pdf"))?.string?.contains("Etosha at noon") == true)
    }

    func testSRGBBooksExportAsBefore() throws {
        let directory = try temporaryDirectory()
        var book = try book(in: directory)
        try BookPDF.writePrint(book, directory: directory, to: directory.appendingPathComponent("A"))
        book.printSettings?.colorOutput = .srgb
        try BookPDF.writePrint(book, directory: directory, to: directory.appendingPathComponent("B"))
        for file in ["Interior.pdf", "Cover.pdf"] {
            let a = try XCTUnwrap(CGPDFDocument(directory.appendingPathComponent("A/" + file) as CFURL))
            let b = try XCTUnwrap(CGPDFDocument(directory.appendingPathComponent("B/" + file) as CFURL))
            XCTAssertEqual(a.numberOfPages, b.numberOfPages)
            for index in 1...a.numberOfPages {
                XCTAssertEqual(a.page(at: index)?.getBoxRect(.trimBox), b.page(at: index)?.getBoxRect(.trimBox))
            }
            let text = String(decoding: try Data(contentsOf: directory.appendingPathComponent("B/" + file)), as: UTF8.self)
            XCTAssertTrue(text.contains("sRGB IEC61966-2.1"))
            XCTAssertFalse(text.contains("/N 4"))
        }
    }

    func testProfilesAreCopiedIntoTheBookAndCheckedByThePreflight() throws {
        let directory = try temporaryDirectory()
        var book = try book(in: directory)
        let rgb = try Data(contentsOf: URL(fileURLWithPath: "/System/Library/ColorSync/Profiles/sRGB Profile.icc"))
        XCTAssertThrowsError(try BookStorage.importICCProfile(rgb, named: "sRGB Profile.icc", id: "file:sRGB", in: directory)) {
            XCTAssertEqual($0 as? BookStorage.ProfileError, .notCMYKOutput("sRGB Profile.icc"))
        }
        let reference = try BookStorage.importICCProfile(try Data(contentsOf: Self.genericCMYK), named: "Generic CMYK Profile.icc",
                                                         id: "installed:Generic CMYK Profile.icc", in: directory)
        XCTAssertEqual(reference.name, "Generic CMYK Profile")
        XCTAssertTrue(reference.filename.hasPrefix("Generic CMYK Profile-") && reference.filename.hasSuffix(".icc"))
        book.printSettings?.colorOutput = .cmyk(reference)
        XCTAssertFalse(BookPDF.preflight(book, directory: directory, profile: .print).blockers.contains {
            $0.problem.kind == "colorProfileUnusable"
        })
        // The book's own setting drives Generic Print.
        try BookPDF.writePrint(book, directory: directory, to: directory.appendingPathComponent("Press"))
        XCTAssertTrue(String(decoding: try Data(contentsOf: directory.appendingPathComponent("Press/Interior.pdf")), as: UTF8.self)
            .contains("Generic CMYK Profile"))
        try FileManager.default.removeItem(at: BookStorage.profileURL(filename: reference.filename, in: directory))
        let report = BookPDF.preflight(book, directory: directory, profile: .print)
        XCTAssertEqual(report.blockers.filter { $0.problem.kind == "colorProfileUnusable" }.first?.message(language: "en"),
                       "The color profile Generic CMYK Profile is missing or is not a CMYK output profile")
        XCTAssertThrowsError(try BookPDF.writePrint(book, directory: directory, to: directory.appendingPathComponent("Again")))
        // A 0.10 manifest has no colorOutput: sRGB.
        let old = try JSONDecoder().decode(PrintSettings.self, from: Data(#"{"bleedMM":3,"safeMM":10,"targetPPI":300,"spreads":false}"#.utf8))
        XCTAssertNil(old.colorOutput)
        XCTAssertFalse(old.writesCMYK)
    }

    func testThePrintServiceColorModeIsAWarningWhenTheBookDiffers() throws {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/PrintProfiles", isDirectory: true)
        let cmykOnly = try XCTUnwrap(PrintProfileCatalog.load(from: fixtures).profile("test-imagewrap"))
        let book = Book(title: "T", format: cmykOnly.sizes[1].format, pages: [BookPage(layout: .text)])
        let report = BookPDF.preflight(book, directory: nil, profile: .service(PrintPlan(profile: cmykOnly)))
        XCTAssertTrue(report.warnings.contains { $0.message(language: "en") == "The printer asks for CMYK; the book writes sRGB" })
    }

    func testFlattenedTransparencyLeavesNoTranslucentPanel() throws {
        let directory = try temporaryDirectory()
        var book = try book(in: directory)
        book.cover = nil
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/PrintProfiles", isDirectory: true)
        var profile = try XCTUnwrap(PrintProfileCatalog.load(from: fixtures).profile("test-trimonly"))
        let live = directory.appendingPathComponent("live.pdf")
        try BookPDF.write(book, directory: directory, plan: PrintPlan(profile: profile), to: live)
        XCTAssertTrue(String(decoding: try Data(contentsOf: live), as: UTF8.self).contains("/ca 0.9"), "the classic panel is translucent")
        profile.color.flattenTransparency = true
        let flat = directory.appendingPathComponent("flat.pdf")
        try BookPDF.write(book, directory: directory, plan: PrintPlan(profile: profile), to: flat, color: .cmyk(try converter()))
        let text = String(decoding: try Data(contentsOf: flat), as: UTF8.self)
        XCTAssertFalse(text.contains("/ca 0.9"), "no live transparency")
        let document = try XCTUnwrap(PDFDocument(url: flat)?.string)
        XCTAssertTrue(document.contains("Black text on the page"), "the text stays text")
    }

    func testPSODownloadChecksTheProfileAndLeavesNothingOnFailure() async throws {
        let directory = try temporaryDirectory()
        let destination = directory.appendingPathComponent("Profiles/PSOcoated_v3.icc")
        // An archive with the right file name but the wrong profile is refused and nothing is kept.
        let staged = directory.appendingPathComponent("zip", isDirectory: true)
        try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: Self.genericCMYK, to: staged.appendingPathComponent("PSOcoated_v3.icc"))
        let zip = directory.appendingPathComponent("pso.zip")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", staged.path, zip.path]
        try ditto.run()
        ditto.waitUntilExit()
        let archive = try Data(contentsOf: zip)
        do {
            _ = try await ECIProfile.install(to: destination, fetch: { _ in archive })
            XCTFail("A profile that is not PSO Coated v3 was accepted")
        } catch {
            XCTAssertEqual(error as? ECIProfile.Failure, .wrongProfile)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        do {
            _ = try await ECIProfile.install(to: destination, fetch: { _ in throw URLError(.notConnectedToInternet) })
            XCTFail("A failed download succeeded")
        } catch {
            XCTAssertEqual(error as? ECIProfile.Failure, .download)
        }
        // With the expected name the same archive installs, as the real one will.
        let data = try await ECIProfile.install(to: destination, expectedName: "Generic CMYK", fetch: { _ in archive })
        XCTAssertEqual(try Data(contentsOf: destination), data)
        XCTAssertNil(ECIProfile.installedData(at: destination), "the installed file is still checked against PSO Coated v3")
    }
}

