import AppKit
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
        await workspace.openProject(at: package).value
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
    func testRenamedOpenPackageKeepsItsEditsAfterQuitAndReopen() async throws {
        let package = scratch.appendingPathComponent("Trip.papergrain", isDirectory: true)
        let renamed = scratch.appendingPathComponent("Trip renamed.papergrain", isDirectory: true)
        try BookStorage.write(Book(title: "Trip"), to: package)
        let defaults = MemoryDefaults()

        let workspace = Workspace(defaults: defaults)
        await workspace.openProject(at: package).value
        try FileManager.default.moveItem(at: package, to: renamed)
        workspace.book.title = "Edited after the rename"
        // Quitting flushes the open book.
        XCTAssertTrue(workspace.flushSave())
        XCTAssertFalse(workspace.locationLost)
        XCTAssertNil(workspace.problem)
        XCTAssertTrue(BookStorage.sameLocation(try XCTUnwrap(workspace.directory), renamed))
        XCTAssertFalse(workspace.recentBooks.contains { $0.path == package.standardizedFileURL.path })

        let relaunched = Workspace(defaults: defaults)
        await relaunched.reopenLastBook().value
        XCTAssertEqual(relaunched.book.title, "Edited after the rename")
        XCTAssertTrue(BookStorage.sameLocation(try XCTUnwrap(relaunched.directory), renamed))
    }

    func testMissingPackageReportsTheMoveAndCanStillBeSavedElsewhere() async throws {
        let package = scratch.appendingPathComponent("Ejected.papergrain", isDirectory: true)
        let rescue = scratch.appendingPathComponent("Rescued.papergrain", isDirectory: true)
        try BookStorage.write(Book(title: "Ejected", pages: [BookPage(text: "Kept")]), to: package)

        let workspace = Workspace(defaults: MemoryDefaults())
        await workspace.openProject(at: package).value
        try FileManager.default.removeItem(at: package)
        workspace.book.pages[0].text = "Written after the eject"

        XCTAssertFalse(workspace.flushSave())
        XCTAssertTrue(workspace.locationLost)
        XCTAssertEqual(workspace.problem, AppError.bookMoved(title: "Ejected").errorDescription)

        await workspace.saveProjectCopy(from: try XCTUnwrap(workspace.directory), to: rescue).value
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
        await workspace.openProject(at: package).value
        XCTAssertFalse(workspace.isReadOnly)
        // Let any autosave scheduled by opening run.
        try await Task.sleep(for: .milliseconds(400))
        workspace.saveProject()
        await workspace.closeBook().value

        XCTAssertNil(workspace.directory)
        XCTAssertEqual(try Data(contentsOf: manifest), before)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: manifest.path)[.modificationDate] as? Date, modified)
    }

    func testEditsAreSavedWithTheWriterVersion() async throws {
        let package = scratch.appendingPathComponent("Edited.papergrain", isDirectory: true)
        try BookStorage.write(Book(title: "Before"), to: package)
        let workspace = Workspace(defaults: MemoryDefaults())
        await workspace.openProject(at: package).value
        workspace.book.title = "After"
        try await waitUntil { (try? BookStorage.read(from: package).title) == "After" }
        // A book without a map page keeps the revision 0.10 reads.
        XCTAssertEqual(try BookStorage.read(from: package).writerVersion, 1)
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
        await workspace.openProject(at: package).value
        XCTAssertEqual(workspace.readOnlyReason, .newerFormat(title: "Future"))
        XCTAssertEqual(workspace.problem, AppError.newerFormat(title: "Future").errorDescription)
        XCTAssertFalse(workspace.canSaveAs)
        XCTAssertFalse(workspace.addPhotoFiles([scratch.appendingPathComponent("none.png")], language: "en"))

        workspace.book.title = "Changed in an older build"
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertTrue(workspace.flushSave())
        await workspace.closeBook().value
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
        await workspace.openProject(at: package).value
        XCTAssertEqual(workspace.readOnlyReason, .readOnlyLocation(title: "Locked"))
        XCTAssertTrue(workspace.canSaveAs)
        workspace.book.title = "Kept in memory"
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertTrue(workspace.flushSave())
        XCTAssertEqual(workspace.problem, AppError.readOnlyLocation(title: "Locked").errorDescription)

        await workspace.saveProjectCopy(from: try XCTUnwrap(workspace.directory), to: copy).value
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

        await workspace.openProject(at: draft).value
        XCTAssertTrue(workspace.needsSaveLocation)
        workspace.book.title = "Holiday, edited"
        await workspace.saveProjectCopy(from: try XCTUnwrap(workspace.directory), to: saved).value
        try await waitUntil { workspace.directory.map { BookStorage.sameLocation($0, saved) } ?? false }

        XCTAssertFalse(workspace.needsSaveLocation)
        XCTAssertEqual(try BookStorage.read(from: saved).title, "Holiday, edited")
        XCTAssertFalse(FileManager.default.fileExists(atPath: draft.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: trash.appendingPathComponent(draft.lastPathComponent).path))
        await workspace.closeBook().value
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

    // A5
    func testEditorSessionChangesForAnotherPackageWithTheSameBookIDButNotOnSaveAs() async throws {
        let original = scratch.appendingPathComponent("Trip.papergrain", isDirectory: true)
        let copy = scratch.appendingPathComponent("Trip v2.papergrain", isDirectory: true)
        let book = Book(title: "Trip", pages: [BookPage(text: "Original")])
        try BookStorage.write(book, to: original)
        let workspace = Workspace(defaults: MemoryDefaults())
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false

        await workspace.openProject(at: original).value
        let first = workspace.editorSession
        await workspace.saveProjectCopy(from: original, to: copy).value
        XCTAssertEqual(workspace.editorSession, first, "Save As keeps editing the same document")

        undoManager.beginUndoGrouping()
        workspace.applyBookTemplate(.atlas, showPageNumbers: nil, undoManager: undoManager, actionName: "Template")
        undoManager.endUndoGrouping()
        XCTAssertTrue(undoManager.canUndo)

        await workspace.openProject(at: original).value
        XCTAssertEqual(workspace.book.id, book.id)
        XCTAssertNotEqual(workspace.editorSession, first, "The original is another document")
        XCTAssertFalse(undoManager.canUndo)
        XCTAssertNil(try BookStorage.read(from: original).template)
    }

    // A6
    func testSaveAsCopiesOffTheMainThreadAndKeepsEditsMadeMeanwhile() async throws {
        let package = scratch.appendingPathComponent("Source.papergrain", isDirectory: true)
        let copy = scratch.appendingPathComponent("Copy.papergrain", isDirectory: true)
        try BookStorage.write(Book(title: "Source"), to: package)
        let workspace = Workspace(defaults: MemoryDefaults())
        await workspace.openProject(at: package).value

        let saving = workspace.saveProjectCopy(from: try XCTUnwrap(workspace.directory), to: copy)
        XCTAssertTrue(workspace.savingCopy)
        XCTAssertFalse(workspace.canSaveAs)
        workspace.book.title = "Edited during the copy"
        await saving.value

        XCTAssertFalse(workspace.savingCopy)
        XCTAssertTrue(BookStorage.sameLocation(try XCTUnwrap(workspace.directory), copy))
        try await waitUntil { (try? BookStorage.read(from: copy).title) == "Edited during the copy" }
        XCTAssertEqual(try BookStorage.read(from: package).title, "Source")
    }

    func testImportedFilesAreCheckedByTypeAndCopiedWritable() throws {
        let assets = scratch.appendingPathComponent("Book/assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        let book = assets.deletingLastPathComponent()
        let fake = scratch.appendingPathComponent("Not an image.png")
        try Data("plain text".utf8).write(to: fake)
        XCTAssertThrowsError(try LocalImages.storeFile(fake, name: "Not an image.png", in: book))

        let image = scratch.appendingPathComponent("Locked.png")
        let pixels = try Self.png(width: 64, height: 48)
        try pixels.write(to: image)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: image.path)
        let photo = try LocalImages.storeFile(image, name: "Locked.png", in: book)
        let stored = BookStorage.assetURL(filename: photo.filename, in: book)
        XCTAssertEqual(try Data(contentsOf: stored), pixels)
        XCTAssertEqual([photo.pixelWidth, photo.pixelHeight], [64, 48])
        XCTAssertTrue(photo.filename.hasSuffix(".png"))
        XCTAssertTrue(FileManager.default.isWritableFile(atPath: stored.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: assets.path).count, 1)
    }

    // A7
    func testAlbumPickerSelectsTheLastUsedAlbumOrTheFirst() async throws {
        let albums = [Album(id: "recents", title: "Recents", count: 40, isSmart: true),
                      Album(id: "favorites", title: "Favorites", count: 3, isSmart: true),
                      Album(id: "trip", title: "Namibia", count: 12)]
        XCTAssertEqual(AlbumPicker.initialAlbum(in: albums, last: "trip"), "trip")
        XCTAssertEqual(AlbumPicker.initialAlbum(in: albums, last: "deleted"), "recents")
        XCTAssertEqual(AlbumPicker.initialAlbum(in: albums, last: ""), "recents")
        XCTAssertNil(AlbumPicker.initialAlbum(in: [], last: "trip"))
    }

    // A8
    func testDropDuringSaveAsLandsInTheNewPackage() async throws {
        let package = scratch.appendingPathComponent("Before.papergrain", isDirectory: true)
        let copy = scratch.appendingPathComponent("After.papergrain", isDirectory: true)
        try BookStorage.write(Book(title: "Moving"), to: package)
        let files = try (1...3).map { index in
            let url = scratch.appendingPathComponent("Drop \(index).png")
            try Self.png(width: 30, height: 20 + index).write(to: url)
            return url
        }
        let workspace = Workspace(defaults: MemoryDefaults())
        await workspace.openProject(at: package).value

        XCTAssertTrue(workspace.addPhotoFiles(files, language: "en"))
        await workspace.saveProjectCopy(from: try XCTUnwrap(workspace.directory), to: copy).value
        try await waitUntil { !workspace.importing }

        XCTAssertNil(workspace.problem)
        XCTAssertTrue(BookStorage.sameLocation(try XCTUnwrap(workspace.directory), copy))
        XCTAssertEqual(workspace.book.photos.count, 3)
        try await waitUntil { (try? BookStorage.read(from: copy).photos.count) == 3 }
        for photo in try BookStorage.read(from: copy).photos {
            XCTAssertTrue(FileManager.default.fileExists(atPath: BookStorage.assetURL(filename: photo.filename, in: copy).path))
        }
    }

    func testPhotosDroppedDuringAnAnalysisAreAnalysedAfterIt() async throws {
        let package = scratch.appendingPathComponent("Analysis.papergrain", isDirectory: true)
        try BookStorage.write(Book(title: "Analysis"), to: package)
        let images = try (1...3).map { index in
            let url = scratch.appendingPathComponent("Analyse \(index).png")
            try Self.png(width: 160 + index, height: 120).write(to: url)
            return url
        }
        let workspace = Workspace(defaults: MemoryDefaults())
        await workspace.openProject(at: package).value

        XCTAssertTrue(workspace.addPhotoFiles(Array(images.prefix(2)), language: "en"))
        try await waitUntil { !workspace.importing }
        XCTAssertTrue(workspace.isAnalyzing)
        XCTAssertTrue(workspace.addPhotoFiles([images[2]], language: "en"))
        try await waitUntil(timeout: 60) {
            !workspace.importing && !workspace.isAnalyzing && workspace.book.photos.count == 3
        }
        XCTAssertEqual(workspace.book.photos.filter { $0.analysis?.revision == PhotoAnalysis.currentRevision }.count, 3)
    }

    func testQuittingFlushesTheBookWithoutAWindow() async throws {
        let package = scratch.appendingPathComponent("Quit.papergrain", isDirectory: true)
        try BookStorage.write(Book(title: "Before quitting"), to: package)
        let workspace = Workspace(defaults: MemoryDefaults())
        await workspace.openProject(at: package).value
        workspace.book.title = "Flushed at quit"
        NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: nil)
        XCTAssertEqual(try BookStorage.read(from: package).title, "Flushed at quit")
    }

    // A9
    func testAppErrorsExistInItalianAndEnglish() async throws {
        try CompiledCatalog.install()
        let errors: [AppError] = [
            .bookMoved(title: "Trip"), .newerFormat(title: "Trip"), .readOnlyLocation(title: "Trip"),
            .damagedManifest(package: "Trip"), .imageUnavailable(name: "IMG_0001.HEIC"), .imageUnavailable(name: nil),
            .someImagesUnavailable(imported: 2, unavailable: ["a.heic", nil]),
        ]
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "interfaceLanguage")
        defer { defaults.set(previous, forKey: "interfaceLanguage") }

        defaults.set("it", forKey: "interfaceLanguage")
        let italian = errors.map { $0.localizedDescription }
        defaults.set("en", forKey: "interfaceLanguage")
        let english = errors.map { $0.localizedDescription }

        for (it, en) in zip(italian, english) {
            XCTAssertNotEqual(it, en)
            XCTAssertFalse(it.contains(" · "), "One language per message")
        }
        XCTAssertTrue(italian[4].contains("«IMG_0001.HEIC»"))
        XCTAssertTrue(english[4].contains("“IMG_0001.HEIC”"))
        XCTAssertEqual(english[6], "Imported 2 photos. 2 images were unavailable: a.heic.")
        XCTAssertEqual(italian[6], "Importate 2 foto. 2 immagini non erano disponibili: a.heic.")
        XCTAssertEqual(PhotoImportError.unreadableImage.localizedDescription, english[5])
    }

    func testUnreadableDroppedImageIsReportedByName() async throws {
        let package = scratch.appendingPathComponent("Names.papergrain", isDirectory: true)
        try BookStorage.write(Book(title: "Names"), to: package)
        let good = scratch.appendingPathComponent("Good.png")
        try Self.png(width: 20, height: 20).write(to: good)
        let bad = scratch.appendingPathComponent("Broken.jpg")
        try Data("not a jpeg".utf8).write(to: bad)
        let workspace = Workspace(defaults: MemoryDefaults())
        await workspace.openProject(at: package).value

        XCTAssertTrue(workspace.addPhotoFiles([bad], language: "en"))
        try await waitUntil { !workspace.importing }
        XCTAssertEqual(workspace.problem, AppError.imageUnavailable(name: "Broken.jpg").localizedDescription)

        XCTAssertTrue(workspace.addPhotoFiles([good, bad], language: "en"))
        try await waitUntil { !workspace.importing }
        XCTAssertEqual(workspace.problem,
                       AppError.someImagesUnavailable(imported: 1, unavailable: ["Broken.jpg"]).localizedDescription)
        XCTAssertEqual(workspace.book.photos.map(\.name), ["Good.png"])
    }

    func testDamagedManifestAndWriteFailuresHaveSpecificMessages() async throws {
        let package = scratch.appendingPathComponent("Damaged.papergrain", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: package.appendingPathComponent("manifest.json"))
        let workspace = Workspace(defaults: MemoryDefaults())
        await workspace.openProject(at: package).value
        XCTAssertNil(workspace.directory)
        XCTAssertEqual(workspace.problem, AppError.damagedManifest(package: "Damaged").localizedDescription)

        let readOnly = NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteVolumeReadOnly.rawValue)
        XCTAssertEqual(AppError.saving(readOnly, title: "T") as? AppError, .readOnlyLocation(title: "T"))
        let denied = NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteUnknown.rawValue,
                             userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))])
        XCTAssertEqual(AppError.saving(denied, title: "T") as? AppError, .readOnlyLocation(title: "T"))
        let other = NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteOutOfSpace.rawValue)
        XCTAssertNil(AppError.saving(other, title: "T") as? AppError)
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
