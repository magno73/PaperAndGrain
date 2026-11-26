import Foundation
import XCTest
@testable import PaperAndGrain

@MainActor
final class PhotoRelinkTests: XCTestCase {
    private var scratch: URL!

    override func setUp() async throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoRelinkTests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: scratch) }

    private func waitUntil(timeout: TimeInterval = 20, _ condition: @escaping @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return XCTFail("Timed out") }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    /// A book with two photos placed on a page with manual frames, opened in a workspace.
    private func openBook() async throws -> (Workspace, URL, [BookPhoto]) {
        let package = scratch.appendingPathComponent("Trip.papergrain", isDirectory: true)
        try BookStorage.write(Book(title: "Trip"), to: package)
        let workspace = Workspace(defaults: DocumentReleaseTests.MemoryDefaults())
        await workspace.openProject(at: package).value
        let files = try ["Alpha.png", "Beta.png"].enumerated().map { index, name in
            let url = scratch.appendingPathComponent(name)
            try DocumentReleaseTests.png(width: 400, height: 300 + index * 10).write(to: url)
            return url
        }
        XCTAssertTrue(workspace.addPhotoFiles(files, language: "en"))
        try await waitUntil { !workspace.importing && !workspace.isAnalyzing && workspace.book.photos.count == 2 }
        let photos = workspace.book.photos
        var page = BookPage(layout: .gallery, photoIDs: photos.map(\.id))
        page.photoPlacements = [photos[0].id: PhotoPlacement(frame: PageRect(x: 0.1, y: 0.1, width: 0.5, height: 0.4))]
        workspace.book.pages = [page]
        return (workspace, package, photos)
    }

    private func blockers(_ workspace: Workspace, _ package: URL) -> [BookPDF.PreflightIssue] {
        BookPDF.preflight(workspace.book, directory: package, profile: .print).blockers
    }

    func testRelinkKeepsTheIdPlacementsAndClearsTheBlocker() async throws {
        let (workspace, package, photos) = try await openBook()
        let lost = photos[0]
        let page = workspace.book.pages[0]
        try FileManager.default.removeItem(at: BookStorage.assetURL(filename: lost.filename, in: package))
        XCTAssertEqual(PhotoRelink.missing(in: workspace.book.photos, directory: package).map(\.id), [lost.id])
        XCTAssertTrue(blockers(workspace, package).contains { $0.problem == .missingFile(lost.name) })

        // A replacement with other proportions (400 x 300 became 300 x 400).
        let replacement = scratch.appendingPathComponent("Other.png")
        try DocumentReleaseTests.png(width: 300, height: 400).write(to: replacement)
        var report: PhotoRelink.Report?
        XCTAssertTrue(workspace.relinkPhotos([lost.id: replacement], language: "en") { report = $0 })
        try await waitUntil { report != nil && !workspace.importing && !workspace.isAnalyzing }

        XCTAssertEqual(report?.relinked, 1)
        XCTAssertEqual(report?.proportionsChanged, [lost.name], "proportions differ by more than 1 %")
        let now = try XCTUnwrap(workspace.book.photos.first { $0.id == lost.id })
        XCTAssertNotEqual(now.filename, lost.filename)
        XCTAssertEqual(now.name, lost.name)
        XCTAssertEqual(now.pixelWidth, 300)
        XCTAssertEqual(now.pixelHeight, 400)
        XCTAssertEqual(workspace.book.pages, [page], "placements and page ids stay")
        XCTAssertTrue(FileManager.default.fileExists(atPath: BookStorage.assetURL(filename: now.filename, in: package).path))
        XCTAssertTrue(blockers(workspace, package).isEmpty)
        // The saved manifest has the same photo id pointing at the new file.
        XCTAssertTrue(workspace.flushSave())
        let saved = try BookStorage.read(from: package)
        XCTAssertEqual(saved.photos.first { $0.id == lost.id }?.filename, now.filename)
        XCTAssertEqual(saved.pages, [page])
    }

    func testRelinkRefusesAFileThatIsNotAnImage() async throws {
        let (workspace, package, photos) = try await openBook()
        let lost = photos[1]
        try FileManager.default.removeItem(at: BookStorage.assetURL(filename: lost.filename, in: package))
        let text = scratch.appendingPathComponent("notes.txt")
        try "not an image".write(to: text, atomically: true, encoding: .utf8)
        var report: PhotoRelink.Report?
        XCTAssertTrue(workspace.relinkPhotos([lost.id: text], language: "en") { report = $0 })
        try await waitUntil { report != nil && !workspace.importing }
        XCTAssertEqual(report?.relinked, 0)
        XCTAssertEqual(report?.failed, [lost.name])
        XCTAssertEqual(workspace.book.photos.first { $0.id == lost.id }?.filename, lost.filename)
    }

    func testReadOnlyBookRefusesToRelink() async throws {
        let package = scratch.appendingPathComponent("Future.papergrain", isDirectory: true)
        var future = Book(title: "Future", photos: [BookPhoto(name: "a.png", filename: "a.png", pixelWidth: 10, pixelHeight: 10)])
        future.writerVersion = Workspace.writerVersion + 1
        try BookStorage.write(future, to: package)
        let workspace = Workspace(defaults: DocumentReleaseTests.MemoryDefaults())
        await workspace.openProject(at: package).value
        XCTAssertTrue(workspace.isReadOnly)
        let file = scratch.appendingPathComponent("b.png")
        try DocumentReleaseTests.png(width: 10, height: 10).write(to: file)
        XCTAssertFalse(workspace.relinkPhotos([future.photos[0].id: file], language: "en") { _ in })
    }

    func testFolderMatchingIgnoresCaseAndExtension() throws {
        func photo(_ name: String) -> BookPhoto { BookPhoto(name: name, filename: UUID().uuidString, pixelWidth: 4, pixelHeight: 3) }
        let withExtension = photo("IMG_0001.JPG"), withoutExtension = photo("sunset"), nowhere = photo("lost.png")
        let folder = scratch.appendingPathComponent("Originals", isDirectory: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Sub"), withIntermediateDirectories: true)
        let a = folder.appendingPathComponent("img_0001.jpg")
        let b = folder.appendingPathComponent("Sub/SUNSET.heic")
        for url in [a, b] { try DocumentReleaseTests.png(width: 8, height: 6).write(to: url) }
        try "x".write(to: folder.appendingPathComponent("lost.txt"), atomically: true, encoding: .utf8)
        try DocumentReleaseTests.png(width: 8, height: 6).write(to: folder.appendingPathComponent(".hidden.png"))

        let files = PhotoRelink.imageFiles(in: folder)
        XCTAssertEqual(Set(files.map(\.lastPathComponent)), ["img_0001.jpg", "SUNSET.heic"])
        let result = PhotoRelink.match(missing: [withExtension, withoutExtension, nowhere], files: files)
        XCTAssertEqual(result.matches[withExtension.id]?.lastPathComponent, "img_0001.jpg")
        XCTAssertEqual(result.matches[withoutExtension.id]?.lastPathComponent, "SUNSET.heic")
        XCTAssertEqual(result.unmatched.map(\.id), [nowhere.id])
    }

    func testProportionsRuleAndRelinkedValues() {
        let old = BookPhoto(name: "a", filename: "old", pixelWidth: 4000, pixelHeight: 3000,
                            analysis: PhotoAnalysis(labels: ["sky"], concepts: []), location: nil)
        let close = BookPhoto(name: "a", filename: "new", pixelWidth: 2000, pixelHeight: 1505)
        let far = BookPhoto(name: "a", filename: "new", pixelWidth: 2000, pixelHeight: 1400)
        XCTAssertFalse(PhotoRelink.proportionsDiffer(old, close))
        XCTAssertTrue(PhotoRelink.proportionsDiffer(old, far))
        let merged = PhotoRelink.relinked(old, with: close)
        XCTAssertEqual(merged.id, old.id)
        XCTAssertEqual(merged.filename, "new")
        XCTAssertNil(merged.analysis)
    }
}
