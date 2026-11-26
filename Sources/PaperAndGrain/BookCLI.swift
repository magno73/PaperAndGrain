import Darwin
import Foundation

/// Explicit headless entry point; Finder and ordinary launches still use the SwiftUI app.
enum BookCLI {
    /// The image readers throw the app's localized error; the CLI reports it in English with the path.
    static func isUnreadableImage(_ error: Error) -> Bool {
        if case PhotoImportError.unreadableImage = error { return true }
        if case AppError.imageUnavailable = error { return true }
        return false
    }

    struct Spec: Decodable {
        struct Asset: Decodable {
            let id: String
            let path: String
            /// `BookPhoto.caption`: printed with the photo on every page.
            let caption: String?
        }
        /// The model's text box, with an optional id: a new UUID is assigned when it is absent.
        struct TextBox: Decodable {
            let id: UUID?
            let text: String?
            let frame: PageRect
            let typography: EditorialTextStyle?
            let usesFullWidth: Bool?
            let backgroundColor: UInt32?
            let hidesBackground: Bool?
            let borderColor: UInt32?
            let borderWidth: Double?
        }
        struct Page: Decodable {
            let layout: PageLayout?
            let arrangement: PageArrangement?
            let photos: [String]?
            let heading: String?
            let text: String?
            let typography: EditorialTypography?
            let textBoxes: [TextBox]?
            /// `story`, `photo:<asset id>` or `box:<text box UUID>`, back to front.
            let layerOrder: [String]?
            /// The manifest's `PhotoPlacement` (frame, crop, captionPosition), keyed by asset id.
            let photoPlacements: [String: PhotoPlacement]?
            /// The manifest's `PageMap`, for a page with arrangement `map` or `mapAboveText`.
            let map: PageMap?
        }
        /// A print-service product from `print-profiles`: it sets the print settings, and the format when
        /// the spec gives none.
        struct PrintService: Decodable {
            let profile: String
            let size: String?
            let paper: String?
        }
        struct Cover: Decodable {
            let title: String?
            let frontPhoto: String?
            let backPhoto: String?
            let backText: String?
            let spineMM: Double?
            let typography: EditorialTypography?
        }
        let version: Int
        let title: String
        let format: BookFormat?
        let template: BookTemplate?
        let showPageNumbers: Bool?
        let typography: EditorialTypography?
        let assets: [Asset]
        let pages: [Page]
        let cover: Cover?
        let printService: PrintService?
        /// `Book.ignoredSpellings`: words the spelling check leaves alone.
        let ignoredSpellings: [String]?
    }

    struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    /// Italian template names for `templates`. The CLI runs without the compiled String Catalog
    /// (`swift build` puts no resources next to the binary), so it keeps its own copy of these names;
    /// `L10nTests` checks that they match the catalog.
    static let italianTemplateNames: [BookTemplate: String] = [
        .diary: "Diario", .atlas: "Atlante", .gallery: "Galleria", .essential: "Essenziale",
        .swissGrid: "Griglia svizzera", .berlinQuarter: "Quaderno berlinese",
        .japaneseInterval: "Intervallo giapponese", .monograph: "Monografia", .postcard: "Cartolina",
        .nocturne: "Notturno", .slide: "Diapositiva", .roadLog: "Diario di bordo",
    ]

    static func run(_ args: [String]) async -> Int32 {
        // Messages and errors stay in English whatever Settings › Language says.
        L10n.useEnglishOnly()
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
            var warnings: [String] = []
            let book = try BookCLIEditing.patch(source: url(arguments[0], relativeTo: currentDirectory),
                                                patchURL: url(arguments[1], relativeTo: currentDirectory), output: output,
                                                warnings: &warnings)
            struct PatchResult: Encodable { let project: String; let id: UUID; let warnings: [String] }
            return try encode(PatchResult(project: output.path, id: book.id, warnings: warnings))
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
        case "templates":
            guard arguments.isEmpty else { throw Failure("Usage: templates") }
            return try execute(args)
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

    /// The three commands that need no options; `executeExtended` resolves paths and handles help.
    static func execute(_ args: [String]) throws -> Data {
        switch (args.first, args.count) {
        case ("templates", 1):
            struct Arrangement: Encodable { let id: String; let layout: String; let capacity: Int }
            struct Defaults: Encodable {
                let adjustments = PhotoAdjustments()
                let film = FilmSettings()
                let printSettings = PrintSettings()
                let crop = PhotoCrop()
            }
            struct Template: Encodable {
                struct Name: Encodable { let it: String; let en: String }
                let id: String
                let name: Name
                let family: String
            }
            struct Catalog: Encodable {
                let templates: [Template]
                let layouts: [PageLayout]
                let arrangements: [Arrangement]
                let defaults = Defaults()
            }
            let templates = BookTemplate.allCases.map {
                Template(id: $0.rawValue, name: .init(it: italianTemplateNames[$0] ?? $0.englishName, en: $0.englishName),
                         family: String(describing: $0.family))
            }
            return try encode(Catalog(templates: templates, layouts: PageLayout.allCases,
                                      arrangements: PageArrangement.allCases.map {
                Arrangement(id: $0.rawValue, layout: $0.layout.rawValue, capacity: $0.photoCapacity)
            }))
        case ("inspect", 2):
            return try BookCLIEditing.readManifest(source: URL(fileURLWithPath: args[1]))
        case ("build", 3):
            let source = URL(fileURLWithPath: args[1]).standardizedFileURL
            let output = URL(fileURLWithPath: args[2]).standardizedFileURL
            var photos: [String: UUID] = [:]
            let book = try build(specURL: source, output: output, photos: &photos)
            struct BuildResult: Encodable { let project: String; let id: UUID; let photos: [String: UUID] }
            return try encode(BuildResult(project: output.path, id: book.id, photos: photos))
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

    static let textStyleKeys = ["fontName", "pointSize", "alignment", "color", "lineSpacing"]
    static let frameKeys = ["x", "y", "width", "height"]

    /// `caption` is a book style only: pages and the cover have no caption style of their own.
    private static func checkTypographyKeys(_ value: Any?, at path: String, caption: Bool = false) throws {
        try checkKeys(value, caption ? ["title", "body", "caption"] : ["title", "body"], at: path)
        let typography = value as? [String: Any]
        try checkKeys(typography?["caption"], textStyleKeys, at: path + ".caption")
        try checkKeys(typography?["title"], textStyleKeys, at: path + ".title")
        try checkKeys(typography?["body"], textStyleKeys, at: path + ".body")
    }

    /// The product and size a spec names, checked against the catalog and the spec's format.
    private static func printService(_ service: Spec.PrintService, format: BookFormat?) throws
        -> (PrintProfile, PrintProfile.Size) {
        let id = service.profile == "pixart" ? PrintProfileCatalog.pixartID : service.profile
        guard let profile = PrintProfileCatalog.bundled.profile(id) else {
            throw Failure("Unknown printService.profile \(service.profile). Use an id from print-profiles")
        }
        if let paper = service.paper, profile.papers?.contains(where: { $0.id == paper }) != true {
            throw Failure("Unknown printService.paper \(paper) for \(profile.id). Papers: "
                          + (profile.papers ?? []).map(\.id).joined(separator: ", "))
        }
        let size: PrintProfile.Size?
        if let id = service.size {
            guard let chosen = profile.size(id) else {
                throw Failure("Unknown printService.size \(id) for \(profile.id). Sizes: "
                              + profile.sizes.map(\.id).joined(separator: ", "))
            }
            size = chosen
        } else {
            size = format.flatMap(profile.size(matching:)) ?? (profile.sizes.count == 1 ? profile.sizes.first : nil)
        }
        guard let size else {
            throw Failure("printService.size is required for \(profile.id). Sizes: "
                          + profile.sizes.map(\.id).joined(separator: ", "))
        }
        if let format, !size.matches(format) {
            throw Failure("format \(format.widthMM) × \(format.heightMM) mm does not match printService.size \(size.id) "
                          + "(\(size.format.widthMM) × \(size.format.heightMM) mm); leave format out to use the size")
        }
        return (profile, size)
    }

    private static func checkSpecKeys(_ data: Data) throws {
        let root = try JSONSerialization.jsonObject(with: data)
        try checkKeys(root, ["version", "title", "format", "template", "showPageNumbers", "typography", "assets", "pages",
                             "cover", "printService", "ignoredSpellings"], at: "spec")
        guard let spec = root as? [String: Any] else { return }
        try checkKeys(spec["format"], ["widthMM", "heightMM"], at: "format")
        try checkKeys(spec["printService"], ["profile", "size", "paper"], at: "printService")
        try checkTypographyKeys(spec["typography"], at: "typography", caption: true)
        try checkEachKeys(spec["assets"], ["id", "path", "caption"], at: "assets")
        try checkEachKeys(spec["pages"], ["layout", "arrangement", "photos", "heading", "text", "typography", "textBoxes",
                                          "layerOrder", "photoPlacements", "map"], at: "pages")
        for (index, page) in (spec["pages"] as? [[String: Any]] ?? []).enumerated() {
            try checkTypographyKeys(page["typography"], at: "pages[\(index)].typography")
            try checkKeys(page["map"], ["photos", "showsRoute", "showsLabels", "showsBorders", "zoom", "centerOffset", "labels"],
                          at: "pages[\(index)].map")
            let map = page["map"] as? [String: Any]
            try checkKeys(map?["centerOffset"], ["x", "y"], at: "pages[\(index)].map.centerOffset")
            try checkEachKeys(map?["labels"], ["key", "name", "hidden"], at: "pages[\(index)].map.labels")
            if let placements = page["photoPlacements"], !(placements is NSNull) {
                guard let map = placements as? [String: Any] else {
                    throw Failure("Expected an object at pages[\(index)].photoPlacements")
                }
                for (asset, placement) in map {
                    let path = "pages[\(index)].photoPlacements.\(asset)"
                    try checkKeys(placement, ["frame", "crop", "captionPosition"], at: path)
                    try checkKeys((placement as? [String: Any])?["frame"], frameKeys, at: path + ".frame")
                    try checkKeys((placement as? [String: Any])?["crop"], ["x", "y", "zoom"], at: path + ".crop")
                }
            }
            let path = "pages[\(index)].textBoxes"
            try checkEachKeys(page["textBoxes"], ["id", "text", "frame", "typography", "usesFullWidth", "backgroundColor",
                                                  "hidesBackground", "borderColor", "borderWidth"], at: path)
            for (offset, box) in (page["textBoxes"] as? [[String: Any]] ?? []).enumerated() {
                try checkKeys(box["frame"], frameKeys, at: "\(path)[\(offset)].frame")
                try checkKeys(box["typography"], textStyleKeys, at: "\(path)[\(offset)].typography")
            }
        }
        try checkKeys(spec["cover"], ["title", "frontPhoto", "backPhoto", "backText", "spineMM", "typography"], at: "cover")
        try checkTypographyKeys((spec["cover"] as? [String: Any])?["typography"], at: "cover.typography")
    }

    static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    static func url(_ path: String, relativeTo directory: URL) -> URL {
        URL(fileURLWithPath: path, relativeTo: directory).standardizedFileURL
    }

    static func build(specURL: URL, output: URL) throws -> Book {
        var photos: [String: UUID] = [:]
        return try build(specURL: specURL, output: output, photos: &photos)
    }

    /// Builds the book; `photos` maps each spec asset id to the UUID of its photo, for later patches.
    static func build(specURL: URL, output: URL, photos: inout [String: UUID]) throws -> Book {
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
        if let service = spec.printService {
            let (profile, size) = try printService(service, format: spec.format)
            var settings = PrintSettings()
            settings.choose(profile, size: size, paperID: service.paper)
            book.printSettings = settings
            book.format = size.format
        }
        var ids: [String: UUID] = [:]
        for asset in spec.assets {
            guard !asset.id.isEmpty, ids[asset.id] == nil, !asset.path.isEmpty else {
                throw Failure("Expected unique, non-empty asset id and path: " + asset.id)
            }
            let url = URL(fileURLWithPath: asset.path, relativeTo: specURL.deletingLastPathComponent())
                .standardizedFileURL.resolvingSymlinksInPath()
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                throw Failure("Expected a local image file for asset \"\(asset.id)\": " + asset.path)
            }
            let photo: BookPhoto
            do {
                photo = try LocalImages.store(Data(contentsOf: url), preferredExtension: nil,
                                              name: URL(fileURLWithPath: asset.path).lastPathComponent, sourceID: nil,
                                              date: nil, in: staging)
            } catch where BookCLI.isUnreadableImage(error) {
                throw Failure("Image unavailable or unreadable for asset \"\(asset.id)\": " + asset.path)
            }
            var captioned = photo
            captioned.caption = asset.caption?.isEmpty == false ? asset.caption : nil
            book.photos.append(captioned)
            ids[asset.id] = photo.id
        }
        func photoID(_ key: String) throws -> UUID {
            guard let id = ids[key] else { throw Failure("Unknown asset: " + key) }
            return id
        }
        photos = ids
        book.typography = spec.typography
        book.ignoredSpellings = spec.ignoredSpellings?.isEmpty == false ? spec.ignoredSpellings : nil
        for (index, page) in spec.pages.enumerated() {
            let boxes = page.textBoxes?.map { box in
                PageTextBox(id: box.id ?? UUID(), text: box.text ?? "", frame: box.frame, typography: box.typography,
                            usesFullWidth: box.usesFullWidth, backgroundColor: box.backgroundColor,
                            hidesBackground: box.hidesBackground, borderColor: box.borderColor, borderWidth: box.borderWidth)
            }
            var built = BookPage(layout: page.layout ?? page.arrangement?.layout ?? .gallery,
                                 photoIDs: try (page.photos ?? []).map(photoID), text: page.text ?? "",
                                 heading: page.heading, textBoxes: boxes, arrangement: page.arrangement,
                                 typography: page.typography)
            if let placements = page.photoPlacements, !placements.isEmpty {
                var resolved: [UUID: PhotoPlacement] = [:]
                for (asset, placement) in placements {
                    guard let id = ids[asset], built.photoIDs.contains(id) else {
                        throw Failure("Page \(index + 1) (pages[\(index)]) photoPlacements key \"\(asset)\" "
                            + "does not name an asset placed on this page")
                    }
                    resolved[id] = placement
                }
                built.photoPlacements = resolved
            }
            built.map = page.map == PageMap() ? nil : page.map
            built.layerOrder = try page.layerOrder.map { entries in
                try entries.map { entry in try layer(entry, on: built, photoID: { ids[$0] }, at: index) }
            }
            // A new book has no reason to store what it would not show: build treats warnings as errors.
            if let problem = try BookCLIEditing.checkPage(built, at: index).first { throw Failure(problem) }
            book.pages.append(built)
        }
        if let cover = spec.cover {
            guard (cover.spineMM ?? 0) >= 0 else { throw Failure("Expected a nonnegative spineMM") }
            book.cover = try BookCover(title: cover.title ?? spec.title, frontPhotoID: cover.frontPhoto.map(photoID),
                                       backPhotoID: cover.backPhoto.map(photoID), spineMM: cover.spineMM ?? 0,
                                       backText: cover.backText, typography: cover.typography)
        }
        try BookCLIEditing.checkTextStyles(book)
        try BookCLIEditing.validatePackage(book, in: staging)
        // A book with a map page is marked for this version, so an older app does not rewrite it.
        if Workspace.writerVersion(for: book) > 1 { book.writerVersion = Workspace.writerVersion(for: book) }
        try BookStorage.write(book, to: staging)
        // Atomic no-clobber publication even when another process creates the output concurrently.
        guard renamex_np(staging.path, output.path, UInt32(RENAME_EXCL)) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: output.path])
        }
        return book
    }

    /// Resolves a spec layer: photos are named by asset id, text boxes by UUID, both on the same page.
    private static func layer(_ entry: String, on page: BookPage, photoID: (String) -> UUID?, at index: Int) throws -> PageLayer {
        let name = "Page \(index + 1) (pages[\(index)]) layerOrder entry \"\(entry)\""
        if entry == "story" { return .story }
        if entry.hasPrefix("photo:") {
            guard let id = photoID(String(entry.dropFirst(6))), page.photoIDs.contains(id) else {
                throw Failure("\(name) does not name an asset placed on this page")
            }
            return .photo(id)
        }
        if entry.hasPrefix("box:") {
            guard let id = UUID(uuidString: String(entry.dropFirst(4))),
                  page.textBoxes?.contains(where: { $0.id == id }) == true else {
                throw Failure("\(name) does not name a text box id on this page")
            }
            return .textBox(id)
        }
        throw Failure("\(name) must be \"story\", \"photo:<asset id>\" or \"box:<text box UUID>\"")
    }
}
