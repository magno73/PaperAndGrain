import Foundation
import XCTest

/// `scripts/l10n-merge.py`: the three-way merge driver for the String Catalog.
final class L10nMergeTests: XCTestCase {
    private let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("L10nMerge-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func entry(_ it: String) -> [String: Any] {
        ["extractionState": "manual",
         "localizations": ["it": ["stringUnit": ["state": "translated", "value": it]]]]
    }

    private func write(_ name: String, _ strings: [String: Any]) throws -> URL {
        let catalog: [String: Any] = ["sourceLanguage": "en", "strings": strings, "version": "1.0"]
        let data = try JSONSerialization.data(withJSONObject: catalog, options: [.prettyPrinted, .sortedKeys])
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func merge(_ base: URL, _ ours: URL, _ theirs: URL) throws -> (status: Int32, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", repository.appendingPathComponent("scripts/l10n-merge.py").path,
                             base.path, ours.path, theirs.path]
        let pipe = Pipe()
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    func testCatalogMergedWithItselfIsByteIdentical() throws {
        let catalog = repository.appendingPathComponent("Resources/Localizable.xcstrings")
        let copy = directory.appendingPathComponent("ours.xcstrings")
        try FileManager.default.copyItem(at: catalog, to: copy)
        let result = try merge(catalog, copy, catalog)
        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertEqual(try Data(contentsOf: copy), try Data(contentsOf: catalog))
    }

    func testKeysAddedOnBothSidesAreBothKept() throws {
        let base = try write("base", ["Alpha": entry("a"), "Zulu": entry("z")])
        let ours = try write("ours", ["Alpha": entry("a"), "Mike": entry("m"), "Zulu": entry("z")])
        let theirs = try write("theirs", ["Alpha": entry("a"), "Bravo": entry("b"), "Zulu": entry("z")])
        let result = try merge(base, ours, theirs)
        XCTAssertEqual(result.status, 0, result.stderr)
        let text = try String(contentsOf: ours, encoding: .utf8)
        XCTAssertFalse(text.contains("<<<<<<<"))
        let strings = try XCTUnwrap((JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])?["strings"] as? [String: Any])
        XCTAssertEqual(Set(strings.keys), ["Alpha", "Bravo", "Mike", "Zulu"])
        let positions = ["Alpha", "Bravo", "Mike", "Zulu"].compactMap { text.range(of: "\"\($0)\"")?.lowerBound }
        XCTAssertEqual(positions, positions.sorted(), "keys stay in code point order")
    }

    func testDifferentTranslationsOfOneKeyStopTheMerge() throws {
        let base = try write("base", ["Alpha": entry("a"), "Save": entry("Salva")])
        let ours = try write("ours", ["Alpha": entry("a"), "Save": entry("Registra")])
        let theirs = try write("theirs", ["Alpha": entry("a"), "Save": entry("Conserva")])
        let before = try Data(contentsOf: ours)
        let result = try merge(base, ours, theirs)
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stderr.contains("Save"), result.stderr)
        XCTAssertEqual(try Data(contentsOf: ours), before, "a conflict leaves our file untouched")
    }
}
