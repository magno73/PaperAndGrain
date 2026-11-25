import CoreGraphics
import XCTest
@testable import PaperAndGrain

/// B11: story matching must prefer real subjects over common words read in a photo.
final class PrintReleaseTestsStoryMatching: XCTestCase {
    private func sign(_ text: String) -> PhotoAnalysis {
        PhotoAnalysis(labels: ["sign"], concepts: [], revision: PhotoAnalysis.currentRevision,
                      classifications: [PhotoClassification(label: "sign", confidence: 0.4)],
                      recognizedText: [PhotoText(text: text, confidence: 0.95, box: PhotoBox(.zero))])
    }

    private let elephant = PhotoAnalysis(labels: ["elephant", "savanna"], concepts: ["wildlife", "outdoors"],
                                         revision: PhotoAnalysis.currentRevision,
                                         classifications: [PhotoClassification(label: "elephant", confidence: 0.8),
                                                           PhotoClassification(label: "savanna", confidence: 0.5)])

    /// Every match must be explainable: its value appears in the story, directly or through a listed term.
    private func assertExplainable(_ matches: [PhotoMatchEvidence], story: String, file: StaticString = #filePath,
                                   line: UInt = #line) {
        let words = Set(story.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted))
        for match in matches where match.source == "text" {
            XCTAssertTrue(words.contains(match.value), "\(match.value) is not in the story", file: file, line: line)
            XCTAssertGreaterThanOrEqual(match.value.count, 4, file: file, line: line)
        }
    }

    func testItalianStoryPrefersTheSubjectOverCommonWordsOnASign() {
        let story = "Non siamo entrati nel parco, ma non importa: abbiamo visto gli elefanti all’aperto."
        let warning = sign("NON ENTRARE")
        XCTAssertEqual(PhotoAnalyzer.matches(warning, for: story), [])
        let found = PhotoAnalyzer.matches(elephant, for: story)
        XCTAssertEqual(Set(found.map(\.value)), ["elephant", "outdoors"])
        XCTAssertGreaterThan(PhotoAnalyzer.score(elephant, for: story), PhotoAnalyzer.score(warning, for: story))
        assertExplainable(found, story: story)

        // "aperto" alone (an open restaurant) is not the outdoors; "all'aperto" is.
        XCTAssertFalse(PhotoAnalyzer.matches(elephant, for: "Il ristorante era aperto fino a tardi").contains {
            $0.value == "outdoors"
        })
        // A real word read on a sign still counts, and is shown as text evidence next to the subject.
        let entrance = PhotoAnalyzer.matches(warning, for: "Il cartello diceva di non entrare nel recinto")
        XCTAssertEqual(Set(entrance.map(\.value)), ["entrare", "sign"])
        assertExplainable(entrance, story: "Il cartello diceva di non entrare nel recinto")
    }

    func testEnglishStoryIgnoresStopWordsAndKeepsRealWords() {
        let story = "This was the road to Windhoek, with nothing but dust for hours."
        let board = sign("THIS WAY TO WINDHOEK WITH CARE")
        let found = PhotoAnalyzer.matches(board, for: story)
        XCTAssertEqual(found.map(\.value), ["windhoek"])
        XCTAssertEqual(found.first?.source, "text")
        assertExplainable(found, story: story)
        let elephants = PhotoAnalyzer.matches(elephant, for: "Two elephants crossed the savanna at dawn")
        XCTAssertEqual(Set(elephants.map(\.value)), ["elephant", "savanna", "outdoors"])
        XCTAssertGreaterThan(PhotoAnalyzer.score(elephant, for: story + " Elephants"), PhotoAnalyzer.score(board, for: "this"))
    }

    func testStoryWithoutMatchesFindsNothing() {
        let story = "Cena al ristorante, poi una lunga chiacchierata fino a tardi. Dinner, then a long talk."
        for analysis in [sign("NON ENTRARE"), sign("THIS WAY"), sign("CENA"), elephant] {
            XCTAssertEqual(PhotoAnalyzer.matches(analysis, for: story).filter { $0.value != "cena" }, [])
        }
        // A four-letter word read on a sign is a real, explainable match.
        XCTAssertEqual(PhotoAnalyzer.matches(sign("CENA"), for: story).map(\.value), ["cena"])
    }
}
