import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import PaperAndGrain

final class PageArrangementTests: XCTestCase {
    func testStudioGalleryAndPhotoTextPlacementDifferByTemplate() throws {
        let photos = (1...3).map { index in
            BookPhoto(name: "Photo \(index)", filename: "photo-\(index).jpg", pixelWidth: 600, pixelHeight: 400)
        }
        let gallery = BookPage(photoIDs: photos.map(\.id))
        let overlay = BookPage(photoIDs: [photos[0].id], text: "In viaggio al mattino presto.",
                               heading: "Quando il deserto cambia colore", arrangement: .textOverPhoto)
        let templates: [BookTemplate] = [.swissGrid, .berlinQuarter, .japaneseInterval]
        for format in [BookFormat.square, .portrait, .landscape] {
            let books = templates.map { Book(title: "Example", format: format, photos: photos, template: $0) }
            let galleries = books.map { PageComposition(page: gallery, book: $0) }
            XCTAssertEqual(galleries[0].photos[0].frame.width, galleries[0].photos[1].frame.width, accuracy: 0.001)
            XCTAssertGreaterThan(galleries[1].photos[0].frame.width, galleries[1].photos[1].frame.width * 2)
            XCTAssertGreaterThan(galleries[2].photos[0].frame.minX, galleries[2].photos[1].frame.minX)
            XCTAssertGreaterThan(galleries[2].photos[1].frame.minY, galleries[2].photos[0].frame.maxY)
            let overlays = books.map { PageComposition(page: overlay, book: $0) }
            let panels = try overlays.map { try XCTUnwrap($0.storyBackground) }
            XCTAssertLessThan(panels[1].maxY, panels[0].minY)
            XCTAssertLessThan(panels[0].minX, panels[2].minX)
            for (book, composition) in zip(books, overlays) {
                XCTAssertEqual(composition.photos.first?.frame, composition.bounds)
                let panel = try XCTUnwrap(composition.storyBackground)
                let mark = try XCTUnwrap(book.editorialStyle.overlayMark(in: panel))
                XCTAssertTrue(panel.contains(mark))
                let block = try XCTUnwrap(composition.storyDrawingBlocks(page: overlay, book: book).first)
                XCTAssertTrue(panel.contains(block.frame))
                XCTAssertTrue(EditorialTypesetter.fits(block.text, in: block.frame))
            }
        }
    }

    func testEveryArrangementRespectsItsCapacityAndMarginsInEachFormat() throws {
        XCTAssertEqual(PageArrangement.allCases.count, 17)
        for format in [BookFormat.square, .portrait, .landscape] {
            let bounds = CGRect(origin: CGPoint(x: 12, y: 22), size: format.pageSize)
            let safe = bounds.insetBy(dx: 30, dy: 30)
            for arrangement in PageArrangement.allCases {
                let geometry = arrangement.geometry(in: bounds, inside: safe, gap: 10)
                XCTAssertEqual(geometry.photos.count, arrangement.photoCapacity)
                let margins = arrangement.isFullBleed ? bounds : safe
                for (index, photo) in geometry.photos.enumerated() {
                    XCTAssertTrue(margins.insetBy(dx: -0.001, dy: -0.001).contains(photo))
                    XCTAssertGreaterThan(min(photo.width, photo.height), 0)
                    for other in geometry.photos.dropFirst(index + 1) {
                        let overlap = photo.intersection(other)
                        XCTAssertLessThan(min(overlap.width, overlap.height), 0.0001)
                    }
                }
                if arrangement.isFullBleed {
                    let area = geometry.photos.reduce(0) { $0 + $1.width * $1.height }
                    XCTAssertEqual(area, bounds.width * bounds.height, accuracy: 0.0001)
                }
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

    func testLibraryDropReplacesASmallSpreadFrameWithOnePhotoAcrossBothPages() throws {
        let old = BookPhoto(name: "Old", filename: "old.jpg", pixelWidth: 1600, pixelHeight: 1200)
        let incoming = BookPhoto(name: "Wide", filename: "wide.jpg", pixelWidth: 4000, pixelHeight: 1600)
        let book = Book(title: "Panorama", photos: [old, incoming])
        let small = PageRect(x: 0.12, y: 0.23, width: 0.31, height: 0.32)
        let crop = PhotoCrop(x: 0.3, y: 0.6, zoom: 1.2)

        for template in [nil, PageArrangement.fullSpread] {
            var page = BookPage(layout: .fullSpread)
            page.arrangement = template
            page.placePhotoAcrossSpread(incoming.id)
            XCTAssertEqual(PageComposition(page: page, book: book).photos.first?.frame.width,
                           2 * book.format.pageSize.width)

            page.photoIDs = [old.id, incoming.id]
            page.photoPlacements = [
                old.id: PhotoPlacement(frame: small), incoming.id: PhotoPlacement(frame: small, crop: crop)
            ]
            page.placePhotoAcrossSpread(incoming.id)
            XCTAssertEqual(page.photoIDs, [incoming.id, old.id])

            let composition = PageComposition(page: page, book: book, bleed: 5)
            XCTAssertEqual(composition.photos.map(\.id), [incoming.id])
            let photo = try XCTUnwrap(composition.photos.first)
            XCTAssertTrue(photo.fills)
            XCTAssertEqual(photo.frame, composition.bounds.insetBy(dx: -5, dy: -5))
            XCTAssertEqual(photo.crop, crop)
        }
    }

    func testSeamlessPhotoLayoutsExtendOnlyOutsideEdgesForPrint() throws {
        let counts: [PageArrangement: Int] = [
            .bleedTwoAcross: 2, .bleedTwoStacked: 2, .bleedThreeAcross: 3, .bleedFourGrid: 4, .bleedHeroAboveTwo: 3
        ]
        XCTAssertEqual(Set(PageArrangement.allCases.filter(\.isFullBleed)), Set(counts.keys).union([.fullBleed, .fullSpread, .textOverPhoto]))
        let photos = (0..<4).map { BookPhoto(name: "Slot \($0)", filename: "slot\($0).png", pixelWidth: 40, pixelHeight: 60) }
        let book = Book(title: "Seams", format: BookFormat(widthMM: 182, heightMM: 211), photos: photos, template: .atlas)
        let bounds = CGRect(origin: .zero, size: book.format.pageSize)
        let inset = bounds.insetBy(dx: 40, dy: 40)
        for (arrangement, count) in counts {
            XCTAssertEqual(arrangement.layout, .gallery)
            XCTAssertEqual(arrangement.photoCapacity, count)
            let page = BookPage(photoIDs: photos.map(\.id), arrangement: arrangement)
            let geometry = arrangement.geometry(in: bounds, inside: inset, gap: 15)
            XCTAssertEqual(geometry.photos, arrangement.geometry(in: bounds, inside: .zero, gap: 200).photos)
            let screen = PageComposition(page: page, book: book)
            XCTAssertEqual(screen.photos.map(\.frame), geometry.photos)
            XCTAssertTrue(screen.photos.allSatisfy(\.fills))
            XCTAssertNil(screen.rule)
            XCTAssertNil(screen.folio)
            let print = PageComposition(page: page, book: book, bleed: 8)
            XCTAssertEqual(print.photos.map(\.id), Array(photos.prefix(count)).map(\.id))
            for (trim, slot) in zip(screen.photos.map(\.frame), print.photos.map(\.frame)) {
                XCTAssertEqual(slot.minX, trim.minX < 0.001 ? -8 : trim.minX, accuracy: 0.0001)
                XCTAssertEqual(slot.minY, trim.minY < 0.001 ? -8 : trim.minY, accuracy: 0.0001)
                XCTAssertEqual(slot.maxX, trim.maxX > bounds.maxX - 0.001 ? bounds.maxX + 8 : trim.maxX, accuracy: 0.0001)
                XCTAssertEqual(slot.maxY, trim.maxY > bounds.maxY - 0.001 ? bounds.maxY + 8 : trim.maxY, accuracy: 0.0001)
            }
            let restored = try JSONDecoder().decode(BookPage.self, from: JSONEncoder().encode(page))
            XCTAssertEqual(restored.arrangement, arrangement)
            let slots = geometry.photos
            switch arrangement {
            case .bleedTwoAcross, .bleedThreeAcross:
                for (index, slot) in slots.enumerated() {
                    let width = bounds.width / CGFloat(count)
                    XCTAssertEqual(slot.minX, width * CGFloat(index), accuracy: 0.0001)
                    XCTAssertEqual(slot.width, width, accuracy: 0.0001)
                    XCTAssertEqual(slot.height, bounds.height, accuracy: 0.0001)
                }
            case .bleedTwoStacked:
                XCTAssertEqual(slots[0].maxY, slots[1].minY, accuracy: 0.0001)
                XCTAssertEqual(slots[0].height, bounds.height / 2, accuracy: 0.0001)
            case .bleedFourGrid:
                XCTAssertEqual(slots[0].maxX, slots[1].minX, accuracy: 0.0001)
                XCTAssertEqual(slots[0].maxY, slots[2].minY, accuracy: 0.0001)
                XCTAssertEqual(slots[3].origin, CGPoint(x: bounds.midX, y: bounds.midY))
            case .bleedHeroAboveTwo:
                XCTAssertEqual(slots[0].width, bounds.width, accuracy: 0.0001)
                XCTAssertGreaterThan(slots[0].height, slots[1].height)
                XCTAssertEqual(slots[0].maxY, slots[1].minY, accuracy: 0.0001)
                XCTAssertEqual(slots[1].maxX, slots[2].minX, accuracy: 0.0001)
            default: XCTFail("Unexpected photo layout")
            }
        }
    }

    func testSeamlessExportShowsNoPaperBetweenImagesOrAtThePageEdges() throws {
        let project = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: project) }
        let photos = (0..<4).map { BookPhoto(name: "Field \($0)", filename: "field.png", pixelWidth: 24, pixelHeight: 24) }
        let pages = PageArrangement.allCases.filter { $0.isFullBleed && $0.layout == .gallery }
            .map { BookPage(photoIDs: photos.map(\.id), arrangement: $0) }
        let book = Book(title: "Continuous photo area", photos: photos, pages: pages, template: .atlas)
        try BookStorage.write(book, to: project)
        let image = try context(width: 24, height: 24)
        image.setFillColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
        image.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
        let asset = BookStorage.assetURL(filename: "field.png", in: project)
        let encoder = try XCTUnwrap(CGImageDestinationCreateWithURL(asset as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(encoder, try XCTUnwrap(image.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(encoder))
        let result = project.appendingPathComponent("print")
        try BookPDF.writePrint(book, directory: project, to: result)
        let pdfURL = result.appendingPathComponent("Interior.pdf")
        let pdf = try XCTUnwrap(CGPDFDocument(pdfURL as CFURL))
        XCTAssertEqual(pdf.numberOfPages, pages.count)
        for number in 1...pdf.numberOfPages {
            let page = try XCTUnwrap(pdf.page(at: number))
            let raster = try context(width: 101, height: 101)
            raster.setFillColor(gray: 1, alpha: 1)
            raster.fill(CGRect(x: 0, y: 0, width: 101, height: 101))
            let media = page.getBoxRect(.mediaBox)
            raster.scaleBy(x: 101 / media.width, y: 101 / media.height)
            raster.drawPDFPage(page)
            let rgba = try XCTUnwrap(raster.data).assumingMemoryBound(to: UInt8.self)
            let peak = stride(from: 0, to: 101 * 101 * 4, by: 4).map { rgba[$0] }.max() ?? 255
            XCTAssertLessThan(peak, 42, "Unexpected uncovered paper in \(pages[number - 1].arrangement!.rawValue)")
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
