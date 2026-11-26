import CoreGraphics
import Foundation
import PDFKit
import XCTest
@testable import PaperAndGrain

/// Map pages (T14). Geography comes from `Tests/Fixtures/test-map.mapdata`, synthetic shapes written by
/// `scripts/make-map-data.py --fixture`: every name in it starts with TEST; it is not real geography.
final class MapTests: XCTestCase {
    private static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/test-map.mapdata")

    private func store() throws -> MapDataStore {
        let store = MapDataStore(url: Self.fixture)
        XCTAssertNotNil(store.geography())
        return store
    }

    /// Five places in Namibia, in capture order, the last two photos at the same place.
    private func namibia(placeNames: Bool = true) -> Book {
        let stops: [(String?, Double, Double)] = [
            ("Windhoek", -22.57, 17.08), (nil, -22.95, 14.52), ("Sossusvlei", -24.73, 15.29),
            ("Etosha", -18.86, 16.33), (nil, -17.78, 15.95), (nil, -17.7801, 15.9502),
        ]
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var photos: [BookPhoto] = []
        for (index, stop) in stops.enumerated() {
            var photo = BookPhoto(name: "p\(index)", filename: "p\(index).jpg", pixelWidth: 600, pixelHeight: 400)
            photo.capturedAt = start.addingTimeInterval(Double(index) * 86_400)
            photo.location = PhotoLocation(name: placeNames ? stop.0 : nil, latitude: stop.1, longitude: stop.2)
            photos.append(photo)
        }
        let pages = [BookPage(photoIDs: photos.map(\.id)), BookPage(layout: .gallery, arrangement: .map)]
        return Book(title: "Namibia", photos: photos, pages: pages, template: .diary)
    }

    // MARK: Data

    func testTheFixtureDecodes() throws {
        let world = try XCTUnwrap(try store().geography())
        XCTAssertEqual(world.land.count, 3)
        XCTAssertEqual(world.lakes.count, 1)
        XCTAssertEqual(world.borders.map(\.disputed), [false, true])
        XCTAssertEqual(world.places.map(\.name), ["TEST Capital", "TEST Coast", "TEST North", "TEST Island"])
        XCTAssertEqual(world.places[0].name(language: "it"), "TEST Capitale")
        XCTAssertEqual(world.places[2].name(language: "it"), "TEST North", "falls back to the name")
        XCTAssertEqual(world.places[0].coordinate.latitude, -22.57, accuracy: 0.0001)
        XCTAssertEqual(world.land[0].minLongitude, 11.7, accuracy: 0.0001)
        XCTAssertThrowsError(try MapGeography.decode(compressed: Data("not a map".utf8)))
        XCTAssertNil(MapDataStore(url: nil).geography())
    }

    // MARK: Geometry

    func testProjectionOfKnownCoordinates() {
        XCTAssertEqual(MapGeometry.mercatorY(0), 0, accuracy: 1e-9)
        XCTAssertEqual(MapGeometry.mercatorY(45), 50.4987, accuracy: 0.001)
        XCTAssertEqual(MapGeometry.mercatorY(-45), -50.4987, accuracy: 0.001)
        XCTAssertEqual(MapGeometry.mercatorY(85), MapGeometry.mercatorY(80), "limited to 80°")
        let region = MapGeometry.Region(minX: 10, maxX: 20, minY: MapGeometry.mercatorY(-30), maxY: MapGeometry.mercatorY(-20))
        let frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        let corner = region.point(MapCoordinate(longitude: 10, latitude: -20), in: frame)
        XCTAssertEqual(corner.x, 0, accuracy: 1e-9)
        XCTAssertEqual(corner.y, 0, accuracy: 1e-9, "north is up")
        XCTAssertEqual(region.point(MapCoordinate(longitude: 20, latitude: -30), in: frame).y, 100, accuracy: 1e-9)
    }

    func testRegionsForOnePlaceACountryAndAcrossTheDateLine() throws {
        let one = try XCTUnwrap(MapGeometry.region(for: [MapCoordinate(longitude: 17, latitude: -22)], aspect: 1.5))
        XCTAssertGreaterThanOrEqual(one.width, MapGeometry.minimumSpan)
        XCTAssertEqual(one.width / one.height, 1.5, accuracy: 1e-9)
        XCTAssertEqual((one.minX + one.maxX) / 2, 17, accuracy: 1e-9)

        let book = namibia()
        let stops = MapComposition.locatedPhotos(book, settings: PageMap()).map(\.coordinate)
        let country = try XCTUnwrap(MapGeometry.region(for: stops, aspect: 1))
        let frame = CGRect(x: 0, y: 0, width: 400, height: 400)
        for stop in stops {
            let point = country.point(stop, in: frame)
            XCTAssertTrue(frame.insetBy(dx: 30, dy: 30).contains(point), "padded: \(point)")
        }
        XCTAssertLessThan(country.width, 20)

        let pacific = [MapCoordinate(longitude: 178.5, latitude: -18), MapCoordinate(longitude: -179.2, latitude: -16.5)]
        let across = try XCTUnwrap(MapGeometry.region(for: pacific, aspect: 1))
        XCTAssertLessThan(across.width, 10, "the narrower window across 180°")
        XCTAssertNotNil(across.wrapStart)
        for place in pacific { XCTAssertTrue(frame.contains(across.point(place, in: frame))) }
        // Zoom halves the span around the same centre.
        let zoomed = try XCTUnwrap(MapGeometry.region(for: stops, aspect: 1, zoom: 2))
        XCTAssertEqual(zoomed.width, country.width / 2, accuracy: 1e-9)
    }

    func testNearbyPointsMerge() {
        let merged = MapGeometry.merge([CGPoint(x: 0, y: 0), CGPoint(x: 5, y: 0), CGPoint(x: 3, y: 1), CGPoint(x: 0, y: 2)],
                                       threshold: 4)
        XCTAssertEqual(merged.map(\.members), [[0, 2, 3], [1]])
        XCTAssertEqual(merged[0].point, .zero)
    }

    func testClipping() {
        let rect = CGRect(x: 0, y: 0, width: 10, height: 10)
        let square = [CGPoint(x: -5, y: -5), CGPoint(x: 5, y: -5), CGPoint(x: 5, y: 5), CGPoint(x: -5, y: 5)]
        let clipped = MapGeometry.clip(polygon: square, to: rect)
        XCTAssertEqual(clipped.map(\.x).min(), 0)
        XCTAssertEqual(clipped.map(\.y).max(), 5)
        XCTAssertTrue(MapGeometry.clip(polygon: square.map { CGPoint(x: $0.x + 40, y: $0.y) }, to: rect).isEmpty)
        let pieces = MapGeometry.clip(polyline: [CGPoint(x: -5, y: 5), CGPoint(x: 5, y: 5), CGPoint(x: 15, y: 5), CGPoint(x: 5, y: 8)],
                                      to: rect)
        XCTAssertEqual(pieces.count, 2)
        XCTAssertEqual(pieces[0], [CGPoint(x: 0, y: 5), CGPoint(x: 5, y: 5), CGPoint(x: 10, y: 5)])
    }

    func testLabelsAreDeterministicAndDoNotOverlap() {
        let dots = (0..<12).map { CGPoint(x: 40 + CGFloat($0 % 4) * 30, y: 40 + CGFloat($0 / 4) * 14) }
        let sizes: [CGSize?] = dots.indices.map { CGSize(width: 40 + CGFloat($0 * 3), height: 11) }
        let importance = dots.indices.map { $0 % 3 }
        let frame = CGRect(x: 0, y: 0, width: 260, height: 120)
        let first = MapGeometry.placeLabels(dots: dots, sizes: sizes, importance: importance, frame: frame, dotRadius: 2.4, gap: 3)
        XCTAssertEqual(first, MapGeometry.placeLabels(dots: dots, sizes: sizes, importance: importance, frame: frame,
                                                       dotRadius: 2.4, gap: 3))
        let placed = first.compactMap { $0 }
        XCTAssertFalse(placed.isEmpty)
        XCTAssertLessThan(placed.count, dots.count, "a crowded map drops the least important names")
        for (index, label) in placed.enumerated() {
            XCTAssertTrue(frame.contains(label))
            for other in placed.dropFirst(index + 1) { XCTAssertFalse(label.intersects(other)) }
            for dot in dots { XCTAssertFalse(label.contains(dot)) }
        }
    }

    // MARK: Composition

    func testAMapOfFivePlacesWithNamesAndARoute() throws {
        let store = try store()
        let book = namibia()
        let frame = CGRect(x: 40, y: 40, width: 500, height: 500)
        let map = MapComposition(page: book.pages[1], book: book, frame: frame, fillsTrim: false, language: "en", store: store)
        XCTAssertEqual(map.places.count, 5, "the last two photos are one place")
        XCTAssertEqual(map.places.last?.photoCount, 2)
        XCTAssertEqual(map.route.count, 5)
        XCTAssertFalse(map.geography?.land.isEmpty ?? true)
        // Names: the photos' place name, else the nearest town within 50 km, else none.
        XCTAssertEqual(map.places.map(\.suggestedName), ["Windhoek", "TEST Coast", "Sossusvlei", "Etosha", "TEST North"])
        let unnamed = namibia(placeNames: false)
        let italian = MapComposition(page: unnamed.pages[1], book: unnamed, frame: frame, fillsTrim: false,
                                     language: "it", store: store)
        XCTAssertEqual(italian.places.map(\.suggestedName), ["TEST Capitale", "TEST Costa", nil, nil, "TEST North"])
        // Author's names and hidden places.
        var page = book.pages[1]
        page.map = PageMap(showsRoute: false, labels: [MapLabel(key: map.places[0].key, name: "Home"),
                                                         MapLabel(key: map.places[2].key, hidden: true)])
        let edited = MapComposition(page: page, book: book, frame: frame, fillsTrim: false, language: "en", store: store)
        XCTAssertEqual(edited.places[0].name, "Home")
        XCTAssertNil(edited.places[2].name)
        XCTAssertNil(edited.places[2].label)
        XCTAssertTrue(edited.route.isEmpty)
        for place in map.places { XCTAssertTrue(frame.contains(place.point)) }
    }

    func testAMapWithoutLocatedPhotosIsABlocker() throws {
        var book = namibia()
        for index in book.photos.indices { book.photos[index].location = nil }
        let composition = PageComposition(page: book.pages[1], book: book)
        XCTAssertEqual(composition.map?.isEmpty, true)
        let report = BookPDF.preflight(book, directory: nil, profile: .print)
        let issue = try XCTUnwrap(report.blockers.first { $0.problem == .mapWithoutPlaces })
        XCTAssertEqual(issue.pageID, book.pages[1].id)
        // Only placed photos count by default; "all" reads the library.
        var library = namibia()
        library.pages[0].photoIDs = []
        XCTAssertTrue(MapComposition.locatedPhotos(library, settings: PageMap()).isEmpty)
        XCTAssertEqual(MapComposition.locatedPhotos(library, settings: PageMap(photos: .all)).count, 6)
    }

    func testMapPagesLayOut() throws {
        let book = namibia()
        let whole = PageComposition(page: book.pages[1], book: book)
        let map = try XCTUnwrap(whole.map)
        XCTAssertTrue(whole.photos.isEmpty)
        XCTAssertNil(whole.story)
        XCTAssertFalse(map.fillsTrim)
        var trim = book
        trim.template = .essential
        XCTAssertEqual(PageComposition(page: trim.pages[1], book: trim).map?.frame, PageComposition(page: trim.pages[1], book: trim).bounds)
        var above = book.pages[1]
        above.arrangement = .mapAboveText
        above.layout = .mixed
        above.text = "We drove north."
        let both = PageComposition(page: above, book: book)
        let mapFrame = try XCTUnwrap(both.map?.frame)
        let story = try XCTUnwrap(both.story)
        XCTAssertLessThan(mapFrame.maxY, story.minY)
        XCTAssertNil(PageComposition(page: book.pages[0], book: book).map)
    }

    // MARK: Saved books

    func testOnlyBooksWithAMapPageNeedTheNewWriterVersion() throws {
        let book = namibia()
        XCTAssertEqual(Workspace.writerVersion(for: book), 2)
        var plain = book
        plain.pages.removeLast()
        XCTAssertEqual(Workspace.writerVersion(for: plain), 1)
        XCTAssertEqual(Workspace.stamped(plain).writerVersion, 1)
        XCTAssertEqual(Workspace.stamped(book).writerVersion, 2)
        // A manifest this version cannot decode, from a newer writer, is "newer", not "damaged".
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(#"{"id":"\#(UUID())","title":"Future","pages":[{"id":"\#(UUID())","layout":"globe"}],"photos":[],"writerVersion":99}"#.utf8)
            .write(to: root.appendingPathComponent("manifest.json"))
        XCTAssertThrowsError(try BookStorage.read(from: root)) { error in
            guard case AppError.newerFormat(let title)? = error as? AppError else { return XCTFail("\(error)") }
            XCTAssertEqual(title, "Future")
        }
        // A 0.10 manifest has no map field.
        let decoded = try JSONDecoder().decode(Book.self, from: JSONEncoder().encode(plain))
        XCTAssertNil(decoded.pages[0].map)
    }

    // MARK: PDF and command line

    func testTheMapPrintsAsVectorsAndTheCommandLineBuildsIt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let spec = root.appendingPathComponent("spec.json")
        try Data("""
        {"version":1,"title":"Map","template":"nocturne","assets":[],
         "pages":[{"arrangement":"map","map":{"showsBorders":false,"zoom":1.2,"labels":[{"key":"0.00,0.00","hidden":true}]}},
                  {"layout":"gallery"}]}
        """.utf8).write(to: spec)
        let project = root.appendingPathComponent("Map.papergrain")
        _ = try BookCLI.execute(["build", spec.path, project.path])
        var book = try BookStorage.read(from: project)
        XCTAssertEqual(book.writerVersion, 2)
        XCTAssertEqual(book.pages[0].arrangement, .map)
        XCTAssertEqual(book.pages[0].map?.countryBorders, false)
        XCTAssertEqual(book.pages[0].map?.resolvedZoom, 1.2)
        // Locate three library photos; the map counts all of them.
        let located = namibia()
        book.photos = Array(located.photos.prefix(3))
        book.pages[0].map?.photos = .all
        let pdfURL = root.appendingPathComponent("Map.pdf")
        try BookPDF.write(book, directory: project, to: pdfURL)
        let pdf = try XCTUnwrap(PDFDocument(url: pdfURL))
        let text = try XCTUnwrap(pdf.page(at: 0)?.string)
        XCTAssertTrue(text.contains("Windhoek") && text.contains("Sossusvlei"))
        let size = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: pdfURL.path)[.size] as? Int)
        XCTAssertLessThan(size, 300_000)
        XCTAssertFalse(try Data(contentsOf: pdfURL).range(of: Data("/Subtype /Image".utf8)) != nil, "no image on a map page")
        let bad = root.appendingPathComponent("bad.json")
        try Data(#"{"version":1,"title":"M","assets":[],"pages":[{"arrangement":"map","map":{"zoom":20}}]}"#.utf8).write(to: bad)
        XCTAssertThrowsError(try BookCLI.execute(["build", bad.path, root.appendingPathComponent("B.papergrain").path]))
    }
}
