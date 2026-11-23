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
    private var saveTask: Task<Void, Never>?
    static let bookType = UTType(exportedAs: "local.paperandgrain.book", conformingTo: .package)

    func scheduleSave() {
        guard directory != nil else { return }
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(220))
            if !Task.isCancelled { flushSave() }
        }
    }

    func flushSave() {
        guard let directory else { return }
        do { try BookStorage.write(book, to: directory) } catch { problem = error.localizedDescription }
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
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let urls = panel.urls
        importImages(count: urls.count, title: language == "it" ? "Nuovo libro" : "New Book",
                     format: .square, language: language) { index, directory in
            try await LocalImages.importFile(urls[index], into: directory)
        }
    }

    func cancelImport() { importTask?.cancel() }

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
                keepFolder = true
                flushSave()
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
        guard let directory, analysisTask == nil else { return }
        let pending = book.photos.filter { $0.analysis == nil }
        guard !pending.isEmpty else { return }
        let documentID = book.id
        let runID = UUID()
        analysisRun = runID
        analysisProgress = (0, pending.count)
        analysisTask = Task {
            var failures = 0
            for (offset, photo) in pending.enumerated() {
                if Task.isCancelled || book.id != documentID { break }
                do {
                    let result = try await PhotoAnalyzer.analyze(
                        url: BookStorage.assetURL(filename: photo.filename, in: directory)
                    )
                    if Task.isCancelled || book.id != documentID { break }
                    if let index = book.photos.firstIndex(where: { $0.id == photo.id }) {
                        book.photos[index].analysis = result
                    }
                } catch {
                    if Task.isCancelled { break }
                    failures += 1
                }
                if analysisRun == runID { analysisProgress = (offset + 1, pending.count) }
            }
            guard analysisRun == runID else { return }
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

    private var analysisRun: UUID?

    private func open(_ incoming: Book, in folder: URL) {
        analysisTask?.cancel()
        analysisTask = nil
        analysisRun = nil
        analysisProgress = nil
        directory = folder
        book = incoming
        UserDefaults.standard.set(folder.path, forKey: "lastBook")
    }

    func reopenLastBook() {
        guard directory == nil,
              let path = UserDefaults.standard.string(forKey: "lastBook"),
              let restored = try? BookStorage.read(from: URL(fileURLWithPath: path)) else { return }
        open(restored, in: URL(fileURLWithPath: path))
    }

    func openProject() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Self.bookType]
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openProject(at: url)
    }

    func openProject(at url: URL) {
        do {
            let restored = try BookStorage.read(from: url)
            flushSave()
            open(restored, in: url)
        } catch { problem = error.localizedDescription }
    }

    func closeBook() {
        flushSave()
        analysisTask?.cancel()
        analysisTask = nil
        analysisRun = nil
        analysisProgress = nil
        directory = nil
        UserDefaults.standard.removeObject(forKey: "lastBook")
    }

    func saveProject() {
        guard let directory else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.bookType]
        panel.nameFieldStringValue = safeFilename(book.title)
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        guard destination.standardizedFileURL != directory.standardizedFileURL else {
            flushSave()
            return
        }
        do {
            let files = FileManager.default
            let staging = destination.deletingLastPathComponent()
                .appendingPathComponent(".\(UUID().uuidString).papergrain", isDirectory: true)
            try files.copyItem(at: directory, to: staging)
            defer { try? files.removeItem(at: staging) }
            try BookStorage.write(book, to: staging)
            if files.fileExists(atPath: destination.path) {
                _ = try files.replaceItemAt(destination, withItemAt: staging)
            } else {
                try files.moveItem(at: staging, to: destination)
            }
            // An in-flight classifier keeps reading the old asset directory.
            // Its results still update this document and are saved to the new location.
            self.directory = destination
            UserDefaults.standard.set(destination.path, forKey: "lastBook")
        } catch { problem = error.localizedDescription }
    }

    func loadDemo(language: String) {
        guard let image = Bundle.main.url(forResource: "Demo", withExtension: "png") else { return }
        importImages(count: 1, title: language == "it" ? "Sardegna, settembre" : "Sardinia in September",
                     format: .square, language: language) { _, directory in
            try await LocalImages.importFile(image, into: directory)
        }
    }

    func exportPDF() {
        guard let directory, !book.pages.isEmpty, !exporting else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = safeFilename(book.title)
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let snapshot = book
        exporting = true
        Task {
            defer { exporting = false }
            do {
                try await Task.detached(priority: .userInitiated) {
                    try BookPDF.write(snapshot, directory: directory, to: destination)
                }.value
            } catch { problem = error.localizedDescription }
        }
    }

    private func safeFilename(_ title: String) -> String {
        let clean = title.replacingOccurrences(of: "/", with: "–").replacingOccurrences(of: ":", with: "–")
        return clean.isEmpty ? "Paper and Grain" : clean
    }
}
