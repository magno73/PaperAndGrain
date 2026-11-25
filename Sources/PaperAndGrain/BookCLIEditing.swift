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
        try BookCLI.checkNewPackage(target)
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

    /// Page rules shared by `build` and `patch`. A layout that contradicts the arrangement or a photo listed twice
    /// is an error. Photos beyond the capacity and story text on a layout without a story stay stored, as in the
    /// app, but are not shown; they come back as warnings.
    static func checkPage(_ page: BookPage, at index: Int) throws -> [String] {
        let name = "Page \(index + 1) (pages[\(index)])"
        if let arrangement = page.arrangement, arrangement.layout != page.layout {
            throw Failure("\(name) has layout \"\(page.layout.rawValue)\", but arrangement \"\(arrangement.rawValue)\" "
                + "needs layout \"\(arrangement.layout.rawValue)\"")
        }
        if let duplicate = page.photoIDs.first(where: { id in page.photoIDs.filter { $0 == id }.count > 1 }) {
            throw Failure("\(name) lists photo \(duplicate.uuidString) more than once")
        }
        var warnings: [String] = []
        let capacity: Int
        let shape: String
        if let arrangement = page.arrangement {
            capacity = arrangement.photoCapacity
            shape = "arrangement \"\(arrangement.rawValue)\""
        } else {
            switch page.layout {
            case .text: capacity = 0
            case .fullPage, .fullSpread: capacity = 1
            case .mixed, .gallery: capacity = Int.max
            }
            shape = "layout \"\(page.layout.rawValue)\""
        }
        if page.photoIDs.count > capacity {
            warnings.append("\(name) has \(page.photoIDs.count) photos; \(shape) shows \(capacity). "
                + "The others stay stored but are not shown")
        }
        if page.hasStoryText, page.layout != .mixed, page.layout != .text {
            warnings.append("\(name) has a heading or text that \(shape) does not show. Use layout \"mixed\" or \"text\"")
        }
        return warnings
    }

    static func patch(source: URL, patchURL: URL, output: URL) throws -> Book {
        var warnings: [String] = []
        return try patch(source: source, patchURL: patchURL, output: output, warnings: &warnings)
    }

    /// Applies the patch; `warnings` lists the page states the app keeps but does not show, for changed pages only.
    static func patch(source: URL, patchURL: URL, output: URL, warnings: inout [String]) throws -> Book {
        var found: [String] = []
        defer { warnings = found }
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
            guard !result.pages.isEmpty else { throw Failure("The book must keep at least one page") }
            let original = Dictionary(book.pages.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for (index, page) in result.pages.enumerated() where original[page.id] != page {
                found += try checkPage(page, at: index)
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
        func checkFile(_ url: URL, _ owner: String) throws {
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                throw Failure("\(owner) refers to a missing file in the package: " + url.lastPathComponent)
            }
        }
        for photo in book.photos {
            try checkFile(BookStorage.assetURL(filename: photo.filename, in: package), "Photo \(photo.id.uuidString)")
        }
        let looks = book.photos.compactMap { photo in photo.film.map { ("Photo \(photo.id.uuidString) film", $0) } }
            + [book.film].compactMap { $0 }.map { ("film", $0) }
        for (owner, film) in looks {
            if let lut = film.lutFilename { try checkFile(BookStorage.lutURL(filename: lut, in: package), owner + ".lutFilename") }
            for (field, value) in [("strength", film.strength), ("grain", film.grain), ("grainSize", film.grainSize)]
            where !(0...1).contains(value) {
                throw Failure("\(owner).\(field) must be between 0 and 1 (found \(value))")
            }
        }
        func checkFrame(_ frame: PageRect, _ owner: String) throws {
            guard frame.width > 0, frame.height > 0 else {
                throw Failure("\(owner) must have a positive width and height")
            }
        }
        func checkPlacement(_ placement: PhotoPlacement, _ owner: String) throws {
            if let frame = placement.frame { try checkFrame(frame, owner + ".frame") }
            if let crop = placement.crop {
                guard (0...1).contains(crop.x), (0...1).contains(crop.y) else {
                    throw Failure("\(owner).crop x and y must be between 0 and 1")
                }
                guard (1...12).contains(crop.zoom) else { throw Failure("\(owner).crop.zoom must be between 1 and 12") }
            }
        }
        if let placement = book.cover?.frontPhotoPlacement { try checkPlacement(placement, "cover.frontPhotoPlacement") }
        if let placement = book.cover?.backPhotoPlacement { try checkPlacement(placement, "cover.backPhotoPlacement") }
        for (index, page) in book.pages.enumerated() {
            let name = "Page \(index + 1) (pages[\(index)])"
            if let framing = page.framing, !(0...1).contains(framing) {
                throw Failure("\(name) framing must be between 0 and 1")
            }
            if let duplicate = page.photoIDs.first(where: { id in page.photoIDs.filter { $0 == id }.count > 1 }) {
                throw Failure("\(name) lists photo \(duplicate.uuidString) more than once in photoIDs")
            }
            for (id, placement) in page.photoPlacements ?? [:] {
                guard page.photoIDs.contains(id) else {
                    throw Failure("\(name) has a photoPlacements entry for \(id.uuidString), which is not in photoIDs")
                }
                try checkPlacement(placement, "\(name) photoPlacements[\(id.uuidString)]")
            }
            var boxIDs: Set<UUID> = []
            for box in page.textBoxes ?? [] where !boxIDs.insert(box.id).inserted {
                throw Failure("\(name) has a duplicate text box id \(box.id.uuidString)")
            }
            for (field, frame) in [("titleFrame", page.titleFrame), ("storyFrame", page.storyFrame)] {
                if let frame { try checkFrame(frame, "\(name) \(field)") }
            }
            for (offset, frame) in (page.storyBackdropFrames ?? []).enumerated() {
                try checkFrame(frame, "\(name) storyBackdropFrames[\(offset)]")
            }
            for (offset, box) in (page.textBoxes ?? []).enumerated() {
                try checkFrame(box.frame, "\(name) textBoxes[\(offset)].frame")
            }
        }
        if let frame = book.cover?.frontTitleFrame { try checkFrame(frame, "cover.frontTitleFrame") }
        if let frame = book.cover?.backTextFrame { try checkFrame(frame, "cover.backTextFrame") }
        if let print = book.printSettings {
            guard print.bleedMM >= 0 else { throw Failure("printSettings.bleedMM must be 0 or more") }
            guard print.safeMM >= 0 else { throw Failure("printSettings.safeMM must be 0 or more") }
            guard print.targetPPI > 0 else { throw Failure("printSettings.targetPPI must be greater than 0") }
        }
        guard (book.cover?.spineMM ?? 0) >= 0 else { throw Failure("cover.spineMM must be 0 or more") }
    }
}
