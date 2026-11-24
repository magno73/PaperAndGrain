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
        let assets: [Asset]
        let pages: [Page]
        let cover: Cover?
    }

    struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    static func run(_ args: [String]) -> Int32 {
        do {
            let output = try execute(args)
            FileHandle.standardOutput.write(output + Data([10]))
            return 0
        } catch {
            let message = error is DecodingError ? String(describing: error) : error.localizedDescription
            let data = try? encode(["error": message])
            FileHandle.standardError.write((data ?? Data()) + Data([10]))
            return 1
        }
    }

    static func execute(_ args: [String]) throws -> Data {
        let usage = ["templates", "build SPEC.json OUTPUT.papergrain", "inspect PROJECT.papergrain"]
        switch (args.first, args.count) {
        case ("help", 1), ("--help", 1), (nil, 0):
            return try encode(["commands": usage])
        case ("templates", 1):
            struct Arrangement: Encodable { let id: String; let layout: String; let capacity: Int }
            struct Catalog: Encodable {
                let templates: [BookTemplate]
                let layouts: [PageLayout]
                let arrangements: [Arrangement]
            }
            return try encode(Catalog(templates: BookTemplate.allCases, layouts: PageLayout.allCases,
                                      arrangements: PageArrangement.allCases.map {
                Arrangement(id: $0.rawValue, layout: $0.layout.rawValue, capacity: $0.photoCapacity)
            }))
        case ("inspect", 2):
            return try encode(BookStorage.read(from: URL(fileURLWithPath: args[1])))
        case ("build", 3):
            let source = URL(fileURLWithPath: args[1]).standardizedFileURL
            let output = URL(fileURLWithPath: args[2]).standardizedFileURL
            let book = try build(specURL: source, output: output)
            return try encode(["project": output.path, "id": book.id.uuidString])
        default:
            throw Failure("Usage: PaperAndGrain cli " + usage.joined(separator: " | "))
        }
    }

    private static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    static func build(specURL: URL, output: URL) throws -> Book {
        let files = FileManager.default
        guard output.pathExtension.lowercased() == "papergrain" else {
            throw Failure("Output must end in .papergrain")
        }
        guard !files.fileExists(atPath: output.path) else { throw Failure("Output already exists: " + output.path) }
        let spec = try JSONDecoder().decode(Spec.self, from: Data(contentsOf: specURL))
        guard spec.version == 1, !spec.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !spec.pages.isEmpty else { throw Failure("Expected version 1, a title and at least one page") }
        let staging = output.deletingLastPathComponent().appendingPathComponent(".papergrain-" + UUID().uuidString)
        try files.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? files.removeItem(at: staging) }
        try files.createDirectory(at: staging.appendingPathComponent("assets"), withIntermediateDirectories: false)
        var book = Book(title: spec.title, format: spec.format ?? .square, template: spec.template)
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
