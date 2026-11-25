import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class Workspace: ObservableObject {
    @Published var book = Book(title: "") {
        didSet { scheduleSave() }
    }
    @Published private(set) var directory: URL?
    /// Set for a book written by a newer Paper & Grain or kept where it cannot be written.
    /// Nothing is saved to its package; a read-only location can still be copied with Save As.
    @Published private(set) var readOnlyReason: AppError?
    var isReadOnly: Bool { readOnlyReason != nil }
    /// The manifest as it was last read or written, so unchanged books are never rewritten.
    private var lastSaved: Book?
    /// Revision of the manifest written by this build. Raise it when a release adds data
    /// that older builds would drop: they then open the book read-only instead of rewriting it.
    nonisolated static let writerVersion = 1
    @Published private(set) var importing = false
    @Published private(set) var importProgress = ""
    @Published private(set) var analysisProgress: (done: Int, total: Int)?
    @Published private(set) var exporting = false
    @Published var problem: String?
    /// The open package was moved or removed and could not be found again. Edits stay in memory until Save As.
    @Published private(set) var locationLost = false
    /// Set when a new book opens, so the window can ask for its template first.
    @Published var newBookNeedsTemplate = false
    @Published private(set) var recentBooks: [RecentBook] = []

    private var analysisTask: Task<Void, Never>?
    private var importTask: Task<Void, Never>?
    private var exportTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    // Order autosaves before durable writes and package copies.
    private let saveQueue = DispatchQueue(label: "local.paperandgrain.manifest", qos: .utility)
    private weak var settingsUndoManager: UndoManager?
    private var documentSession = UUID()
    private var directoryIdentity: BookStorage.DirectoryIdentity?
    private let defaults: UserDefaults
    static let bookType = UTType(exportedAs: "local.paperandgrain.book", conformingTo: .package)

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        recentBooks = RecentBook.load(from: defaults)
    }

    /// Books shown in the welcome window and in File › Open Recent.
    struct RecentBook: Codable, Identifiable, Equatable {
        var path: String
        var title: String
        var opened: Date
        var pageCount: Int
        var coverFile: String?
        var isDraft: Bool

        var id: String { path }
        var url: URL { URL(fileURLWithPath: path) }
        var coverURL: URL? { coverFile.map { BookStorage.assetURL(filename: $0, in: url) } }

        static func load(from defaults: UserDefaults) -> [RecentBook] {
            guard let data = defaults.data(forKey: "recentBooks"),
                  let books = try? JSONDecoder().decode([RecentBook].self, from: data) else { return [] }
            return books.filter { FileManager.default.fileExists(atPath: $0.path) }
        }
    }

    private func noteRecentBook() {
        guard let directory else { return }
        let coverID = book.cover?.frontPhotoID ?? book.pages.lazy.flatMap(\.photoIDs).first
        let cover = coverID.flatMap { id in book.photos.first { $0.id == id }?.filename }
        let entry = RecentBook(path: directory.standardizedFileURL.path, title: book.title, opened: Date(),
                               pageCount: book.pages.count, coverFile: cover,
                               isDraft: BookStorage.isManagedDraft(directory))
        var books = recentBooks.filter { $0.path != entry.path }
        books.insert(entry, at: 0)
        recentBooks = Array(books.prefix(12))
        if let data = try? JSONEncoder().encode(recentBooks) { defaults.set(data, forKey: "recentBooks") }
    }

    func forgetRecentBook(_ recent: RecentBook) {
        recentBooks.removeAll { $0.path == recent.path }
        if let data = try? JSONEncoder().encode(recentBooks) { defaults.set(data, forKey: "recentBooks") }
    }

    private struct DocumentLocation: Equatable {
        let id: UUID
        let directory: URL?
        let session: UUID
    }

    private var documentLocation: DocumentLocation {
        DocumentLocation(id: book.id, directory: directory?.standardizedFileURL, session: documentSession)
    }

    var needsSaveLocation: Bool {
        directory.map { BookStorage.isManagedDraft($0) } ?? false
    }

    func scheduleSave() {
        guard let directory, !isReadOnly else { return }
        let origin = documentLocation
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled, documentLocation == origin else { return }
            let snapshot = book
            // Opening a book, or undoing back to the saved state, leaves the package untouched.
            guard snapshot != lastSaved else {
                saveTask = nil
                return
            }
            let identity = directoryIdentity
            do {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    saveQueue.async {
                        continuation.resume(with: Result {
                            try Self.writeManifest(snapshot, in: directory, identity: identity)
                        })
                    }
                }
            } catch {
                guard !Task.isCancelled, documentLocation == origin else { return }
                saveTask = nil
                if case AppError.bookMoved = error, relocate() {
                    scheduleSave()
                } else {
                    reportSaveFailure(error)
                }
                return
            }
            guard documentLocation == origin else { return }
            lastSaved = snapshot
            guard !Task.isCancelled else { return }
            saveTask = nil
        }
    }

    @discardableResult
    func flushSave() -> Bool {
        saveTask?.cancel()
        saveTask = nil
        guard directory != nil, !isReadOnly, book != lastSaved else { return true }
        do {
            try writeNow()
            return true
        } catch AppError.bookMoved where relocate() {
            do {
                try writeNow()
                return true
            } catch {
                reportSaveFailure(error)
                return false
            }
        } catch {
            reportSaveFailure(error)
            return false
        }
    }

    private func writeNow() throws {
        guard let directory else { return }
        let snapshot = book
        let identity = directoryIdentity
        try saveQueue.sync {
            try Self.writeManifest(snapshot, in: directory, identity: identity)
        }
        lastSaved = snapshot
    }

    private func reportSaveFailure(_ error: Error) {
        if case AppError.bookMoved = error { locationLost = true }
        problem = error.localizedDescription
    }

    func applyBookPrintSettings(title: String, format: BookFormat, printSettings: PrintSettings,
                                cover: BookCover?, typography: EditorialTypography?,
                                undoManager: UndoManager?, actionName: String) {
        let changes = [
            SettingsChange(\.title, from: book.title, to: title),
            SettingsChange(\.format, from: book.format, to: format),
            SettingsChange(\.printSettings, from: book.printSettings, to: printSettings),
            SettingsChange(\.cover, from: book.cover, to: cover),
            SettingsChange(\.typography, from: book.typography, to: typography),
        ].compactMap { $0 }
        applySettings(changes, restoring: false, undoManager: undoManager, actionName: actionName)
    }

    func applyBookTemplate(_ template: BookTemplate?, showPageNumbers: Bool?,
                           undoManager: UndoManager?, actionName: String) {
        let changes = [
            SettingsChange(\.template, from: book.template, to: template),
            SettingsChange(\.showPageNumbers, from: book.showPageNumbers, to: showPageNumbers)
        ].compactMap { $0 }
        applySettings(changes, restoring: false, undoManager: undoManager, actionName: actionName)
    }

    private struct SettingsChange {
        let apply: (inout Book, Bool) -> Void

        init?<Value: Equatable>(_ key: WritableKeyPath<Book, Value>, from previous: Value, to next: Value) {
            guard previous != next else { return nil }
            apply = { book, restoring in book[keyPath: key] = restoring ? previous : next }
        }
    }

    private func applySettings(_ changes: [SettingsChange], restoring: Bool,
                               undoManager: UndoManager?, actionName: String) {
        guard directory != nil, !changes.isEmpty else { return }
        var updated = book
        for change in changes { change.apply(&updated, restoring) }
        book = updated
        if let undoManager {
            settingsUndoManager = undoManager
            undoManager.registerUndo(withTarget: self) { [weak undoManager] target in
                target.applySettings(changes, restoring: !restoring, undoManager: undoManager, actionName: actionName)
            }
            undoManager.setActionName(actionName)
        }
        flushSave()
    }

    func start(_ imported: [LibraryPhoto], title: String, format: BookFormat, language: String) {
        guard !imported.isEmpty else { return }
        importImages(count: imported.count, title: title, format: format, language: language) { index, directory in
            try await PhotoLibrary.importPhoto(imported[index], into: directory)
        }
    }

    func importFiles(language: String) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        let origin = documentLocation
        EditorFilePanels.present(panel) { [weak self] response in
            guard let self, self.documentLocation == origin, response == .OK, !panel.urls.isEmpty else { return }
            let urls = panel.urls
            self.importImages(count: urls.count, title: language == "it" ? "Nuovo libro" : "New Book",
                              format: .square, language: language) { index, directory in
                try await LocalImages.importFile(urls[index], into: directory)
            }
        }
    }

    /// Photo library › Import Files…: adds the chosen images to the open book.
    /// New books from files start only from File › New Book from Files and the welcome window.
    func addPhotoFiles(language: String, onImported: @escaping (UUID) -> Void = { _ in }) {
        guard directory != nil, !importing else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        let origin = documentLocation
        EditorFilePanels.present(panel) { [weak self] response in
            guard let self, self.documentLocation == origin, response == .OK, !panel.urls.isEmpty else { return }
            _ = self.addPhotoFiles(panel.urls, language: language, onImported: onImported)
        }
    }

    @discardableResult
    func addPhotoFiles(_ urls: [URL], language: String, onImported: @escaping (UUID) -> Void = { _ in }) -> Bool {
        enqueueDroppedPhotos(language: language, onImported: onImported) {
            try DroppedPhotos.start(files: urls)
        }
    }

    func addDroppedPhotos(_ providers: [NSItemProvider], language: String,
                          onImported: @escaping (UUID) -> Void = { _ in }) -> Bool {
        enqueueDroppedPhotos(language: language, onImported: onImported) {
            try DroppedPhotos.start(providers, fallbackName: language == "it" ? "Foto" : "Photo")
        }
    }

    func addDroppedPhotoPromises(_ promises: [NSFilePromiseReceiver], language: String,
                                 onImported: @escaping (UUID) -> Void = { _ in }) -> Bool {
        enqueueDroppedPhotos(language: language, onImported: onImported) {
            try DroppedPhotos.start(promises)
        }
    }

    private func enqueueDroppedPhotos(language: String, onImported: @escaping (UUID) -> Void,
                                      start: () throws -> DroppedPhotos?) -> Bool {
        guard let directory, !importing else { return false }
        if let readOnlyReason {
            problem = readOnlyReason.localizedDescription
            return false
        }
        let origin = documentLocation
        let italian = language == "it"
        let drop: DroppedPhotos
        do {
            guard let started = try start() else { return false }
            drop = started
        } catch {
            problem = error.localizedDescription
            return false
        }

        importing = true
        importProgress = "0 / \(drop.count)"
        importTask = Task {
            defer {
                drop.cleanUp()
                importing = false
                importTask = nil
            }
            do {
                var completed = 0
                var results: [DroppedPhotos.Outcome] = []
                for await outcome in drop.outcomes {
                    try Task.checkCancellation()
                    guard documentLocation == origin else { return }
                    completed += 1
                    results.append(outcome)
                    importProgress = "\(completed) / \(drop.count)"
                }
                try Task.checkCancellation()
                guard documentLocation == origin else { return }
                let photos = results.sorted { $0.index < $1.index }.compactMap(\.photo)
                guard let first = photos.first else { throw PhotoImportError.unreadableImage }
                try appendDroppedPhotos(photos, from: drop.directory, to: directory)
                onImported(first.id)
                analyze(language: language, photos: photos)
                let failures = drop.count - photos.count
                if failures > 0 {
                    problem = italian
                        ? "Importate \(photos.count) foto. \(failures) immagini non erano disponibili."
                        : "Imported \(photos.count) photos. \(failures) images were unavailable."
                }
            } catch is CancellationError {
                return
            } catch {
                problem = error.localizedDescription
            }
        }
        return true
    }

    private func appendDroppedPhotos(_ photos: [BookPhoto], from scratch: URL, to directory: URL) throws {
        try validateLocation(directory)
        let files = FileManager.default
        let assets = directory.appendingPathComponent("assets", isDirectory: true)
        if !files.fileExists(atPath: assets.path) {
            try files.createDirectory(at: assets, withIntermediateDirectories: false)
        }
        var installed: [URL] = []
        do {
            for photo in photos {
                let source = BookStorage.assetURL(filename: photo.filename, in: scratch)
                let destination = BookStorage.assetURL(filename: photo.filename, in: directory)
                try files.moveItem(at: source, to: destination)
                installed.append(destination)
            }
            var updated = book
            updated.photos.append(contentsOf: photos)
            let snapshot = updated
            let identity = directoryIdentity
            try saveQueue.sync {
                try Self.writeManifest(snapshot, in: directory, identity: identity)
            }
            book = updated
        } catch {
            for destination in installed { try? files.removeItem(at: destination) }
            throw error
        }
    }

    func cancelImport() { importTask?.cancel() }
    func cancelExport() { exportTask?.cancel() }

    private func importImages(
        count: Int, title: String, format: BookFormat, language: String,
        fetch: @escaping (Int, URL) async throws -> BookPhoto
    ) {
        guard !importing else { return }
        importing = true
        importProgress = "0 / \(count)"
        importTask = Task {
            defer {
                importing = false
                importTask = nil
            }
            do {
                let folder = try BookStorage.createWorkspace()
                var keepFolder = false
                defer { if !keepFolder { try? FileManager.default.removeItem(at: folder) } }
                var newBook = Book(title: title, format: format)
                var failures = 0
                for index in 0..<count {
                    try Task.checkCancellation()
                    do {
                        let photo = try await fetch(index, folder)
                        try Task.checkCancellation()
                        newBook.photos.append(photo)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        failures += 1
                    }
                    importProgress = "\(index + 1) / \(count)"
                }
                try Task.checkCancellation()
                guard !newBook.photos.isEmpty else { throw PhotoImportError.unreadableImage }
                newBook.autoLayout()
                try BookStorage.write(Self.stamped(newBook), to: folder)
                guard flushSave() else { return }
                keepFolder = true
                open(newBook, in: folder)
                newBookNeedsTemplate = true
                analyze(language: language)
                if failures > 0 {
                    problem = language == "it"
                        ? "Importate \(newBook.photos.count) foto. \(failures) immagini non erano disponibili."
                        : "Imported \(newBook.photos.count) photos. \(failures) images were unavailable."
                }
            } catch is CancellationError {
                return
            } catch {
                problem = error.localizedDescription
            }
        }
    }

    func analyze(language: String) {
        analyze(language: language, photos: book.photos.filter { ($0.analysis?.revision ?? 0) < PhotoAnalysis.currentRevision })
    }

    private func analyze(language: String, photos pending: [BookPhoto]) {
        guard let directory, !isReadOnly, analysisTask == nil, !pending.isEmpty else { return }
        let documentID = book.id
        let runID = UUID()
        analysisRun = runID
        analysisProgress = (0, pending.count)
        analysisTask = Task {
            var failures = 0
            var updated: [UUID: PhotoAnalysis] = [:]
            for (offset, photo) in pending.enumerated() {
                if Task.isCancelled || book.id != documentID { break }
                do {
                    let result = try await PhotoAnalyzer.analyze(
                        url: BookStorage.assetURL(filename: photo.filename, in: directory)
                    )
                    if Task.isCancelled || book.id != documentID { break }
                    updated[photo.id] = result
                } catch {
                    if Task.isCancelled { break }
                    failures += 1
                }
                if updated.count >= 8 {
                    applyPhotoAnalysis(updated)
                    updated.removeAll(keepingCapacity: true)
                }
                if analysisRun == runID { analysisProgress = (offset + 1, pending.count) }
            }
            guard analysisRun == runID else { return }
            applyPhotoAnalysis(updated)
            analysisProgress = nil
            analysisTask = nil
            analysisRun = nil
            flushSave()
            if failures > 0 {
                problem = language == "it" ? "Analisi non riuscita per \(failures) foto. Puoi riprovare dall’editor."
                    : "Analysis failed for \(failures) photos. You can retry from the editor."
            }
        }
    }

    private func applyPhotoAnalysis(_ updated: [UUID: PhotoAnalysis]) {
        guard !updated.isEmpty else { return }
        var photos = book.photos
        for index in photos.indices {
            if let analysis = updated[photos[index].id] { photos[index].analysis = analysis }
        }
        book.photos = photos
    }

    private var analysisRun: UUID?

    private func open(_ incoming: Book, in folder: URL) {
        settingsUndoManager?.removeAllActions(withTarget: self)
        analysisTask?.cancel()
        analysisTask = nil
        analysisRun = nil
        analysisProgress = nil
        let reason = Self.readOnlyReason(for: incoming, in: folder)
        // The writer version is stamped in memory too, so the open book equals what the next save writes.
        // `lastSaved` is the same value: opening alone never rewrites the manifest.
        let opened = reason == nil ? Self.stamped(incoming) : incoming
        lastSaved = opened
        book = opened
        rememberLocation(folder)
        readOnlyReason = reason
        if let reason { problem = reason.localizedDescription }
    }

    nonisolated static func readOnlyReason(for book: Book, in folder: URL) -> AppError? {
        if (book.writerVersion ?? 0) > writerVersion { return .newerFormat(title: book.title) }
        let files = FileManager.default
        let manifest = folder.appendingPathComponent("manifest.json")
        let volumeReadOnly = (try? folder.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly ?? false
        if volumeReadOnly || !files.isWritableFile(atPath: folder.path) || !files.isWritableFile(atPath: manifest.path) {
            return .readOnlyLocation(title: book.title)
        }
        return nil
    }

    /// The book as this build writes it, with its writer version.
    nonisolated static func stamped(_ book: Book) -> Book {
        var stamped = book
        stamped.writerVersion = writerVersion
        return stamped
    }

    private func rememberLocation(_ folder: URL?) {
        saveTask?.cancel()
        saveTask = nil
        documentSession = UUID()
        if locationLost || readOnlyReason != nil { problem = nil }
        locationLost = false
        readOnlyReason = nil
        directoryIdentity = folder.flatMap { BookStorage.identity(of: $0) }
        directory = folder
        if let folder {
            defaults.set(folder.path, forKey: "lastBook")
            noteRecentBook()
        } else {
            defaults.removeObject(forKey: "lastBook")
        }
    }

    /// Follows the open package after a rename or a move in Finder. It stays the same document:
    /// pending imports, panels and undo history keep working, and saves continue in the new place.
    private func adoptMovedPackage(_ folder: URL) {
        if let previous = directory {
            let path = previous.standardizedFileURL.path
            recentBooks.removeAll { $0.path == path }
        }
        if locationLost { problem = nil }
        locationLost = false
        directoryIdentity = BookStorage.identity(of: folder) ?? directoryIdentity
        directory = folder
        defaults.set(folder.path, forKey: "lastBook")
        noteRecentBook()
    }

    /// Finds the open package again by its volume and file number.
    @discardableResult
    func relocate() -> Bool {
        guard let identity = directoryIdentity, let found = Self.locate(identity) else { return false }
        adoptMovedPackage(found)
        return true
    }

    nonisolated static func locate(_ identity: BookStorage.DirectoryIdentity) -> URL? {
        var fileSystem = fsid_t(val: (Int32(truncatingIfNeeded: identity.volume), 0))
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fsgetpath(&buffer, buffer.count, &fileSystem, identity.inode) > 0 else { return nil }
        let url = URL(fileURLWithPath: String(cString: buffer), isDirectory: true)
        // A package in the Trash counts as gone: the author chooses where to keep the edits.
        guard BookStorage.identity(of: url) == identity,
              !url.pathComponents.contains(where: { $0 == ".Trash" || $0 == ".Trashes" }),
              FileManager.default.fileExists(atPath: url.appendingPathComponent("manifest.json").path)
        else { return nil }
        return url
    }

    private func validateLocation(_ folder: URL) throws {
        try Self.validateLocation(folder, identity: directoryIdentity, title: book.title)
    }

    private nonisolated static func writeManifest(_ snapshot: Book, in folder: URL,
                                                  identity: BookStorage.DirectoryIdentity?) throws {
        try validateLocation(folder, identity: identity, title: snapshot.title)
        try BookStorage.writeExisting(stamped(snapshot), to: folder)
    }

    private nonisolated static func validateLocation(_ folder: URL, identity: BookStorage.DirectoryIdentity?,
                                                     title: String) throws {
        if let identity, BookStorage.identity(of: folder) != identity {
            throw AppError.bookMoved(title: title)
        }
    }

    /// The open book could not be saved because its package is gone. Ask before leaving it.
    private func confirmLeavingLostBook(then leave: @escaping () -> Void) {
        let italian = AppError.interfaceLanguage == "it"
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = italian ? "Il libro non si trova più nella sua posizione"
            : "The book is no longer where it was saved"
        alert.informativeText = italian
            ? "Le ultime modifiche non sono salvate. Puoi salvarle in un’altra posizione oppure chiudere senza salvare."
            : "Your latest changes are not saved. You can save them in another place or close without saving."
        alert.addButton(withTitle: italian ? "Salva con nome…" : "Save As…")
        alert.addButton(withTitle: italian ? "Chiudi senza salvare" : "Close Without Saving")
        alert.addButton(withTitle: italian ? "Annulla" : "Cancel")
        let origin = documentLocation
        EditorFilePanels.present(alert) { [weak self] response in
            guard let self, self.documentLocation == origin else { return }
            switch response {
            case .alertFirstButtonReturn: self.saveProjectAs()
            case .alertSecondButtonReturn: leave()
            default: break
            }
        }
    }

    func reopenLastBook() {
        guard directory == nil,
              let path = defaults.string(forKey: "lastBook"),
              let restored = try? BookStorage.read(from: URL(fileURLWithPath: path)) else { return }
        open(restored, in: URL(fileURLWithPath: path))
    }

    func openProject() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Self.bookType]
        panel.canChooseDirectories = false
        let origin = documentLocation
        EditorFilePanels.present(panel) { [weak self] response in
            guard let self, self.documentLocation == origin, response == .OK, let url = panel.url else { return }
            self.openProject(at: url)
        }
    }

    func openProject(at url: URL) {
        if let directory, BookStorage.sameLocation(directory, url) {
            flushSave()
            return
        }
        if let directoryIdentity, BookStorage.identity(of: url) == directoryIdentity {
            // The same package was moved while open. Continue saving in its new location.
            adoptMovedPackage(url)
            flushSave()
            return
        }
        do {
            let restored = try BookStorage.read(from: url)
            guard flushSave() else {
                if locationLost { confirmLeavingLostBook { [weak self] in self?.open(restored, in: url) } }
                return
            }
            open(restored, in: url)
        } catch { problem = error.localizedDescription }
    }

    func closeBook() {
        guard flushSave() else {
            if locationLost { confirmLeavingLostBook { [weak self] in self?.finishClosing() } }
            return
        }
        finishClosing()
    }

    private func finishClosing() {
        noteRecentBook()
        settingsUndoManager?.removeAllActions(withTarget: self)
        analysisTask?.cancel()
        analysisTask = nil
        analysisRun = nil
        analysisProgress = nil
        rememberLocation(nil)
    }

    func saveProject() {
        if let readOnlyReason {
            problem = readOnlyReason.localizedDescription
        } else if needsSaveLocation {
            saveProjectAs()
        } else {
            flushSave()
        }
    }

    /// A book from a newer Paper & Grain cannot be copied: this build would drop the data it does not know.
    var canSaveAs: Bool {
        guard directory != nil else { return false }
        if case .newerFormat? = readOnlyReason { return false }
        return true
    }

    func saveProjectAs() {
        guard let directory, canSaveAs else {
            if let readOnlyReason { problem = readOnlyReason.localizedDescription }
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.bookType]
        panel.nameFieldStringValue = safeFilename(book.title)
        let origin = documentLocation
        EditorFilePanels.present(panel) { [weak self] response in
            guard let self, self.documentLocation == origin, response == .OK, let destination = panel.url else { return }
            self.saveProjectCopy(from: directory, to: destination)
        }
    }

    func saveProjectCopy(from directory: URL, to destination: URL) {
        guard !BookStorage.sameLocation(directory, destination) else {
            flushSave()
            return
        }
        var directory = directory
        if let identity = directoryIdentity, BookStorage.identity(of: directory) != identity {
            guard relocate(), let found = self.directory else {
                saveDetachedCopy(to: destination)
                return
            }
            directory = found
        }
        do {
            let snapshot = book
            let identity = directoryIdentity
            let title = book.title
            var locked = false
            if case .readOnlyLocation? = readOnlyReason { locked = true }
            try saveQueue.sync {
                try Self.validateLocation(directory, identity: identity, title: title)
                if locked {
                    try Self.copyLockedPackage(Self.stamped(snapshot), from: directory, to: destination)
                } else {
                    try BookStorage.copy(Self.stamped(snapshot), from: directory, to: destination)
                }
            }
            // An in-flight classifier keeps reading the old asset directory.
            // Its results still update this document and are saved to the new location.
            rememberLocation(destination)
            lastSaved = snapshot
        } catch { problem = error.localizedDescription }
    }

    /// A package without write permission keeps them when copied. Stage a writable copy next to the
    /// destination first, then copy it as usual.
    private nonisolated static func copyLockedPackage(_ book: Book, from source: URL, to destination: URL) throws {
        let files = FileManager.default
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString)-source.papergrain", isDirectory: true)
        defer { try? files.removeItem(at: staging) }
        try files.copyItem(at: source, to: staging)
        var items = [staging]
        if let contents = files.enumerator(at: staging, includingPropertiesForKeys: nil) {
            items += contents.compactMap { $0 as? URL }
        }
        for item in items {
            let permissions = (try? files.attributesOfItem(atPath: item.path)[.posixPermissions] as? NSNumber)?.intValue ?? 0o644
            try files.setAttributes([.posixPermissions: permissions | 0o200], ofItemAtPath: item.path)
        }
        try BookStorage.copy(book, from: staging, to: destination)
    }

    /// Save As for a book whose package is gone, for example on an ejected disk: writes the current
    /// manifest so no edit is lost. Photos that were only in the old package stay missing until it returns.
    private func saveDetachedCopy(to destination: URL) {
        do {
            let snapshot = book
            try saveQueue.sync {
                let files = FileManager.default
                let staging = destination.deletingLastPathComponent()
                    .appendingPathComponent(".\(UUID().uuidString).papergrain", isDirectory: true)
                defer { try? files.removeItem(at: staging) }
                try BookStorage.write(Self.stamped(snapshot), to: staging)
                if files.fileExists(atPath: destination.path) {
                    _ = try files.replaceItemAt(destination, withItemAt: staging)
                } else {
                    try files.moveItem(at: staging, to: destination)
                }
            }
            rememberLocation(destination)
            lastSaved = snapshot
        } catch { problem = error.localizedDescription }
    }

    func loadDemo(language: String) {
        guard let image = Bundle.main.url(forResource: "Demo", withExtension: "png") else { return }
        importImages(count: 1, title: language == "it" ? "Sardegna, settembre" : "Sardinia in September",
                     format: .square, language: language) { _, directory in
            try await LocalImages.importFile(image, into: directory)
        }
    }

    func exportPDF(_ request: PDFExportRequest, language: String) {
        guard let directory, !book.pages.isEmpty, !exporting else { return }
        if case .printPackage = request {
            exportPrint(language: language)
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        let suffix: String
        if case .pixart = request {
            suffix = " - Pixartprinting"
        } else {
            suffix = ""
        }
        panel.nameFieldStringValue = safeFilename(book.title) + suffix
        chooseExportDestination(panel, from: directory, request: request)
    }

    func exportPrint(language: String) {
        guard let directory, !book.pages.isEmpty, !exporting else { return }
        let italian = language == "it"
        let warnings = BookPDF.printWarnings(book)
        func chooseDestination() {
            let panel = NSSavePanel()
            panel.message = italian ? "Scegli dove creare la cartella dei PDF" : "Choose where to create the PDF folder"
            panel.nameFieldStringValue = safeFilename(book.title) + (italian ? " – Stampa" : " – Print")
            chooseExportDestination(panel, from: directory, request: .printPackage)
        }
        guard !warnings.isEmpty else {
            chooseDestination()
            return
        }
        let check = NSAlert()
        check.messageText = italian ? "Controllo di stampa" : "Print Check"
        let lines = warnings.prefix(8).joined(separator: "\n")
        let suffix = warnings.count > 8 ? "\n… +\(warnings.count - 8)" : ""
        check.informativeText = lines + suffix
        check.addButton(withTitle: italian ? "Continua" : "Continue")
        check.addButton(withTitle: italian ? "Annulla" : "Cancel")
        let origin = documentLocation
        EditorFilePanels.present(check) { [weak self] response in
            guard let self, self.documentLocation == origin, !self.exporting, response == .alertFirstButtonReturn
            else { return }
            chooseDestination()
        }
    }

    private func chooseExportDestination(_ panel: NSSavePanel, from directory: URL, request: PDFExportRequest) {
        let origin = documentLocation
        EditorFilePanels.present(panel) { [weak self] response in
            guard let self, self.documentLocation == origin, !self.exporting, !self.book.pages.isEmpty,
                  response == .OK, let destination = panel.url else { return }
            self.export(to: destination, from: directory, request: request)
        }
    }

    private func export(to destination: URL, from directory: URL, request: PDFExportRequest) {
        let snapshot = book
        exporting = true
        exportTask = Task {
            defer {
                exporting = false
                exportTask = nil
            }
            do {
                let worker = Task.detached(priority: .userInitiated) {
                    switch request {
                    case .proof:
                        try BookPDF.write(snapshot, directory: directory, to: destination)
                    case .printPackage:
                        try BookPDF.writePrint(snapshot, directory: directory, to: destination)
                    case let .pixart(spineMM):
                        try BookPDF.writePixart(snapshot, directory: directory, spineMM: spineMM, to: destination)
                    }
                }
                try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
            } catch is CancellationError {
                return
            } catch {
                problem = error.localizedDescription
            }
        }
    }

    private func safeFilename(_ title: String) -> String {
        let clean = title.replacingOccurrences(of: "/", with: "–").replacingOccurrences(of: ":", with: "–")
        return clean.isEmpty ? "Paper and Grain" : clean
    }
}
