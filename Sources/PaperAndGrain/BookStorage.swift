import Foundation
import CryptoKit

enum BookStorage {
    private static let files = FileManager.default

    struct DirectoryIdentity: Equatable {
        let volume: UInt64
        let inode: UInt64
    }

    static func identity(of directory: URL) -> DirectoryIdentity? {
        let resolved = directory.standardizedFileURL.resolvingSymlinksInPath()
        guard let attributes = try? files.attributesOfItem(atPath: resolved.path),
              let volume = attributes[.systemNumber] as? NSNumber,
              let inode = attributes[.systemFileNumber] as? NSNumber else { return nil }
        return DirectoryIdentity(volume: volume.uint64Value, inode: inode.uint64Value)
    }

    static func read(from directory: URL) throws -> Book {
        let manifest = directory.appendingPathComponent("manifest.json")
        let book = try JSONDecoder().decode(Book.self, from: Data(contentsOf: manifest))
        try validate(book)
        return book
    }

    static func write(_ book: Book, to directory: URL) throws {
        try validate(book)
        try files.createDirectory(at: directory.appendingPathComponent("assets", isDirectory: true),
                                  withIntermediateDirectories: true)
        try writeManifest(book, to: directory.appendingPathComponent("manifest.json"))
    }

    static func writeExisting(_ book: Book, to directory: URL) throws {
        try validate(book)
        let manifest = directory.appendingPathComponent("manifest.json")
        var isDirectory: ObjCBool = false
        guard files.fileExists(atPath: manifest.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSURLErrorKey: manifest])
        }
        try writeManifest(book, to: manifest)
    }

    private static func writeManifest(_ book: Book, to manifest: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(book).write(to: manifest, options: .atomic)
    }

    static func copy(_ book: Book, from source: URL, to destination: URL) throws {
        let from = source.standardizedFileURL.resolvingSymlinksInPath()
        let to = destination.standardizedFileURL.resolvingSymlinksInPath()
        guard !sameLocation(from, to),
              !from.pathComponents.starts(with: to.pathComponents),
              !to.pathComponents.starts(with: from.pathComponents) else {
            throw CocoaError(.fileWriteInvalidFileName, userInfo: [NSURLErrorKey: destination])
        }

        let destinationExists = files.fileExists(atPath: destination.path)
        let destinationIdentity = destinationExists ? identity(of: destination) : nil
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).papergrain", isDirectory: true)
        defer { try? files.removeItem(at: staging) }
        try files.copyItem(at: from, to: staging)
        guard try read(from: staging).id == book.id else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSURLErrorKey: source])
        }
        try writeExisting(book, to: staging)
        if destinationExists {
            if let destinationIdentity, identity(of: destination) != destinationIdentity {
                throw CocoaError(.fileWriteFileExists, userInfo: [NSURLErrorKey: destination])
            }
            _ = try files.replaceItemAt(destination, withItemAt: staging)
        } else {
            try files.moveItem(at: staging, to: destination)
        }
    }

    static func sameLocation(_ first: URL, _ second: URL) -> Bool {
        if first.standardizedFileURL.resolvingSymlinksInPath().path == second.standardizedFileURL.resolvingSymlinksInPath().path {
            return true
        }
        guard let firstIdentity = identity(of: first) else { return false }
        return firstIdentity == identity(of: second)
    }

    static func assetURL(filename: String, in directory: URL) -> URL {
        let assets = directory.appendingPathComponent("assets", isDirectory: true)
        return assets.appendingPathComponent(validFilename(filename) ? filename : "_invalid_asset")
    }

    static func lutURL(filename: String, in directory: URL) -> URL {
        directory.appendingPathComponent("looks", isDirectory: true)
            .appendingPathComponent(validFilename(filename) ? filename : "_invalid_look")
    }

    static func importLUT(_ source: URL, in directory: URL) throws -> String {
        let suffix = source.pathExtension.lowercased()
        guard ["cube", "png"].contains(suffix) else { throw CocoaError(.fileReadUnknown) }
        let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard (1...50_000_000).contains(size) else { throw CocoaError(.fileReadTooLarge) }
        try FilmRenderer.validateLUT(at: source)
        return try installLUT(Data(contentsOf: source), named: source.lastPathComponent, in: directory)
    }

    static func importBuiltInLUT(_ look: FujifilmFilmLook, resources: URL, in directory: URL) throws -> String {
        let data = try Data(contentsOf: look.url(in: resources))
        return try installLUT(data, named: look.filename, in: directory, matching: look)
    }

    private static func installLUT(_ data: Data, named name: String, in directory: URL,
                                   matching builtIn: FujifilmFilmLook? = nil) throws -> String {
        let hash = SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
        let suffix = (name as NSString).pathExtension.lowercased()
        let title = (name as NSString).deletingPathExtension.replacingOccurrences(of: ":", with: "_")
        let filename = "\(title.prefix(72))-\(hash).\(suffix)"
        if let builtIn, FujifilmFilmLook.importedLook(filename: filename) != builtIn {
            throw CocoaError(.fileReadCorruptFile)
        }
        let destination = lutURL(filename: filename, in: directory)
        try files.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !files.fileExists(atPath: destination.path) {
            try data.write(to: destination, options: [.atomic])
        }
        return filename
    }

    static func createWorkspace() throws -> URL {
        let draft = try draftsDirectory(create: true).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try files.createDirectory(at: draft.appendingPathComponent("assets", isDirectory: true),
                                  withIntermediateDirectories: true)
        return draft
    }

    static func isManagedDraft(_ directory: URL, in draftsRoot: URL? = nil) -> Bool {
        guard let draftsRoot = draftsRoot ?? (try? draftsDirectory(create: false)) else { return false }
        let resolved = directory.standardizedFileURL.resolvingSymlinksInPath()
        return UUID(uuidString: resolved.lastPathComponent) != nil &&
            sameLocation(resolved.deletingLastPathComponent(), draftsRoot)
    }

    private static func draftsDirectory(create: Bool) throws -> URL {
        let support = try files.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: create)
        // Redesign builds keep their own drafts so the main app's books are never touched.
        let folder = Bundle.main.bundleIdentifier?.hasSuffix(".redesign") == true ? "PaperAndGrain-Redesign" : "PaperAndGrain"
        return support.appendingPathComponent("\(folder)/Drafts", isDirectory: true)
    }

    private static func validFilename(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") &&
            !name.contains("\u{0000}") && !name.contains(":")
    }

    private static func validate(_ book: Book) throws {
        let ids = Set(book.photos.map(\.id))
        let looks = book.photos.compactMap(\.film) + [book.film].compactMap { $0 }
        let coverIDs = [book.cover?.frontPhotoID, book.cover?.backPhotoID].compactMap { $0 }
        guard book.schemaVersion == 1,
              book.format.widthMM.isFinite, book.format.widthMM > 0,
              book.format.heightMM.isFinite, book.format.heightMM > 0,
              ids.count == book.photos.count,
              Set(book.pages.map(\.id)).count == book.pages.count,
              book.photos.allSatisfy({ validFilename($0.filename) }),
              book.pages.allSatisfy({ ids.isSuperset(of: $0.photoIDs) }),
              looks.allSatisfy({ $0.lutFilename.map(validFilename) ?? true }),
              ids.isSuperset(of: coverIDs)
        else { throw CocoaError(.fileReadCorruptFile) }
    }
}
