import Foundation

enum BookStorage {
    private static let files = FileManager.default

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
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(book).write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
    }

    static func assetURL(filename: String, in directory: URL) -> URL {
        let assets = directory.appendingPathComponent("assets", isDirectory: true)
        return assets.appendingPathComponent(validFilename(filename) ? filename : "_invalid_asset")
    }

    static func createWorkspace() throws -> URL {
        let support = try files.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
        let draft = support.appendingPathComponent("PaperAndGrain/Drafts", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try files.createDirectory(at: draft.appendingPathComponent("assets", isDirectory: true),
                                  withIntermediateDirectories: true)
        return draft
    }

    private static func validFilename(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") &&
            !name.contains("\u{0000}") && !name.contains(":")
    }

    private static func validate(_ book: Book) throws {
        let ids = Set(book.photos.map(\.id))
        guard book.schemaVersion == 1,
              book.format.widthMM.isFinite, book.format.widthMM > 0,
              book.format.heightMM.isFinite, book.format.heightMM > 0,
              ids.count == book.photos.count,
              Set(book.pages.map(\.id)).count == book.pages.count,
              book.photos.allSatisfy({ validFilename($0.filename) }),
              book.pages.allSatisfy({ ids.isSuperset(of: $0.photoIDs) })
        else { throw CocoaError(.fileReadCorruptFile) }
    }
}
