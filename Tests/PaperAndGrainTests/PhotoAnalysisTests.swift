import XCTest
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers
@testable import PaperAndGrain

final class PhotoAnalysisTests: XCTestCase {
    func testLegacyAnalysisAndMultilingualEvidence() throws {
        let legacy = try JSONDecoder().decode(PhotoAnalysis.self, from: Data(
            #"{"revision":1,"labels":["elephant"],"concepts":["wildlife"]}"#.utf8))
        XCTAssertNil(legacy.classifications)
        XCTAssertNil(PhotoAnalyzer.distance(legacy, legacy))
        for story in ["Two elephants on safari", "Due elefanti durante il safari"] {
            XCTAssertEqual(Set(PhotoAnalyzer.matches(legacy, for: story).map(\.value)), ["elephant", "wildlife"])
        }
        XCTAssertEqual(PhotoAnalyzer.score(legacy, for: "Cena al ristorante"), 0)
        let other = PhotoAnalysis(labels: ["lion"], concepts: ["wildlife"])
        XCTAssertEqual(PhotoAnalyzer.relatedness(legacy, other), 0)
        XCTAssertEqual(PhotoAnalyzer.relatedness(legacy, legacy), 1)
        let dune = PhotoAnalysis(labels: ["sand dune"], concepts: ["desert"])
        XCTAssertTrue(PhotoAnalyzer.matches(dune, for: "Dune del deserto").contains {
            $0.source == "subject" && $0.value == "sand dune"
        })
    }

    func testSyntheticSignOnDevice() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        let context = try XCTUnwrap(CGContext(data: nil, width: 700, height: 220, bitsPerComponent: 8,
                                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 700, height: 220))
        let line = NSAttributedString(string: "WINDHOEK", attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica-Bold" as CFString, 80, nil)
        ])
        context.textPosition = CGPoint(x: 50, y: 80)
        CTLineDraw(CTLineCreateWithAttributedString(line), context)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let result = try await PhotoAnalyzer.analyze(url: url)
        XCTAssertEqual(result.revision, PhotoAnalysis.currentRevision)
        XCTAssertEqual(result.visual?.orientation, "landscape")
        XCTAssertEqual(PhotoAnalyzer.distance(result, result), 0)
        XCTAssertGreaterThan(try XCTUnwrap(result.visual?.contrast), 0.1)
        XCTAssertFalse(try XCTUnwrap(result.visual?.dominantColors).isEmpty)
        if result.unavailableSignals?.contains("text") == true {
            throw XCTSkip("Vision OCR unavailable in this runtime")
        }
        XCTAssertTrue(PhotoAnalyzer.matches(result, for: "Windhoek").contains { $0.source == "text" })
    }
}
