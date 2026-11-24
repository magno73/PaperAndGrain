import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import PaperAndGrain

final class PhotoLocationTests: XCTestCase {
    func testLocationFromProjectCopyReadsCityAndSignedCoordinates() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        let context = try XCTUnwrap(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8,
            bytesPerRow: 32, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        let properties: [CFString: Any] = [
            kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCCity: "Fixture City"],
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 30, kCGImagePropertyGPSLatitudeRef: "S",
                kCGImagePropertyGPSLongitude: 60, kCGImagePropertyGPSLongitudeRef: "W"
            ]
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        XCTAssertEqual(LocalImages.location(at: url), PhotoLocation(name: "Fixture City", latitude: -30, longitude: -60))
    }

    func testDecodingLocationDiscardsAnInvalidPair() throws {
        let location = try JSONDecoder().decode(PhotoLocation.self, from: Data(#"{"name":"  City ","latitude":91,"longitude":2}"#.utf8))
        XCTAssertEqual(location, PhotoLocation(name: "City"))
        XCTAssertFalse(PhotoLocation(longitude: 0).hasMetadata)
        XCTAssertTrue(PhotoLocation(latitude: 0, longitude: 0).hasMetadata)
    }
}
