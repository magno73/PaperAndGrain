import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import PaperAndGrain

final class PageArrangementTests: XCTestCase {
    func testEveryArrangementRespectsItsCapacityAndMarginsInEachFormat() throws {
        XCTAssertEqual(PageArrangement.allCases.count, 11)
        for format in [BookFormat.square, .portrait, .landscape] {
            let bounds = CGRect(origin: CGPoint(x: 12, y: 22), size: format.pageSize)
            let safe = bounds.insetBy(dx: 30, dy: 30)
            for arrangement in PageArrangement.allCases {
                let geometry = arrangement.geometry(in: bounds, inside: safe, gap: 10)
                XCTAssertEqual(geometry.photos.count, arrangement.photoCapacity)
                let isEdgeToEdge = arrangement == .fullBleed || arrangement == .textOverPhoto
                let margins = isEdgeToEdge ? bounds : safe
                for (index, photo) in geometry.photos.enumerated() {
                    XCTAssertTrue(margins.insetBy(dx: -0.001, dy: -0.001).contains(photo))
                    XCTAssertGreaterThan(min(photo.width, photo.height), 0)
                    for other in geometry.photos.dropFirst(index + 1) {
                        XCTAssertFalse(photo.intersects(other))
                    }
                }
                if isEdgeToEdge { XCTAssertEqual(geometry.photos, [bounds]) }
                XCTAssertEqual(geometry.story != nil, arrangement.layout == .text || arrangement.layout == .mixed)
                if let story = geometry.story {
                    XCTAssertTrue(safe.insetBy(dx: -0.001, dy: -0.001).contains(story))
                    if arrangement == .textOverPhoto {
                        let panel = try XCTUnwrap(geometry.storyBackground)
                        XCTAssertTrue(safe.contains(panel))
                        XCTAssertTrue(panel.contains(story))
                        XCTAssertGreaterThan(story.minX, panel.minX)
                    } else {
                        XCTAssertNil(geometry.storyBackground)
                        XCTAssertFalse(geometry.photos.contains(where: { $0.intersects(story) }))
                    }
                }
            }

            func geometry(_ kind: PageArrangement) -> PageArrangement.Geometry {
                kind.geometry(in: bounds, inside: safe, gap: 10)
            }
            let above = geometry(.heroAboveTwo).photos
            XCTAssertEqual(above[0].width, safe.width, accuracy: 0.0001)
            XCTAssertGreaterThan(above[0].height, above[1].height)
            XCTAssertEqual(above[1].minY - above[0].maxY, 10, accuracy: 0.0001)
            XCTAssertEqual(above[2].minX - above[1].maxX, 10, accuracy: 0.0001)
            let below = geometry(.twoAboveHero).photos
            XCTAssertGreaterThan(below[2].height, below[0].height)
            XCTAssertLessThan(below[0].minX, below[1].minX)
            let opening = geometry(.textAbovePhoto)
            XCTAssertLessThan(try XCTUnwrap(opening.story).maxY, opening.photos[0].minY)
            let closing = geometry(.photoAboveText)
            XCTAssertLessThan(closing.photos[0].maxY, try XCTUnwrap(closing.story).minY)
        }
    }

    func testPresetSlotsRemainBoundToPhotoOrderWhenAnExistingFrameMoves() throws {
        let photos = (0..<5).map { i in
            BookPhoto(name: "Photo \(i)", filename: "p\(i).png", pixelWidth: 40 + i * 7, pixelHeight: 30)
        }
        let ids = photos.map(\.id)
        let crop = PhotoCrop(x: 0.2, y: 0.8, zoom: 1.7)
        let moved = PageRect(x: 0.38, y: 0.05, width: 0.3, height: 0.15)
        var page = BookPage(layout: .gallery, photoIDs: ids, text: "Keep my story", heading: "Keep my heading",
                            photoPlacements: [ids[0]: PhotoPlacement(frame: moved, crop: crop)], arrangement: .fourGrid)
        let book = Book(title: "Slots", photos: photos, pages: [page])
        let layout = PageComposition(page: page, book: book)
        let safe = layout.bounds.insetBy(dx: book.contentInsetPoints, dy: book.contentInsetPoints)
        let slots = PageArrangement.fourGrid.geometry(in: layout.bounds, inside: safe, gap: book.editorialStyle.imageGap)
        XCTAssertEqual(layout.photos.map(\.id), Array(ids.prefix(4)))
        XCTAssertEqual(layout.photos[0].frame, moved.photoRect(in: layout.bounds))
        XCTAssertEqual(layout.photos[0].crop, crop)
        XCTAssertEqual(layout.photos[1].frame, slots.photos[1])
        XCTAssertTrue(layout.photos.allSatisfy(\.fills))
        let incomplete = PageComposition(page: page, book: book, photoForID: { $0 == ids[1] ? nil : book.photo($0) })
        XCTAssertEqual(incomplete.photos.first(where: { $0.id == ids[2] })?.frame, slots.photos[2])
        page.photoPlacements?[ids[4]] = PhotoPlacement(frame: moved)
        XCTAssertEqual(PageComposition(page: page, book: book).photos.map(\.id), ids)
        let encoded = try JSONEncoder().encode(page)
        XCTAssertEqual(try JSONDecoder().decode(BookPage.self, from: encoded), page)
        page.arrangement = nil
        let legacy = try JSONEncoder().encode(page)
        let dictionary = try XCTUnwrap(JSONSerialization.jsonObject(with: legacy) as? [String: Any])
        XCTAssertNil(dictionary["arrangement"])
        let reopened = try JSONDecoder().decode(BookPage.self, from: legacy)
        XCTAssertEqual(reopened.photoIDs, ids)
        XCTAssertEqual(reopened.heading, "Keep my heading")
        XCTAssertEqual(reopened.text, "Keep my story")
        XCTAssertNil(PageComposition(page: reopened, book: book).storyBackground)
    }

    func testOverlayPrintsItsBackingAtTheSharedPositionAndKeepsEditableType() throws {
        let project = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: project) }
        let photo = BookPhoto(name: "Blue field", filename: "blue.png", pixelWidth: 32, pixelHeight: 32)
        let page = BookPage(layout: .mixed, photoIDs: [photo.id], text: "Overlay caption", arrangement: .textOverPhoto)
        var book = Book(title: "Overlap", photos: [photo], pages: [page])
        book.template = .atlas
        try BookStorage.write(book, to: project)
        let source = try context(width: 32, height: 32)
        source.setFillColor(red: 0.08, green: 0.20, blue: 0.64, alpha: 1)
        source.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        let asset = BookStorage.assetURL(filename: photo.filename, in: project)
        let encoder = try XCTUnwrap(CGImageDestinationCreateWithURL(asset as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(encoder, try XCTUnwrap(source.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(encoder))
        let composition = PageComposition(page: page, book: book, bleed: 8)
        XCTAssertEqual(composition.photos[0].frame, composition.bounds.insetBy(dx: -8, dy: -8))
        XCTAssertNil(composition.folio)
        var blank = page
        blank.text = "  "
        XCTAssertNil(PageComposition(page: blank, book: book).storyBackground)
        blank.heading = "Heading alone"
        XCTAssertEqual(PageComposition(page: blank, book: book).storyBackground, composition.storyBackground)
        var full = page
        full.arrangement = .fullBleed
        let fullPhoto = PageComposition(page: full, book: book, bleed: 8)
        XCTAssertEqual(fullPhoto.photos[0].frame, composition.photos[0].frame)

        let output = project.appendingPathComponent("proof.pdf")
        try BookPDF.write(book, directory: project, to: output)
        let document = try XCTUnwrap(PDFDocument(url: output))
        let proof = try XCTUnwrap(document.page(at: 0))
        let caption = try XCTUnwrap(document.findString("Overlay caption").first)
        let selection = caption.bounds(for: proof)
        let story = try XCTUnwrap(composition.story)
        XCTAssertTrue(story.contains(CGPoint(x: selection.midX, y: composition.bounds.height - selection.midY)))
        let cgPage = try XCTUnwrap(proof.pageRef)
        func color(at point: CGPoint) throws -> [Double] {
            let pixel = try context(width: 1, height: 1)
            pixel.translateBy(x: 0.5 - point.x, y: 0.5 - (composition.bounds.height - point.y))
            pixel.drawPDFPage(cgPage)
            let rgba = try XCTUnwrap(pixel.data).assumingMemoryBound(to: UInt8.self)
            return (0..<3).map { Double(rgba[$0]) / 255 }
        }
        let background = try XCTUnwrap(composition.storyBackground)
        let blue = try color(at: CGPoint(x: composition.bounds.midX, y: 10))
        XCTAssertGreaterThan(blue[2] - blue[0], 0.4)
        let filled = try color(at: CGPoint(x: background.maxX - 2, y: background.midY))
        let paper = book.editorialStyle.paper
        let channels = [Double((paper >> 16) & 255), Double((paper >> 8) & 255), Double(paper & 255)]
        for index in 0..<3 {
            XCTAssertEqual(filled[index], 0.90 * channels[index] / 255 + 0.10 * blue[index], accuracy: 0.025)
        }
    }

    private func context(width: Int, height: Int) throws -> CGContext {
        try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 4 * width,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
    }
}
