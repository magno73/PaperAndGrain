import Darwin
import Foundation

/// Explicit headless entry point; Finder and ordinary launches still use the SwiftUI app.
enum BookCLI {
    struct Spec: Decodable {
        struct Asset: Decodable {
            let id: String
            let path: String
        }
        struct Page: Decodable {
            let layout: PageLayout?
            let arrangement: PageArrangement?
            let photos: [String]?
            let heading: String?
            let text: String?
        }
        struct Cover: Decodable {
            let title: String?
            let frontPhoto: String?
            let backPhoto: String?
            let backText: String?
            let spineMM: Double?
        }
        let version: Int
        let title: String
        let format: BookFormat?
        let template: BookTemplate?
        let showPageNumbers: Bool?
        let assets: [Asset]
        let pages: [Page]
        let cover: Cover?
    }

    struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    static func run(_ args: [String]) async -> Int32 {
        do {
            let output = try await executeExtended(args)
            FileHandle.standardOutput.write(output + Data([10]))
            return 0
        } catch {
            let message = error is DecodingError ? String(describing: error) : error.localizedDescription
            let data = try? encode(["error": message])
            FileHandle.standardError.write((data ?? Data()) + Data([10]))
            return 1
        }
    }

    static func executeExtended(_ args: [String], currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath,
                                                                              isDirectory: true)) async throws -> Data {
        guard let command = args.first, command != "help", command != "--help" else {
            return try encode(["commands": usage])
        }
        let arguments = Array(args.dropFirst())
        switch command {
        case "patch":
            guard arguments.count == 3 else { throw Failure("Usage: patch SOURCE.papergrain PATCH.json OUTPUT.papergrain") }
            let output = url(arguments[2], relativeTo: currentDirectory)
            let book = try BookCLIEditing.patch(source: url(arguments[0], relativeTo: currentDirectory),
                                                patchURL: url(arguments[1], relativeTo: currentDirectory), output: output)
            return try encode(["project": output.path, "id": book.id.uuidString])
        case "auto-layout":
            guard arguments.count == 2 else { throw Failure("Usage: auto-layout SOURCE.papergrain OUTPUT.papergrain") }
            let output = url(arguments[1], relativeTo: currentDirectory)
            let book = try BookCLIEditing.derive(source: url(arguments[0], relativeTo: currentDirectory), output: output) { book, _ in
                guard !book.photos.isEmpty else { throw Failure("Automatic layout needs at least one photo") }
                book.autoLayout()
            }
            return try encode(["project": output.path, "id": book.id.uuidString])
        case "build":
            guard arguments.count == 2 else { throw Failure("Usage: build SPEC.json OUTPUT.papergrain") }
            return try execute([command] + arguments.map { url($0, relativeTo: currentDirectory).path })
        case "inspect":
            guard arguments.count == 1 else { throw Failure("Usage: inspect PROJECT.papergrain") }
            return try execute([command, url(arguments[0], relativeTo: currentDirectory).path])
        case "templates": return try execute(args)
        default:
            if let output = try await BookCLIPhotoIndex.run(command: command, arguments: arguments, currentDirectory: currentDirectory) {
                return output
            }
            if let output = try await BookCLIMedia.run(command: command, arguments: arguments, currentDirectory: currentDirectory) {
                return output
            }
            throw Failure("Unknown command: \(command). Run 'cli help' for usage.")
        }
    }

    private static var usage: [String] {
        ["templates", "build SPEC.json OUTPUT.papergrain", "inspect PROJECT.papergrain",
         "patch SOURCE.papergrain PATCH.json OUTPUT.papergrain", "auto-layout SOURCE.papergrain OUTPUT.papergrain"]
            + BookCLIPhotoIndex.usage + BookCLIMedia.usage
    }

    static func execute(_ args: [String]) throws -> Data {
        let usage = ["templates", "build SPEC.json OUTPUT.papergrain", "inspect PROJECT.papergrain"]
        switch (args.first, args.count) {
        case ("help", 1), ("--help", 1), (nil, 0):
            return try encode(["commands": usage])
        case ("templates", 1):
            struct Arrangement: Encodable { let id: String; let layout: String; let capacity: Int }
            struct Defaults: Encodable {
                let adjustments = PhotoAdjustments()
                let film = FilmSettings()
                let printSettings = PrintSettings()
                let crop = PhotoCrop()
            }
            struct Catalog: Encodable {
                let templates: [BookTemplate]
                let layouts: [PageLayout]
                let arrangements: [Arrangement]
                let defaults = Defaults()
            }
            return try encode(Catalog(templates: BookTemplate.allCases, layouts: PageLayout.allCases,
                                      arrangements: PageArrangement.allCases.map {
                Arrangement(id: $0.rawValue, layout: $0.layout.rawValue, capacity: $0.photoCapacity)
            }))
        case ("inspect", 2):
            return try BookCLIEditing.readManifest(source: URL(fileURLWithPath: args[1]))
        case ("build", 3):
            let source = URL(fileURLWithPath: args[1]).standardizedFileURL
            let output = URL(fileURLWithPath: args[2]).standardizedFileURL
            let book = try build(specURL: source, output: output)
            return try encode(["project": output.path, "id": book.id.uuidString])
        default:
            throw Failure("Usage: PaperAndGrain cli " + usage.joined(separator: " | "))
        }
    }

    /// A new package needs the .papergrain extension, an existing parent folder and a free name.
    static func checkNewPackage(_ output: URL) throws {
        guard output.pathExtension.lowercased() == "papergrain" else {
            throw Failure("Output must end in .papergrain: " + output.path)
        }
        let parent = output.deletingLastPathComponent().resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw Failure("Output parent directory does not exist: " + parent.path)
        }
        var entry = stat()
        guard lstat(output.path, &entry) != 0 else { throw Failure("Output already exists: " + output.path) }
    }

    /// Decodable ignores unknown keys; reject them so a misspelled field does not silently change the result.
    static func checkKeys(_ value: Any?, _ allowed: [String], at path: String) throws {
        guard let value, !(value is NSNull) else { return }
        guard let object = value as? [String: Any] else { throw Failure("Expected an object at \(path)") }
        if let key = object.keys.sorted().first(where: { !allowed.contains($0) }) {
            throw Failure("Unknown key \"\(key)\" at \(path). Valid keys: " + allowed.sorted().joined(separator: ", "))
        }
    }

    /// Checks every object of an array with `checkKeys`, naming elements as `path[index]`.
    static func checkEachKeys(_ value: Any?, _ allowed: [String], at path: String) throws {
        guard let value, !(value is NSNull) else { return }
        guard let array = value as? [Any] else { throw Failure("Expected an array at \(path)") }
        for (index, element) in array.enumerated() { try checkKeys(element, allowed, at: "\(path)[\(index)]") }
    }

    private static func checkSpecKeys(_ data: Data) throws {
        let root = try JSONSerialization.jsonObject(with: data)
        try checkKeys(root, ["version", "title", "format", "template", "showPageNumbers", "assets", "pages", "cover"],
                      at: "spec")
        guard let spec = root as? [String: Any] else { return }
        try checkKeys(spec["format"], ["widthMM", "heightMM"], at: "format")
        try checkEachKeys(spec["assets"], ["id", "path"], at: "assets")
        try checkEachKeys(spec["pages"], ["layout", "arrangement", "photos", "heading", "text"], at: "pages")
        try checkKeys(spec["cover"], ["title", "frontPhoto", "backPhoto", "backText", "spineMM"], at: "cover")
    }

    static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    static func url(_ path: String, relativeTo directory: URL) -> URL {
        URL(fileURLWithPath: path, relativeTo: directory).standardizedFileURL
    }

    static func build(specURL: URL, output: URL) throws -> Book {
        let files = FileManager.default
        try checkNewPackage(output)
        let specData = try Data(contentsOf: specURL)
        try checkSpecKeys(specData)
        let spec = try JSONDecoder().decode(Spec.self, from: specData)
        guard spec.version == 1, !spec.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !spec.pages.isEmpty else { throw Failure("Expected version 1, a title and at least one page") }
        let staging = output.deletingLastPathComponent().appendingPathComponent(".papergrain-" + UUID().uuidString)
        try files.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? files.removeItem(at: staging) }
        try files.createDirectory(at: staging.appendingPathComponent("assets"), withIntermediateDirectories: false)
        var book = Book(title: spec.title, format: spec.format ?? .square, template: spec.template,
                        showPageNumbers: spec.showPageNumbers)
        var ids: [String: UUID] = [:]
        for asset in spec.assets {
            guard !asset.id.isEmpty, ids[asset.id] == nil, !asset.path.isEmpty else {
                throw Failure("Expected unique, non-empty asset id and path: " + asset.id)
            }
            let url = URL(fileURLWithPath: asset.path, relativeTo: specURL.deletingLastPathComponent()).standardizedFileURL
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                throw Failure("Expected a local image file: " + asset.path)
            }
            let photo = try LocalImages.store(Data(contentsOf: url), preferredExtension: nil,
                                              name: url.lastPathComponent, sourceID: nil, date: nil, in: staging)
            book.photos.append(photo)
            ids[asset.id] = photo.id
        }
        func photoID(_ key: String) throws -> UUID {
            guard let id = ids[key] else { throw Failure("Unknown asset: " + key) }
            return id
        }
        for (index, page) in spec.pages.enumerated() {
            let layout = page.arrangement?.layout ?? page.layout ?? .gallery
            let photos = try (page.photos ?? []).map(photoID)
            let limit = page.arrangement?.photoCapacity ?? {
                switch layout {
                case .text: return 0
                case .fullPage, .fullSpread: return 1
                case .mixed, .gallery: return Int.max
                }
            }()
            let hasText = !(page.heading ?? "").isEmpty || !(page.text ?? "").isEmpty
            guard page.layout == nil || page.layout == layout, photos.count <= limit,
                  Set(photos).count == photos.count, !hasText || layout == .mixed || layout == .text else {
                throw Failure("Page \(index + 1): incompatible layout, text or photo slots")
            }
            book.pages.append(BookPage(layout: layout, photoIDs: photos, text: page.text ?? "",
                                       heading: page.heading, arrangement: page.arrangement))
        }
        if let cover = spec.cover {
            guard (cover.spineMM ?? 0) >= 0 else { throw Failure("Expected a nonnegative spineMM") }
            book.cover = try BookCover(title: cover.title ?? spec.title, frontPhotoID: cover.frontPhoto.map(photoID),
                                       backPhotoID: cover.backPhoto.map(photoID), spineMM: cover.spineMM ?? 0,
                                       backText: cover.backText)
        }
        try BookStorage.write(book, to: staging)
        // Atomic no-clobber publication even when another process creates the output concurrently.
        guard renamex_np(staging.path, output.path, UInt32(RENAME_EXCL)) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: output.path])
        }
        return book
    }
}
