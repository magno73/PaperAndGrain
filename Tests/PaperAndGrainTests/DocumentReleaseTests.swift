import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import PaperAndGrain

/// Regression tests for the documents, saving and import work of the release plan (section A).
@MainActor
final class DocumentReleaseTests: XCTestCase {
    private var scratch: URL!

    override func setUp() async throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocumentReleaseTests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    // A1
    func testTrayImportAddsFilesToTheOpenBookAndKeepsItsPages() async throws {
        let package = scratch.appendingPathComponent("Trip.papergrain", isDirectory: true)
        let pages = [BookPage(text: "Day one"), BookPage(text: "Day two")]
        let original = Book(title: "Trip", pages: pages)
        try BookStorage.write(original, to: package)
        let files = try (1...3).map { index in
            let url = scratch.appendingPathComponent("Photo \(index).png")
            try Self.png(width: 40 + index, height: 30).write(to: url)
            return url
        }

        let workspace = Workspace(defaults: MemoryDefaults())
        workspace.openProject(at: package)
        var revealed: UUID?
        XCTAssertTrue(workspace.addPhotoFiles(files, language: "en") { revealed = $0 })
        try await waitUntil { !workspace.importing }

        XCTAssertNil(workspace.problem)
        XCTAssertEqual(workspace.book.id, original.id)
        XCTAssertTrue(BookStorage.sameLocation(try XCTUnwrap(workspace.directory), package))
        XCTAssertEqual(workspace.book.pages, pages)
        XCTAssertEqual(workspace.book.photos.map(\.name), ["Photo 1.png", "Photo 2.png", "Photo 3.png"])
        XCTAssertEqual(revealed, workspace.book.photos.first?.id)
        let saved = try BookStorage.read(from: package)
        XCTAssertEqual(saved.photos.count, 3)
        XCTAssertEqual(saved.pages, pages)
        for photo in saved.photos {
            XCTAssertTrue(FileManager.default.fileExists(atPath: BookStorage.assetURL(filename: photo.filename, in: package).path))
        }
    }

    // A2
    func testRenamedOpenPackageKeepsItsEditsAfterQuitAndReopen() throws {
        let package = scratch.appendingPathComponent("Trip.papergrain", isDirectory: true)
        let renamed = scratch.appendingPathComponent("Trip renamed.papergrain", isDirectory: true)
        try BookStorage.write(Book(title: "Trip"), to: package)
        let defaults = MemoryDefaults()

        let workspace = Workspace(defaults: defaults)
        workspace.openProject(at: package)
        try FileManager.default.moveItem(at: package, to: renamed)
        workspace.book.title = "Edited after the rename"
        // Quitting flushes the open book.
        XCTAssertTrue(workspace.flushSave())
        XCTAssertFalse(workspace.locationLost)
        XCTAssertNil(workspace.problem)
        XCTAssertTrue(BookStorage.sameLocation(try XCTUnwrap(workspace.directory), renamed))
        XCTAssertFalse(workspace.recentBooks.contains { $0.path == package.standardizedFileURL.path })

        let relaunched = Workspace(defaults: defaults)
        relaunched.reopenLastBook()
        XCTAssertEqual(relaunched.book.title, "Edited after the rename")
        XCTAssertTrue(BookStorage.sameLocation(try XCTUnwrap(relaunched.directory), renamed))
    }

    func testMissingPackageReportsTheMoveAndCanStillBeSavedElsewhere() throws {
        let package = scratch.appendingPathComponent("Ejected.papergrain", isDirectory: true)
        let rescue = scratch.appendingPathComponent("Rescued.papergrain", isDirectory: true)
        try BookStorage.write(Book(title: "Ejected", pages: [BookPage(text: "Kept")]), to: package)

        let workspace = Workspace(defaults: MemoryDefaults())
        workspace.openProject(at: package)
        try FileManager.default.removeItem(at: package)
        workspace.book.pages[0].text = "Written after the eject"

        XCTAssertFalse(workspace.flushSave())
        XCTAssertTrue(workspace.locationLost)
        XCTAssertEqual(workspace.problem, AppError.bookMoved(title: "Ejected").errorDescription)

        workspace.saveProjectCopy(from: try XCTUnwrap(workspace.directory), to: rescue)
        XCTAssertFalse(workspace.locationLost)
        XCTAssertNil(workspace.problem)
        XCTAssertTrue(BookStorage.sameLocation(try XCTUnwrap(workspace.directory), rescue))
        XCTAssertEqual(try BookStorage.read(from: rescue).pages.first?.text, "Written after the eject")
        XCTAssertTrue(workspace.flushSave())
    }

    // A3
    func testOpeningAndClosingLeavesTheManifestByteIdentical() async throws {
        let package = scratch.appendingPathComponent("Untouched.papergrain", isDirectory: true)
        try BookStorage.write(Book(title: "Untouched", pages: [BookPage(text: "Same")]), to: package)
        let manifest = package.appendingPathComponent("manifest.json")
        let before = try Data(contentsOf: manifest)
        let modified = try FileManager.default.attributesOfItem(atPath: manifest.path)[.modificationDate] as? Date

        let workspace = Workspace(defaults: MemoryDefaults())
        workspace.openProject(at: package)
        XCTAssertFalse(workspace.isReadOnly)
        // Let any autosave scheduled by opening run.
        try await Task.sleep(for: .milliseconds(400))
        workspace.saveProject()
        workspace.closeBook()

        XCTAssertNil(workspace.directory)
        XCTAssertEqual(try Data(contentsOf: manifest), before)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: manifest.path)[.modificationDate] as? Date, modified)
    }

    func testEditsAreSavedWithTheWriterVersion() async throws {
        let package = scratch.appendingPathComponent("Edited.papergrain", isDirectory: true)
        try BookStorage.write(Book(title: "Before"), to: package)
        let workspace = Workspace(defaults: MemoryDefaults())
        workspace.openProject(at: package)
        workspace.book.title = "After"
        try await waitUntil { (try? BookStorage.read(from: package).title) == "After" }
        XCTAssertEqual(try BookStorage.read(from: package).writerVersion, Workspace.writerVersion)
        XCTAssertEqual(try BookStorage.read(from: package), workspace.book)
    }

    func testBookFromANewerWriterOpensReadOnlyAndIsNeverRewritten() async throws {
        let package = scratch.appendingPathComponent("Future.papergrain", isDirectory: true)
        var future = Book(title: "Future")
        future.writerVersion = Workspace.writerVersion + 1
        try BookStorage.write(future, to: package)
        let manifest = package.appendingPathComponent("manifest.json")
        let before = try Data(contentsOf: manifest)

        let workspace = Workspace(defaults: MemoryDefaults())
        workspace.openProject(at: package)
        XCTAssertEqual(workspace.readOnlyReason, .newerFormat(title: "Future"))
        XCTAssertEqual(workspace.problem, AppError.newerFormat(title: "Future").errorDescription)
        XCTAssertFalse(workspace.canSaveAs)
        XCTAssertFalse(workspace.addPhotoFiles([scratch.appendingPathComponent("none.png")], language: "en"))

        workspace.book.title = "Changed in an older build"
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertTrue(workspace.flushSave())
        workspace.closeBook()
        XCTAssertEqual(try Data(contentsOf: manifest), before)
    }

    func testReadOnlyLocationOpensWithoutErrorsAndSaveAsMakesItEditable() async throws {
        let package = scratch.appendingPathComponent("Locked.papergrain", isDirectory: true)
        let copy = scratch.appendingPathComponent("Unlocked.papergrain", isDirectory: true)
        try BookStorage.write(Book(title: "Locked"), to: package)
        let manifest = package.appendingPathComponent("manifest.json")
        let files = FileManager.default
        try files.setAttributes([.posixPermissions: 0o444], ofItemAtPath: manifest.path)
        try files.setAttributes([.posixPermissions: 0o555], ofItemAtPath: package.path)
        defer {
            try? files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: package.path)
            try? files.setAttributes([.posixPermissions: 0o644], ofItemAtPath: manifest.path)
        }

        let workspace = Workspace(defaults: MemoryDefaults())
        workspace.openProject(at: package)
        XCTAssertEqual(workspace.readOnlyReason, .readOnlyLocation(title: "Locked"))
        XCTAssertTrue(workspace.canSaveAs)
        workspace.book.title = "Kept in memory"
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertTrue(workspace.flushSave())
        XCTAssertEqual(workspace.problem, AppError.readOnlyLocation(title: "Locked").errorDescription)

        workspace.saveProjectCopy(from: try XCTUnwrap(workspace.directory), to: copy)
        XCTAssertNil(workspace.readOnlyReason)
        XCTAssertNil(workspace.problem)
        XCTAssertEqual(try BookStorage.read(from: copy).title, "Kept in memory")
        XCTAssertEqual(try BookStorage.read(from: package).title, "Locked")
    }

    // A4
    func testEveryDraftIsListedEvenBeyondTheRecentsLimit() async throws {
        let drafts = scratch.appendingPathComponent("Drafts", isDirectory: true)
        for index in 1...15 {
            try BookStorage.write(Book(title: "Draft \(index)"), to: drafts.appendingPathComponent(UUID().uuidString))
        }
        try FileManager.default.createDirectory(at: drafts.appendingPathComponent("Not a draft"), withIntermediateDirectories: true)

        let workspace = Workspace(defaults: MemoryDefaults(), draftsRoot: drafts)
        await workspace.refreshDrafts().value

        XCTAssertEqual(workspace.drafts.count, 15)
        XCTAssertEqual(Set(workspace.libraryBooks.map(\.title)), Set((1...15).map { "Draft \($0)" }))
        XCTAssertTrue(workspace.libraryBooks.allSatisfy(\.isDraft))
    }

    func testSaveAsFromADraftRetiresItToTheTrash() async throws {
        let drafts = scratch.appendingPathComponent("Drafts", isDirectory: true)
        let trash = scratch.appendingPathComponent("Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let draft = drafts.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try BookStorage.write(Book(title: "Holiday"), to: draft)
        let saved = scratch.appendingPathComponent("Holiday.papergrain", isDirectory: true)
        let workspace = Workspace(defaults: MemoryDefaults(), draftsRoot: drafts) { url in
            try FileManager.default.moveItem(at: url, to: trash.appendingPathComponent(url.lastPathComponent))
        }

        workspace.openProject(at: draft)
        XCTAssertTrue(workspace.needsSaveLocation)
        workspace.book.title = "Holiday, edited"
        workspace.saveProjectCopy(from: try XCTUnwrap(workspace.directory), to: saved)
        try await waitUntil { workspace.directory.map { BookStorage.sameLocation($0, saved) } ?? false }

        XCTAssertFalse(workspace.needsSaveLocation)
        XCTAssertEqual(try BookStorage.read(from: saved).title, "Holiday, edited")
        XCTAssertFalse(FileManager.default.fileExists(atPath: draft.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: trash.appendingPathComponent(draft.lastPathComponent).path))
        workspace.closeBook()
        await workspace.refreshDrafts().value
        XCTAssertEqual(workspace.libraryBooks.map(\.title), ["Holiday, edited"])
        XCTAssertFalse(workspace.libraryBooks[0].isDraft)
    }

    func testDeleteDraftMovesOnlyADraftToTheTrash() async throws {
        let drafts = scratch.appendingPathComponent("Drafts", isDirectory: true)
        let draft = drafts.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let named = scratch.appendingPathComponent("Named.papergrain", isDirectory: true)
        try BookStorage.write(Book(title: "Scratch"), to: draft)
        try BookStorage.write(Book(title: "Named"), to: named)
        var trashed: [URL] = []
        let workspace = Workspace(defaults: MemoryDefaults(), draftsRoot: drafts) { trashed.append($0) }
        await workspace.refreshDrafts().value

        workspace.deleteDraft(try XCTUnwrap(workspace.drafts.first))
        workspace.deleteDraft(Workspace.RecentBook(path: named.path, title: "Named", opened: Date(), pageCount: 0,
                                                   coverFile: nil, isDraft: true))
        XCTAssertEqual(trashed.map(\.lastPathComponent), [draft.lastPathComponent])
        XCTAssertTrue(workspace.drafts.isEmpty)
    }

    // MARK: - Helpers

    func waitUntil(timeout: TimeInterval = 10, _ condition: @escaping @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return XCTFail("Timed out waiting for the workspace") }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    static func png(width: Int, height: Int) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.8, green: 0.5, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    final class MemoryDefaults: UserDefaults {
        private var values: [String: Any] = [:]

        override func set(_ value: Any?, forKey defaultName: String) { values[defaultName] = value }
        override func string(forKey defaultName: String) -> String? { values[defaultName] as? String }
        override func data(forKey defaultName: String) -> Data? { values[defaultName] as? Data }
        override func object(forKey defaultName: String) -> Any? { values[defaultName] }
        override func removeObject(forKey defaultName: String) { values.removeValue(forKey: defaultName) }
    }
}
