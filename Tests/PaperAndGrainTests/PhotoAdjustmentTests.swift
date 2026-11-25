import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import PaperAndGrain

final class PhotoAdjustmentTests: XCTestCase {
    private let space = CGColorSpace(name: CGColorSpace.sRGB)!
    private let size = 40

    func testNeutralSettingsAndLegacyProjectsRetainTheirPixels() throws {
        let project = try folder()
        defer { try? FileManager.default.removeItem(at: project) }
        let url = try fixture(in: project)
        for film in [FilmSettings(), FilmSettings(preset: .documentary), FilmSettings(grain: 0.23)] {
            XCTAssertEqual(try render(url, film: film), try render(url, adjustments: PhotoAdjustments(), film: film))
        }
        let photo = BookPhoto(name: "Pattern", filename: url.lastPathComponent, pixelWidth: size, pixelHeight: size)
        var book = Book(title: "Adjustments", photos: [photo], pages: [BookPage(layout: .fullPage, photoIDs: [photo.id])])
        try BookStorage.write(book, to: project)
        let old = try BookStorage.read(from: project)
        XCTAssertNil(old.photos[0].adjustments)
        var correction = PhotoAdjustments()
        correction.exposure = 0.75
        correction.curveMidtones = 0.25
        book.photos[0].adjustments = correction
        try BookStorage.write(book, to: project)
        XCTAssertEqual(try BookStorage.read(from: project).photos[0].adjustments, correction)

        let proof = project.appendingPathComponent("proof.pdf")
        try BookPDF.write(book, directory: project, to: proof)
        let page = try XCTUnwrap(CGPDFDocument(proof as CFURL)?.page(at: 1))
        let bitmap = try context()
        bitmap.scaleBy(x: CGFloat(size) / book.format.pageSize.width, y: CGFloat(size) / book.format.pageSize.height)
        bitmap.drawPDFPage(page)
        let pdf = try bytes(bitmap)
        let corrected = try render(url, adjustments: correction)
        let original = try render(url)
        let pixel = (size / 2 * size + size / 4) * 4
        XCTAssertEqual(Double(pdf[pixel]), Double(corrected[pixel]), accuracy: 5)
        XCTAssertGreaterThan(Int(pdf[pixel]) - Int(original[pixel]), 10)
    }

    func testSelectiveColorAndMonochromeAffectTheIntendedChannels() throws {
        let project = try folder()
        defer { try? FileManager.default.removeItem(at: project) }
        let url = try fixture(in: project)
        let original = try render(url)
        let red = (size / 2 * size + 8) * 4
        let green = (size / 2 * size + 32) * 4
        var correction = PhotoAdjustments()
        correction.selectiveColor = .red
        correction.selectiveHue = 1
        let shifted = try render(url, adjustments: correction)
        XCTAssertGreaterThan(Int(shifted[red+1]) - Int(original[red+1]), 25)
        for channel in 0...2 { XCTAssertEqual(Double(shifted[green+channel]), Double(original[green+channel]), accuracy: 3) }
        correction = PhotoAdjustments(monochrome: 1)
        let monochrome = try render(url, adjustments: correction)
        XCTAssertEqual(Double(monochrome[red]), Double(monochrome[red+1]), accuracy: 2)
        XCTAssertEqual(Double(monochrome[green]), Double(monochrome[green+2]), accuracy: 2)
        correction.monochromeGrain = 0.8
        let grain = try render(url, adjustments: correction)
        XCTAssertNotEqual(grain, monochrome)
        XCTAssertEqual(grain, try render(url, adjustments: correction))
    }

    func testCurvesLevelsAndWhiteBalanceUseTheEditableValues() throws {
        let project = try folder()
        defer { try? FileManager.default.removeItem(at: project) }
        let gray = try fixture(in: project, gray: 0.5)
        let baseline = try render(gray)
        let curves = PhotoAdjustments(curveMidtones: 0.75)
        XCTAssertEqual(curves.curvePoints[2].y, 0.65, accuracy: 0.0001)
        let lifted = try render(gray, adjustments: curves)
        XCTAssertEqual(Double(lifted[0]) / 255, curves.curvePoints[2].y, accuracy: 0.012)
        let gamma = try render(gray, adjustments: PhotoAdjustments(levelsGamma: 2))
        XCTAssertGreaterThan(Int(gamma[0]) - Int(baseline[0]), 40)
        let whiteBalance = try render(gray, adjustments: PhotoAdjustments(warmth: 1))
        XCTAssertGreaterThan(Int(whiteBalance[0]) - Int(whiteBalance[2]), 30)
        let clamped = PhotoAdjustments(exposure: .infinity, levelsWhite: 0, levelsGamma: .nan).normalized
        XCTAssertEqual(clamped.exposure, 0)
        XCTAssertEqual(clamped.levelsWhite, 0.55)
        XCTAssertEqual(clamped.levelsGamma, 1)
    }

    func testSpatialCorrectionsAndProcessingBeforeTheLUT() throws {
        let project = try folder()
        defer { try? FileManager.default.removeItem(at: project) }
        let url = try fixture(in: project)
        let original = try render(url)
        for field in [\PhotoAdjustments.definition, \.vignette] {
            var settings = PhotoAdjustments()
            settings[keyPath: field] = 1
            XCTAssertNotEqual(try render(url, adjustments: settings), original, String(describing: field))
        }
        // Sharpening and noise reduction work at a fraction of the long edge, which is below a pixel
        // on the 40 px fixture, so they are checked on a photo-sized pattern.
        let side = 1600
        for field in [\PhotoAdjustments.sharpness, \.noiseReduction] {
            let large = try XCTUnwrap(CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                                bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            let pixels = try XCTUnwrap(large.data).assumingMemoryBound(to: UInt8.self)
            for i in stride(from: 0, to: side * side * 4, by: 4) {
                let x = (i / 4) % side, y = (i / 4) / side
                let fleck: UInt8 = (x + y).isMultiple(of: 2) ? 6 : 0
                pixels[i] = (x < side / 2 ? 142 : 42) + fleck
                pixels[i + 1] = (x < side / 2 ? 40 : 142) + fleck
                pixels[i + 2] = 38 + fleck
                pixels[i + 3] = 255
            }
            let before = Data(bytes: pixels, count: side * side * 4)
            var settings = PhotoAdjustments()
            settings[keyPath: field] = 1
            XCTAssertTrue(PhotoDevelopment.applySpatial(settings, to: large))
            XCTAssertNotEqual(Data(bytes: pixels, count: side * side * 4), before, String(describing: field))
        }
        let lut = project.appendingPathComponent("constant.cube")
        let body = ["LUT_3D_SIZE 2"] + Array(repeating: "0.28 0.46 0.67", count: 8)
        try body.joined(separator: "\n").write(to: lut, atomically: true, encoding: .utf8)
        let film = FilmSettings(preset: .custom)
        let first = try render(url, film: film, lut: lut)
        let adjusted = PhotoAdjustments(brilliance: 0.45, exposure: 0.9, saturation: -0.4, monochrome: 0.3,
                                        monochromeGrain: 0.8, sharpness: 0.5, vignette: 0.6)
        XCTAssertEqual(first, try render(url, adjustments: adjusted, film: film, lut: lut))
    }

    func testAutomaticRespondsToThePhotoAndPreservesManualColorChoices() throws {
        let project = try folder()
        defer { try? FileManager.default.removeItem(at: project) }
        let dark = try fixture(in: project, name: "dark", gray: 0.15)
        let bright = try fixture(in: project, name: "bright", gray: 0.85)
        let lift = try XCTUnwrap(PhotoAdjustments.automatic(from: dark))
        let dim = try XCTUnwrap(PhotoAdjustments.automatic(from: bright))
        XCTAssertGreaterThan(lift.exposure, 0.3)
        XCTAssertLessThan(dim.exposure, -0.3)
        XCTAssertGreaterThan(try render(dark, adjustments: lift)[0], try render(dark)[0])
        XCTAssertLessThan(try render(bright, adjustments: dim)[0], try render(bright)[0])
        let manual = PhotoAdjustments(warmth: 0.25, tint: -0.2, sharpness: 0.3, curveShadows: -0.2)
        let combined = manual.applyingAutomatic(lift)
        XCTAssertEqual(combined.exposure, lift.exposure)
        XCTAssertEqual(combined.warmth, manual.warmth)
        XCTAssertEqual(combined.tint, manual.tint)
        XCTAssertEqual(combined.sharpness, manual.sharpness)
        XCTAssertEqual(combined.curvePoints, manual.curvePoints)
    }

    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url.appendingPathComponent("assets"), withIntermediateDirectories: true)
        return url
    }

    private func context() throws -> CGContext {
        try XCTUnwrap(CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                space: space, bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue |
                                    CGImageAlphaInfo.premultipliedLast.rawValue))
    }

    private func bytes(_ context: CGContext) throws -> Data {
        Data(bytes: try XCTUnwrap(context.data), count: size * size * 4)
    }

    private func fixture(in project: URL, name: String = "pattern", gray: Double? = nil) throws -> URL {
        let bitmap = try context()
        let buffer = try XCTUnwrap(bitmap.data).assumingMemoryBound(to: UInt8.self)
        for y in 0..<size {
            for x in 0..<size {
                let i = (y * size + x) * 4
                let fleck = (x + y).isMultiple(of: 2) ? 4 : 0
                buffer[i] = gray.map { UInt8($0 * 255) } ?? UInt8((x < size / 2 ? 142 : 42) + fleck)
                buffer[i+1] = gray.map { UInt8($0 * 255) } ?? UInt8((x < size / 2 ? 40 : 142) + fleck)
                buffer[i+2] = gray.map { UInt8($0 * 255) } ?? UInt8(38 + fleck)
                buffer[i+3] = 255
            }
        }
        let url = BookStorage.assetURL(filename: name + ".png", in: project)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(bitmap.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    private func render(_ url: URL, adjustments: PhotoAdjustments? = nil, film: FilmSettings = FilmSettings(),
                        lut: URL? = nil) throws -> Data {
        let image = try XCTUnwrap(FilmRenderer.image(from: url, maxPixelSize: size, settings: film, lutURL: lut,
                                                     adjustments: adjustments))
        let bitmap = try context()
        bitmap.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        return try bytes(bitmap)
    }
}
