import Foundation
import XCTest
@testable import PaperAndGrain

final class ProjectSaveTests: XCTestCase {
    func testWorkspaceSavesAndReattachesTheOpenPackageWithoutRestoringStaleEdits() async throws {
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = folder.appendingPathComponent("Original.papergrain", isDirectory: true)
        let moved = folder.appendingPathComponent("Moved.papergrain", isDirectory: true)
        let book = Book(title: "Original")
        try BookStorage.write(book, to: original)

        try await MainActor.run {
            let defaults = MemoryDefaults()
            let workspace = Workspace(defaults: defaults)
            workspace.openProject(at: original)
            guard !workspace.needsSaveLocation else { return XCTFail("An opened package already has a save location") }
            workspace.book.title = "Saved by shortcut"
            workspace.saveProject()
            XCTAssertEqual(try BookStorage.read(from: original).title, "Saved by shortcut")

            workspace.book.title = "Current edits"
            workspace.openProject(at: original)
            XCTAssertEqual(workspace.book.title, "Current edits")
            XCTAssertEqual(try BookStorage.read(from: original).title, "Current edits")

            try FileManager.default.moveItem(at: original, to: moved)
            let replacement = Book(title: "Different project")
            try BookStorage.write(replacement, to: original)
            workspace.book.title = "Continue after move"
            XCTAssertFalse(workspace.flushSave())
            XCTAssertEqual(try BookStorage.read(from: original), replacement)

            workspace.openProject(at: moved)
            XCTAssertTrue(BookStorage.sameLocation(try XCTUnwrap(workspace.directory), moved))
            XCTAssertEqual(defaults.string(forKey: "lastBook"), moved.path)
            XCTAssertEqual(try BookStorage.read(from: moved).title, "Continue after move")
        }
    }

    func testSettingsUndoAndRedoPreserveLaterPageEditsAndSaveTheResult() async throws {
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let project = folder.appendingPathComponent("Settings.papergrain", isDirectory: true)
        let original = Book(title: "Before", pages: [BookPage(text: "Before")])
        try BookStorage.write(original, to: project)

        try await MainActor.run {
            let workspace = Workspace(defaults: MemoryDefaults())
            workspace.openProject(at: project)
            let undoManager = UndoManager()
            undoManager.groupsByEvent = false

            undoManager.beginUndoGrouping()
            workspace.applyBookPrintSettings(title: "After", format: .portrait, printSettings: PrintSettings(),
                                             cover: BookCover(title: "Cover"), typography: nil,
                                             undoManager: undoManager, actionName: "Book & Print")
            undoManager.endUndoGrouping()

            undoManager.beginUndoGrouping()
            workspace.applyBookTemplate(.atlas, undoManager: undoManager, actionName: "Book Template")
            undoManager.endUndoGrouping()

            workspace.book.pages[0].text = "Later edit"
            undoManager.undo()
            XCTAssertNil(workspace.book.template)
            XCTAssertEqual(workspace.book.title, "After")

            undoManager.undo()
            XCTAssertFalse(undoManager.canUndo)
            XCTAssertEqual(workspace.book.title, original.title)
            XCTAssertEqual(workspace.book.format, original.format)
            XCTAssertNil(workspace.book.cover)
            XCTAssertNil(workspace.book.printSettings)
            XCTAssertEqual(workspace.book.pages[0].text, "Later edit")
            XCTAssertEqual(try BookStorage.read(from: project), workspace.book)

            undoManager.redo()
            undoManager.redo()
            XCTAssertEqual(workspace.book.title, "After")
            XCTAssertEqual(workspace.book.format, .portrait)
            XCTAssertEqual(workspace.book.cover?.title, "Cover")
            XCTAssertEqual(workspace.book.template, .atlas)
            XCTAssertEqual(workspace.book.pages[0].text, "Later edit")
            XCTAssertEqual(try BookStorage.read(from: project), workspace.book)

            workspace.closeBook()
            XCTAssertFalse(undoManager.canUndo)
        }
    }

    func testNamedSaveWritesOnlyAnExistingManifest() throws {
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let named = folder.appendingPathComponent("Book.papergrain", isDirectory: true)
        var book = Book(title: "Before")
        try BookStorage.write(book, to: named)
        let asset = BookStorage.assetURL(filename: "fixture.txt", in: named)
        let original = Data("fixture".utf8)
        try original.write(to: asset)
        let identity = try XCTUnwrap(BookStorage.identity(of: named))

        book.title = "After"
        try BookStorage.writeExisting(book, to: named)

        XCTAssertEqual(try BookStorage.read(from: named), book)
        XCTAssertEqual(try Data(contentsOf: asset), original)
        XCTAssertEqual(BookStorage.identity(of: named), identity)

        try FileManager.default.removeItem(at: named)
        XCTAssertThrowsError(try BookStorage.writeExisting(book, to: named))
        XCTAssertFalse(FileManager.default.fileExists(atPath: named.path))
    }

    func testDraftDetectionRequiresAManagedUUIDFolder() throws {
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let draftRoot = folder.appendingPathComponent("Drafts", isDirectory: true)
        let name = UUID().uuidString

        XCTAssertTrue(BookStorage.isManagedDraft(draftRoot.appendingPathComponent(name), in: draftRoot))
        XCTAssertFalse(BookStorage.isManagedDraft(folder.appendingPathComponent(name), in: draftRoot))
        XCTAssertFalse(BookStorage.isManagedDraft(draftRoot.appendingPathComponent(name + ".papergrain"), in: draftRoot))
    }

    func testSaveAsCopiesThroughASourceAliasAndKeepsTheOriginal() throws {
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = folder.appendingPathComponent("Original.papergrain", isDirectory: true)
        let alias = folder.appendingPathComponent("Alias.papergrain", isDirectory: true)
        let copy = folder.appendingPathComponent("Copy.papergrain", isDirectory: true)
        let book = Book(title: "Original")
        try BookStorage.write(book, to: original)
        try BookStorage.write(Book(title: "Previous copy"), to: copy)
        let data = Data("copied asset".utf8)
        try data.write(to: BookStorage.assetURL(filename: "fixture.txt", in: original))
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: original)
        var edited = book
        edited.title = "Current work"

        try BookStorage.copy(edited, from: alias, to: copy)

        XCTAssertEqual(try BookStorage.read(from: original), book)
        XCTAssertEqual(try BookStorage.read(from: copy), edited)
        XCTAssertEqual(try Data(contentsOf: BookStorage.assetURL(filename: "fixture.txt", in: copy)), data)
        XCTAssertTrue(BookStorage.sameLocation(original, alias))
        XCTAssertFalse(BookStorage.sameLocation(original, copy))
    }

    func testFailedCopyPreservesExistingDestinationAndLeavesNoStagingFolder() throws {
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("Source.papergrain", isDirectory: true)
        let destination = folder.appendingPathComponent("Destination.papergrain", isDirectory: true)
        let other = Book(title: "Other book")
        try BookStorage.write(Book(title: "Original book"), to: source)
        try BookStorage.write(other, to: destination)

        XCTAssertThrowsError(try BookStorage.copy(Book(title: "Stale panel"), from: source, to: destination))
        XCTAssertEqual(try BookStorage.read(from: destination), other)
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertEqual(Set(files), [source.lastPathComponent, destination.lastPathComponent])
        let nested = source.appendingPathComponent("Nested.papergrain", isDirectory: true)
        let book = try BookStorage.read(from: source)
        XCTAssertThrowsError(try BookStorage.copy(book, from: source, to: nested))
    }

    private func scratchFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private final class MemoryDefaults: UserDefaults {
        private var values: [String: Any] = [:]

        override func set(_ value: Any?, forKey defaultName: String) { values[defaultName] = value }
        override func string(forKey defaultName: String) -> String? { values[defaultName] as? String }
        override func removeObject(forKey defaultName: String) { values.removeValue(forKey: defaultName) }
    }
}
