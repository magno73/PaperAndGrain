import CryptoKit
import Darwin
import Foundation

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
        defer { removeStaged(staging) }
        try files.copyItem(at: from, to: staging)
        addOwnerWrite(staging)
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

    /// Copies keep the source permissions; a staged copy of a read-only package must become writable
    /// before its manifest is rewritten or the copy is removed. Symbolic links are left untouched.
    @discardableResult
    static func addOwnerWrite(_ root: URL) -> Bool {
        var succeeded = true
        func visit(_ path: String) {
            var entry = stat()
            guard lstat(path, &entry) == 0 else { succeeded = false; return }
            let type = entry.st_mode & S_IFMT
            guard type == S_IFDIR || type == S_IFREG else { return }
            let mode = entry.st_mode & 0o7777
            let wanted = mode | S_IWUSR | (type == S_IFDIR ? S_IRUSR | S_IXUSR : 0)
            if wanted != mode, chmod(path, wanted) != 0 { succeeded = false }
            if type == S_IFDIR, let children = try? files.contentsOfDirectory(atPath: path) {
                for child in children { visit((path as NSString).appendingPathComponent(child)) }
            }
        }
        visit(root.path)
        return succeeded
    }

    /// Removes a staged package, making it writable first so a read-only copy does not linger.
    static func removeStaged(_ url: URL) {
        guard files.fileExists(atPath: url.path) else { return }
        addOwnerWrite(url)
        try? files.removeItem(at: url)
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
        guard ["cube", "png"].contains(suffix) else {
            throw ValidationError("LUT file must be a 3D .cube or a Hald CLUT .png: " + source.lastPathComponent)
        }
        let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard (1...50_000_000).contains(size) else {
            throw ValidationError("LUT file must be 1 byte to 50 MB (found \(size) bytes): " + source.lastPathComponent)
        }
        try FilmRenderer.validateLUT(at: source)
        return try installLUT(Data(contentsOf: source), named: source.lastPathComponent, in: directory)
    }

    static func importBuiltInLUT(_ look: BundledFilmLook, resources: URL, in directory: URL) throws -> String {
        let data = try Data(contentsOf: look.url(in: resources))
        return try installLUT(data, named: look.filename, in: directory, matching: look)
    }

    private static func installLUT(_ data: Data, named name: String, in directory: URL,
                                   matching builtIn: BundledFilmLook? = nil) throws -> String {
        let hash = SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
        let suffix = (name as NSString).pathExtension.lowercased()
        let title = (name as NSString).deletingPathExtension.replacingOccurrences(of: ":", with: "_")
        let filename = "\(title.prefix(72))-\(hash).\(suffix)"
        if let builtIn, BundledFilmLook.importedLook(filename: filename) != builtIn {
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

    static func draftsDirectory(create: Bool) throws -> URL {
        let support = try files.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: create)
        return support.appendingPathComponent("PaperAndGrain/Drafts", isDirectory: true)
    }

    private static func validFilename(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") &&
            !name.contains("\u{0000}") && !name.contains(":")
    }

    /// A manifest check that failed, named so that an agent or the author can find the field.
    struct ValidationError: LocalizedError, Equatable {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    static let pixelDimensionRange = 1...1_000_000

    /// Checks the references and values every reader relies on. Each failure names the field, so a damaged
    /// package can be repaired by hand. Layer order entries that name unknown objects are ignored, not errors.
    private static func validate(_ book: Book) throws {
        guard book.schemaVersion == 1 else {
            throw ValidationError("Unsupported schemaVersion \(book.schemaVersion); expected 1")
        }
        for (field, value) in [("widthMM", book.format.widthMM), ("heightMM", book.format.heightMM)]
        where !(value.isFinite && value > 0) {
            throw ValidationError("format.\(field) must be greater than 0 (found \(value))")
        }
        var ids: Set<UUID> = []
        for (index, photo) in book.photos.enumerated() {
            let name = "Photo \(photo.id.uuidString) (photos[\(index)])"
            guard ids.insert(photo.id).inserted else { throw ValidationError("\(name) has a duplicate id") }
            guard validFilename(photo.filename) else {
                throw ValidationError("\(name) has an invalid filename \"\(photo.filename)\"")
            }
            for (field, value) in [("pixelWidth", photo.pixelWidth), ("pixelHeight", photo.pixelHeight)]
            where !pixelDimensionRange.contains(value) {
                throw ValidationError("\(name) has \(field) \(value); expected 1 to 1000000")
            }
            if let lut = photo.film?.lutFilename, !validFilename(lut) {
                throw ValidationError("\(name) has an invalid film.lutFilename \"\(lut)\"")
            }
        }
        if let lut = book.film?.lutFilename, !validFilename(lut) {
            throw ValidationError("film.lutFilename \"\(lut)\" is not a valid file name")
        }
        var pageIDs: Set<UUID> = []
        for (index, page) in book.pages.enumerated() {
            let name = "Page \(index + 1) (pages[\(index)])"
            guard pageIDs.insert(page.id).inserted else {
                throw ValidationError("\(name) has a duplicate id \(page.id.uuidString)")
            }
            if let unknown = page.photoIDs.first(where: { !ids.contains($0) }) {
                throw ValidationError("\(name) references unknown photo \(unknown.uuidString) in photoIDs")
            }
        }
        for (field, id) in [("frontPhotoID", book.cover?.frontPhotoID), ("backPhotoID", book.cover?.backPhotoID)] {
            if let id, !ids.contains(id) {
                throw ValidationError("cover.\(field) references unknown photo \(id.uuidString)")
            }
        }
    }
}
