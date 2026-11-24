import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class Workspace: ObservableObject {
    @Published var book = Book(title: "")
    @Published private(set) var directory: URL?
    @Published private(set) var importing = false
    @Published private(set) var importProgress = ""
    @Published private(set) var analysisProgress: (done: Int, total: Int)?
    @Published private(set) var exporting = false
    @Published var problem: String?

    private var analysisTask: Task<Void, Never>?
    private var importTask: Task<Void, Never>?
    private var exportTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var documentSession = UUID()
    private var directoryIdentity: BookStorage.DirectoryIdentity?
    private let defaults: UserDefaults
    static let bookType = UTType(exportedAs: "local.paperandgrain.book", conformingTo: .package)

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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
        guard directory != nil else { return }
        let origin = documentLocation
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled, documentLocation == origin else { return }
            saveTask = nil
            flushSave()
        }
    }

    @discardableResult
    func flushSave() -> Bool {
        saveTask?.cancel()
        saveTask = nil
        guard let directory else { return true }
        do {
            try validateLocation(directory)
            try BookStorage.writeExisting(book, to: directory)
            return true
        } catch {
            problem = error.localizedDescription
            return false
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
            self.importImages(count: urls.count, title: language == "it" ? "Nuovo libro" : "New Book",
                              format: .square, language: language) { index, directory in
                try await LocalImages.importFile(urls[index], into: directory)
            }
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
            try BookStorage.writeExisting(updated, to: directory)
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
                try BookStorage.write(newBook, to: folder)
                guard flushSave() else { return }
                keepFolder = true
                open(newBook, in: folder)
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
        guard let directory, analysisTask == nil, !pending.isEmpty else { return }
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
        analysisTask?.cancel()
        analysisTask = nil
        analysisRun = nil
        analysisProgress = nil
        book = incoming
        rememberLocation(folder)
    }

    private func rememberLocation(_ folder: URL?) {
        saveTask?.cancel()
        saveTask = nil
        documentSession = UUID()
        directoryIdentity = folder.flatMap { BookStorage.identity(of: $0) }
        directory = folder
        if let folder {
            defaults.set(folder.path, forKey: "lastBook")
        } else {
            defaults.removeObject(forKey: "lastBook")
        }
    }

    private func validateLocation(_ folder: URL) throws {
        if let directoryIdentity, BookStorage.identity(of: folder) != directoryIdentity {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSURLErrorKey: folder])
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
            rememberLocation(url)
            flushSave()
            return
        }
        do {
            let restored = try BookStorage.read(from: url)
            guard flushSave() else { return }
            open(restored, in: url)
        } catch { problem = error.localizedDescription }
    }

    func closeBook() {
        guard flushSave() else { return }
        analysisTask?.cancel()
        analysisTask = nil
        analysisRun = nil
        analysisProgress = nil
        rememberLocation(nil)
    }

    func saveProject() {
        if needsSaveLocation {
            saveProjectAs()
        } else {
            flushSave()
        }
    }

    func saveProjectAs() {
        guard let directory else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.bookType]
        panel.nameFieldStringValue = safeFilename(book.title)
        let origin = documentLocation
        EditorFilePanels.present(panel) { [weak self] response in
            guard let self, self.documentLocation == origin, response == .OK, let destination = panel.url else { return }
            self.saveProjectCopy(from: directory, to: destination)
        }
    }

    private func saveProjectCopy(from directory: URL, to destination: URL) {
        guard !BookStorage.sameLocation(directory, destination) else {
            flushSave()
            return
        }
        do {
            try validateLocation(directory)
            try BookStorage.copy(book, from: directory, to: destination)
            // An in-flight classifier keeps reading the old asset directory.
            // Its results still update this document and are saved to the new location.
            rememberLocation(destination)
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
