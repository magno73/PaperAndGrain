import Foundation
import XCTest
@testable import PaperAndGrain

/// The String Catalog compiled as `build-app.sh` does, once per test run, in a temporary folder.
enum CompiledCatalog {
    static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static let directory: Result<URL, Error> = Result {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaperAndGrainCatalog-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["xcstringstool", "compile",
                             repository.appendingPathComponent("Resources/Localizable.xcstrings").path,
                             "--output-directory", output.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "xcstringstool failed"])
        }
        return output
    }

    /// Lookups read the compiled catalog, as in the app bundle.
    static func install() throws {
        L10n.useResources(at: try directory.get())
    }

    static func bundle(_ code: String) throws -> Bundle {
        try XCTUnwrap(Bundle(url: try directory.get().appendingPathComponent(code + ".lproj")))
    }
}

final class L10nTests: XCTestCase {
    override func setUpWithError() throws {
        try CompiledCatalog.install()
    }

    func testLanguageCodes() {
        XCTAssertTrue(L10n.isItalian("it"))
        XCTAssertTrue(L10n.isItalian("it-IT"))
        XCTAssertTrue(L10n.isItalian("IT"))
        XCTAssertFalse(L10n.isItalian("en"))
        XCTAssertEqual(L10n.code("fr"), "en")
        XCTAssertEqual(L10n.resolve("system", preferredLanguages: ["it-CH", "en"]), "it")
        XCTAssertEqual(L10n.resolve("system", preferredLanguages: ["de-DE"]), "en")
        XCTAssertEqual(L10n.resolve("system", preferredLanguages: []), "en")
        XCTAssertEqual(L10n.resolve("en", preferredLanguages: ["it"]), "en")
        XCTAssertEqual(L10n.resolve("it", preferredLanguages: ["en"]), "it")
    }

    func testLooksUpItalianAndEnglish() {
        XCTAssertEqual(L10n.string("Page", language: "it"), "Pagina")
        XCTAssertEqual(L10n.string("Page", language: "en"), "Page")
        XCTAssertEqual(L10n.string("Save Project", language: "it"), "Salva progetto")
    }

    func testMissingKeyFallsBackToTheKeyOrDefault() {
        XCTAssertEqual(L10n.string("No such string in the catalog", language: "it"), "No such string in the catalog")
        XCTAssertEqual(L10n.string("no.such.key", language: "it", default: "Fallback"), "Fallback")
    }

    func testExplicitKeysKeepTheirOwnItalian() {
        XCTAssertEqual(L10n.string("Square", language: "it"), "Square", "plain Square has no entry")
        XCTAssertEqual(L10n.string("photo.orientation.square", language: "it", default: "Square"), "Quadrata")
        XCTAssertEqual(L10n.string("format.shape.square", language: "it", default: "Square"), "Quadrati")
        XCTAssertEqual(L10n.string("format.shape.square", language: "en", default: "Square"), "Square")
        XCTAssertEqual(L10n.string("Landscape", language: "it"), "Orizzontale")
        XCTAssertEqual(BookFormatPreset.Shape.landscape.title("it"), "Orizzontali")
    }

    func testPluralsInBothLanguages() {
        XCTAssertEqual(L10n.format("%lld pages", language: "en", [1]), "1 page")
        XCTAssertEqual(L10n.format("%lld pages", language: "en", [2]), "2 pages")
        XCTAssertEqual(L10n.format("%lld pages", language: "it", [1]), "1 pagina")
        XCTAssertEqual(L10n.format("%lld pages", language: "it", [12]), "12 pagine")
        XCTAssertEqual(L10n.format("%lld selected", language: "it", [1]), "1 selezionata")
        XCTAssertEqual(L10n.format("%lld selected", language: "it", [3]), "3 selezionate")
    }

    func testFormatWithTwoArgumentsAndPluralSubstitutions() {
        XCTAssertEqual(L10n.format("%1$lld photos · %2$lld unused", language: "en", [1, 1]), "1 photo · 1 unused")
        XCTAssertEqual(L10n.format("%1$lld photos · %2$lld unused", language: "en", [5, 2]), "5 photos · 2 unused")
        XCTAssertEqual(L10n.format("%1$lld photos · %2$lld unused", language: "it", [5, 1]), "5 foto · 1 non usata")
        XCTAssertEqual(L10n.format("%1$lld photos · %2$lld unused", language: "it", [5, 2]), "5 foto · 2 non usate")
        XCTAssertEqual(L10n.format("Print: %1$@, below the recommended %2$lld ppi", language: "it", ["120 ppi", 300]),
                       "Stampa: 120 ppi, sotto i 300 ppi consigliati")
        XCTAssertEqual(L10n.format("Questions or problems: [%1$@](mailto:%1$@) · [Source on GitHub](%2$@)",
                                   language: "en", ["a@b.c", "https://x"]),
                       "Questions or problems: [a@b.c](mailto:a@b.c) · [Source on GitHub](https://x)")
    }

    func testWithoutTheCatalogEverythingIsEnglish() throws {
        L10n.useResources(at: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? CompiledCatalog.install() }
        XCTAssertEqual(L10n.string("Page", language: "it"), "Page")
        XCTAssertEqual(L10n.string("toolbar.hide_photo_library", language: "it", default: "Hide Photo Library"),
                       "Hide Photo Library")
        XCTAssertEqual(L10n.format("Print: %@", language: "it", ["300 ppi"]), "Print: 300 ppi")
    }

    func testViewHelpersUseTheChosenLanguage() {
        struct Probe: Localizing { let language: String }
        XCTAssertEqual(Probe(language: "it").tr("Cancel"), "Annulla")
        XCTAssertEqual(Probe(language: "en").tr("Cancel"), "Cancel")
        XCTAssertEqual(Probe(language: "it").tr("Hide Photo Library", key: "toolbar.hide_photo_library"),
                       "Nascondi la fototeca")
        XCTAssertEqual(Probe(language: "it").tr("Hide Photo Library"), "Nascondi fototeca")
        XCTAssertEqual(Probe(language: "it").tr("%lld pages", 2), "2 pagine")
        XCTAssertTrue(Probe(language: "it").isItalian)
    }

    /// Model names are passed as variables, so the key check in scripts/l10n-pairs.py cannot see them.
    func testEveryModelNameHasAnItalianEntry() throws {
        let italian = try CompiledCatalog.bundle("it")
        let missing = "\u{0}missing"
        var names = BookTemplate.allCases.flatMap { [$0.englishName, $0.description(language: "en")] }
        names += BookTemplate.Family.allCases.flatMap { [$0.title(language: "en"), $0.subtitle(language: "en")] }
        names += BookFormatPreset.all.map(\.note)
        names += BundledFilmLook.all.map(\.english)
        names += PageArrangement.allCases.map { PageArrangementPicker.name($0, language: "en") }
        names += PageLayout.allCases.map { PageArrangementPicker.automaticName($0, language: "en") }
        names += ["desert", "sand", "wildlife", "water", "town", "road", "people", "outdoors", "mountains", "sunset", "birds"]
            .map { PhotoAnalyzer.displayName(for: $0, language: "en") }
        for name in names {
            XCTAssertNotEqual(italian.localizedString(forKey: name, value: missing, table: nil), missing, name)
        }
        XCTAssertEqual(PhotoAnalyzer.displayName(for: "town", language: "it"), "Città")
        XCTAssertEqual(BookTemplate.swissGrid.name(language: "it"), "Griglia svizzera")
    }

    /// The CLI keeps Italian template names without the catalog; they must match it.
    func testCLITemplateNamesMatchTheCatalog() {
        for template in BookTemplate.allCases {
            XCTAssertEqual(BookCLI.italianTemplateNames[template], template.name(language: "it"), template.rawValue)
        }
    }

    func testPreflightMessagesInBothLanguages() {
        typealias Issue = BookPDF.PreflightIssue
        let overflow = Issue(location: .page(2), problem: .textOverflows)
        XCTAssertEqual(overflow.message(language: "en"), "p. 2 · Text overflows")
        XCTAssertEqual(overflow.message(language: "it"), "p. 2 · Il testo eccede lo spazio")
        let file = Issue(location: .cover, problem: .missingFile("lost.png"))
        XCTAssertEqual(file.message(language: "en"), "Cover · lost.png · Photo file missing")
        XCTAssertEqual(file.message(language: "it"), "Copertina · lost.png · File della foto mancante")
        let blanks = Issue(problem: .blankPages([1, 4]))
        XCTAssertEqual(blanks.message(language: "it"), "Pagine bianche di compensazione · 1, 4")
        let low = Issue(location: .page(1), problem: .lowResolution(photo: "a.png", ppi: 290, target: 300))
        XCTAssertEqual(low.message(language: "it"), "p. 1 · a.png · 290 ppi < 300 ppi")
        XCTAssertEqual(Issue(problem: .invalidDimensions).message(language: "it"), "Dimensioni non valide")
    }
}
