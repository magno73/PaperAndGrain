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
            _ = BookStorage.addOwnerWrite(url)
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

    // MARK: C5

    func testPatchAppliesTheBuildPageRules() async throws {
        let root = try temporaryDirectory()
        let source = try build(baseSpec(pages: [["arrangement": "twoAcross", "photos": ["a"]], ["layout": "text", "text": "Ciao"]]),
                               in: root, name: "Source.papergrain")
        var patch = try writePatch(#"[{"op":"replace","path":"/pages/0/layout","value":"mixed"}]"#, in: root)
        var text = message(try BookCLIEditing.patch(source: source, patchURL: patch, output: root.appendingPathComponent("A.papergrain")))
        XCTAssertTrue(text.contains("Page 1 (pages[0])") && text.contains("twoAcross") && text.contains("gallery"), text)
        patch = try writePatch(#"[{"op":"remove","path":"/pages/1"},{"op":"remove","path":"/pages/0"}]"#, in: root)
        text = message(try BookCLIEditing.patch(source: source, patchURL: patch, output: root.appendingPathComponent("B.papergrain")))
        XCTAssertTrue(text.contains("at least one page"), text)

        // Photos beyond the capacity stay stored, as in the app, and are reported as warnings.
        let more = try build(["version": 1, "title": "T", "assets": [["id": "a", "path": "pixel.png"], ["id": "b", "path": "pixel.png"],
                                                                     ["id": "c", "path": "pixel.png"]],
                              "pages": [["arrangement": "twoAcross", "photos": ["a", "b"]], ["layout": "gallery"]]],
                             in: root, name: "More.papergrain")
        let ids = try BookStorage.read(from: more).photos.map(\.id.uuidString)
        patch = try writePatch(#"[{"op":"add","path":"/pages/0/photoIDs/-","value":"\#(ids[2])"},"# +
                               #"{"op":"replace","path":"/pages/1/text","value":"Hidden"}]"#, in: root)
        let output = try await BookCLI.executeExtended(["patch", more.path, patch.path, root.appendingPathComponent("C.papergrain").path])
        let report = try XCTUnwrap(JSONSerialization.jsonObject(with: output) as? [String: Any])
        let warnings = try XCTUnwrap(report["warnings"] as? [String])
        XCTAssertEqual(warnings.count, 2, "\(warnings)")
        XCTAssertTrue(warnings[0].contains("Page 1 (pages[0])") && warnings[0].contains("3 photos"), warnings[0])
        XCTAssertTrue(warnings[1].contains("Page 2 (pages[1])") && warnings[1].contains("gallery"), warnings[1])
        XCTAssertEqual(try BookStorage.read(from: root.appendingPathComponent("C.papergrain")).pages[0].photoIDs.count, 3)

        // A patch that leaves the pages alone reports no warnings for them.
        patch = try writePatch(#"[{"op":"replace","path":"/title","value":"Again"}]"#, in: root)
        let again = try await BookCLI.executeExtended(["patch", root.appendingPathComponent("C.papergrain").path, patch.path,
                                                       root.appendingPathComponent("D.papergrain").path])
        XCTAssertEqual((try JSONSerialization.jsonObject(with: again) as? [String: Any])?["warnings"] as? [String], [])
    }

    func testBuildReportsPageRuleFailuresWithThePageIndex() throws {
        let root = try temporaryDirectory()
        var text = message(try build(baseSpec(pages: [["layout": "fullPage", "photos": ["a"]],
                                                      ["layout": "mixed", "arrangement": "twoAcross"]]), in: root))
        XCTAssertTrue(text.contains("Page 2 (pages[1])") && text.contains("twoAcross"), text)
        text = message(try build(baseSpec(pages: [["layout": "gallery", "text": "Lost"]]), in: root))
        XCTAssertTrue(text.contains("Page 1 (pages[0])") && text.contains("gallery"), text)
    }

    // MARK: C6

    func testCopyDuplicatesPagesAndTextBoxesWithFreshIDs() throws {
        let root = try temporaryDirectory()
        let source = try build(baseSpec(pages: [["layout": "text", "text": "Uno"]]), in: root, name: "Source.papergrain")
        let box = UUID().uuidString
        var patch = try writePatch("""
        [{"op":"add","path":"/pages/0/textBoxes","value":[{"id":"\(box)","text":"Nota","frame":{"x":0.1,"y":0.1,"width":0.3,"height":0.2}}]},
         {"op":"add","path":"/pages/0/layerOrder","value":["story","box:\(box)"]}]
        """, in: root)
        let boxed = root.appendingPathComponent("Boxed.papergrain")
        _ = try BookCLIEditing.patch(source: source, patchURL: patch, output: boxed)
        patch = try writePatch(#"[{"op":"copy","from":"/pages/0","path":"/pages/-"},"# +
                               #"{"op":"copy","from":"/pages/0/textBoxes/0","path":"/pages/0/textBoxes/-"}]"#, in: root)
        let book = try BookCLIEditing.patch(source: boxed, patchURL: patch, output: root.appendingPathComponent("Copied.papergrain"))
        XCTAssertEqual(book.pages.count, 2)
        XCTAssertNotEqual(book.pages[0].id, book.pages[1].id)
        let original = try XCTUnwrap(book.pages[0].textBoxes)
        XCTAssertEqual(original.count, 2)
        XCTAssertEqual(original[0].id.uuidString, box)
        XCTAssertNotEqual(original[1].id, original[0].id)
        let copy = try XCTUnwrap(book.pages[1].textBoxes?.first)
        XCTAssertNotEqual(copy.id.uuidString, box)
        XCTAssertEqual(copy.text, "Nota")
        XCTAssertEqual(book.pages[1].layerOrder, [.story, .textBox(copy.id)])
        XCTAssertEqual(book.pages[0].layerOrder, [.story, .textBox(original[0].id)])
    }

    // MARK: C7

    func testBuildAcceptsTextBoxesTypographyAndLayerOrder() throws {
        let root = try temporaryDirectory()
        let box = UUID()
        let project = try build([
            "version": 1, "title": "T", "assets": [["id": "a", "path": "pixel.png"]],
            "typography": ["title": ["fontName": "Didot", "color": 0x223344], "body": ["pointSize": 12, "lineSpacing": 1.4]],
            "pages": [[
                "arrangement": "textBesidePhoto", "photos": ["a"], "text": "Racconto",
                "typography": ["body": ["alignment": "justified", "color": 0x101010]],
                "textBoxes": [["id": box.uuidString, "text": "Nota", "frame": ["x": 0.1, "y": 0.1, "width": 0.4, "height": 0.2],
                               "typography": ["pointSize": 9, "lineSpacing": 0.9], "usesFullWidth": true,
                               "backgroundColor": 0xFFFFFF, "hidesBackground": false, "borderColor": 0, "borderWidth": 2],
                              ["text": "Seconda", "frame": ["x": 0.5, "y": 0.5, "width": 0.2, "height": 0.2]]],
                "layerOrder": ["story", "photo:a", "box:\(box.uuidString)"],
            ]],
            "cover": ["title": "T", "typography": ["title": ["color": 0xAA0000]]],
        ], in: root)
        let book = try BookStorage.read(from: project)
        let photo = try XCTUnwrap(book.photos.first)
        XCTAssertEqual(book.typography?.title?.fontName, "Didot")
        XCTAssertEqual(book.typography?.title?.color, 0x223344)
        XCTAssertEqual(book.typography?.body?.lineSpacing, 1.4)
        XCTAssertEqual(book.cover?.typography?.title?.color, 0xAA0000)
        let page = try XCTUnwrap(book.pages.first)
        XCTAssertEqual(page.typography?.body?.alignment, .justified)
        let boxes = try XCTUnwrap(page.textBoxes)
        XCTAssertEqual(boxes.count, 2)
        XCTAssertEqual(boxes[0].id, box)
        XCTAssertEqual(boxes[0].frame, PageRect(x: 0.1, y: 0.1, width: 0.4, height: 0.2))
        XCTAssertEqual(boxes[0].typography?.pointSize, 9)
        XCTAssertEqual(boxes[0].usesFullWidth, true)
        XCTAssertEqual(boxes[0].backgroundColor, 0xFFFFFF)
        XCTAssertEqual(boxes[0].hidesBackground, false)
        XCTAssertEqual(boxes[0].borderColor, 0)
        XCTAssertEqual(boxes[0].borderWidth, 2)
        XCTAssertNotEqual(boxes[1].id, box)
        XCTAssertEqual(boxes[1].text, "Seconda")
        XCTAssertEqual(page.layerOrder, [.story, .photo(photo.id), .textBox(box)])
    }

    func testBuildRejectsOutOfRangeStylesAndUnknownLayers() throws {
        let root = try temporaryDirectory()
        func page(_ extra: [String: Any]) -> [String: Any] {
            var spec = baseSpec(pages: [["layout": "mixed", "photos": ["a"]].merging(extra) { $1 }])
            spec["title"] = "T"
            return spec
        }
        let frame: [String: Any] = ["x": 0, "y": 0, "width": 0.5, "height": 0.5]
        let cases: [([String: Any], String)] = [
            (page(["typography": ["body": ["color": 0x1000000]]]), "typography.body.color"),
            (page(["typography": ["title": ["lineSpacing": 3]]]), "typography.title.lineSpacing"),
            (page(["textBoxes": [["text": "x", "frame": frame, "borderWidth": 13]]]), "textBoxes[0].borderWidth"),
            (page(["textBoxes": [["text": "x", "frame": frame, "borderColor": 0x1000000]]]), "textBoxes[0].borderColor"),
            (page(["textBoxes": [["text": "x", "frame": frame, "typography": ["lineSpacing": 0.5]]]]), "textBoxes[0].typography.lineSpacing"),
            (page(["textBoxes": [["text": "x", "frame": ["x": 0, "y": 0, "width": 0, "height": 0.5]]]]), "textBoxes[0].frame"),
            (page(["textBoxes": [["text": "x", "frame": frame, "colour": 1]]]), "\"colour\""),
            (page(["layerOrder": ["photo:missing"]]), "photo:missing"),
            (page(["layerOrder": ["box:\(UUID().uuidString)"]]), "box:"),
            (page(["layerOrder": ["title"]]), "title"),
        ]
        for (spec, expected) in cases {
            let text = message(try build(spec, in: root, name: "Out-\(UUID()).papergrain"))
            XCTAssertTrue(text.contains(expected), "\(expected) not in: \(text)")
        }
        var spec = baseSpec()
        spec["typography"] = ["body": ["color": 0x1000000]]
        XCTAssertTrue(message(try build(spec, in: root)).contains("typography.body.color"))
        XCTAssertFalse(try entries(root).contains { $0.hasSuffix(".papergrain") })
    }

    func testPatchRangeChecksColorsBorderAndLineSpacing() throws {
        let root = try temporaryDirectory()
        let source = try build(baseSpec(pages: [["layout": "text", "text": "Uno"]]), in: root, name: "Source.papergrain")
        for (operation, expected) in [
            (#"{"op":"add","path":"/typography","value":{"body":{"color":16777216}}}"#, "typography.body.color"),
            (#"{"op":"add","path":"/pages/0/typography","value":{"title":{"lineSpacing":2.5}}}"#, "typography.title.lineSpacing"),
            (#"{"op":"add","path":"/pages/0/textBoxes","value":[{"id":"\#(UUID().uuidString)","text":"x","frame":{"x":0,"y":0,"width":0.2,"height":0.2},"borderWidth":-1}]}"#,
             "textBoxes[0].borderWidth"),
            (#"{"op":"add","path":"/cover","value":{"title":"T","spineMM":0,"typography":{"title":{"color":99999999}}}}"#, "cover.typography.title.color"),
        ] {
            let patch = try writePatch("[\(operation)]", in: root)
            let text = message(try BookCLIEditing.patch(source: source, patchURL: patch, output: root.appendingPathComponent("Out.papergrain")))
            XCTAssertTrue(text.contains(expected), "\(expected) not in: \(text)")
        }
    }

    // MARK: C8

    func testBuildReturnsThePhotoIDForEachAsset() async throws {
        let root = try temporaryDirectory()
        try Self.pixel.write(to: root.appendingPathComponent("pixel.png"))
        let spec = root.appendingPathComponent("spec.json")
        try JSONSerialization.data(withJSONObject: [
            "version": 1, "title": "T", "assets": [["id": "a", "path": "pixel.png"], ["id": "b", "path": "pixel.png"]],
            "pages": [["layout": "gallery", "photos": ["b", "a"]]],
        ]).write(to: spec)
        let output = try await BookCLI.executeExtended(["build", spec.path, root.appendingPathComponent("B.papergrain").path])
        let report = try XCTUnwrap(JSONSerialization.jsonObject(with: output) as? [String: Any])
        let photos = try XCTUnwrap(report["photos"] as? [String: String])
        let book = try BookStorage.read(from: root.appendingPathComponent("B.papergrain"))
        XCTAssertEqual(photos, ["a": book.photos[0].id.uuidString, "b": book.photos[1].id.uuidString])
        XCTAssertEqual(book.pages[0].photoIDs.map(\.uuidString), [photos["b"], photos["a"]])
    }

    func testTemplatesListIDNameAndFamily() async throws {
        let output = try await BookCLI.executeExtended(["templates"])
        let catalog = try XCTUnwrap(JSONSerialization.jsonObject(with: output) as? [String: Any])
        let templates = try XCTUnwrap(catalog["templates"] as? [[String: Any]])
        XCTAssertEqual(templates.compactMap { $0["id"] as? String }, BookTemplate.allCases.map(\.rawValue))
        let swiss = try XCTUnwrap(templates.first { $0["id"] as? String == "swissGrid" })
        XCTAssertEqual(swiss["name"] as? [String: String], ["it": "Griglia svizzera", "en": "Swiss Grid"])
        XCTAssertEqual(swiss["family"] as? String, "studio")
        XCTAssertEqual(templates.first { $0["id"] as? String == "roadLog" }?["family"] as? String, "photobook")
    }

    func testAnalyzeValidatesTheOutputBeforeAnalysing() async throws {
        let root = try temporaryDirectory()
        let source = try build(baseSpec(), in: root, name: "Source.papergrain")
        for (output, expected) in [("missing/Out.papergrain", "parent directory does not exist"),
                                   ("Out.pdf", "must end in .papergrain"),
                                   ("Source.papergrain", "already exists"),
                                   ("Source.papergrain/Inner.papergrain", "inside the source")] {
            do {
                _ = try await BookCLIPhotoIndex.run(command: "analyze", arguments: [source.path, "--output", output],
                                                    currentDirectory: root)
                XCTFail("Analysed with output \(output)")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains(expected), error.localizedDescription)
            }
        }
        XCTAssertNil(try BookStorage.read(from: source).photos[0].analysis)
    }

    func testBuildFollowsSymlinksAndNamesUnreadableImages() throws {
        let root = try temporaryDirectory()
        try Self.pixel.write(to: root.appendingPathComponent("pixel.png"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link.png"),
                                                   withDestinationURL: root.appendingPathComponent("pixel.png"))
        try Data("not an image".utf8).write(to: root.appendingPathComponent("broken.png"))
        let spec = root.appendingPathComponent("spec.json")
        try JSONSerialization.data(withJSONObject: [
            "version": 1, "title": "T", "assets": [["id": "a", "path": "link.png"]], "pages": [["photos": ["a"]]],
        ]).write(to: spec)
        let book = try BookCLI.build(specURL: spec, output: root.appendingPathComponent("Linked.papergrain"))
        XCTAssertEqual(book.photos.count, 1)
        try JSONSerialization.data(withJSONObject: [
            "version": 1, "title": "T", "assets": [["id": "a", "path": "broken.png"]], "pages": [["photos": ["a"]]],
        ]).write(to: spec)
        let text = message(try BookCLI.build(specURL: spec, output: root.appendingPathComponent("Broken.papergrain")))
        XCTAssertTrue(text.contains("broken.png") && text.contains("Image unavailable"), text)
    }

    // MARK: C9

    func testHelpAndUsageStillAnswerAfterTheCleanUp() async throws {
        for args in [[], ["help"], ["--help"]] {
            let output = try await BookCLI.executeExtended(args)
            let commands = try XCTUnwrap((JSONSerialization.jsonObject(with: output) as? [String: Any])?["commands"] as? [String])
            XCTAssertTrue(commands.contains("templates") && commands.contains { $0.hasPrefix("export-pdf") })
        }
        do {
            _ = try await BookCLI.executeExtended(["templates", "extra"])
            XCTFail("Accepted an extra argument")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Usage: templates")
        }
        do {
            _ = try await BookCLI.executeExtended(["photos", "Book.papergrain", "--bogus"])
            XCTFail("Accepted an unknown option")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    func testImportPhotosNamesUnreadableImages() async throws {
        let root = try temporaryDirectory()
        try build(baseSpec(), in: root, name: "Source.papergrain")
        try Data("not an image".utf8).write(to: root.appendingPathComponent("broken.png"))
        try Data(#"{"version":1,"files":["broken.png"]}"#.utf8).write(to: root.appendingPathComponent("import.json"))
        do {
            _ = try await BookCLIMedia.run(command: "import-photos",
                                           arguments: ["Source.papergrain", "--spec", "import.json", "--output", "Out.papergrain"],
                                           currentDirectory: root)
            XCTFail("Imported a broken image")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("broken.png"), error.localizedDescription)
        }
    }
}
