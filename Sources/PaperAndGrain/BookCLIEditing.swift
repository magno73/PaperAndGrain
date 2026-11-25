import Darwin
import Foundation

enum BookCLIEditing {
    typealias Failure = BookCLI.Failure

    /// A private package copy is the only location exposed to mutators.
    static func derive(source: URL, output: URL, mutate: (inout Book, URL) throws -> Void) throws -> Book {
        let files = FileManager.default
        let input = source.standardizedFileURL.resolvingSymlinksInPath()
        let target = output.standardizedFileURL
        let parent = target.deletingLastPathComponent().resolvingSymlinksInPath()
        guard target.pathExtension.lowercased() == "papergrain", !files.fileExists(atPath: target.path) else {
            throw Failure("Expected a new .papergrain output")
        }
        var ancestor = parent
        while true {
            guard !BookStorage.sameLocation(ancestor, input) else { throw Failure("Output lies inside the source") }
            let next = ancestor.deletingLastPathComponent()
            if ancestor.path == "/" || next.path == ancestor.path { break }
            ancestor = next
        }
        try checkTree(input)
        let sourceManifest = input.appendingPathComponent("manifest.json")
        let original = try Data(contentsOf: sourceManifest)
        let stage = parent.appendingPathComponent(".papergrain-" + UUID().uuidString)
        defer { BookStorage.removeStaged(stage) }
        try files.copyItem(at: input, to: stage)
        BookStorage.addOwnerWrite(stage)
        let copied = try snapshot(source: stage)
        var book = copied.book
        guard copied.raw == original, try Data(contentsOf: sourceManifest) == original else {
            throw Failure("Source changed while copying")
        }
        try mutate(&book, stage)
        book.id = UUID()
        try validate(book, in: stage)
        try BookStorage.writeExisting(book, to: stage)
        guard try BookStorage.read(from: stage) == book else { throw Failure("Output verification failed") }
        guard renamex_np(stage.path, target.path, UInt32(RENAME_EXCL)) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: target.path])
        }
        return book
    }

    static func read(source: URL) throws -> Book {
        try snapshot(source: source).book
    }

    static func readManifest(source: URL) throws -> Data {
        try snapshot(source: source).raw
    }

    private static func snapshot(source: URL) throws -> (book: Book, raw: Data) {
        let directory = source.standardizedFileURL.resolvingSymlinksInPath()
        try checkTree(directory)
        let raw = try Data(contentsOf: directory.appendingPathComponent("manifest.json"))
        let book = try BookStorage.read(from: directory)
        guard try JSONDecoder().decode(Book.self, from: raw) == book else { throw Failure("Manifest changed while reading") }
        try checkFields(JSONSerialization.jsonObject(with: raw), against: json(book))
        try validate(book, in: directory)
        return (book, raw)
    }

    private static func checkTree(_ url: URL) throws {
        let files = FileManager.default
        let type = try files.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType
        if type == .typeRegular { return }
        guard type == .typeDirectory else { throw Failure("Unsupported package entry: " + url.lastPathComponent) }
        for child in try files.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
            try checkTree(child)
        }
    }

    private static func json(_ book: Book) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(book))
    }

    // Codable ignores unrecognized keys. Check every supplied member against the decoded model.
    private static func checkFields(_ value: Any, against model: Any, key: String = "") throws {
        if let object = value as? [String: Any], let expected = model as? [String: Any] {
            for (field, child) in object {
                guard let recognized = expected[field] else { throw Failure("Unknown or null field: " + field) }
                try checkFields(child, against: recognized, key: field)
            }
        } else if let array = value as? [Any], let expected = model as? [Any] {
            guard array.count == expected.count else { throw Failure("Invalid array: " + key) }
            if key == "photoPlacements" {
                // Codable represents UUID dictionaries as alternating keys and values, in unspecified order.
                for index in stride(from: 0, to: array.count, by: 2) {
                    guard let id = array[index] as? String,
                          let other = stride(from: 0, to: expected.count, by: 2).first(where: {
                              (expected[$0] as? String)?.uppercased() == id.uppercased()
                          }) else { throw Failure("Invalid placement key") }
                    try checkFields(array[index + 1], against: expected[other + 1])
                }
            } else {
                for (child, reference) in zip(array, expected) { try checkFields(child, against: reference) }
            }
        }
    }

    static func patch(source: URL, patchURL: URL, output: URL) throws -> Book {
        guard let edits = try JSONSerialization.jsonObject(with: Data(contentsOf: patchURL)) as? [[String: Any]] else {
            throw Failure("Expected an array of JSON Patch operations")
        }
        return try derive(source: source, output: output) { book, stage in
            // Read the staged representation directly to retain UUID dictionary order across operations.
            var document = try JSONSerialization.jsonObject(with: Data(contentsOf: stage.appendingPathComponent("manifest.json")))
            for (index, edit) in edits.enumerated() {
                do { try apply(edit, to: &document) }
                catch { throw Failure("Operation \(index + 1): " + error.localizedDescription) }
            }
            let data = try JSONSerialization.data(withJSONObject: document)
            let result = try JSONDecoder().decode(Book.self, from: data)
            try checkFields(document, against: json(result))
            guard book.id == result.id, book.schemaVersion == result.schemaVersion,
                  result.photos.count == book.photos.count else { throw Failure("Protected book or asset metadata changed") }
            let indexed = Dictionary(uniqueKeysWithValues: book.photos.map { ($0.id, $0) })
            for photo in result.photos {
                guard let old = indexed[photo.id], photo.filename == old.filename,
                      photo.pixelWidth == old.pixelWidth, photo.pixelHeight == old.pixelHeight,
                      photo.sourceID == old.sourceID, photo.capturedAt == old.capturedAt else {
                    throw Failure("Use media import to change the asset inventory")
                }
            }
            book = result
        }
    }

    private static func pointer(_ raw: Any?) throws -> [String] {
        guard let path = raw as? String, path.hasPrefix("/") else { throw Failure("Expected a non-root JSON Pointer") }
        return try path.dropFirst().components(separatedBy: "/").map { token in
            guard token.range(of: "~([^01]|$)", options: .regularExpression) == nil else {
                throw Failure("Invalid JSON Pointer escape")
            }
            return token.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
        }
    }

    private static func apply(_ edit: [String: Any], to root: inout Any) throws {
        let path = try pointer(edit["path"])
        guard let op = edit["op"] as? String else { throw Failure("Missing operation") }
        var value = edit["value"]
        var action = op
        if op == "move" || op == "copy" {
            let from = try pointer(edit["from"])
            guard op != "move" || from == path || !path.starts(with: from) else {
                throw Failure("Cannot move a parent into a child")
            }
            value = try visit(&root, path: from[...], op: op == "move" ? "remove" : "read", value: nil)
            action = "add"
        }
        if op != "test", path.last == "id" { throw Failure("Object IDs are immutable") }
        if action == "test" {
            let old = try visit(&root, path: path[...], op: "read", value: nil)
            guard let value, let old, try comparable(old) == comparable(value) else { throw Failure("Test failed") }
            return
        }
        guard ["add", "remove", "replace"].contains(action), action == "remove" || value != nil else {
            throw Failure("Unknown operation or missing value")
        }
        _ = try visit(&root, path: path[...], op: action, value: value)
    }

    private static func comparable(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
    }

    private static func visit(_ node: inout Any, path: ArraySlice<String>, op: String, value: Any?) throws -> Any? {
        guard let key = path.first else { throw Failure("Empty path") }
        let rest = path.dropFirst()
        if var object = node as? [String: Any] {
            let old = object[key]
            if !rest.isEmpty {
                guard var child = old else { throw Failure("Missing field: " + key) }
                let found = try visit(&child, path: rest, op: op, value: value)
                object[key] = child
                node = object
                return found
            }
            guard op == "add" || old != nil else { throw Failure("Missing field: " + key) }
            if op != "read" { object[key] = op == "remove" ? nil : value; node = object }
            return old
        }
        if var array = node as? [Any] {
            let adding = rest.isEmpty && op == "add"
            let index: Int
            if adding && key == "-" { index = array.count }
            else {
                guard let i = Int(key), String(i) == key, i >= 0 else { throw Failure("Invalid array index: " + key) }
                index = i
            }
            guard index < array.count || (adding && index == array.count) else { throw Failure("Index out of bounds: " + key) }
            if !rest.isEmpty {
                let found = try visit(&array[index], path: rest, op: op, value: value)
                node = array
                return found
            }
            let old = index < array.count ? array[index] : nil
            if op == "remove" { array.remove(at: index) }
            if op == "add", let value { array.insert(value, at: index) }
            if op == "replace", let value {
                if let id = (old as? [String: Any])?["id"] as? String,
                   (value as? [String: Any])?["id"] as? String != id {
                    throw Failure("Retain the object ID when replacing an array element")
                }
                array[index] = value
            }
            node = array
            return old
        }
        throw Failure("Cannot traverse a scalar")
    }

    private static func validate(_ book: Book, in package: URL) throws {
        func checkFile(_ url: URL) throws {
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                throw Failure("Missing resource: " + url.lastPathComponent)
            }
        }
        for photo in book.photos { try checkFile(BookStorage.assetURL(filename: photo.filename, in: package)) }
        for film in book.photos.compactMap(\.film) + [book.film].compactMap({ $0 }) {
            if let lut = film.lutFilename { try checkFile(BookStorage.lutURL(filename: lut, in: package)) }
            guard [film.strength, film.grain, film.grainSize].allSatisfy({ (0...1).contains($0) }) else {
                throw Failure("Film strength, grain and grainSize must be between 0 and 1")
            }
        }
        func checkFrame(_ frame: PageRect) throws {
            guard frame.width > 0, frame.height > 0 else { throw Failure("Frame dimensions must be positive") }
        }
        func checkPlacement(_ placement: PhotoPlacement) throws {
            if let frame = placement.frame { try checkFrame(frame) }
            if let crop = placement.crop {
                guard (0...1).contains(crop.x), (0...1).contains(crop.y), (1...12).contains(crop.zoom) else {
                    throw Failure("Invalid crop center or zoom")
                }
            }
        }
        for placement in [book.cover?.frontPhotoPlacement, book.cover?.backPhotoPlacement].compactMap({ $0 }) {
            try checkPlacement(placement)
        }
        for page in book.pages {
            if let framing = page.framing, !(0...1).contains(framing) { throw Failure("Invalid page framing") }
            let ids = Set(page.photoIDs)
            guard ids.count == page.photoIDs.count,
                  Set(page.photoPlacements?.keys.map { $0 } ?? []).isSubset(of: ids),
                  Set((page.textBoxes ?? []).map(\.id)).count == (page.textBoxes ?? []).count else {
                throw Failure("Invalid page placements or duplicate IDs")
            }
            for placement in page.photoPlacements?.values.map({ $0 }) ?? [] { try checkPlacement(placement) }
            for frame in [page.titleFrame, page.storyFrame].compactMap({ $0 }) + (page.storyBackdropFrames ?? [])
                + (page.textBoxes ?? []).map(\.frame) { try checkFrame(frame) }
        }
        for frame in [book.cover?.frontTitleFrame, book.cover?.backTextFrame].compactMap({ $0 }) { try checkFrame(frame) }
        if let print = book.printSettings {
            guard print.bleedMM >= 0, print.safeMM >= 0, print.targetPPI > 0 else { throw Failure("Invalid print dimensions") }
        }
        guard (book.cover?.spineMM ?? 0) >= 0 else { throw Failure("Invalid cover spine") }
    }
}
