import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import PaperAndGrain

/// Regression tests for the print output fixes of the release plan (section B).
final class PrintReleaseTests: XCTestCase {
    // MARK: B1 page numbers

    func testPrintedFoliosMatchTheEditorWhenImpositionInsertsBlanks() throws {
        let folder = try PrintFixtures.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = BookPage(layout: .text, text: "Alfa")
        let panorama = BookPage(layout: .fullSpread)
        let last = BookPage(layout: .text, text: "Omega")
        var book = Book(title: "Folio", pages: [first, panorama, last], template: .atlas)
        XCTAssertEqual(Book.pageNumbers(of: book.pages), [1, 2, 4])
        XCTAssertEqual(book.pageNumber(of: last), 4)

        // First page on the right: a blank opens the interior but the first page still reads 1.
        book.printSettings = PrintSettings(bleedMM: 0, spreads: false, firstPageOnRight: true)
        let right = folder.appendingPathComponent("right")
        try BookPDF.writePrint(book, directory: folder, to: right)
        let rightPages = try PrintFixtures.pageWords(right.appendingPathComponent("Interior.pdf"))
        let alfa = try XCTUnwrap(rightPages.firstIndex { $0.contains("Alfa") })
        XCTAssertTrue(rightPages[alfa].contains("1"), "\(rightPages[alfa])")
        XCTAssertFalse(rightPages[alfa].contains("2"))
        let omega = try XCTUnwrap(rightPages.firstIndex { $0.contains("Omega") })
        XCTAssertTrue(rightPages[omega].contains("4"), "\(rightPages[omega])")

        // Facing pages: a blank before the panorama must not shift the later folios.
        book.printSettings = PrintSettings(bleedMM: 0, spreads: false, firstPageOnRight: false)
        book.pages = [first, panorama, last]
        let left = folder.appendingPathComponent("left")
        try BookPDF.writePrint(book, directory: folder, to: left)
        let leftPages = try PrintFixtures.pageWords(left.appendingPathComponent("Interior.pdf"))
        XCTAssertEqual(leftPages.count, 5)
        let later = try XCTUnwrap(leftPages.firstIndex { $0.contains("Omega") })
        XCTAssertTrue(leftPages[later].contains("4"), "\(leftPages[later])")
        XCTAssertFalse(leftPages[later].contains("5"))

        // Pixart moves the imposition by one slot; the folios stay the same.
        let pixart = folder.appendingPathComponent("pixart.pdf")
        book.cover = BookCover(title: "Folio")
        try BookPDF.writePixart(book, directory: folder, spineMM: 7, to: pixart)
        let pixartPages = try PrintFixtures.pageWords(pixart)
        let pixartAlfa = try XCTUnwrap(pixartPages.firstIndex { $0.contains("Alfa") })
        XCTAssertTrue(pixartPages[pixartAlfa].contains("1"), "\(pixartPages[pixartAlfa])")
        let pixartOmega = try XCTUnwrap(pixartPages.firstIndex { $0.contains("Omega") })
        XCTAssertTrue(pixartPages[pixartOmega].contains("4"), "\(pixartPages[pixartOmega])")
    }

    func testPrintWarningsNameTheEditorPageNumber() throws {
        let folder = try PrintFixtures.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let photo = try PrintFixtures.photo(in: folder, width: 40, height: 40)
        var book = Book(title: "Warnings", photos: [photo],
                        pages: [BookPage(layout: .text, text: "Uno"), BookPage(layout: .gallery, photoIDs: [photo.id])])
        book.printSettings = PrintSettings(firstPageOnRight: true)
        let warnings = BookPDF.printWarnings(book)
        XCTAssertTrue(warnings.contains { $0.hasPrefix("p. 2 ·") && $0.contains(photo.name) }, "\(warnings)")
    }

    // MARK: B2 Pixart cover title

    static let coverTitles = [
        "Namibia", "Giappone 2024", "Sulle strade del Damaraland", "A Journey Through the Skeleton Coast",
        "Tra dune, canyon e oceano: diario di tre settimane", "Kolmanskop", "Fish River Canyon at Dawn",
        "Etosha", "Il lungo viaggio verso il mare di Swakopmund", "Wildlife and Wide Horizons",
        "Spitzkoppe", "Deserto del Namib", "Three Weeks in the Kalahari and Beyond", "Sossusvlei",
    ]

    func testPixartCoverFitsTheTitleInThePanelItDrawsIn() throws {
        let folder = try PrintFixtures.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let output = folder.appendingPathComponent("pixart.pdf")
        var failures: [String] = []
        for template in [nil] + BookTemplate.allCases.map(Optional.some) {
            for title in Self.coverTitles {
                var book = Book(title: title, pages: [BookPage(layout: .text)], template: template)
                book.cover = BookCover(title: title)
                // Only titles that fit in the editor's cover are expected to fit in the Pixart panel.
                let editor = BookCoverGeometry(book: book, front: true)
                guard editor.titleFrame.map({ EditorialTypesetter.fits(editor.title, in: $0) }) ?? true else { continue }
                do {
                    try BookPDF.writePixart(book, directory: folder, spineMM: 8, to: output)
                } catch {
                    failures.append("\(template?.rawValue ?? "classic") · \(title) · \(error.localizedDescription)")
                }
                let panel = CGSize(width: PixartPrintProfile.panelWidth * 72 / 25.4,
                                   height: PixartPrintProfile.panelHeight * 72 / 25.4)
                let face = BookCoverGeometry(book: book, front: true, size: panel)
                if let frame = face.titleFrame, !EditorialTypesetter.fits(face.title, in: frame) {
                    failures.append("\(template?.rawValue ?? "classic") · \(title) · panel geometry overflows")
                }
            }
        }
        XCTAssertEqual(failures, [])
    }

    func testCoverOverflowIsReportedAsCover() throws {
        let folder = try PrintFixtures.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var book = Book(title: "Overflow", pages: [BookPage(layout: .text)])
        book.cover = BookCover(title: "Overflow", backText: String(repeating: "Troppo testo sul retro. ", count: 400))
        XCTAssertThrowsError(try BookPDF.writePrint(book, directory: folder, to: folder.appendingPathComponent("print"))) {
            guard case BookPDF.ExportError.coverTextOverflow = $0 else { return XCTFail("Expected a cover overflow, got \($0)") }
            // One language per message: the interface language, English without the compiled catalog.
            XCTAssertEqual($0.localizedDescription,
                           L10n.string("Text overflows on the cover", language: L10n.interfaceLanguage))
            XCTAssertFalse($0.localizedDescription.contains(" · "))
        }
    }

    // MARK: B3 bleed without re-crop

    func testPrintBleedKeepsTheEditorCropInsideTheTrim() throws {
        let folder = try PrintFixtures.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        // 900 × 600 with a blue stripe change every 112 px; the page shows the middle of it.
        let photo = try PrintFixtures.photo(in: folder, width: 900, height: 600)
        let page = BookPage(layout: .fullPage, photoIDs: [photo.id], arrangement: .fullBleed)
        var book = Book(title: "Bleed", photos: [photo], pages: [page])
        book.printSettings = PrintSettings(bleedMM: 3, targetPPI: 72)
        let editor = try XCTUnwrap(PageComposition(page: page, book: book).photos.first)
        let placement = editor.crop.imageRect(for: CGSize(width: 900, height: 600), in: editor.frame, fills: true)
        let trim = PageComposition(page: page, book: book).bounds
        let stripe = CGFloat(900 / 8) * placement.width / 900
        let stripes: [CGFloat] = (1..<8).map { CGFloat($0) * stripe + placement.minX }
        let expected = stripes
            .filter { $0 > trim.minX + 2 && $0 < trim.maxX - 2 }
        XCTAssertFalse(expected.isEmpty)
        let sourcePixel = placement.width / 900

        let package = folder.appendingPathComponent("print")
        try BookPDF.writePrint(book, directory: folder, to: package)
        let scale: CGFloat = 3
        let raster = try PrintFixtures.raster(package.appendingPathComponent("Interior.pdf"), page: 1, scale: scale)
        let bleed = 3 * 72 / 25.4
        let row = raster.height / 2
        func blue(atPagePoint x: CGFloat) -> UInt8 {
            let column = min(raster.width - 1, max(0, Int(((x + bleed) * scale).rounded(.down))))
            return raster.bytes[(row * raster.width + column) * 4 + 2]
        }
        var found: [CGFloat] = []
        var previous = blue(atPagePoint: trim.minX) > 120
        for column in Int((bleed + trim.minX) * scale)..<Int((bleed + trim.maxX) * scale) {
            let high = raster.bytes[(row * raster.width + column) * 4 + 2] > 120
            if high != previous { found.append(CGFloat(column) / scale - bleed) }
            previous = high
        }
        XCTAssertEqual(found.count, expected.count, "\(found) vs \(expected)")
        for (actual, wanted) in zip(found, expected) {
            XCTAssertEqual(actual, wanted, accuracy: sourcePixel + 1 / scale)
        }
        // The crop has spare image on the left, so the bleed shows the real continuation, not a mirror.
        let outside = raster.bytes[(row * raster.width + Int(bleed * 0.5 * scale)) * 4]
        let inside = raster.bytes[(row * raster.width + Int(bleed * 1.5 * scale)) * 4]
        XCTAssertLessThan(Int(outside), Int(inside))

        // With the photo aligned to its left edge there is no spare image: the bleed mirrors the trim edge.
        book.pages[0].photoPlacements = [photo.id: PhotoPlacement(crop: PhotoCrop(x: 0, y: 0.5))]
        let aligned = folder.appendingPathComponent("aligned")
        try BookPDF.writePrint(book, directory: folder, to: aligned)
        let mirrored = try PrintFixtures.raster(aligned.appendingPathComponent("Interior.pdf"), page: 1, scale: scale)
        let left = mirrored.bytes[(row * mirrored.width + Int(bleed * 0.5 * scale)) * 4]
        let right = mirrored.bytes[(row * mirrored.width + Int(bleed * 1.5 * scale)) * 4]
        XCTAssertEqual(Int(left), Int(right), accuracy: 3)
        XCTAssertNotEqual(mirrored.bytes[(row * mirrored.width + 1) * 4 + 1], 0, "bleed left unpainted")
    }

    // MARK: B4 JPEG images streamed to a file

    func testPhotosAreEmbeddedAsJPEGAtTheProfileResolution() throws {
        let folder = try PrintFixtures.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let photo = try PrintFixtures.photo(in: folder, width: 3000, height: 3000)
        let page = BookPage(layout: .fullPage, photoIDs: [photo.id], arrangement: .fullBleed)
        var book = Book(title: "JPEG", photos: [photo], pages: [page])
        book.printSettings = PrintSettings(bleedMM: 0, targetPPI: 300)
        let proof = folder.appendingPathComponent("proof.pdf")
        try BookPDF.write(book, directory: folder, to: proof)
        let package = folder.appendingPathComponent("print")
        try BookPDF.writePrint(book, directory: folder, to: package)
        let side = 210 / 25.4
        for (url, ppi) in [(proof, 150.0), (package.appendingPathComponent("Interior.pdf"), 300.0)] {
            let images = try PrintFixtures.images(url, page: 1)
            XCTAssertEqual(images.count, 1, url.lastPathComponent)
            XCTAssertEqual(images.first?.format, .jpegEncoded, url.lastPathComponent)
            XCTAssertEqual(Double(images.first?.width ?? 0), side * ppi, accuracy: 3, url.lastPathComponent)
        }
        // Only the finished files remain: the temporary stream is moved into place.
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted(),
                       ["assets", "print", "proof.pdf"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: package.path).sorted(), ["Interior.pdf"])

        // A failed export keeps the previous file and leaves no temporary file behind.
        let previous = try Data(contentsOf: proof)
        book.pages.append(BookPage(layout: .text, textBoxes: [PageTextBox(text: String(repeating: "Troppo ", count: 3000),
                                                                           frame: PageRect(x: 0.1, y: 0.1, width: 0.2, height: 0.1))]))
        XCTAssertThrowsError(try BookPDF.write(book, directory: folder, to: proof))
        XCTAssertEqual(try Data(contentsOf: proof), previous)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted(),
                       ["assets", "print", "proof.pdf"])
    }

    // MARK: B5 preflight and progress

    func testPreflightListsEveryBlockerSeparatelyFromWarnings() throws {
        let folder = try PrintFixtures.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let small = try PrintFixtures.photo(in: folder, width: 60, height: 60, name: "small")
        let lost = BookPhoto(name: "lost.png", filename: "lost.png", pixelWidth: 4000, pixelHeight: 4000)
        var tinted = try PrintFixtures.photo(in: folder, width: 4000, height: 4000, name: "tinted")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("looks"), withIntermediateDirectories: true)
        try "LUT_3D_SIZE 2\nnot a number\n".write(to: BookStorage.lutURL(filename: "broken.cube", in: folder),
                                                  atomically: true, encoding: .utf8)
        tinted.film = FilmSettings(preset: .custom, lutFilename: "broken.cube")
        let overflowing = PageTextBox(text: String(repeating: "Troppo testo ", count: 400),
                                      frame: PageRect(x: 0.1, y: 0.1, width: 0.3, height: 0.1))
        let book = Book(title: "Preflight", photos: [small, lost, tinted], pages: [
            BookPage(layout: .gallery, photoIDs: [small.id]),
            BookPage(layout: .text, text: "Breve", textBoxes: [overflowing]),
            BookPage(layout: .gallery, photoIDs: [lost.id, UUID()]),
            BookPage(layout: .gallery, photoIDs: [tinted.id]),
        ])
        let report = BookPDF.preflight(book, directory: folder, profile: .print)
        let blockers = report.blockers.map { $0.message(language: "en") }
        XCTAssertEqual(blockers.count, 4, "\(blockers)")
        XCTAssertTrue(blockers.contains("p. 2 · “Troppo testo Troppo testo” · Text overflows"), "\(blockers)")
        XCTAssertTrue(blockers.contains("p. 3 · Missing photo"), "\(blockers)")
        XCTAssertTrue(blockers.contains("p. 3 · lost.png · Photo file missing"))
        XCTAssertTrue(blockers.contains("p. 4 · broken.cube · Unreadable LUT"))
        XCTAssertTrue(report.blockers.contains { $0.location == .page(4) && $0.problem == .unreadableLUT("broken.cube") && $0.target == .photo(tinted.id) })
        XCTAssertEqual(report.warnings.count, 1)
        XCTAssertTrue(report.warnings[0].message(language: "en").hasPrefix("p. 1 · small.png ·"), "\(report.warnings)")

        // The viewing PDF has no print warnings, but the same blockers stop it.
        let proof = BookPDF.preflight(book, directory: folder, profile: .proof)
        XCTAssertEqual(proof.blockers, report.blockers)
        XCTAssertEqual(proof.warnings, [])
        XCTAssertThrowsError(try BookPDF.write(book, directory: folder, to: folder.appendingPathComponent("proof.pdf")))

        var clean = book
        clean.pages = [book.pages[0]]
        XCTAssertEqual(BookPDF.preflight(clean, directory: folder, profile: .proof), BookPDF.Preflight())
    }

    func testResolutionAtTheTargetDoesNotWarnInAnyProfile() throws {
        // 2480 px across a 210 mm page is 299.96 ppi: it rounds to the target and must not warn.
        for side in [2480, 2481] {
            let photo = BookPhoto(name: "exact.png", filename: "exact.png", pixelWidth: side, pixelHeight: side)
            var book = Book(title: "Exact", photos: [photo],
                            pages: [BookPage(layout: .fullPage, photoIDs: [photo.id], arrangement: .fullBleed)])
            book.printSettings = PrintSettings(bleedMM: 3, targetPPI: 300)
            XCTAssertEqual(BookPDF.printWarnings(book).filter { $0.contains("ppi") }, [], "\(side)")
            XCTAssertEqual(BookPDF.printWarnings(book, pixart: true).filter { $0.contains("ppi") }, [], "\(side)")
        }
        let photo = BookPhoto(name: "low.png", filename: "low.png", pixelWidth: 2400, pixelHeight: 2400)
        var book = Book(title: "Low", photos: [photo],
                        pages: [BookPage(layout: .fullPage, photoIDs: [photo.id], arrangement: .fullBleed)])
        book.printSettings = PrintSettings(targetPPI: 300)
        XCTAssertEqual(BookPDF.printWarnings(book, pixart: true).filter { $0.contains("ppi") },
                       ["p. 1 · low.png · 290 ppi < 300 ppi"])
    }

    func testExportReportsProgressPerSheet() throws {
        let folder = try PrintFixtures.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var book = Book(title: "Progress", pages: (0..<5).map { BookPage(layout: .text, text: "Pagina \($0)") })
        book.cover = BookCover(title: "Progress")
        final class Values: @unchecked Sendable {
            let lock = NSLock()
            var all: [Double] = []
            func add(_ value: Double) { lock.lock(); all.append(value); lock.unlock() }
        }
        let proof = Values()
        try BookPDF.write(book, directory: folder, to: folder.appendingPathComponent("proof.pdf"), progress: proof.add)
        XCTAssertEqual(proof.all, [0, 0.2, 0.4, 0.6, 0.8, 1, 1])
        let print = Values()
        book.printSettings = PrintSettings(spreads: true)
        try BookPDF.writePrint(book, directory: folder, to: folder.appendingPathComponent("print"), progress: print.add)
        // Three interior sheets and the cover.
        XCTAssertEqual(print.all, [0, 0.25, 0.5, 0.75, 1, 1])
        let pixart = Values()
        try BookPDF.writePixart(book, directory: folder, spineMM: 6, to: folder.appendingPathComponent("pixart.pdf"),
                                progress: pixart.add)
        XCTAssertEqual(pixart.all.first, 0)
        XCTAssertEqual(pixart.all.last, 1)
        XCTAssertEqual(pixart.all, pixart.all.sorted())
        XCTAssertEqual(pixart.all.count, 2 + 1 + 6)
    }

    // MARK: B6 re-export a print package

    func testPrintPackageReplacesAPreviousExportAndChecksTheFolderFirst() throws {
        let folder = try PrintFixtures.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var book = Book(title: "Again", pages: [BookPage(layout: .text, text: "Prima")])
        book.cover = BookCover(title: "Again")
        let package = folder.appendingPathComponent("print")
        try BookPDF.writePrint(book, directory: folder, to: package)
        try Data().write(to: package.appendingPathComponent(".DS_Store"))
        book.pages[0].text = "Seconda"
        try BookPDF.writePrint(book, directory: folder, to: package)
        let words = try PrintFixtures.pageWords(package.appendingPathComponent("Interior.pdf"))
        XCTAssertTrue(words[0].contains("Seconda"))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: package.path).sorted(), ["Cover.pdf", "Interior.pdf"])

        // A folder with other files is refused before anything is rendered: the missing photo is never reached.
        let other = folder.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: other.appendingPathComponent("notes.txt"))
        book.pages[0].photoIDs = [UUID()]
        XCTAssertThrowsError(try BookPDF.writePrint(book, directory: folder, to: other)) { error in
            XCTAssertEqual((error as? CocoaError)?.code, .fileWriteFileExists, "\(error)")
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: other.path), ["notes.txt"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted(), ["assets", "other", "print"])
    }

    // MARK: B7 seams follow the paint order

    func testSeamUnderlapFollowsTheLayerOrder() throws {
        let folder = try PrintFixtures.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let red = try PrintFixtures.solid(in: folder, name: "red", red: 220, green: 20, blue: 20)
        let blue = try PrintFixtures.solid(in: folder, name: "blue", red: 20, green: 20, blue: 220)
        var page = BookPage(photoIDs: [red.id, blue.id], arrangement: .bleedTwoAcross)
        var book = Book(title: "Seams", photos: [red, blue], pages: [page])
        book.printSettings = PrintSettings(bleedMM: 0)
        let mid = book.format.pageSize.width / 2
        func colors() throws -> (left: UInt8, right: UInt8) {
            let package = folder.appendingPathComponent(UUID().uuidString)
            try BookPDF.writePrint(book, directory: folder, to: package)
            let raster = try PrintFixtures.raster(package.appendingPathComponent("Interior.pdf"), page: 1, scale: 2)
            let row = raster.height / 2
            // Red channel 4 pt either side of the shared edge.
            return (raster.bytes[(row * raster.width + Int((mid - 4) * 2)) * 4],
                    raster.bytes[(row * raster.width + Int((mid + 4) * 2)) * 4])
        }
        var sides = try colors()
        XCTAssertGreaterThan(sides.left, 180)
        XCTAssertLessThan(sides.right, 60)
        // The left photo brought to the front must not spread over the right one.
        page.layerOrder = [.photo(blue.id), .story, .photo(red.id)]
        book.pages = [page]
        sides = try colors()
        XCTAssertGreaterThan(sides.left, 180)
        XCTAssertLessThan(sides.right, 60, "the front photo covers its neighbor")
    }

    // MARK: B8 compensation blanks

    func testCompensationBlanksUseTheTemplatePaperIncludingTheBleed() throws {
        let folder = try PrintFixtures.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var book = Book(title: "Night", pages: [BookPage(layout: .text, text: "Notte")], template: .nocturne)
        book.printSettings = PrintSettings(bleedMM: 3, spreads: false, firstPageOnRight: true)
        let package = folder.appendingPathComponent("print")
        try BookPDF.writePrint(book, directory: folder, to: package)
        let paper = book.editorialStyle.paper
        let expected = [UInt8(paper >> 16 & 0xFF), UInt8(paper >> 8 & 0xFF), UInt8(paper & 0xFF)]
        let blank = try PrintFixtures.raster(package.appendingPathComponent("Interior.pdf"), page: 1, scale: 1)
        for (x, y) in [(blank.width / 2, blank.height / 2), (1, 1), (blank.width - 2, blank.height - 2)] {
            let i = (y * blank.width + x) * 4
            XCTAssertEqual(Array(blank.bytes[i..<(i + 3)]).map(Int.init), expected.map(Int.init), accuracy: 2, "\(x),\(y)")
        }
        let pixart = folder.appendingPathComponent("pixart.pdf")
        book.printSettings?.firstPageOnRight = false
        book.cover = BookCover(title: "Night")
        try BookPDF.writePixart(book, directory: folder, spineMM: 6, to: pixart)
        let opening = try PrintFixtures.raster(pixart, page: 2, scale: 1)
        let i = (opening.height / 2 * opening.width + opening.width / 2) * 4
        XCTAssertEqual(Array(opening.bytes[i..<(i + 3)]).map(Int.init), expected.map(Int.init), accuracy: 2)
    }

    // MARK: B9 classic cover band

    func testClassicCoverBandRunsIntoTheWrap() throws {
        let folder = try PrintFixtures.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var book = Book(title: "Band", pages: [BookPage(layout: .text, text: "Uno")])
        book.cover = BookCover(title: "Band", backText: "Retro")
        let url = folder.appendingPathComponent("pixart.pdf")
        try BookPDF.writePixart(book, directory: folder, spineMM: 8, to: url)
        let mm = 72 / 25.4
        let cover = try PrintFixtures.raster(url, page: 1, scale: 1)
        // Raster rows run from the top. The band covers the lower part of each face.
        let y = Int((19 + 220 * 0.85) * mm)
        for x in [Int(5 * mm), cover.width - Int(5 * mm), Int((19 + 100) * mm)] {
            let i = (y * cover.width + x) * 4
            XCTAssertGreaterThan(cover.bytes[i], 200, "x \(x): the band should reach this point")
        }
        // Above the band the cover keeps its dark background, in the wrap too.
        let above = (Int(40 * mm) * cover.width + Int(5 * mm)) * 4
        XCTAssertLessThan(cover.bytes[above], 80)
    }

    // MARK: B10 sharpening at any size

    func testSharpeningLooksTheSameInPreviewAndPrint() throws {
        // The same scene, a hard edge and a fine stripe pattern, at preview and at print size.
        // Viewed at the same size (the print averaged down to the preview), the detail added by
        // sharpening must match; with whole-pixel radii the print got about a fifth of it.
        func added(width: Int, settings: PhotoAdjustments, downscale: Int) throws -> [Double] {
            let height = 48
            let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                                  bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
            func scene(_ x: Int) -> UInt8 {
                let position = Double(x) / Double(width)
                if position < 0.5 { return position < 0.25 ? 80 : 170 }
                return UInt8(125 + 45 * sin(position * 2 * .pi * 24))
            }
            for y in 0..<height {
                for x in 0..<width {
                    let i = (y * width + x) * 4
                    let value = scene(x)
                    pixels[i] = value; pixels[i + 1] = value; pixels[i + 2] = value; pixels[i + 3] = 255
                }
            }
            XCTAssertTrue(PhotoDevelopment.applySpatial(settings, to: context))
            return stride(from: 0, to: width, by: downscale).map { start in
                (start..<(start + downscale)).reduce(0.0) { sum, x in
                    sum + Double(Int(pixels[(24 * width + x) * 4]) - Int(scene(x)))
                } / Double(downscale)
            }
        }
        var sharp = PhotoAdjustments()
        sharp.sharpness = 1
        // Preview sizes of the canvas against print renders (whole-pixel radii gave 0.06 to 0.43).
        for (preview, print, factor) in [(600, 3000, 5), (1200, 3600, 3), (1440, 2880, 2), (2048, 4096, 2)] {
            let shown = try added(width: preview, settings: sharp, downscale: 1).reduce(0) { $0 + abs($1) }
            let printed = try added(width: print, settings: sharp, downscale: factor).reduce(0) { $0 + abs($1) }
            XCTAssertGreaterThan(shown, 0)
            XCTAssertEqual(printed / shown, 1, accuracy: 0.4, "\(preview) px against \(print) px")
        }
        let radii = PhotoDevelopment.spatialRadii(longEdge: 3000)
        let small = PhotoDevelopment.spatialRadii(longEdge: 600)
        XCTAssertEqual(radii.noise / small.noise, 5, accuracy: 0.0001)
        XCTAssertEqual(radii.sharpness / small.sharpness, 5, accuracy: 0.0001)
        XCTAssertEqual(radii.definition / small.definition, 5, accuracy: 0.0001)
    }

    // MARK: B12 smaller items

    func testCubeWithResolveInputRangeAndExtraKeywords() throws {
        let folder = try PrintFixtures.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        // A 2-point table over the domain 0...2 that maps the input to half its value.
        var rows = ["TITLE \"Resolve\"", "LUT_3D_SIZE 2", "LUT_3D_INPUT_RANGE 0.0 2.0", "LUT_IN_VIDEO_RANGE"]
        for b in [0.0, 1.0] { for g in [0.0, 1.0] { for r in [0.0, 1.0] { rows.append("\(r) \(g) \(b)") } } }
        let cube = folder.appendingPathComponent("resolve.cube")
        try rows.joined(separator: "\n").write(to: cube, atomically: true, encoding: .utf8)
        XCTAssertNoThrow(try FilmRenderer.validateLUT(at: cube))
        let gray = try PrintFixtures.solid(in: folder, name: "gray", red: 128, green: 128, blue: 128)
        let image = try XCTUnwrap(FilmRenderer.image(from: BookStorage.assetURL(filename: gray.filename, in: folder),
                                                     maxPixelSize: 8, settings: FilmSettings(preset: .custom), lutURL: cube))
        let pixel = try PrintFixtures.firstPixel(image)
        XCTAssertEqual(Int(pixel[0]), 64, accuracy: 2)

        let oneD = folder.appendingPathComponent("curve.cube")
        try "LUT_1D_SIZE 2\n0 0 0\n1 1 1\n".write(to: oneD, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try FilmRenderer.validateLUT(at: oneD))
        let twice = folder.appendingPathComponent("twice.cube")
        try "LUT_3D_SIZE 2\nDOMAIN_MIN 0 0 0\nLUT_3D_INPUT_RANGE 0 1\n".write(to: twice, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try FilmRenderer.validateLUT(at: twice))
    }

    func testHaldLevelTwelveIsResampled() throws {
        let folder = try PrintFixtures.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        // An identity Hald CLUT of level 12: 1728 px square, 144 steps per channel, 16 bits.
        let level = 12, steps = level * level, side = level * level * level
        let context = try XCTUnwrap(CGContext(data: nil, width: side, height: side, bitsPerComponent: 16,
                                              bytesPerRow: side * 8, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGBitmapInfo.byteOrder16Little.rawValue
                                                | CGImageAlphaInfo.premultipliedLast.rawValue))
        let samples = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt16.self)
        for index in 0..<(side * side) {
            let r = index % steps, g = (index / steps) % steps, b = index / (steps * steps)
            samples[index * 4] = UInt16(r * 65535 / (steps - 1))
            samples[index * 4 + 1] = UInt16(g * 65535 / (steps - 1))
            samples[index * 4 + 2] = UInt16(b * 65535 / (steps - 1))
            samples[index * 4 + 3] = 65535
        }
        let hald = folder.appendingPathComponent("identity12.png")
        try PrintFixtures.writePNG(try XCTUnwrap(context.makeImage()), to: hald)
        XCTAssertNoThrow(try FilmRenderer.validateLUT(at: hald))
        let color = try PrintFixtures.solid(in: folder, name: "color", red: 200, green: 90, blue: 30)
        let image = try XCTUnwrap(FilmRenderer.image(from: BookStorage.assetURL(filename: color.filename, in: folder),
                                                     maxPixelSize: 8, settings: FilmSettings(preset: .custom), lutURL: hald))
        let pixel = try PrintFixtures.firstPixel(image)
        XCTAssertEqual(pixel.prefix(3).map(Int.init), [200, 90, 30], accuracy: 2)
        XCTAssertEqual(FilmRenderer.maximumHaldCube, 64)
    }

    func testEmptyTextBoxPrintsOnlyWhatTheAuthorStyled() throws {
        let paper = BookTemplate.atlas.style.paper, ink = BookTemplate.atlas.style.ink
        let frame = PageRect(x: 0.1, y: 0.1, width: 0.4, height: 0.3)
        XCTAssertFalse(PageTextBox(text: "  ", frame: frame).prints(paper: paper, ink: ink))
        XCTAssertFalse(PageTextBox(text: "", frame: frame, backgroundColor: paper).prints(paper: paper, ink: ink))
        let filled = PageTextBox(text: "", frame: frame, backgroundColor: 0xC03020)
        XCTAssertTrue(filled.prints(paper: paper, ink: ink))
        XCTAssertEqual(filled.printedFill(paper: paper), 0xC03020)
        XCTAssertFalse(PageTextBox(text: "", frame: frame, backgroundColor: 0xC03020, hidesBackground: true)
            .prints(paper: paper, ink: ink))
        let bordered = PageTextBox(text: "", frame: frame, borderWidth: 2)
        XCTAssertTrue(bordered.prints(paper: paper, ink: ink))
        XCTAssertNil(bordered.printedFill(paper: paper), "an empty bordered box shows what is under it")
        XCTAssertEqual(PageTextBox(text: "Testo", frame: frame).printedFill(paper: paper), paper)

        // In the PDF the filled box shows its color and the bordered one leaves the photo visible inside.
        let folder = try PrintFixtures.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let blue = try PrintFixtures.solid(in: folder, name: "blue", red: 20, green: 40, blue: 200)
        let page = BookPage(layout: .fullPage, photoIDs: [blue.id], textBoxes: [
            filled, PageTextBox(text: "", frame: PageRect(x: 0.55, y: 0.55, width: 0.3, height: 0.3), borderWidth: 3),
        ], arrangement: .fullBleed)
        let book = Book(title: "Boxes", photos: [blue], pages: [page], template: .atlas)
        let url = folder.appendingPathComponent("proof.pdf")
        try BookPDF.write(book, directory: folder, to: url)
        let raster = try PrintFixtures.raster(url, page: 1, scale: 0.5)
        func color(_ x: Double, _ y: Double) -> [Int] {
            let i = (Int(y * Double(raster.height)) * raster.width + Int(x * Double(raster.width))) * 4
            return raster.bytes[i..<(i + 3)].map(Int.init)
        }
        XCTAssertEqual(color(0.3, 0.25), [0xC0, 0x30, 0x20], accuracy: 3)
        XCTAssertEqual(color(0.7, 0.7), [20, 40, 200], accuracy: 6)
    }

    func testPanoramaHalvesShareOneEmbeddedImage() throws {
        let folder = try PrintFixtures.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let photo = try PrintFixtures.photo(in: folder, width: 1200, height: 600)
        var book = Book(title: "Panorama", photos: [photo],
                        pages: [BookPage(layout: .fullSpread, photoIDs: [photo.id], arrangement: .fullSpread)])
        book.printSettings = PrintSettings(bleedMM: 3, spreads: false)
        let package = folder.appendingPathComponent("print")
        try BookPDF.writePrint(book, directory: folder, to: package)
        let data = try Data(contentsOf: package.appendingPathComponent("Interior.pdf"))
        let marker = Data("/Subtype /Image".utf8)
        var count = 0, start = data.startIndex
        while let range = data.range(of: marker, in: start..<data.endIndex) { count += 1; start = range.upperBound }
        XCTAssertEqual(try PrintFixtures.images(package.appendingPathComponent("Interior.pdf"), page: 1).count, 1)
        XCTAssertEqual(try PrintFixtures.images(package.appendingPathComponent("Interior.pdf"), page: 2).count, 1)
        XCTAssertEqual(count, 1, "both halves embed the same photograph once")
    }

    func testJPEGPrintKeepsSmoothGradientsWithoutBanding() throws {
        let folder = try PrintFixtures.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        // A slow sky-like gradient: 0.25 code values per source pixel, where banding shows first.
        let width = 1600, height = 1600
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: width * 4, space: space,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                pixels[i] = UInt8(60 + x * 100 / width)
                pixels[i + 1] = UInt8(110 + x * 60 / width)
                pixels[i + 2] = 200
                pixels[i + 3] = 255
            }
        }
        let photo = BookPhoto(name: "sky.png", filename: "sky.png", pixelWidth: width, pixelHeight: height)
        try PrintFixtures.writePNG(try XCTUnwrap(context.makeImage()), to: BookStorage.assetURL(filename: photo.filename, in: folder))
        let page = BookPage(layout: .fullPage, photoIDs: [photo.id], arrangement: .fullBleed)
        var book = Book(title: "Sky", photos: [photo], pages: [page])
        book.printSettings = PrintSettings(bleedMM: 0, targetPPI: 300)
        let package = folder.appendingPathComponent("print")
        try BookPDF.writePrint(book, directory: folder, to: package)
        let raster = try PrintFixtures.raster(package.appendingPathComponent("Interior.pdf"), page: 1, scale: 2)
        let row = raster.height / 2
        // Banding would show as steps: values that drift from the ramp or fall back behind the highest so far.
        var worst = 0
        var highest = -1
        var reversals = 0
        for column in 4..<(raster.width - 4) {
            let red = Int(raster.bytes[(row * raster.width + column) * 4])
            let expected = 60 + Int(Double(column) / Double(raster.width) * 100)
            worst = max(worst, abs(red - expected))
            if red < highest - 2 { reversals += 1 }
            highest = max(highest, red)
        }
        XCTAssertLessThanOrEqual(worst, 3)
        XCTAssertEqual(reversals, 0)
    }
}

func XCTAssertEqual(_ lhs: [Int], _ rhs: [Int], accuracy: Int, _ message: String = "",
                    file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { abs($0 - $1) <= accuracy },
                  "\(lhs) is not within \(accuracy) of \(rhs) \(message)", file: file, line: line)
}

enum PrintFixtures {
    /// Image XObjects of one page (1-based): stream encoding and pixel width.
    static func images(_ url: URL, page number: Int) throws -> [(format: CGPDFDataFormat, width: Int)] {
        // The dictionaries point into the document, which must stay alive while they are read.
        let document = try XCTUnwrap(CGPDFDocument(url as CFURL))
        defer { withExtendedLifetime(document) {} }
        let page = try XCTUnwrap(document.page(at: number)?.dictionary)
        var resources: CGPDFDictionaryRef?
        var objects: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(page, "Resources", &resources), let resources,
              CGPDFDictionaryGetDictionary(resources, "XObject", &objects), let objects else { return [] }
        final class Box {
            var found: [(CGPDFDataFormat, Int)] = []
            var nested: [CGPDFDictionaryRef] = []
        }
        let box = Box()
        box.nested = [objects]
        while let objects = box.nested.popLast() {
        CGPDFDictionaryApplyBlock(objects, { _, value, info in
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(value, .stream, &stream), let stream, let dictionary = CGPDFStreamGetDictionary(stream)
            else { return true }
            var subtype: UnsafePointer<CChar>?
            guard CGPDFDictionaryGetName(dictionary, "Subtype", &subtype), let subtype else { return true }
            if String(cString: subtype) == "Form" {
                // Quartz wraps clipped images in form XObjects; look inside them too.
                var resources: CGPDFDictionaryRef?
                var objects: CGPDFDictionaryRef?
                if CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources), let resources,
                   CGPDFDictionaryGetDictionary(resources, "XObject", &objects), let objects {
                    Unmanaged<Box>.fromOpaque(info!).takeUnretainedValue().nested.append(objects)
                }
                return true
            }
            guard String(cString: subtype) == "Image" else { return true }
            var width: CGPDFInteger = 0
            CGPDFDictionaryGetInteger(dictionary, "Width", &width)
            var format = CGPDFDataFormat.raw
            _ = CGPDFStreamCopyData(stream, &format)
            Unmanaged<Box>.fromOpaque(info!).takeUnretainedValue().found.append((format, Int(width)))
            return true
        }, Unmanaged.passUnretained(box).toOpaque())
        }
        return box.found.map { (format: $0.0, width: $0.1) }
    }


    static func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("assets"), withIntermediateDirectories: true)
        return folder
    }

    /// The words of each page of a PDF, in page order.
    static func pageWords(_ url: URL) throws -> [Set<String>] {
        let document = try XCTUnwrap(PDFDocument(url: url))
        return (0..<document.pageCount).map { index in
            Set((document.page(at: index)?.string ?? "").split(whereSeparator: \.isWhitespace).map(String.init))
        }
    }

    /// A synthetic photo: a horizontal gradient with a few colored bands, written as PNG.
    static func photo(in folder: URL, width: Int, height: Int, name: String = UUID().uuidString) throws -> BookPhoto {
        let photo = BookPhoto(name: name + ".png", filename: name + ".png", pixelWidth: width, pixelHeight: height)
        let image = try gradient(width: width, height: height)
        try writePNG(image, to: BookStorage.assetURL(filename: photo.filename, in: folder))
        return photo
    }

    static func solid(in folder: URL, name: String, red: UInt8, green: UInt8, blue: UInt8) throws -> BookPhoto {
        let photo = BookPhoto(name: name + ".png", filename: name + ".png", pixelWidth: 40, pixelHeight: 60)
        let context = try XCTUnwrap(CGContext(data: nil, width: 40, height: 60, bitsPerComponent: 8, bytesPerRow: 160,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 60))
        try writePNG(try XCTUnwrap(context.makeImage()), to: BookStorage.assetURL(filename: photo.filename, in: folder))
        return photo
    }

    /// The first pixel of an image, as 8-bit sRGB RGBA.
    static func firstPixel(_ image: CGImage) throws -> [UInt8] {
        let context = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return Array(UnsafeBufferPointer(start: try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self), count: 4))
    }

    static func gradient(width: Int, height: Int) throws -> CGImage {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: width * 4, space: space,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                pixels[i] = UInt8(255 * x / max(1, width - 1))
                pixels[i + 1] = UInt8(255 * y / max(1, height - 1))
                pixels[i + 2] = UInt8((x / max(1, width / 8)) % 2 == 0 ? 40 : 200)
                pixels[i + 3] = 255
            }
        }
        return try XCTUnwrap(context.makeImage())
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    /// Rasterizes one PDF page (1-based) into sRGB RGBA bytes at the given scale per point.
    static func raster(_ url: URL, page number: Int, scale: CGFloat, box: CGPDFBox = .mediaBox) throws
        -> (bytes: [UInt8], width: Int, height: Int, origin: CGPoint) {
        let page = try XCTUnwrap(CGPDFDocument(url as CFURL)?.page(at: number))
        let rect = page.getBoxRect(box)
        let width = Int((rect.width * scale).rounded()), height = Int((rect.height * scale).rounded())
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -rect.minX, y: -rect.minY)
        context.drawPDFPage(page)
        let data = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        return (Array(UnsafeBufferPointer(start: data, count: width * height * 4)), width, height, rect.origin)
    }
}
