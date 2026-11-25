import CoreGraphics
import Darwin
import Foundation
import ImageIO
import Photos
import UniformTypeIdentifiers

enum BookCLIMedia {
    static let usage = [
        "albums [--request-access]",
        "album-assets ALBUM_ID [--request-access]",
        "album-preview ALBUM_ID --asset ID --output FILE.png [--request-access]",
        "import-photos SOURCE.papergrain --spec SPEC.json --output OUTPUT.papergrain [--request-access]",
        "photo-preview SOURCE.papergrain --photo UUID --output FILE.png [--max-pixels N] [--original]",
        "auto-enhance SOURCE.papergrain --photo UUID --output OUTPUT.papergrain",
        "film-looks",
        "import-lut SOURCE.papergrain (--file PATH | --fujifilm LOOK_ID) [--photo UUID] --output OUTPUT.papergrain",
        "export-pdf SOURCE.papergrain --profile proof|print|pixart --output PATH [--spine-mm MM]",
    ]

    static func run(command: String, arguments: [String], currentDirectory: URL) async throws -> Data? {
        let options: Options
        switch command {
        case "albums":
            options = try Options(arguments, flags: ["--request-access"])
            try await requirePhotosAccess(request: options.has("--request-access"))
            return try encode(PhotoLibrary.albums().map(AlbumResult.init))
        case "album-assets":
            options = try Options(arguments, positional: true, flags: ["--request-access"])
            try await requirePhotosAccess(request: options.has("--request-access"))
            let album = try findAlbum(options.subject())
            return try encode(PhotoLibrary.photos(in: album).map(AssetResult.init))
        case "album-preview":
            options = try Options(arguments, positional: true, values: ["--asset", "--output"],
                                  flags: ["--request-access"])
            let output = try options.url("--output", relativeTo: currentDirectory)
            let asset = try options.required("--asset")
            try validateOutput(output, extension: "png")
            try await requirePhotosAccess(request: options.has("--request-access"))
            let album = try findAlbum(options.subject())
            let photo = try selectAssets([asset], from: album)[0]
            guard let thumbnail = await PhotoLibrary.thumbnail(photo),
                  let image = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else { throw PhotoImportError.unreadableImage }
            return try writePNG(image, to: output)
        case "import-photos":
            options = try Options(arguments, positional: true, values: ["--spec", "--output"],
                                  flags: ["--request-access"])
            return try await importPhotos(options, currentDirectory: currentDirectory)
        case "photo-preview":
            options = try Options(arguments, positional: true, values: ["--photo", "--output", "--max-pixels"],
                                  flags: ["--original"])
            return try preview(options, currentDirectory: currentDirectory)
        case "auto-enhance":
            options = try Options(arguments, positional: true, values: ["--photo", "--output"])
            return try enhance(options, currentDirectory: currentDirectory)
        case "film-looks":
            _ = try Options(arguments)
            return try encode(FilmCatalog(presets: FilmPreset.allCases, fujifilm: FujifilmFilmLook.all.map {
                .init(id: $0.id, name: $0.name, input: $0.input == .linear ? "linear" : "provia")
            }))
        case "import-lut":
            options = try Options(arguments, positional: true, values: ["--file", "--fujifilm", "--photo", "--output"])
            return try importLUT(options, currentDirectory: currentDirectory)
        case "export-pdf":
            options = try Options(arguments, positional: true, values: ["--profile", "--output", "--spine-mm"])
            return try exportPDF(options, currentDirectory: currentDirectory)
        default:
            return nil
        }
    }

    private struct AlbumResult: Encodable {
        let id: String
        let title: String
        let count: Int

        init(_ album: Album) {
            id = album.id
            title = album.title
            count = album.count
        }
    }

    private struct AssetResult: Encodable {
        let id: String
        let capturedAt: Date?
        let width: Int
        let height: Int

        init(_ photo: LibraryPhoto) {
            id = photo.id
            capturedAt = photo.capturedAt
            width = photo.width
            height = photo.height
        }
    }

    private struct ImportSpec: Decodable {
        struct Selection: Decodable {
            let albumID: String
            let assetIDs: [String]
        }

        let version: Int
        let files: [String]?
        let photos: Selection?
    }

    private struct ProjectResult: Encodable {
        let project: String
        let id: UUID
        let photos: [BookPhoto]?
        let lutFilename: String?

        init(_ book: Book, output: URL, photos: [BookPhoto]? = nil, lutFilename: String? = nil) {
            project = output.path
            id = book.id
            self.photos = photos
            self.lutFilename = lutFilename
        }
    }

    private struct FilmCatalog: Encodable {
        struct Look: Encodable {
            let id: String
            let name: String
            let input: String
        }

        let presets: [FilmPreset]
        let fujifilm: [Look]
    }

    private struct ImageResult: Encodable {
        let output: String
        let width: Int
        let height: Int
    }

    private struct PDFResult: Encodable {
        let output: String
        let profile: PDFProfile
        let warnings: [String]
    }

    private enum PDFProfile: String, Encodable {
        case proof, print, pixart
    }

    private static func requirePhotosAccess(request: Bool) async throws {
        guard Bundle.main.bundleURL.pathExtension == "app",
              let description = Bundle.main.object(forInfoDictionaryKey: "NSPhotoLibraryUsageDescription") as? String,
              !description.isEmpty else {
            throw BookCLI.Failure("Use the executable inside the signed Paper & Grain.app bundle for Apple Photos")
        }
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined, request {
            status = await PhotoLibrary.authorize()
        }
        guard status == .authorized || status == .limited else {
            if status == .notDetermined {
                throw BookCLI.Failure("Apple Photos access is undetermined. Use --request-access to request it")
            }
            throw BookCLI.Failure("Apple Photos access is denied or restricted")
        }
    }

    private static func findAlbum(_ id: String) throws -> Album {
        guard let album = PhotoLibrary.albums().first(where: { $0.id == id }) else {
            throw BookCLI.Failure("Album unavailable: " + id)
        }
        return album
    }

    private static func selectAssets(_ ids: [String], from album: Album) throws -> [LibraryPhoto] {
        guard !ids.isEmpty, Set(ids).count == ids.count else {
            throw BookCLI.Failure("Specify a nonempty list of distinct Apple Photos asset IDs")
        }
        let photos = Dictionary(uniqueKeysWithValues: PhotoLibrary.photos(in: album).map { ($0.id, $0) })
        return try ids.map { id in
            guard let photo = photos[id] else {
                throw BookCLI.Failure("Asset unavailable in the selected album: " + id)
            }
            return photo
        }
    }

    private static func importPhotos(_ options: Options, currentDirectory: URL) async throws -> Data {
        let source = try options.source(relativeTo: currentDirectory)
        let specURL = try options.url("--spec", relativeTo: currentDirectory)
        let output = try options.url("--output", relativeTo: currentDirectory)
        try validateOutput(output, extension: "papergrain", outside: source)
        _ = try BookCLIEditing.read(source: source)
        let specData = try Data(contentsOf: specURL)
        let specObject = try JSONSerialization.jsonObject(with: specData)
        try BookCLI.checkKeys(specObject, ["version", "files", "photos"], at: "import spec")
        try BookCLI.checkKeys((specObject as? [String: Any])?["photos"], ["albumID", "assetIDs"], at: "photos")
        let spec = try JSONDecoder().decode(ImportSpec.self, from: specData)
        guard spec.version == 1, spec.files != nil || spec.photos != nil,
              (spec.files?.allSatisfy { !$0.isEmpty } ?? true),
              spec.files?.isEmpty != true else {
            throw BookCLI.Failure("Expected import specification version 1 with nonempty files and/or a Photos selection")
        }

        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("papergrain-import-\(UUID())")
        try FileManager.default.createDirectory(at: scratch.appendingPathComponent("assets"),
                                                withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: scratch) }
        var photos: [BookPhoto] = []
        for path in spec.files ?? [] {
            try Task.checkCancellation()
            let url = resolve(path, relativeTo: specURL.deletingLastPathComponent())
            guard (try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                throw BookCLI.Failure("Expected a local image file: " + path)
            }
            do {
                photos.append(try await LocalImages.importFile(url, into: scratch))
            } catch PhotoImportError.unreadableImage {
                throw BookCLI.Failure("Image unavailable or unreadable: " + path)
            }
        }
        if let selection = spec.photos {
            try await requirePhotosAccess(request: options.has("--request-access"))
            let album = try findAlbum(selection.albumID)
            for photo in try selectAssets(selection.assetIDs, from: album) {
                try Task.checkCancellation()
                photos.append(try await PhotoLibrary.importPhoto(photo, into: scratch))
            }
        }
        let book = try BookCLIEditing.derive(source: source, output: output) { book, staging in
            for photo in photos {
                try Task.checkCancellation()
                try FileManager.default.copyItem(
                    at: BookStorage.assetURL(filename: photo.filename, in: scratch),
                    to: BookStorage.assetURL(filename: photo.filename, in: staging)
                )
            }
            book.photos.append(contentsOf: photos)
        }
        return try encode(ProjectResult(book, output: output, photos: photos))
    }

    private static func preview(_ options: Options, currentDirectory: URL) throws -> Data {
        let source = try options.source(relativeTo: currentDirectory)
        let output = try options.url("--output", relativeTo: currentDirectory)
        try validateOutput(output, extension: "png", outside: source)
        let photoID = try options.uuid("--photo")
        let maximum = options["--max-pixels"] ?? "1600"
        guard let maxPixels = Int(maximum), (1...8192).contains(maxPixels) else {
            throw BookCLI.Failure("--max-pixels must be an integer from 1 through 8192")
        }
        let book = try BookCLIEditing.read(source: source)
        guard let photo = book.photo(photoID) else { throw unknownPhoto(photoID) }
        let original = options.has("--original")
        let settings = original ? FilmSettings() : book.effectiveFilm(for: photo)
        let lut = settings.lutFilename.map { BookStorage.lutURL(filename: $0, in: source) }
        let photoURL = BookStorage.assetURL(filename: photo.filename, in: source)
        guard let image = FilmRenderer.image(from: photoURL, maxPixelSize: maxPixels, settings: settings,
                                             lutURL: lut, adjustments: original ? nil : photo.adjustments)
        else { throw BookPDF.ExportError.missingImage(photo.name) }
        return try writePNG(image, to: output)
    }

    private static func enhance(_ options: Options, currentDirectory: URL) throws -> Data {
        let source = try options.source(relativeTo: currentDirectory)
        let output = try options.url("--output", relativeTo: currentDirectory)
        let photoID = try options.uuid("--photo")
        let book = try BookCLIEditing.derive(source: source, output: output) { book, staging in
            guard let index = book.photos.firstIndex(where: { $0.id == photoID }) else {
                throw unknownPhoto(photoID)
            }
            let photo = book.photos[index]
            let photoURL = BookStorage.assetURL(filename: photo.filename, in: staging)
            guard let suggestion = PhotoAdjustments.automatic(from: photoURL) else {
                throw BookCLI.Failure("Could not analyze photo: " + photo.name)
            }
            let adjusted = (photo.adjustments ?? PhotoAdjustments()).applyingAutomatic(suggestion)
            book.photos[index].adjustments = adjusted == PhotoAdjustments() ? nil : adjusted
        }
        return try encode(ProjectResult(book, output: output, photos: book.photo(photoID).map { [$0] }))
    }

    private static func importLUT(_ options: Options, currentDirectory: URL) throws -> Data {
        let source = try options.source(relativeTo: currentDirectory)
        let output = try options.url("--output", relativeTo: currentDirectory)
        let photoID = try options["--photo"].map { _ in try options.uuid("--photo") }
        let file = options["--file"].map { resolve($0, relativeTo: currentDirectory) }
        let lookID = options["--fujifilm"]
        guard (file != nil) != (lookID != nil) else {
            throw BookCLI.Failure("Specify exactly one of --file and --fujifilm")
        }
        var imported: String?
        let book = try BookCLIEditing.derive(source: source, output: output) { book, staging in
            let filename: String
            if let file {
                filename = try BookStorage.importLUT(file, in: staging)
            } else {
                guard let look = FujifilmFilmLook.all.first(where: { $0.id == lookID }),
                      let resources = Bundle.main.resourceURL,
                      FileManager.default.fileExists(atPath: look.url(in: resources).path) else {
                    throw BookCLI.Failure("Fujifilm LUT unavailable. Use an ID from film-looks and the application bundle")
                }
                filename = try BookStorage.importBuiltInLUT(look, resources: resources, in: staging)
            }
            imported = filename
            if let photoID {
                guard let index = book.photos.firstIndex(where: { $0.id == photoID }) else {
                    throw unknownPhoto(photoID)
                }
                var settings = book.effectiveFilm(for: book.photos[index])
                settings.preset = .custom
                settings.lutFilename = filename
                book.photos[index].film = settings
            } else {
                var settings = book.film ?? FilmSettings()
                settings.preset = .custom
                settings.lutFilename = filename
                book.film = settings
            }
        }
        return try encode(ProjectResult(book, output: output, lutFilename: imported))
    }

    private static func exportPDF(_ options: Options, currentDirectory: URL) throws -> Data {
        let source = try options.source(relativeTo: currentDirectory)
        let output = try options.url("--output", relativeTo: currentDirectory)
        guard let profile = PDFProfile(rawValue: try options.required("--profile")) else {
            throw BookCLI.Failure("Expected --profile proof, print or pixart")
        }
        try validateOutput(output, extension: profile == .print ? nil : "pdf", outside: source)
        let book = try BookCLIEditing.read(source: source)
        try checkExportable(book, profile: profile)
        let spineOption = options["--spine-mm"]
        guard profile == .pixart || spineOption == nil else {
            throw BookCLI.Failure("--spine-mm is only supported for Pixart exports")
        }
        var spine = book.cover?.spineMM
        if let spineOption {
            guard let value = Double(spineOption), PixartPrintProfile.isValidSpine(value) else {
                throw BookCLI.Failure("--spine-mm must be greater than 0 and at most 100")
            }
            spine = value
        }
        try publish(output) { staged in
            switch profile {
            case .proof:
                try BookPDF.write(book, directory: source, to: staged)
            case .print:
                try BookPDF.writePrint(book, directory: source, to: staged)
            case .pixart:
                guard let spine, PixartPrintProfile.isValidSpine(spine) else {
                    throw BookCLI.Failure("Pixart export requires a valid cover spine or --spine-mm")
                }
                try BookPDF.writePixart(book, directory: source, spineMM: spine, to: staged)
            }
        }
        let warnings = profile == .proof ? [] : BookPDF.printWarnings(book, pixart: profile == .pixart)
        return try encode(PDFResult(output: output.path, profile: profile, warnings: warnings))
    }

    /// Names the reason the PDF renderer would refuse the book, before any scratch folder is created.
    private static func checkExportable(_ book: Book, profile: PDFProfile) throws {
        func mm(_ value: Double) -> String { String(format: "%g", (value * 10).rounded() / 10) }
        guard !book.pages.isEmpty else { throw BookCLI.Failure("The book has no pages to export") }
        let format = book.format
        let minimum = 50 * 25.4 / 72
        for (field, value) in [("widthMM", format.widthMM), ("heightMM", format.heightMM)] where !(value > minimum) {
            throw BookCLI.Failure("format.\(field) must be more than \(mm(minimum)) mm for PDF export (found \(mm(value)))")
        }
        let margin = book.contentInsetPoints * 25.4 / 72
        guard margin * 2 < min(format.widthMM, format.heightMM) else {
            throw BookCLI.Failure("The \(mm(format.widthMM)) × \(mm(format.heightMM)) mm page is too small for its "
                + "\(mm(margin)) mm margins. Lower printSettings.safeMM or enlarge the format")
        }
        if profile == .pixart, !PixartPrintProfile.supports(format) {
            throw BookCLI.Failure("Pixart export requires a 210 × 210 mm book; this book is "
                + "\(mm(format.widthMM)) × \(mm(format.heightMM)) mm")
        }
    }

    private static func writePNG(_ image: CGImage, to output: URL) throws -> Data {
        try publish(output) { staged in
            guard let destination = CGImageDestinationCreateWithURL(staged as CFURL, UTType.png.identifier as CFString,
                                                                   1, nil) else {
                throw BookCLI.Failure("Could not create PNG")
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw BookCLI.Failure("Could not write PNG") }
        }
        return try encode(ImageResult(output: output.path, width: image.width, height: image.height))
    }

    private static func publish(_ output: URL, write: (URL) throws -> Void) throws {
        let scratch = output.deletingLastPathComponent().resolvingSymlinksInPath()
            .appendingPathComponent(".papergrain-media-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: scratch) }
        let staged = scratch.appendingPathComponent(output.lastPathComponent)
        try write(staged)
        try Task.checkCancellation()
        guard renamex_np(staged.path, output.path, UInt32(RENAME_EXCL)) == 0 else {
            let code = errno
            if code == EEXIST { throw BookCLI.Failure("Output already exists: " + output.path) }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSFilePathErrorKey: output.path])
        }
    }

    private static func validateOutput(_ output: URL, extension suffix: String?, outside source: URL? = nil) throws {
        if let suffix, output.pathExtension.lowercased() != suffix {
            throw BookCLI.Failure("Output must end in ." + suffix)
        }
        let parent = output.deletingLastPathComponent().resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw BookCLI.Failure("Output parent directory does not exist: " + parent.path)
        }
        if let source, parent.pathComponents.starts(with: source.resolvingSymlinksInPath().pathComponents) {
            throw BookCLI.Failure("Output cannot be inside the source project")
        }
        var entry = stat()
        if lstat(output.path, &entry) == 0 { throw BookCLI.Failure("Output already exists: " + output.path) }
    }

    private static func unknownPhoto(_ id: UUID) -> BookCLI.Failure {
        BookCLI.Failure("Unknown photo UUID: " + id.uuidString)
    }

    private static func resolve(_ path: String, relativeTo directory: URL) -> URL {
        URL(fileURLWithPath: path, relativeTo: directory).standardizedFileURL
    }

    private static func encode<T: Encodable>(_ result: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(result)
    }

    private struct Options {
        private let position: String?
        private var values: [String: String] = [:]
        private var flags: Set<String> = []

        init(_ arguments: [String], positional: Bool = false, values: Set<String> = [], flags: Set<String> = []) throws {
            var remaining = arguments[...]
            if positional {
                guard let subject = remaining.popFirst(), !subject.isEmpty, !subject.hasPrefix("--") else {
                    throw BookCLI.Failure("Missing required source project or album ID")
                }
                position = subject
            } else {
                position = nil
            }
            while let option = remaining.popFirst() {
                if values.contains(option) {
                    guard self.values[option] == nil, let value = remaining.popFirst(),
                          !value.isEmpty, !value.hasPrefix("--") else {
                        throw BookCLI.Failure("Expected one value for " + option)
                    }
                    self.values[option] = value
                } else if flags.contains(option), self.flags.insert(option).inserted {
                    continue
                } else {
                    throw BookCLI.Failure("Unexpected argument: " + option)
                }
            }
        }

        subscript(_ name: String) -> String? { values[name] }

        func has(_ name: String) -> Bool { flags.contains(name) }

        func subject() throws -> String {
            guard let position else { throw BookCLI.Failure("Missing required source project or album ID") }
            return position
        }

        func required(_ name: String) throws -> String {
            guard let value = values[name] else { throw BookCLI.Failure("Missing required argument: " + name) }
            return value
        }

        func url(_ name: String, relativeTo directory: URL) throws -> URL {
            try BookCLIMedia.resolve(required(name), relativeTo: directory)
        }

        func source(relativeTo directory: URL) throws -> URL {
            try BookCLIMedia.resolve(subject(), relativeTo: directory)
        }

        func uuid(_ name: String) throws -> UUID {
            guard let value = UUID(uuidString: try required(name)) else {
                throw BookCLI.Failure("Expected a UUID for " + name)
            }
            return value
        }
    }
}
