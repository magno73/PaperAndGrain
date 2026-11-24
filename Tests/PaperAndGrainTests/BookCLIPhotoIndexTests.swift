import Foundation
import XCTest
@testable import PaperAndGrain

final class BookCLIPhotoIndexTests: XCTestCase {
    func testRankPrefersSubjectsAndCanExcludeUsedPhotos() async throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("test.papergrain")
        let exact = photo("Elephant", label: "elephant", confidence: 0.22, hash: "f000000000000000")
        let broad = photo("Open landscape", label: "landscape", confidence: 0.88, hash: "ffffffffffffffff")
        let cover = photo("Cover elephant", label: "elephant", confidence: 0.93, hash: "f000000000000001")
        try BookStorage.write(Book(title: "Namibia", photos: [exact, broad, cover],
                                   cover: BookCover(title: "Namibia", frontPhotoID: cover.id)), to: project)

        let rank = try await BookCLI.executeExtended(["rank", project.path, "elefanti durante il safari", "--unused"])
        let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: rank) as? [[String: Any]])
        XCTAssertEqual(rows.compactMap { ($0["photo"] as? [String: Any])?["id"] as? String },
                       [exact.id.uuidString, broad.id.uuidString])
        XCTAssertTrue((rows[0]["evidence"] as? [[String: Any]])?.contains { $0["value"] as? String == "elephant" } == true)
        let noMatch = try await BookCLI.executeExtended(["rank", project.path, "Cena al ristorante"])
        XCTAssertEqual((try JSONSerialization.jsonObject(with: noMatch) as? [Any])?.count, 0)

        let near = try await BookCLI.executeExtended(["similar", project.path, exact.id.uuidString, "--by", "near-duplicate", "--limit", "1"])
        let results = try XCTUnwrap(JSONSerialization.jsonObject(with: near) as? [[String: Any]])
        XCTAssertEqual((results[0]["photo"] as? [String: Any])?["id"] as? String, cover.id.uuidString)
        XCTAssertEqual(results[0]["perceptualDistance"] as? Double, 1.0 / 64)
    }

    func testAnalyzeUpdatesLegacyMetadataInNewPackage() async throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.papergrain")
        let output = root.appendingPathComponent("derived.papergrain")
        let legacy = BookPhoto(name: "Pixel", filename: "pixel.png", pixelWidth: 1, pixelHeight: 1,
                               analysis: PhotoAnalysis(labels: ["legacy"], concepts: []))
        let original = Book(title: "Example", photos: [legacy], pages: [BookPage(photoIDs: [legacy.id])])
        try BookStorage.write(original, to: source)
        let image = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aHukAAAAASUVORK5CYII="))
        try image.write(to: BookStorage.assetURL(filename: legacy.filename, in: source))
        let report = try await BookCLI.executeExtended(["analyze", source.path, "--photo", legacy.id.uuidString, "--output", output.path])
        let batch = try XCTUnwrap(JSONSerialization.jsonObject(with: report) as? [String: Any])
        XCTAssertEqual(batch["analyzed"] as? Int, 1)
        XCTAssertEqual(batch["failed"] as? Int, 0)
        XCTAssertEqual(try BookStorage.read(from: source), original)
        let upgraded = try BookStorage.read(from: output)
        XCTAssertEqual(upgraded.photos[0].id, legacy.id)
        XCTAssertEqual(upgraded.photos[0].analysis?.revision, PhotoAnalysis.currentRevision)
        XCTAssertNotNil(upgraded.photos[0].analysis?.visual)
        let repeated = try await BookCLI.executeExtended(["analyze", output.path])
        let reused = try XCTUnwrap(JSONSerialization.jsonObject(with: repeated) as? [String: Any])
        XCTAssertEqual(reused["reused"] as? Int, 1)
        XCTAssertEqual(reused["analyzed"] as? Int, 0)
    }

    private func photo(_ name: String, label: String, confidence: Double, hash: String) -> BookPhoto {
        let analysis = PhotoAnalysis(labels: [label], concepts: ["wildlife"], revision: PhotoAnalysis.currentRevision,
                                     classifications: [PhotoClassification(label: label, confidence: confidence)],
                                     visual: PhotoVisualSignals(orientation: "landscape", brightness: 0.7,
                                                                sharpness: 0.2, contrast: 0.3, dominantColors: [],
                                                                perceptualHash: hash))
        return BookPhoto(name: name, filename: UUID().uuidString + ".png", pixelWidth: 10, pixelHeight: 5, analysis: analysis)
    }

    private func makeFolder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }
}
