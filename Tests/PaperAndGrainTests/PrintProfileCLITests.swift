import CoreGraphics
import XCTest
@testable import PaperAndGrain

/// `print-profiles`, `export-pdf --profile <catalog id>`, the build spec's `printService` and the patch checks.
final class PrintProfileCLITests: XCTestCase {
    private let helpers = CLIReleaseTests()

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("papergrain-profile-cli-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    @discardableResult
    private func build(_ spec: [String: Any], in root: URL, name: String) throws -> URL {
        try helpers.build(spec, in: root, name: name)
    }

    private func baseSpec(pages: [[String: Any]] = [["layout": "fullPage", "photos": ["a"]]]) -> [String: Any] {
        helpers.baseSpec(pages: pages)
    }

    private func writePatch(_ operations: String, in root: URL) throws -> URL { try helpers.writePatch(operations, in: root) }

    private func entries(_ root: URL) throws -> [String] { try helpers.entries(root) }

    private func message(_ expression: @autoclosure () throws -> Any) -> String {
        do {
            _ = try expression()
            XCTFail("Expected an error")
            return ""
        } catch {
            return error.localizedDescription
        }
    }

    private func exportMessage(_ arguments: [String], in root: URL) async -> String {
        do {
            _ = try await BookCLIMedia.run(command: "export-pdf", arguments: arguments, currentDirectory: root)
            XCTFail("Export succeeded")
            return ""
        } catch {
            return error.localizedDescription
        }
    }

    private func export(_ arguments: [String], in root: URL) async throws -> [String: Any] {
        let data = try await BookCLI.executeExtended(["export-pdf"] + arguments.enumerated().map { index, value in
            index == 0 || arguments[index - 1] == "--output" ? root.appendingPathComponent(value).path : value
        })
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testPrintProfilesListsTheCatalog() async throws {
        let data = try await BookCLI.executeExtended(["print-profiles"])
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let profiles = try XCTUnwrap(root["profiles"] as? [[String: Any]])
        let pixart = try XCTUnwrap(profiles.first { $0["id"] as? String == PrintProfileCatalog.pixartID })
        XCTAssertEqual(pixart["service"] as? String, "Pixartprinting")
        XCTAssertEqual((pixart["sizes"] as? [[String: Any]])?.first?["id"] as? String, "21x21")
        XCTAssertNotNil(pixart["sourceURL"] as? String)
    }

    func testCatalogIDAndPixartAliasWriteTheSameBoxes() async throws {
        let root = try temporaryDirectory()
        var spec = baseSpec(pages: [["layout": "fullPage", "photos": ["a"]], ["layout": "text", "text": "Two"]])
        spec["cover"] = ["frontPhoto": "a", "spineMM": 6]
        try build(spec, in: root, name: "Source.papergrain")
        let alias = try await export(["Source.papergrain", "--profile", "pixart", "--output", "Alias.pdf"], in: root)
        let byID = try await export(["Source.papergrain", "--profile", PrintProfileCatalog.pixartID, "--size", "21x21",
                                     "--output", "ID.pdf", "--spine-mm", "9"], in: root)
        XCTAssertEqual(alias["profile"] as? String, "pixart")
        XCTAssertEqual(byID["size"] as? String, "21x21")
        let a = try XCTUnwrap(CGPDFDocument(root.appendingPathComponent("Alias.pdf") as CFURL))
        let b = try XCTUnwrap(CGPDFDocument(root.appendingPathComponent("ID.pdf") as CFURL))
        XCTAssertEqual(a.numberOfPages, b.numberOfPages)
        let points = 72 / 25.4
        XCTAssertEqual(try XCTUnwrap(a.page(at: 1)).getBoxRect(.trimBox).width, (2 * (207 + 11) + 6) * points, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(b.page(at: 1)).getBoxRect(.trimBox).width, (2 * (207 + 11) + 9) * points, accuracy: 0.01)
        for index in 2...a.numberOfPages {
            XCTAssertEqual(a.page(at: index)?.getBoxRect(.mediaBox), b.page(at: index)?.getBoxRect(.mediaBox))
            XCTAssertEqual(a.page(at: index)?.getBoxRect(.trimBox), b.page(at: index)?.getBoxRect(.trimBox))
        }
    }

    func testExportOptionsAreChecked() async throws {
        let root = try temporaryDirectory()
        var spec = baseSpec()
        spec["cover"] = ["frontPhoto": "a"]
        try build(spec, in: root, name: "Source.papergrain")
        var text = await exportMessage(["Source.papergrain", "--profile", "nowhere", "--output", "Out.pdf"], in: root)
        XCTAssertTrue(text.contains("print-profiles") && text.contains("nowhere"), text)
        text = await exportMessage(["Source.papergrain", "--profile", "proof", "--output", "Out.pdf", "--spine-mm", "4"], in: root)
        XCTAssertTrue(text.contains("--spine-mm is only supported for print-service exports"), text)
        text = await exportMessage(["Source.papergrain", "--profile", "pixart", "--output", "Out.pdf", "--size", "a4"], in: root)
        XCTAssertTrue(text.contains("Unknown --size a4") && text.contains("21x21"), text)
        text = await exportMessage(["Source.papergrain", "--profile", "pixart", "--output", "Out.pdf"], in: root)
        XCTAssertTrue(text.contains("needs the spine width"), text)
        text = await exportMessage(["Source.papergrain", "--profile", "pixart", "--output", "Out.pdf", "--spine-mm", "0"], in: root)
        XCTAssertTrue(text.contains("--spine-mm must be greater than 0 and at most 100"), text)
        text = await exportMessage(["Source.papergrain", "--profile", "pixart", "--output", "Out.pdf", "--paper", "matte"], in: root)
        XCTAssertTrue(text.contains("Unknown --paper matte"), text)
        XCTAssertFalse(try entries(root).contains("Out.pdf"))
    }

    func testBuildSpecChoosesAPrintServiceAndPatchChecksIt() async throws {
        let root = try temporaryDirectory()
        var spec = baseSpec()
        spec["printService"] = ["profile": "pixart"]
        let project = try build(spec, in: root, name: "Pixart.papergrain")
        let book = try BookStorage.read(from: project)
        XCTAssertEqual(book.format, BookFormat(widthMM: 210, heightMM: 210))
        XCTAssertEqual(book.printSettings?.profileID, PrintProfileCatalog.pixartID)
        XCTAssertEqual(book.printSettings?.profileSizeID, "21x21")
        XCTAssertEqual(book.printSettings?.bleedMM, 3)
        XCTAssertEqual(book.printSettings?.safeMM, 5, "the largest outer safe margin of the product")
        XCTAssertNotNil(PrintPlan(book: book))

        spec["format"] = ["widthMM": 300, "heightMM": 200]
        var text = message(try build(spec, in: root, name: "Wrong.papergrain"))
        XCTAssertTrue(text.contains("does not match printService.size 21x21"), text)
        spec["format"] = nil
        spec["printService"] = ["profile": "pixart", "size": "a4"]
        text = message(try build(spec, in: root, name: "Wrong.papergrain"))
        XCTAssertTrue(text.contains("Unknown printService.size a4"), text)
        spec["printService"] = ["profile": "pixart", "spine": 4]
        text = message(try build(spec, in: root, name: "Wrong.papergrain"))
        XCTAssertTrue(text.contains("spine"), text)

        var patch = try writePatch(#"[{"op":"replace","path":"/printSettings/profileID","value":"nowhere"}]"#, in: root)
        text = message(try BookCLIEditing.patch(source: project, patchURL: patch, output: root.appendingPathComponent("P.papergrain")))
        XCTAssertTrue(text.contains("printSettings.profileID nowhere"), text)
        patch = try writePatch(#"[{"op":"add","path":"/printSettings/profileMeasures","value":{"spineMM":7.5}}]"#, in: root)
        _ = try BookCLIEditing.patch(source: project, patchURL: patch, output: root.appendingPathComponent("Spine.papergrain"))
        let patched = try BookStorage.read(from: root.appendingPathComponent("Spine.papergrain"))
        XCTAssertEqual(PrintPlan(book: patched)?.value(.spine, for: patched, interiorPages: 2), 7.5)
        let exported = try await export(["Spine.papergrain", "--profile", "pixart", "--output", "Spine.pdf"], in: root)
        XCTAssertEqual(exported["size"] as? String, "21x21")
    }
}
