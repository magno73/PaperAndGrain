import Foundation
import XCTest
@testable import PaperAndGrain

/// Command-line regressions found in the pre-release review (C1 to C9).
final class CLIReleaseTests: XCTestCase {
    static let pixel = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aHukAAAAASUVORK5CYII=")!

    func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("papergrain-cli-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        addTeardownBlock {
            _ = try? BookStorage.addOwnerWrite(url)
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    /// Builds a small book from `spec` (one asset `a` is written next to it) and returns the project URL.
    @discardableResult
    func build(_ spec: [String: Any], in root: URL, name: String = "Book.papergrain") throws -> URL {
        try Self.pixel.write(to: root.appendingPathComponent("pixel.png"))
        let specURL = root.appendingPathComponent("spec-\(UUID()).json")
        try JSONSerialization.data(withJSONObject: spec).write(to: specURL)
        let project = root.appendingPathComponent(name)
        _ = try BookCLI.build(specURL: specURL, output: project)
        return project
    }

    func baseSpec(pages: [[String: Any]] = [["layout": "fullPage", "photos": ["a"]]]) -> [String: Any] {
        ["version": 1, "title": "Test", "assets": [["id": "a", "path": "pixel.png"]], "pages": pages]
    }

    func writePatch(_ operations: String, in root: URL) throws -> URL {
        let url = root.appendingPathComponent("patch-\(UUID()).json")
        try Data(operations.utf8).write(to: url)
        return url
    }

    func entries(_ root: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
    }

    func message(_ expression: @autoclosure () throws -> Any) -> String {
        do {
            _ = try expression()
            XCTFail("Expected an error")
            return ""
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: C1

    func testReadOnlySourceCanBeEditedAndLeavesNoStagingCopy() throws {
        let root = try temporaryDirectory()
        let source = try build(baseSpec(), in: root, name: "Source.papergrain")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/chmod")
        process.arguments = ["-R", "a-w", source.path]
        try process.run()
        process.waitUntilExit()
        let patch = try writePatch(#"[{"op":"replace","path":"/title","value":"Edited"}]"#, in: root)
        let book = try BookCLIEditing.patch(source: source, patchURL: patch,
                                            output: root.appendingPathComponent("Edited.papergrain"))
        XCTAssertEqual(book.title, "Edited")
        XCTAssertEqual(try BookStorage.read(from: root.appendingPathComponent("Edited.papergrain")).title, "Edited")
        // A failing edit must not leave a hidden staging copy either.
        let bad = try writePatch(#"[{"op":"replace","path":"/format/widthMM","value":-1}]"#, in: root)
        XCTAssertThrowsError(try BookCLIEditing.patch(source: source, patchURL: bad,
                                                      output: root.appendingPathComponent("Bad.papergrain")))
        XCTAssertFalse(try entries(root).contains { $0.hasPrefix(".papergrain-") })
    }

    // MARK: C2

    func testBuildRejectsUnknownKeysNamingTheKeyAndTheValidOnes() throws {
        let root = try temporaryDirectory()
        var spec = baseSpec()
        spec["templte"] = "atlas"
        var text = message(try self.build(spec, in: root))
        XCTAssertTrue(text.contains("\"templte\""), text)
        XCTAssertTrue(text.contains("template"), text)
        spec = baseSpec(pages: [["layout": "fullPage", "photo": ["a"]]])
        text = message(try self.build(spec, in: root))
        XCTAssertTrue(text.contains("\"photo\"") && text.contains("pages[0]") && text.contains("photos"), text)
        spec = baseSpec()
        spec["assets"] = [["id": "a", "path": "pixel.png", "name": "x"]]
        XCTAssertTrue(message(try self.build(spec, in: root)).contains("assets[0]"))
        spec = baseSpec()
        spec["cover"] = ["frontPhotos": "a"]
        XCTAssertTrue(message(try self.build(spec, in: root)).contains("cover"))
        spec = baseSpec()
        spec["format"] = ["width": 210, "heightMM": 210]
        XCTAssertTrue(message(try self.build(spec, in: root)).contains("format"))
        XCTAssertFalse(try entries(root).contains { $0.hasSuffix(".papergrain") || $0.hasPrefix(".papergrain-") })
    }

    func testImportSpecRejectsUnknownKeys() async throws {
        let root = try temporaryDirectory()
        try build(baseSpec(), in: root, name: "Source.papergrain")
        for spec in [#"{"version":1,"file":["pixel.png"]}"#,
                     #"{"version":1,"photos":{"albumID":"x","assetIDs":["y"],"asset":1}}"#] {
            try Data(spec.utf8).write(to: root.appendingPathComponent("import.json"))
            do {
                _ = try await BookCLIMedia.run(command: "import-photos",
                                               arguments: ["Source.papergrain", "--spec", "import.json", "--output", "Out.papergrain"],
                                               currentDirectory: root)
                XCTFail("Accepted \(spec)")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("Unknown key"), error.localizedDescription)
            }
        }
    }

    // MARK: C3

    /// Rewrites the manifest of `project` with `edit` applied to its JSON object.
    func editManifest(_ project: URL, _ edit: (inout [String: Any]) -> Void) throws {
        let url = project.appendingPathComponent("manifest.json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        edit(&object)
        try JSONSerialization.data(withJSONObject: object).write(to: url)
    }

    func testAbsurdPixelDimensionsAreRejectedBeforeExport() async throws {
        let root = try temporaryDirectory()
        let project = try build(baseSpec(), in: root, name: "Source.papergrain")
        for (field, value) in [("pixelWidth", 4_000_000_000_000_000), ("pixelHeight", 0)] {
            try editManifest(project) { manifest in
                var photos = manifest["photos"] as! [[String: Any]]
                photos[0]["pixelWidth"] = 1
                photos[0]["pixelHeight"] = 1
                photos[0][field] = value
                manifest["photos"] = photos
            }
            do {
                _ = try await BookCLIMedia.run(command: "export-pdf",
                                               arguments: ["Source.papergrain", "--profile", "proof", "--output", "Out.pdf"],
                                               currentDirectory: root)
                XCTFail("Exported a book with \(field) \(value)")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains(field), error.localizedDescription)
            }
        }
        XCTAssertFalse(try entries(root).contains { $0.hasPrefix(".papergrain") || $0 == "Out.pdf" })
    }

    // MARK: C4

    func testDamagedManifestsNameTheFailingCheck() throws {
        let root = try temporaryDirectory()
        let project = try build(baseSpec(pages: [["layout": "fullPage", "photos": ["a"]], ["layout": "fullPage", "photos": ["a"]]]),
                                in: root)
        let pristine = try Data(contentsOf: project.appendingPathComponent("manifest.json"))
        let unknown = UUID().uuidString
        let cases: [(String, (inout [String: Any]) -> Void)] = [
            ("schemaVersion 2", { $0["schemaVersion"] = 2 }),
            ("format.widthMM must be greater than 0", { $0["format"] = ["widthMM": 0, "heightMM": 210] }),
            ("Page 2 (pages[1]) references unknown photo \(unknown)", { manifest in
                var pages = manifest["pages"] as! [[String: Any]]
                pages[1]["photoIDs"] = [unknown]
                manifest["pages"] = pages
            }),
            ("Page 2 (pages[1]) has a duplicate id", { manifest in
                var pages = manifest["pages"] as! [[String: Any]]
                pages[1]["id"] = pages[0]["id"]
                manifest["pages"] = pages
            }),
            ("has a duplicate id", { manifest in
                let photos = manifest["photos"] as! [[String: Any]]
                manifest["photos"] = photos + photos
            }),
            ("invalid filename \"../x\"", { manifest in
                var photos = manifest["photos"] as! [[String: Any]]
                photos[0]["filename"] = "../x"
                manifest["photos"] = photos
            }),
            ("cover.backPhotoID references unknown photo \(unknown)", { $0["cover"] = ["title": "T", "spineMM": 0, "backPhotoID": unknown] }),
            ("film.lutFilename", { $0["film"] = ["preset": "custom", "strength": 1, "grain": 0, "grainSize": 0.5, "lutFilename": "a/b"] }),
        ]
        for (expected, edit) in cases {
            try pristine.write(to: project.appendingPathComponent("manifest.json"))
            try editManifest(project, edit)
            let text = message(try BookStorage.read(from: project))
            XCTAssertTrue(text.contains(expected), "\(expected) not in: \(text)")
            XCTAssertFalse(text.contains("correct format"), text)
        }
    }

    func testLayerOrderEntriesForUnknownObjectsAreIgnored() throws {
        let root = try temporaryDirectory()
        let project = try build(baseSpec(), in: root)
        try editManifest(project) { manifest in
            var pages = manifest["pages"] as! [[String: Any]]
            pages[0]["layerOrder"] = ["photo:\(UUID().uuidString)", "story", "box:\(UUID().uuidString)"]
            manifest["pages"] = pages
        }
        XCTAssertEqual(try BookStorage.read(from: project).pages[0].layerOrder?.count, 3)
        XCTAssertNoThrow(try BookCLIEditing.read(source: project))
    }

    func testOutputPathErrorsAreSpecific() throws {
        let root = try temporaryDirectory()
        let source = try build(baseSpec(), in: root, name: "Source.papergrain")
        let spec = root.appendingPathComponent("spec.json")
        try JSONSerialization.data(withJSONObject: baseSpec()).write(to: spec)
        let missing = root.appendingPathComponent("missing/Out.papergrain")
        XCTAssertTrue(message(try BookCLI.build(specURL: spec, output: missing)).contains("parent directory does not exist"))
        XCTAssertTrue(message(try BookCLI.build(specURL: spec, output: root.appendingPathComponent("Out.book")))
            .contains("must end in .papergrain"))
        let patch = try writePatch("[]", in: root)
        XCTAssertTrue(message(try BookCLIEditing.patch(source: source, patchURL: patch, output: missing))
            .contains("parent directory does not exist"))
        XCTAssertTrue(message(try BookCLIEditing.patch(source: source, patchURL: patch, output: root.appendingPathComponent("Out.json")))
            .contains("must end in .papergrain"))
        XCTAssertTrue(message(try BookCLIEditing.patch(source: source, patchURL: patch, output: source))
            .contains("already exists"))
    }

    func exportMessage(_ arguments: [String], in root: URL) async -> String {
        do {
            _ = try await BookCLIMedia.run(command: "export-pdf", arguments: arguments, currentDirectory: root)
            XCTFail("Export succeeded")
            return ""
        } catch {
            return error.localizedDescription
        }
    }

    func testExportProblemsAreSpecific() async throws {
        let root = try temporaryDirectory()
        var spec = baseSpec()
        spec["format"] = ["widthMM": 300, "heightMM": 200]
        try build(spec, in: root, name: "Wide.papergrain")
        var text = await exportMessage(["Wide.papergrain", "--profile", "pixart", "--output", "Out.pdf", "--spine-mm", "4"], in: root)
        XCTAssertTrue(text.contains("210 × 210 mm") && text.contains("300 × 200 mm"), text)
        try BookStorage.write(Book(title: "Empty"), to: root.appendingPathComponent("Empty.papergrain"))
        text = await exportMessage(["Empty.papergrain", "--profile", "proof", "--output", "Out.pdf"], in: root)
        XCTAssertTrue(text.contains("no pages"), text)
        var small = Book(title: "Small", format: BookFormat(widthMM: 25, heightMM: 25), pages: [BookPage(layout: .text)])
        small.printSettings = PrintSettings(bleedMM: 3, safeMM: 15)
        try BookStorage.write(small, to: root.appendingPathComponent("Small.papergrain"))
        text = await exportMessage(["Small.papergrain", "--profile", "print", "--output", "Press"], in: root)
        XCTAssertTrue(text.contains("too small for its 15 mm margins"), text)
        XCTAssertFalse(try entries(root).contains { $0.hasPrefix(".papergrain-media") || $0 == "Out.pdf" || $0 == "Press" })
    }

    func testLUTFileErrorsNameTheProblem() throws {
        let root = try temporaryDirectory()
        let text = root.appendingPathComponent("look.txt")
        try Data("x".utf8).write(to: text)
        XCTAssertTrue(message(try BookStorage.importLUT(text, in: root)).contains(".cube"))
        let empty = root.appendingPathComponent("empty.cube")
        try Data().write(to: empty)
        XCTAssertTrue(message(try BookStorage.importLUT(empty, in: root)).contains("1 byte to 50 MB"))
    }
}
