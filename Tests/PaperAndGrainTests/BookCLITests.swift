import Foundation
import XCTest
@testable import PaperAndGrain

final class BookCLITests: XCTestCase {
    func testBuildAndInspectNativeBookWithoutOverwriting() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let spec = root.appendingPathComponent("spec.json")
        let project = root.appendingPathComponent("demo.papergrain")
        let image = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aHukAAAAASUVORK5CYII="))
        try image.write(to: root.appendingPathComponent("pixel.png"))
        try Data("""
        {"version":1,"title":"Test","template":"atlas","assets":[{"id":"a","path":"pixel.png"}],
         "pages":[{"arrangement":"textBesidePhoto","photos":["a"],"heading":"Prima","text":"Racconto"},
                  {"arrangement":"fullSpread","photos":["a"]}],"cover":{"frontPhoto":"a","backText":"Retro"}}
        """.utf8).write(to: spec)
        _ = try BookCLI.execute(["build", spec.path, project.path])
        let inspected = try JSONDecoder().decode(Book.self, from: BookCLI.execute(["inspect", project.path]))
        let photo = try XCTUnwrap(inspected.photos.first)
        XCTAssertEqual(try Data(contentsOf: BookStorage.assetURL(filename: photo.filename, in: project)), image)
        XCTAssertEqual(inspected.pages.map(\.photoIDs), [[photo.id], [photo.id]])
        XCTAssertEqual(inspected.pages.map(\.effectiveLayout), [.mixed, .fullSpread])
        XCTAssertEqual(inspected.pages.first?.heading, "Prima")
        XCTAssertEqual(inspected.cover?.frontPhotoID, photo.id)
        XCTAssertThrowsError(try BookCLI.execute(["build", spec.path, project.path]))
        XCTAssertEqual(try BookStorage.read(from: project), inspected)
    }

    func testInvalidPhotoReferenceLeavesNoPackageOrStagingDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let spec = root.appendingPathComponent("spec.json")
        try Data(#"{"version":1,"title":"Test","assets":[],"pages":[{"photos":["missing"]}]}"#.utf8).write(to: spec)
        XCTAssertThrowsError(try BookCLI.execute(["build", spec.path, root.appendingPathComponent("demo.papergrain").path]))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["spec.json"])
    }

    func testBuildSpecAcceptsIgnoredSpellings() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let spec = root.appendingPathComponent("spec.json")
        let project = root.appendingPathComponent("demo.papergrain")
        try Data(#"{"version":1,"title":"Test","assets":[],"pages":[{"layout":"text","text":"Swakopmund"}],"ignoredSpellings":["Swakopmund","Etosha"]}"#.utf8).write(to: spec)
        _ = try BookCLI.execute(["build", spec.path, project.path])
        XCTAssertEqual(try BookStorage.read(from: project).ignoredSpellings, ["Swakopmund", "Etosha"])
    }

    func testAPrintServiceKeepsTheTypedTrimInsideTheSizesRange() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let spec = root.appendingPathComponent("spec.json")
        // WhiteWall gives the trim per order: 270 x 352 mm is inside the range of the 27 x 35.6 cm size.
        try Data(#"{"version":1,"title":"T","format":{"widthMM":270,"heightMM":352},"printService":{"profile":"whitewall-coffee-table-book","size":"27x35.6"},"assets":[],"pages":[{"layout":"gallery"}]}"#.utf8).write(to: spec)
        let project = root.appendingPathComponent("A.papergrain")
        _ = try BookCLI.execute(["build", spec.path, project.path])
        XCTAssertEqual(try BookStorage.read(from: project).format, BookFormat(widthMM: 270, heightMM: 352))
        // Without a format the size's own trim is used; a trim outside the range is an error.
        try Data(#"{"version":1,"title":"T","printService":{"profile":"whitewall-coffee-table-book","size":"27x35.6"},"assets":[],"pages":[{"layout":"gallery"}]}"#.utf8).write(to: spec)
        let typical = root.appendingPathComponent("B.papergrain")
        _ = try BookCLI.execute(["build", spec.path, typical.path])
        XCTAssertEqual(try BookStorage.read(from: typical).format, BookFormat(widthMM: 270, heightMM: 356))
        try Data(#"{"version":1,"title":"T","format":{"widthMM":300,"heightMM":352},"printService":{"profile":"whitewall-coffee-table-book","size":"27x35.6"},"assets":[],"pages":[{"layout":"gallery"}]}"#.utf8).write(to: spec)
        XCTAssertThrowsError(try BookCLI.execute(["build", spec.path, root.appendingPathComponent("C.papergrain").path]))
    }
}
