import XCTest
@testable import PaperAndGrain

final class InspectorPhotoLibraryCacheTests: XCTestCase {
    func testResultsRefreshWhenPhotoMetadataChangesWithoutChangingID() {
        let cache = InspectorPhotoLibraryCache()
        var photo = BookPhoto(name: "Dune", filename: "dune.jpg", pixelWidth: 100, pixelHeight: 100)

        let empty = cache.results(photos: [photo], language: "en", search: "desert", concept: "desert")
        XCTAssertTrue(empty.photos.isEmpty)
        XCTAssertTrue(empty.concepts.isEmpty)

        photo.analysis = PhotoAnalysis(labels: ["dune"], concepts: ["desert", "desert"])
        let analyzed = cache.results(photos: [photo], language: "en", search: "desert", concept: "desert")
        XCTAssertEqual(analyzed.photos, [photo])
        XCTAssertEqual(analyzed.concepts.map(\.count), [1])

        photo.analysis = nil
        let cleared = cache.results(photos: [photo], language: "en", search: "desert", concept: "desert")
        XCTAssertTrue(cleared.photos.isEmpty)
        XCTAssertTrue(cleared.concepts.isEmpty)
    }

    func testSearchRefreshesForLanguageAndPhotoOrder() throws {
        try CompiledCatalog.install()
        var first = BookPhoto(name: "Town", filename: "town.jpg", pixelWidth: 100, pixelHeight: 100)
        first.analysis = PhotoAnalysis(labels: ["Street"], concepts: ["town"])
        var second = BookPhoto(name: "Città", filename: "citta.jpg", pixelWidth: 100, pixelHeight: 100)
        second.analysis = PhotoAnalysis(labels: ["Street"], concepts: ["town"])
        let cache = InspectorPhotoLibraryCache()

        let english = cache.results(photos: [first, second], language: "en", search: "citta", concept: nil)
        XCTAssertEqual(english.photos, [second])
        XCTAssertEqual(english.concepts.map(\.name), ["Town"])

        let italian = cache.results(photos: [first, second], language: "it", search: "citta", concept: nil)
        XCTAssertEqual(italian.photos, [first, second])
        XCTAssertEqual(italian.concepts.map(\.name), ["Città"])

        let reordered = cache.results(photos: [second, first], language: "it", search: "street", concept: "town")
        XCTAssertEqual(reordered.photos, [second, first])
        let unfiltered = cache.results(photos: [second], language: "it", search: "", concept: nil)
        XCTAssertEqual(unfiltered.photos, [second])
        XCTAssertEqual(unfiltered.concepts.map(\.count), [1])
    }
}
