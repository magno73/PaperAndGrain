import Foundation
import XCTest
@testable import PaperAndGrain

/// Command-line regressions found in the pre-release review (C1 to C9).
final class CLIReleaseTests: XCTestCase {
    static let pixel = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aHukAAAAASUVORK5CYII=")!

    func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("papergrain-cli-\(UUID())")
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
}
