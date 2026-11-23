import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import PaperAndGrain

final class DroppedPhotosTests: XCTestCase {
    func testFileURLTakesPrecedenceOverTheProvidersThumbnail() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = folder.appendingPathComponent("Original.png")
        let pixels = try png(width: 180, height: 92)
        try pixels.write(to: original)
        let provider = NSItemProvider()
        register(try png(width: 12, height: 6), type: .png, with: provider)
        register(original.dataRepresentation, type: .fileURL, with: provider)

        let drop = try XCTUnwrap(DroppedPhotos.start([provider], fallbackName: "Photo"))
        defer { drop.cleanUp() }
        var outcomes = drop.outcomes.makeAsyncIterator()
        let outcome = await outcomes.next()
        let photo = try XCTUnwrap(outcome?.photo)

        XCTAssertEqual(photo.name, "Original.png")
        XCTAssertEqual(photo.pixelWidth, 180)
        XCTAssertEqual(photo.pixelHeight, 92)
        XCTAssertEqual(try Data(contentsOf: BookStorage.assetURL(filename: photo.filename, in: drop.directory)), pixels)
    }

    func testConcreteImageDropsPreserveBytesAndSuggestedName() async throws {
        let pixels = try png(width: 104, height: 58)
        let provider = NSItemProvider()
        provider.suggestedName = "From another app.png"
        register(pixels, type: .png, with: provider)

        let drop = try XCTUnwrap(DroppedPhotos.start([provider], fallbackName: "Photo"))
        defer { drop.cleanUp() }
        var outcomes = drop.outcomes.makeAsyncIterator()
        let outcome = await outcomes.next()
        let photo = try XCTUnwrap(outcome?.photo)

        XCTAssertEqual(photo.name, "From another app.png")
        XCTAssertEqual(photo.pixelWidth, 104)
        XCTAssertEqual(photo.pixelHeight, 58)
        XCTAssertEqual(try Data(contentsOf: BookStorage.assetURL(filename: photo.filename, in: drop.directory)), pixels)
    }

    func testSeveralFilesInOnePromiseAndFailuresReachTheBatch() async throws {
        let pixels = try png(width: 40, height: 20)
        let first = FixturePromise()
        first.files = [("a.png", pixels), ("failed.png", nil)]
        let second = FixturePromise()
        second.files = [("b.png", pixels)]

        let drop = try XCTUnwrap(DroppedPhotos.start([first, second]))
        defer { drop.cleanUp() }
        var outcomes: [DroppedPhotos.Outcome] = []
        for await outcome in drop.outcomes { outcomes.append(outcome) }

        XCTAssertEqual(drop.count, 3)
        XCTAssertEqual(outcomes.sorted { $0.index < $1.index }.map { $0.photo?.name }, ["a.png", nil, "b.png"])
    }

    private func register(_ data: Data, type: UTType, with provider: NSItemProvider) {
        provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .all) { completion in
            completion(data, nil)
            return nil
        }
    }

    private func png(width: Int, height: Int) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                               bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 0.23, green: 0.47, blue: 0.75, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let output = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(output, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(output))
        return data as Data
    }

    private final class FixturePromise: NSFilePromiseReceiver {
        var files: [(name: String, data: Data?)] = []

        override var fileNames: [String] { files.map(\.name) }
        override var fileTypes: [String] { [UTType.png.identifier] }

        override func receivePromisedFiles(atDestination destinationDir: URL, options: [AnyHashable: Any] = [:],
                                           operationQueue: OperationQueue, reader: @escaping (URL, Error?) -> Void) {
            for file in files {
                operationQueue.addOperation {
                    let url = destinationDir.appendingPathComponent(file.name)
                    do {
                        guard let data = file.data else { throw CocoaError(.fileReadCorruptFile) }
                        try data.write(to: url)
                        reader(url, nil)
                    } catch {
                        reader(url, error)
                    }
                }
            }
        }
    }
}
