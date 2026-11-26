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
    /// Fraction of the current export, 0 to 1, reported per sheet.
    @Published private(set) var exportProgress = 0.0
    /// Save As copies the package off the main thread behind the progress overlay.
    @Published private(set) var savingCopy = false
    /// The open book is an unsaved draft: Save Project asks for a place. Cached when the location changes.
    @Published private(set) var needsSaveLocation = false
    @Published var problem: String?
    /// The open package was moved or removed and could not be found again. Edits stay in memory until Save As.
    @Published private(set) var locationLost = false
    /// Set when a new book opens, so the window can ask for its template first.
    @Published var newBookNeedsTemplate = false
    @Published private(set) var recentBooks: [RecentBook] = []
    /// Unsaved books found in the Drafts folder, whether or not they are still in the recents list.
    @Published private(set) var drafts: [RecentBook] = []
    /// Identifies the editing session of one opened package. It changes when another package is opened
    /// or the book is closed, not on Save As or when a moved package is found again. The editor is keyed
    /// on it, so undo history never crosses into another package that shares the same book id.
    @Published private(set) var editorSession = UUID()

    private var analysisTask: Task<Void, Never>?
    private var importTask: Task<Void, Never>?
    private var exportTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var copyTask: Task<Void, Never>?
    private nonisolated(unsafe) var terminationObserver: NSObjectProtocol?
    /// Photos added while an analysis runs; analysed when that run ends.
    private var queuedAnalysis: [UUID] = []
    private var openRequest: UUID?
    // Order autosaves before durable writes and package copies.
    private let saveQueue = DispatchQueue(label: "me.magno.paperandgrain.manifest", qos: .utility)
    private weak var settingsUndoManager: UndoManager?
    private var documentSession = UUID()
    private var directoryIdentity: BookStorage.DirectoryIdentity?
    private let defaults: UserDefaults
    private let draftsRoot: URL?
    private let moveToTrash: (URL) throws -> Void
    static let bookType = UTType(exportedAs: "me.magno.paperandgrain.book", conformingTo: .package)

    init(defaults: UserDefaults = .standard, draftsRoot: URL? = nil,
         moveToTrash: @escaping (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) {
        self.defaults = defaults
        self.draftsRoot = draftsRoot ?? (try? BookStorage.draftsDirectory(create: false))
        self.moveToTrash = moveToTrash
        recentBooks = RecentBook.load(from: defaults)
        // Quitting flushes the open book even when its window is already closed.
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.flushSave() }
        }
    }

    deinit {
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
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
                               isDraft: isDraft(directory))
        var books = recentBooks.filter { $0.path != entry.path }
        books.insert(entry, at: 0)
        recentBooks = Array(books.prefix(12))
        if let data = try? JSONEncoder().encode(recentBooks) { defaults.set(data, forKey: "recentBooks") }
    }

    func forgetRecentBook(_ recent: RecentBook) {
        recentBooks.removeAll { $0.path == recent.path }
        if let data = try? JSONEncoder().encode(recentBooks) { defaults.set(data, forKey: "recentBooks") }
    }

    private func isDraft(_ folder: URL) -> Bool {
        guard let draftsRoot else { return false }
        return BookStorage.isManagedDraft(folder, in: draftsRoot)
    }

    /// The welcome window's books: every draft in the Drafts folder plus the recently opened packages.
    var libraryBooks: [RecentBook] {
        let draftPaths = Set(drafts.map(\.path))
        let recentDrafts = Dictionary(recentBooks.filter { draftPaths.contains($0.path) }.map { ($0.path, $0) },
                                      uniquingKeysWith: { first, _ in first })
        let listed = drafts.map { recentDrafts[$0.path] ?? $0 }
        return (listed + recentBooks.filter { !$0.isDraft && !draftPaths.contains($0.path) })
            .sorted { $0.opened > $1.opened }
    }

    /// Lists the Drafts folder off the main thread. Recents alone lose drafts beyond the twelfth,
    /// after Remove from Recents or when the preferences are reset.
    @discardableResult
    func refreshDrafts() -> Task<Void, Never> {
        let root = draftsRoot
        return Task {
            let found = await Task.detached(priority: .utility) { root.map(Self.listDrafts(in:)) ?? [] }.value
            drafts = found
        }
    }

    nonisolated static func listDrafts(in root: URL) -> [RecentBook] {
        let files = FileManager.default
        guard let folders = try? files.contentsOfDirectory(at: root, includingPropertiesForKeys: nil,
                                                           options: [.skipsHiddenFiles]) else { return [] }
        return folders.compactMap { folder -> RecentBook? in
            guard UUID(uuidString: folder.lastPathComponent) != nil,
                  let book = try? BookStorage.read(from: folder) else { return nil }
            let manifest = folder.appendingPathComponent("manifest.json")
            let modified = (try? files.attributesOfItem(atPath: manifest.path)[.modificationDate] as? Date) ?? .distantPast
            let coverID = book.cover?.frontPhotoID ?? book.pages.lazy.flatMap(\.photoIDs).first
            let cover = coverID.flatMap { id in book.photos.first { $0.id == id }?.filename }
            return RecentBook(path: folder.standardizedFileURL.path, title: book.title, opened: modified,
                              pageCount: book.pages.count, coverFile: cover, isDraft: true)
        }
    }

    /// Welcome window › Delete Draft…, after confirmation. The draft goes to the Trash.
    func deleteDraft(_ draft: RecentBook) {
        let folder = draft.url
        guard isDraft(folder), !(directory.map { BookStorage.sameLocation($0, folder) } ?? false) else { return }
        do {
            try moveToTrash(folder)
            forgetRecentBook(draft)
            drafts.removeAll { $0.path == draft.path }
        } catch { problem = error.localizedDescription }
    }

    /// After Save As the draft has been copied and adopted: retire it so its stale card cannot be edited.
    private func retireDraft(_ folder: URL) {
        let path = folder.standardizedFileURL.path
        guard (try? moveToTrash(folder)) != nil else { return }
        recentBooks.removeAll { $0.path == path }
        if let data = try? JSONEncoder().encode(recentBooks) { defaults.set(data, forKey: "recentBooks") }
        drafts.removeAll { $0.path == path }
    }

    private struct DocumentLocation: Equatable {
        let id: UUID
        let directory: URL?
        let session: UUID
    }

    private var documentLocation: DocumentLocation {
        DocumentLocation(id: book.id, directory: directory?.standardizedFileURL, session: documentSession)
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

    /// Writes the book off the main thread when it differs from the saved manifest.
    /// Returns false when it could not be saved.
    @discardableResult
    func save() async -> Bool {
        saveTask?.cancel()
        saveTask = nil
        for attempt in 0..<2 {
            guard let directory, !isReadOnly, book != lastSaved else { return true }
            let snapshot = book
            let identity = directoryIdentity
            do {
                try await onSaveQueue { try Self.writeManifest(snapshot, in: directory, identity: identity) }
                if self.directory == directory { lastSaved = snapshot }
                return true
            } catch AppError.bookMoved where attempt == 0 && relocate() {
                continue
            } catch {
                if self.directory == directory { reportSaveFailure(error) }
                return false
            }
        }
        return false
    }

    /// Saves until the book matches its package, so edits made while a write was running are kept
    /// before the workspace leaves this book.
    private func saveBeforeLeaving() async -> Bool {
        for _ in 0..<3 {
            guard await save() else { return false }
            if isReadOnly || directory == nil || book == lastSaved { return true }
        }
        return book == lastSaved
    }

    private func onSaveQueue<Value>(_ work: @escaping @Sendable () throws -> Value) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            saveQueue.async { continuation.resume(with: Result { try work() }) }
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
        let error = AppError.saving(error, title: book.title)
        switch error {
        case AppError.bookMoved: locationLost = true
        case let reason as AppError where reason == .readOnlyLocation(title: book.title):
            // Stop retrying a package that cannot be written; Save As stays available.
            readOnlyReason = reason
        default: break
        }
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

    /// Keeps the cover and page measures typed for the book's print service, as one undoable step.
    func savePrintMeasures(_ measures: PrintMeasures, undoManager: UndoManager?, actionName: String) {
        guard var settings = book.printSettings, settings.profileID != nil else { return }
        settings.profileMeasures = measures == PrintMeasures() ? nil : measures
        let changes = [SettingsChange(\.printSettings, from: book.printSettings, to: settings)].compactMap { $0 }
        guard !changes.isEmpty else { return }
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
            self.importImages(count: urls.count, title: L10n.string("New Book", language: language),
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
            try DroppedPhotos.start(providers, fallbackName: L10n.string("Photo", language: language))
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
        guard directory != nil, !importing else { return false }
        if let readOnlyReason {
            problem = readOnlyReason.localizedDescription
            return false
        }
        // A slow drop survives Save As and a move in Finder: it follows the session, not the folder.
        let session = editorSession
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
                    guard editorSession == session else { return }
                    completed += 1
                    results.append(outcome)
                    importProgress = "\(completed) / \(drop.count)"
                }
                try Task.checkCancellation()
                guard editorSession == session else { return }
                let ordered = results.sorted { $0.index < $1.index }
                let photos = ordered.compactMap(\.photo)
                // Outcomes that never arrived (a cancelled promise) count as unavailable without a name.
                let unavailable = ordered.filter { $0.photo == nil }.map(\.name)
                    + Array(repeating: nil, count: max(0, drop.count - ordered.count))
                guard let first = photos.first else {
                    throw unavailable.count == 1 ? AppError.imageUnavailable(name: unavailable[0])
                        : AppError.someImagesUnavailable(imported: 0, unavailable: unavailable)
                }
                try await appendDroppedPhotos(photos, from: drop.directory, session: session)
                onImported(first.id)
                analyze(language: language, photos: photos)
                if !unavailable.isEmpty {
                    problem = AppError.someImagesUnavailable(imported: photos.count, unavailable: unavailable).localizedDescription
                }
            } catch is CancellationError {
                return
            } catch {
                problem = error.localizedDescription
            }
        }
        return true
    }

    /// Installs the photos in the session's current package, after any Save As copy in progress.
    private func appendDroppedPhotos(_ photos: [BookPhoto], from scratch: URL, session: UUID) async throws {
        while let copyTask {
            await copyTask.value
        }
        guard editorSession == session else { throw CancellationError() }
        if let identity = directoryIdentity, let current = directory, BookStorage.identity(of: current) != identity {
            relocate()
        }
        guard let directory else { throw CancellationError() }
        var updated = book
        updated.photos.append(contentsOf: photos)
        let snapshot = updated
        let identity = directoryIdentity
        try await onSaveQueue {
            try Self.validateLocation(directory, identity: identity, title: snapshot.title)
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
                try Self.writeManifest(snapshot, in: directory, identity: identity)
            } catch {
                for destination in installed { try? files.removeItem(at: destination) }
                throw error
            }
        }
        // The package already holds the photos; another book opened meanwhile must not receive them.
        guard editorSession == session else { throw CancellationError() }
        // Edits made while the files moved stay: add the photos to the current book.
        if self.directory == directory { lastSaved = snapshot }
        book.photos.append(contentsOf: photos)
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
                var unavailable: [String?] = []
                for index in 0..<count {
                    try Task.checkCancellation()
                    do {
                        let photo = try await fetch(index, folder)
                        try Task.checkCancellation()
                        newBook.photos.append(photo)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch let AppError.imageUnavailable(name) {
                        unavailable.append(name)
                    } catch {
                        unavailable.append(nil)
                    }
                    importProgress = "\(index + 1) / \(count)"
                }
                try Task.checkCancellation()
                guard !newBook.photos.isEmpty else {
                    throw unavailable.count == 1 ? AppError.imageUnavailable(name: unavailable[0])
                        : AppError.someImagesUnavailable(imported: 0, unavailable: unavailable)
                }
                newBook.autoLayout()
                let firstManifest = Self.stamped(newBook)
                try await Task.detached(priority: .userInitiated) { try BookStorage.write(firstManifest, to: folder) }.value
                guard await saveBeforeLeaving() else { return }
                keepFolder = true
                open(newBook, in: folder)
                newBookNeedsTemplate = true
                analyze(language: language)
                if !unavailable.isEmpty {
                    problem = AppError.someImagesUnavailable(imported: newBook.photos.count,
                                                            unavailable: unavailable).localizedDescription
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
        guard let directory, !isReadOnly, !pending.isEmpty else { return }
        guard analysisTask == nil else {
            // Photos dropped during a run are analysed when it ends.
            queuedAnalysis.append(contentsOf: pending.map(\.id).filter { !queuedAnalysis.contains($0) })
            return
        }
        let session = editorSession
        let runID = UUID()
        analysisRun = runID
        analysisProgress = (0, pending.count)
        analysisTask = Task {
            var failures = 0
            var updated: [UUID: PhotoAnalysis] = [:]
            for (offset, photo) in pending.enumerated() {
                if Task.isCancelled || editorSession != session { break }
                // Read from the current package: Save As may adopt a new one and retire a draft mid-run.
                let folder = self.directory ?? directory
                do {
                    let result: PhotoAnalysis
                    do {
                        result = try await PhotoAnalyzer.analyze(url: BookStorage.assetURL(filename: photo.filename, in: folder))
                    } catch where !Task.isCancelled && self.directory != nil && self.directory != folder {
                        result = try await PhotoAnalyzer.analyze(
                            url: BookStorage.assetURL(filename: photo.filename, in: self.directory ?? folder)
                        )
                    }
                    if Task.isCancelled || editorSession != session { break }
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
            let queued = Set(queuedAnalysis)
            queuedAnalysis.removeAll()
            if !queued.isEmpty {
                analyze(language: language, photos: book.photos.filter {
                    queued.contains($0.id) && ($0.analysis?.revision ?? 0) < PhotoAnalysis.currentRevision
                })
            }
            await save()
            if failures > 0 {
                problem = L10n.format("Analysis failed for %lld photos. You can retry from the editor.",
                                      language: language, [failures])
            }
        }
    }

    /// Lets tests wait for the photo analysis, including runs started for queued photos.
    var isAnalyzing: Bool { analysisTask != nil }

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
        editorSession = UUID()
        analysisTask?.cancel()
        analysisTask = nil
        analysisRun = nil
        analysisProgress = nil
        queuedAnalysis.removeAll()
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
        needsSaveLocation = folder.map(isDraft) ?? false
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
        needsSaveLocation = isDraft(folder)
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
        let language = L10n.interfaceLanguage
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.string("The book is no longer where it was saved", language: language)
        alert.informativeText = L10n.string("Your latest changes are not saved. You can save them in another place or close without saving.", language: language)
        alert.addButton(withTitle: L10n.string("Save As…", language: language))
        alert.addButton(withTitle: L10n.string("Close Without Saving", language: language))
        alert.addButton(withTitle: L10n.string("Cancel", language: language))
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

    @discardableResult
    func reopenLastBook() -> Task<Void, Never> {
        guard directory == nil, let path = defaults.string(forKey: "lastBook") else { return Task {} }
        let url = URL(fileURLWithPath: path)
        let request = UUID()
        openRequest = request
        return Task {
            guard let restored = try? await Self.readBook(at: url), openRequest == request, directory == nil else { return }
            open(restored, in: url)
        }
    }

    private nonisolated static func readBook(at url: URL) async throws -> Book {
        try await Task.detached(priority: .userInitiated) { try BookStorage.read(from: url) }.value
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

    /// Reads the package and saves the open book off the main thread, then switches to it.
    @discardableResult
    func openProject(at url: URL) -> Task<Void, Never> {
        if let directory, BookStorage.sameLocation(directory, url) {
            return Task { await save() }
        }
        if let directoryIdentity, BookStorage.identity(of: url) == directoryIdentity {
            // The same package was moved while open. Continue saving in its new location.
            adoptMovedPackage(url)
            return Task { await save() }
        }
        let request = UUID()
        openRequest = request
        return Task {
            let restored: Book
            do {
                restored = try await Self.readBook(at: url)
            } catch {
                if openRequest == request { problem = AppError.opening(error, at: url).localizedDescription }
                return
            }
            guard openRequest == request else { return }
            guard await saveBeforeLeaving() else {
                if locationLost { confirmLeavingLostBook { self.open(restored, in: url) } }
                return
            }
            guard openRequest == request else { return }
            open(restored, in: url)
        }
    }

    @discardableResult
    func closeBook() -> Task<Void, Never> {
        let session = editorSession
        return Task {
            guard await saveBeforeLeaving() else {
                if locationLost { confirmLeavingLostBook { self.finishClosing() } }
                return
            }
            guard editorSession == session, directory != nil else { return }
            finishClosing()
        }
    }

    private func finishClosing() {
        openRequest = nil
        noteRecentBook()
        editorSession = UUID()
        settingsUndoManager?.removeAllActions(withTarget: self)
        analysisTask?.cancel()
        analysisTask = nil
        analysisRun = nil
        analysisProgress = nil
        queuedAnalysis.removeAll()
        rememberLocation(nil)
    }

    func saveProject() {
        if let readOnlyReason {
            problem = readOnlyReason.localizedDescription
        } else if needsSaveLocation {
            saveProjectAs()
        } else {
            Task { await save() }
        }
    }

    /// A book from a newer Paper & Grain cannot be copied: this build would drop the data it does not know.
    var canSaveAs: Bool {
        guard directory != nil, !savingCopy else { return false }
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

    /// Copies the package to `destination` off the main thread and continues editing there.
    @discardableResult
    func saveProjectCopy(from directory: URL, to destination: URL) -> Task<Void, Never> {
        guard !savingCopy else { return Task {} }
        guard !BookStorage.sameLocation(directory, destination) else {
            return Task { await save() }
        }
        savingCopy = true
        let session = editorSession
        let task = Task {
            defer {
                savingCopy = false
                copyTask = nil
            }
            var source = directory
            if let identity = directoryIdentity, BookStorage.identity(of: source) != identity {
                guard relocate(), let found = self.directory else {
                    await saveDetachedCopy(to: destination, session: session)
                    return
                }
                source = found
            }
            let snapshot = book
            let identity = directoryIdentity
            let from = source
            let locked: Bool
            if case .readOnlyLocation? = readOnlyReason { locked = true } else { locked = false }
            do {
                try await onSaveQueue {
                    try Self.validateLocation(from, identity: identity, title: snapshot.title)
                    if locked {
                        try Self.copyLockedPackage(Self.stamped(snapshot), from: from, to: destination)
                    } else {
                        try BookStorage.copy(Self.stamped(snapshot), from: from, to: destination)
                    }
                }
            } catch {
                if editorSession == session { problem = error.localizedDescription }
                return
            }
            guard editorSession == session else { return }
            adoptCopy(at: destination, snapshot: snapshot, retiring: isDraft(source) ? source : nil)
        }
        copyTask = task
        return task
    }

    private func adoptCopy(at destination: URL, snapshot: Book, retiring draft: URL?) {
        rememberLocation(destination)
        lastSaved = snapshot
        // Edits made while the package was copied are saved in the new place.
        if book != snapshot { scheduleSave() }
        // The analysis follows the new location, so nothing reads from the draft any more.
        if let draft { retireDraft(draft) }
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
    private func saveDetachedCopy(to destination: URL, session: UUID) async {
        let snapshot = book
        do {
            try await onSaveQueue {
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
        } catch {
            if editorSession == session { problem = error.localizedDescription }
            return
        }
        guard editorSession == session else { return }
        adoptCopy(at: destination, snapshot: snapshot, retiring: nil)
    }

    func loadDemo(language: String) {
        guard let image = Bundle.main.url(forResource: "Demo", withExtension: "png") else { return }
        importImages(count: 1, title: L10n.string("Sardinia in September", language: language),
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
        let suffix: String
        if case let .service(plan) = request {
            suffix = " - " + safeFilename(plan.profile.service)
            if plan.profile.files.arrangement == .separate {
                // Separate interior and cover files go in a new folder, like Generic Print.
                panel.message = L10n.string("Choose where to create the PDF folder", language: language)
            } else {
                panel.allowedContentTypes = [.pdf]
            }
        } else {
            panel.allowedContentTypes = [.pdf]
            suffix = ""
        }
        panel.nameFieldStringValue = safeFilename(book.title) + suffix
        chooseExportDestination(panel, from: directory, request: request)
    }

    func exportPrint(language: String) {
        guard let directory, !book.pages.isEmpty, !exporting else { return }
        let warnings = BookPDF.printWarnings(book, language: language)
        func chooseDestination() {
            let panel = NSSavePanel()
            panel.message = L10n.string("Choose where to create the PDF folder", language: language)
            panel.nameFieldStringValue = safeFilename(book.title) + L10n.string(" – Print", language: language)
            chooseExportDestination(panel, from: directory, request: .printPackage)
        }
        guard !warnings.isEmpty else {
            chooseDestination()
            return
        }
        let check = NSAlert()
        check.messageText = L10n.string("Print Check", language: language)
        let lines = warnings.prefix(8).joined(separator: "\n")
        let suffix = warnings.count > 8 ? "\n… +\(warnings.count - 8)" : ""
        check.informativeText = lines + suffix
        check.addButton(withTitle: L10n.string("Continue", language: language))
        check.addButton(withTitle: L10n.string("Cancel", language: language))
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
        exportProgress = 0
        exportTask = Task {
            defer {
                exporting = false
                exportTask = nil
            }
            do {
                // The exporter reports from its own thread; the progress card reads it on the main actor.
                let progress: @Sendable (Double) -> Void = { [self] fraction in
                    Task { @MainActor in self.exportProgress = min(1, max(0, fraction)) }
                }
                let worker = Task.detached(priority: .userInitiated) {
                    switch request {
                    case .proof:
                        try BookPDF.write(snapshot, directory: directory, to: destination, progress: progress)
                    case .printPackage:
                        try BookPDF.writePrint(snapshot, directory: directory, to: destination, progress: progress)
                    case let .service(plan):
                        try BookPDF.write(snapshot, directory: directory, plan: plan, to: destination, progress: progress)
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
