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
        XCTAssertThrowsError(try MapGeography.decode(file: Data("not a map".utf8)))
        XCTAssertNil(MapDataStore(url: nil).geography())
    }

    /// Damaged data is refused, never a crash: the frame's CRC catches changed bytes, and the decoder checks
    /// every count, coordinate and length of a payload that passes it.
    func testDamagedMapDataIsRefused() throws {
        let files = [try Data(contentsOf: Self.fixture), try Data(contentsOf: try XCTUnwrap(MapDataStore.bundledURL))]
        var random = SystemRandomNumberGenerator()
        for file in files {
            XCTAssertNoThrow(try MapGeography.decode(file: file))
            for _ in 0..<200 {
                var bytes = [UInt8](file)
                for _ in 0..<Int.random(in: 1...3, using: &random) {
                    let index = Int.random(in: 0..<bytes.count, using: &random)
                    bytes[index] ^= UInt8.random(in: 1...255, using: &random)
                }
                XCTAssertThrowsError(try MapGeography.decode(file: Data(bytes)))
            }
            XCTAssertThrowsError(try MapGeography.decode(file: file.prefix(file.count - 1)))
        }
        // Corruptions behind a valid frame, straight into the decoder.
        let payload = try (Data(try Data(contentsOf: Self.fixture)[12...]) as NSData).decompressed(using: .zlib) as Data
        XCTAssertNoThrow(try MapGeography.decode(payload: payload))
        for _ in 0..<3_000 {
            var bytes = [UInt8](payload)
            for _ in 0..<Int.random(in: 1...3, using: &random) {
                let index = Int.random(in: 6..<bytes.count, using: &random)
                bytes[index] = UInt8.random(in: 0...255, using: &random)
            }
            _ = try? MapGeography.decode(payload: Data(bytes))
        }
        // A delta that would overflow, and a point off the globe.
        var overflow = Array("PGMAP".utf8) + [1]
        func u32(_ value: UInt32) -> [UInt8] { (0..<4).map { UInt8((value >> (8 * $0)) & 0xFF) } }
        overflow += u32(1) + u32(2) + u32(0) + u32(0) + [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01, 0x00]
        overflow += u32(0) + u32(0) + u32(0)
        XCTAssertThrowsError(try MapGeography.decode(payload: Data(overflow)))
        var offGlobe = Array("PGMAP".utf8) + [1] + u32(1) + u32(1) + u32(2_000_000) + u32(0) + u32(0) + u32(0) + u32(0)
        XCTAssertThrowsError(try MapGeography.decode(payload: Data(offGlobe))) { XCTAssertEqual($0 as? MapGeography.FormatError, .outOfRange) }
        offGlobe = Array("PGMAP".utf8) + [1] + u32(UInt32.max)
        XCTAssertThrowsError(try MapGeography.decode(payload: Data(offGlobe)))
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
            for dot in dots {
                XCTAssertFalse(label.intersects(CGRect(x: dot.x - 2.4, y: dot.y - 2.4, width: 4.8, height: 4.8)))
            }
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
        // A hidden place is gone: no dot, no name; it stays listed for the Page tab.
        XCTAssertEqual(edited.places.count, 4)
        XCTAssertFalse(edited.places.contains { $0.key == map.places[2].key })
        XCTAssertEqual(edited.hiddenPlaces.map(\.suggestedName), ["Sossusvlei"])
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

    /// 0.10's page model: its arrangements, no map field. Unknown keys are ignored, as by `Codable`.
    private struct OldBook: Decodable {
        enum OldArrangement: String, Decodable {
            case fullBleed, fullSpread, bleedTwoAcross, bleedTwoStacked, bleedThreeAcross, bleedFourGrid, bleedHeroAboveTwo
            case twoAcross, twoStacked, fourGrid, heroAboveTwo, twoAboveHero
            case textAbovePhoto, photoAboveText, textBesidePhoto, textOverPhoto, textOnly
        }
        struct OldPage: Decodable {
            var id: UUID
            var layout: PageLayout
            var photoIDs: [UUID]
            var text: String
            var heading: String?
            var arrangement: OldArrangement?
        }
        var title: String
        var pages: [OldPage]
        var writerVersion: Int?
    }

    func testABookWithMapPagesDecodesIn010AndReadsAsNewer() throws {
        var book = Workspace.stamped(namibia())
        var above = BookPage(layout: .mixed, text: "North.", arrangement: .mapAboveText)
        above.map = PageMap(showsRoute: false, labels: [MapLabel(key: "-22.57,17.08", name: "Home")])
        book.pages.append(above)
        let data = try JSONEncoder().encode(book)
        // 0.10 decodes it: a text page with a field it ignores, written by version 2, which it opens as newer.
        let old = try JSONDecoder().decode(OldBook.self, from: data)
        XCTAssertEqual(old.writerVersion, 2)
        XCTAssertEqual(old.pages[1].arrangement, .textOnly)
        XCTAssertEqual(old.pages[1].layout, .text)
        XCTAssertEqual(old.pages[2].arrangement, .textOnly)
        XCTAssertEqual(old.pages[2].text, "North.")
        // 0.11 reads the same pages back as maps, unchanged.
        let again = try JSONDecoder().decode(Book.self, from: data)
        XCTAssertEqual(again, book)
        XCTAssertEqual(again.pages[1].arrangement, .map)
        XCTAssertEqual(again.pages[2].arrangement, .mapAboveText)
        XCTAssertEqual(again.pages[2].map?.label("-22.57,17.08")?.name, "Home")
        XCTAssertNil(again.pages[2].map?.layout, "the saved layout lives only in the manifest")
        // Other pages are coded as before: a text page without a map stays a text page.
        let text = BookPage(layout: .text, text: "Only words", arrangement: .textOnly)
        XCTAssertEqual(try JSONDecoder().decode(BookPage.self, from: JSONEncoder().encode(text)), text)
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(text), encoding: .utf8))
        XCTAssertFalse(json.contains("map"))
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
        // The halo is drawn from glyph outlines: each name is in the text once.
        XCTAssertEqual(text.components(separatedBy: "Windhoek").count - 1, 1)
        XCTAssertEqual(text.components(separatedBy: "Sossusvlei").count - 1, 1)
        let size = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: pdfURL.path)[.size] as? Int)
        XCTAssertLessThan(size, 300_000)
        XCTAssertFalse(try Data(contentsOf: pdfURL).range(of: Data("/Subtype /Image".utf8)) != nil, "no image on a map page")
        let bad = root.appendingPathComponent("bad.json")
        try Data(#"{"version":1,"title":"M","assets":[],"pages":[{"arrangement":"map","map":{"zoom":20}}]}"#.utf8).write(to: bad)
        XCTAssertThrowsError(try BookCLI.execute(["build", bad.path, root.appendingPathComponent("B.papergrain").path]))
    }

    func testAMapPagePrintsInCMYKAfterTheEditorComposedIt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var book = namibia()
        book.template = .nocturne
        book.pages = [book.pages[1]]
        book.pages[0].map = PageMap(photos: .all)
        book.printSettings = PrintSettings()
        // The editor composes the page first, without a print converter.
        XCTAssertFalse(PageComposition(page: book.pages[0], book: book).map?.places.isEmpty ?? true)
        let profile = URL(fileURLWithPath: "/System/Library/ColorSync/Profiles/Generic CMYK Profile.icc")
        let converter = try PrintColor.converter(for: Data(contentsOf: profile))
        let output = root.appendingPathComponent("Press")
        try BookPDF.writePrint(book, directory: root, to: output, color: .cmyk(converter))
        let pdf = output.appendingPathComponent("Interior.pdf")
        XCTAssertFalse(String(decoding: try Data(contentsOf: pdf), as: UTF8.self).contains("DeviceRGB"))
        let document = try XCTUnwrap(CGPDFDocument(pdf as CFURL))
        for index in 1...document.numberOfPages {
            let page = try XCTUnwrap(document.page(at: index))
            final class Recorder { var operands = [[Double]]() }
            for name in ["sc", "scn", "rg", "RG", "SC", "SCN"] {
                let recorder = Recorder()
                let table = CGPDFOperatorTableCreate()!
                CGPDFOperatorTableSetCallback(table, name) { scanner, info in
                    guard let info else { return }
                    var values = [Double](), number: CGPDFReal = 0
                    while CGPDFScannerPopNumber(scanner, &number) { values.append(Double(number)) }
                    Unmanaged<Recorder>.fromOpaque(info).takeUnretainedValue().operands.append(values)
                }
                let stream = CGPDFContentStreamCreateWithPage(page)
                let scanner = CGPDFScannerCreate(stream, table, Unmanaged.passUnretained(recorder).toOpaque())
                CGPDFScannerScan(scanner)
                CGPDFScannerRelease(scanner)
                CGPDFContentStreamRelease(stream)
                CGPDFOperatorTableRelease(table)
                for operands in recorder.operands {
                    XCTAssertNotEqual(operands.count, 3, "page \(index): an RGB color with \(name)")
                }
                if name == "rg" || name == "RG" { XCTAssertTrue(recorder.operands.isEmpty) }
            }
        }
        // And the canvas afterwards still gets RGB colors, not the print's.
        let after = try XCTUnwrap(PageComposition(page: book.pages[0], book: book).map?.places.first?.label)
        let color = after.attribute(NSAttributedString.Key(kCTForegroundColorAttributeName as String), at: 0, effectiveRange: nil)
        XCTAssertEqual((color as! CGColor).numberOfComponents, 4, "sRGB: three components and alpha")
        XCTAssertNotEqual((color as! CGColor).colorSpace?.model, .cmyk)
    }

    func testTheCommandLineKeepsMapsAndVersionsConsistent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let spec = root.appendingPathComponent("spec.json")
        try Data(#"{"version":1,"title":"T","assets":[],"pages":[{"arrangement":"textOnly","layout":"text","map":{}}]}"#.utf8).write(to: spec)
        XCTAssertThrowsError(try BookCLI.execute(["build", spec.path, root.appendingPathComponent("A.papergrain").path]))
        try Data(#"{"version":1,"title":"T","assets":[],"pages":[{"arrangement":"map"},{"layout":"gallery"}]}"#.utf8).write(to: spec)
        let map = root.appendingPathComponent("Map.papergrain")
        _ = try BookCLI.execute(["build", spec.path, map.path])
        XCTAssertEqual(try BookStorage.read(from: map).writerVersion, 2)
        // Removing the last map page brings the version back to 1.
        let patch = root.appendingPathComponent("patch.json")
        try Data(#"[{"op":"remove","path":"/pages/0"}]"#.utf8).write(to: patch)
        let plain = root.appendingPathComponent("Plain.papergrain")
        XCTAssertEqual(try BookCLIEditing.patch(source: map, patchURL: patch, output: plain).writerVersion, 1)
        XCTAssertEqual(try BookStorage.read(from: plain).writerVersion, 1)
        // The zoom slider's doubling scale lands on round values inside the model's range.
        XCTAssertEqual(MapZoomSlider.zoom(atStep: 0), 1)
        XCTAssertEqual(MapZoomSlider.zoom(atStep: 3.2), PageMap.zoomRange.upperBound)
        XCTAssertEqual(MapZoomSlider.zoom(atStep: -3), PageMap.zoomRange.lowerBound)
    }

    /// Books made before locations were saved on import: coordinates read later are kept in the book,
    /// a place name already there survives, and photos that already have coordinates are untouched.
    func testReadLocationsAreAdoptedWhereTheBookHasNone() {
        var named = BookPhoto(name: "a", filename: "a.jpg", pixelWidth: 10, pixelHeight: 10)
        named.location = PhotoLocation(name: "Sossusvlei")
        let bare = BookPhoto(name: "b", filename: "b.jpg", pixelWidth: 10, pixelHeight: 10)
        var placed = BookPhoto(name: "c", filename: "c.jpg", pixelWidth: 10, pixelHeight: 10)
        placed.location = PhotoLocation(latitude: -22.9, longitude: 14.5)
        let read: [UUID: PhotoLocation] = [
            named.id: PhotoLocation(latitude: -24.7, longitude: 15.3),
            bare.id: PhotoLocation(name: "Windhoek", latitude: -22.56, longitude: 17.08),
            placed.id: PhotoLocation(latitude: 0, longitude: 0)
        ]
        let photos = Book.photosAdopting(read, in: [named, bare, placed])
        XCTAssertEqual(photos?[0].location, PhotoLocation(name: "Sossusvlei", latitude: -24.7, longitude: 15.3))
        XCTAssertEqual(photos?[1].location, PhotoLocation(name: "Windhoek", latitude: -22.56, longitude: 17.08))
        XCTAssertEqual(photos?[2].location, placed.location)
        XCTAssertNil(Book.photosAdopting([:], in: [named, bare, placed]))
    }

    func testAHiddenPlaceLeavesTheMapAndTheFit() throws {
        let store = try store()
        // Departure photos in Milan and Munich, then the trip in Namibia.
        var book = namibia()
        var milano = BookPhoto(name: "m", filename: "m.jpg", pixelWidth: 10, pixelHeight: 10)
        milano.location = PhotoLocation(name: "Milano", latitude: 45.46, longitude: 9.19)
        milano.capturedAt = Date(timeIntervalSince1970: 1_600_000_000)
        var monaco = BookPhoto(name: "b", filename: "b.jpg", pixelWidth: 10, pixelHeight: 10)
        monaco.location = PhotoLocation(name: "Monaco di Baviera", latitude: 48.14, longitude: 11.58)
        monaco.capturedAt = Date(timeIntervalSince1970: 1_600_000_100)
        book.photos += [milano, monaco]
        book.pages[0].photoIDs += [milano.id, monaco.id]
        let frame = CGRect(x: 40, y: 40, width: 500, height: 500)
        let wide = MapComposition(page: book.pages[1], book: book, frame: frame, fillsTrim: false, language: "en", store: store)
        XCTAssertEqual(wide.places.count, 7 - 2 - 1, "Europe and Africa: Namibia's nearby places merge")
        XCTAssertGreaterThan(try XCTUnwrap(wide.region).height, 40)
        // Hiding Milan and Munich: no dot, no name, off the route, out of the fit.
        let keys = wide.places.filter { $0.name == "Milano" || $0.name == "Monaco di Baviera" }.map(\.key)
        XCTAssertEqual(keys.count, 2)
        var page = book.pages[1]
        page.map = PageMap(labels: keys.map { MapLabel(key: $0, hidden: true) })
        let trip = MapComposition(page: page, book: book, frame: frame, fillsTrim: false, language: "en", store: store)
        XCTAssertEqual(trip.places.count, 5)
        XCTAssertFalse(trip.places.contains { $0.name == "Milano" || $0.name == "Monaco di Baviera" })
        XCTAssertEqual(Set(trip.hiddenPlaces.map(\.suggestedName)), ["Milano", "Monaco di Baviera"])
        XCTAssertEqual(trip.route.count, 5)
        XCTAssertLessThan(try XCTUnwrap(trip.region).width, 20, "fitted to Namibia")
        for place in trip.places { XCTAssertTrue(frame.contains(place.point)) }
        // Every place hidden: the map still shows its land, with no dot, and it is not "without places".
        page.map = PageMap(labels: (keys + trip.places.map(\.key)).map { MapLabel(key: $0, hidden: true) })
        let none = MapComposition(page: page, book: book, frame: frame, fillsTrim: false, language: "en", store: store)
        XCTAssertTrue(none.places.isEmpty)
        XCTAssertFalse(none.isEmpty)
        XCTAssertNotNil(none.region)
    }

    func testFramingIsIndependentOfTheShownSizeAndTownsReachFurtherOnWideMaps() throws {
        let store = try store()
        let book = namibia()
        var page = book.pages[1]
        page.map = PageMap(zoom: 1.5, centerOffset: MapOffset(x: 0.2, y: -0.1))
        // The canvas at any zoom, the thumbnails and the PDF compose the same page in page points.
        let page1 = MapComposition(page: page, book: book, frame: CGRect(x: 0, y: 0, width: 400, height: 300),
                                   fillsTrim: false, store: store)
        let page2 = MapComposition(page: page, book: book, frame: CGRect(x: 10, y: 10, width: 800, height: 600),
                                   fillsTrim: false, store: store)
        XCTAssertEqual(try XCTUnwrap(page1.region), try XCTUnwrap(page2.region))
        // A drag moves the map with the pointer: a whole width at 200 % is half the fitted span.
        let moved = MapGeometry.panned(MapOffset(x: 0, y: 0), by: CGSize(width: -400, height: 150),
                                       shownSize: CGSize(width: 400, height: 300), zoom: 2)
        XCTAssertEqual(moved.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(moved.y, -0.25, accuracy: 1e-9)
        XCTAssertEqual(MapGeometry.panned(MapOffset(x: 1.9, y: 0), by: CGSize(width: -400, height: 0),
                                          shownSize: CGSize(width: 400, height: 300), zoom: 1).x, 2, "limited")
        // Names: 50 km on a regional map, up to 150 km on a wide one.
        let regional = try XCTUnwrap(MapGeometry.region(for: [MapCoordinate(longitude: 17, latitude: -22)], aspect: 1))
        XCTAssertEqual(MapComposition.labelReach(for: regional), 50)
        let world = try XCTUnwrap(MapGeometry.region(for: [MapCoordinate(longitude: 9, latitude: 45),
                                                           MapCoordinate(longitude: 17, latitude: -22)], aspect: 1))
        XCTAssertEqual(MapComposition.labelReach(for: world), 150)
        let place = try XCTUnwrap(store.geography()?.places.first)
        let nearby = MapCoordinate(longitude: place.coordinate.longitude + 1, latitude: place.coordinate.latitude)
        XCTAssertNil(MapComposition.nearestTown(to: nearby, in: try XCTUnwrap(store.geography()), language: "en"))
        XCTAssertEqual(MapComposition.nearestTown(to: nearby, in: try XCTUnwrap(store.geography()), language: "en", within: 150),
                       place.name)
    }
}
