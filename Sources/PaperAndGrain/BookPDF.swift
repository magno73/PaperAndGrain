import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum BookPDF {
    private static let pointsPerMM = 72.0 / 25.4

    enum ExportError: LocalizedError {
        case invalidBook
        case missingImage(String)
        case textOverflow(Int)
        case coverTextOverflow

        var errorDescription: String? {
            switch self {
            case .invalidBook: "Impossibile creare il PDF · Could not create the PDF"
            case let .missingImage(name): "Foto non disponibile · Photo unavailable — \(name)"
            case let .textOverflow(number): "Il testo eccede lo spazio a pagina \(number) · Text overflows on page \(number)"
            case .coverTextOverflow: "Il testo eccede lo spazio in copertina · Text overflows on the cover"
            }
        }
    }

    /// `progress` receives the completed fraction, from 0 to 1, after each sheet. It is called on the
    /// exporting thread.
    static func write(_ book: Book, directory: URL, to destination: URL,
                      progress: (@Sendable (Double) -> Void)? = nil) throws {
        let meter = ProgressMeter(total: sheetCount(book, settings: nil, pixart: false), report: progress)
        try render(book, directory: directory, settings: nil, cover: nil, to: destination, meter: meter)
        meter.finish()
    }

    static func writePrint(_ book: Book, directory: URL, to destination: URL,
                           progress: (@Sendable (Double) -> Void)? = nil) throws {
        let settings = book.printSettings ?? PrintSettings()
        let meter = ProgressMeter(total: sheetCount(book, settings: settings, pixart: false) + (book.cover == nil ? 0 : 1),
                                  report: progress)
        let fm = FileManager.default
        // Check the destination before rendering: only a previous package may be replaced.
        if fm.fileExists(atPath: destination.path) {
            let previous = Set(["Interior.pdf", "Cover.pdf", ".DS_Store"])
            guard let contents = try? fm.contentsOfDirectory(atPath: destination.path),
                  Set(contents).isSubset(of: previous) else { throw CocoaError(.fileWriteFileExists) }
        }
        let scratch = destination.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: scratch) }
        try render(book, directory: directory, settings: settings, cover: nil,
                   to: scratch.appendingPathComponent("Interior.pdf"), meter: meter)
        if let cover = book.cover {
            try render(book, directory: directory, settings: settings, cover: cover,
                       to: scratch.appendingPathComponent("Cover.pdf"), meter: meter)
        }
        try Task.checkCancellation()
        if fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(destination, withItemAt: scratch)
        } else {
            try fm.moveItem(at: scratch, to: destination)
        }
        meter.finish()
    }

    static func writePixart(_ book: Book, directory: URL, spineMM: Double, to destination: URL,
                            progress: (@Sendable (Double) -> Void)? = nil) throws {
        guard PixartPrintProfile.supports(book.format), PixartPrintProfile.isValidSpine(spineMM) else {
            throw ExportError.invalidBook
        }
        let settings = pixartSettings(book)
        let meter = ProgressMeter(total: 1 + sheetCount(book, settings: settings, pixart: true), report: progress)
        try render(book, directory: directory, settings: settings, cover: nil, to: destination,
                   pixartSpineMM: spineMM, meter: meter)
        meter.finish()
    }

    /// Counts rendered sheets and reports the completed fraction.
    private final class ProgressMeter {
        private let total: Int
        private var done = 0
        private let report: (@Sendable (Double) -> Void)?

        init(total: Int, report: (@Sendable (Double) -> Void)?) {
            self.total = max(1, total)
            self.report = report
            report?(0)
        }

        func sheetDone() {
            done += 1
            report?(min(1, Double(done) / Double(total)))
        }

        func finish() { report?(1) }
    }

    private static func sheetCount(_ book: Book, settings: PrintSettings?, pixart: Bool) -> Int {
        let slots = leaves(book.pages, settings: settings, pixart: pixart).count
        return settings?.spreads == true ? (slots + 1) / 2 : slots
    }

    private static func pixartSettings(_ book: Book) -> PrintSettings {
        var settings = book.printSettings ?? PrintSettings()
        settings.spreads = false
        settings.bleedMM = PixartPrintProfile.bleed
        settings.targetPPI = 300
        return settings
    }

    /// The three exports; the preflight checks what each of them will render.
    enum Profile: Sendable {
        case proof, print, pixart
    }

    /// Problems found before an export. Blockers make the export fail and must be fixed first;
    /// warnings describe a weaker print. Messages read "location · Italiano / English".
    struct Preflight: Equatable, Sendable {
        var blockers: [String] = []
        var warnings: [String] = []
    }

    /// Every problem in one list, blockers first, for callers that show a single list.
    static func printWarnings(_ book: Book, pixart: Bool = false) -> [String] {
        let report = preflight(book, directory: nil, profile: pixart ? .pixart : .print)
        return report.blockers + report.warnings
    }

    /// A cheap pass over the book that lists everything that would stop the export (text that
    /// does not fit, photos or files that are missing, a LUT that cannot be read) and the print
    /// warnings (resolution, blank pages). Without `directory`, files on disk are not checked.
    static func preflight(_ book: Book, directory: URL?, profile: Profile) -> Preflight {
        let settings: PrintSettings? = switch profile {
        case .proof: nil
        case .print: book.printSettings ?? PrintSettings()
        case .pixart: pixartSettings(book)
        }
        let w = book.format.widthMM * pointsPerMM
        let h = book.format.heightMM * pointsPerMM
        let bleed = (settings?.bleedMM ?? 0) * pointsPerMM
        let ppi = settings?.targetPPI ?? ImageOutput.proof.ppi
        let safe = book.contentInsetPoints
        guard w.isFinite, h.isFinite, min(w,h) > 50, safe >= 0, 2*safe < min(w,h),
              bleed.isFinite, bleed >= 0, ppi.isFinite, ppi > 0 else {
            return Preflight(blockers: ["Dimensioni non valide · Invalid print dimensions"])
        }
        var report = Preflight()
        var checkedFiles = Set<String>()
        var checkedLooks = Set<String>()
        let fm = FileManager.default
        func checkFiles(_ photo: BookPhoto, location: String) {
            guard let directory else { return }
            if checkedFiles.insert(photo.filename).inserted,
               !fm.fileExists(atPath: BookStorage.assetURL(filename: photo.filename, in: directory).path) {
                report.blockers.append("\(location) · \(photo.name) · File della foto mancante / Photo file missing")
            }
            let film = book.effectiveFilm(for: photo)
            guard film.preset == .custom, film.strength > 0 else { return }
            let name = film.lutFilename ?? ""
            guard checkedLooks.insert(name).inserted else { return }
            if film.lutFilename.map({ (try? FilmRenderer.validateLUT(at: BookStorage.lutURL(filename: $0, in: directory))) == nil }) ?? true {
                report.blockers.append("\(location) · \(name.isEmpty ? photo.name : name) · LUT illeggibile / Unreadable LUT")
            }
        }
        func checkResolution(_ photo: BookPhoto, frame: CGRect, fills: Bool, crop: PhotoCrop, location: String) {
            guard settings != nil else { return }
            let pixels = CGSize(width: photo.pixelWidth, height: photo.pixelHeight)
            let drawn = crop.imageRect(for: pixels, in: frame, fills: fills)
            guard drawn.width > 0 else { return }
            // Compare what is printed in the message, so "300 ppi < 300 ppi" cannot appear.
            let actual = (pixels.width * 72 / drawn.width).rounded()
            if actual < ppi.rounded() {
                report.warnings.append(String(format: "%@ · %@ · %.0f ppi < %.0f ppi", location, photo.name, actual, ppi))
            }
        }
        func overflow(_ location: String) { report.blockers.append(location + " · Il testo eccede lo spazio / Text overflows") }

        let slots = leaves(book.pages, settings: settings, pixart: profile == .pixart)
        let blanks = slots.indices.filter { slots[$0] == nil }.map { String($0 + 1) }
        if !blanks.isEmpty, settings != nil {
            report.warnings.append("Pagine bianche di compensazione / Blank pages for alignment · " + blanks.joined(separator: ", "))
        }
        let style = book.editorialStyle
        for leaf in slots.compactMap({ $0 }) where leaf.half == 0 {
            let page = leaf.page
            let loc = "p. "+String(leaf.number)
            if page.photoIDs.contains(where: { book.photo($0) == nil }) {
                report.blockers.append(loc + " · Foto mancante / Missing photo")
            }
            let composition = PageComposition(page: page, book: book)
            for slot in composition.photos {
                checkFiles(slot.photo, location: loc)
                checkResolution(slot.photo, frame: slot.frame, fills: slot.fills, crop: slot.crop, location: loc)
            }
            let story = composition.storyDrawingBlocks(page: page, book: book)
            var fits = story.allSatisfy { $0.text.length == 0 || EditorialTypesetter.fits($0.text, in: $0.frame) }
            for box in composition.textBoxes where fits && box.prints(paper: style.paper, ink: style.ink) {
                let frame = box.frame.rect(in: composition.bounds)
                fits = EditorialTypesetter.fits(PageComposition.boxText(box: box, book: book),
                                                in: frame.insetBy(dx: box.textInsetPoints, dy: box.textInsetPoints))
            }
            if !fits { overflow(loc) }
        }
        if let cover = book.cover, profile != .proof {
            let location = "Copertina / Cover"
            var coverFits = true
            for (id, front) in [(cover.frontPhotoID, true), (cover.backPhotoID, false)] {
                let face = profile == .pixart
                    ? BookCoverGeometry(book: book, front: front, size: CGSize(
                        width: PixartPrintProfile.panelWidth * pointsPerMM,
                        height: PixartPrintProfile.panelHeight * pointsPerMM))
                    : BookCoverGeometry(book: book, front: front, bleed: bleed)
                if let frame = face.titleFrame, !EditorialTypesetter.fits(face.title, in: frame) { coverFits = false }
                guard let id else { continue }
                if let photo = book.photo(id) {
                    checkFiles(photo, location: location)
                    checkResolution(photo, frame: face.photoFrame, fills: face.fills, crop: face.photoCrop, location: location)
                } else {
                    report.blockers.append(location + " · Foto mancante / Missing photo")
                }
            }
            if !coverFits { overflow(location) }
        }
        return report
    }

    private struct Leaf {
        let page: BookPage
        let half: Int
        let number: Int
    }

    private static func leaves(_ pages: [BookPage], settings: PrintSettings?, pixart: Bool = false) -> [Leaf?] {
        var leaves = [Leaf?]()
        if settings?.firstPageOnRight == true { leaves.append(nil) }
        // Folios follow the editor's numbering, so blanks added for the imposition are not counted.
        for (page, number) in zip(pages, Book.pageNumbers(of: pages)) {
            if page.effectiveLayout == .fullSpread && settings != nil && !leaves.count.isMultiple(of: 2) {
                leaves.append(nil)
            }
            leaves.append(Leaf(page: page, half: 0, number: number))
            if page.effectiveLayout == .fullSpread {
                leaves.append(Leaf(page: page, half: 1, number: number + 1))
            }
        }
        if settings?.spreads == true && !leaves.count.isMultiple(of: 2) { leaves.append(nil) }
        if pixart {
            // Generic imposition starts at a left slot; the first physical Pixart interior is right.
            if settings?.firstPageOnRight == true { leaves.removeFirst() }
            else { leaves.insert(nil, at: 0) }
        }
        return leaves
    }

    private static let rgb = CGColorSpace(name: CGColorSpace.sRGB)!

    private static func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, alpha: CGFloat = 1) -> CGColor {
        CGColor(colorSpace: rgb, components: [red, green, blue, alpha])!
    }

    private static func box(_ rect: CGRect) -> Data {
        var value = rect
        return withUnsafeBytes(of: &value) { Data($0) }
    }

    /// Resolution and JPEG quality of the photographs embedded in a PDF.
    struct ImageOutput {
        let ppi: Double
        let quality: Double

        /// The viewing PDF is for screens: about 150 ppi at quality 0.85.
        static let proof = ImageOutput(ppi: 150, quality: 0.85)
        static func print(_ settings: PrintSettings) -> ImageOutput { ImageOutput(ppi: settings.targetPPI, quality: 0.95) }
    }

    /// Streams the PDF into a hidden file next to `url` and moves it into place only when it is complete,
    /// so a failed or cancelled export leaves an existing file untouched.
    private static func render(_ book: Book, directory: URL, settings: PrintSettings?, cover: BookCover?, to url: URL,
                               pixartSpineMM: Double? = nil, meter: ProgressMeter? = nil) throws {
        let fm = FileManager.default
        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.deletingPathExtension().lastPathComponent)-\(UUID().uuidString).pdf")
        defer { try? fm.removeItem(at: temporary) }
        try renderDocument(book, directory: directory, settings: settings, cover: cover, to: temporary,
                           pixartSpineMM: pixartSpineMM, meter: meter)
        try Task.checkCancellation()
        if fm.fileExists(atPath: url.path) {
            _ = try fm.replaceItemAt(url, withItemAt: temporary)
        } else {
            try fm.moveItem(at: temporary, to: url)
        }
    }

    private static func renderDocument(_ book: Book, directory: URL, settings: PrintSettings?, cover: BookCover?,
                                       to url: URL, pixartSpineMM: Double?, meter: ProgressMeter?) throws {
        let w = book.format.widthMM * pointsPerMM
        let h = book.format.heightMM * pointsPerMM
        let bleed = (settings?.bleedMM ?? 0) * pointsPerMM
        let safe = book.contentInsetPoints
        let images = settings.map(ImageOutput.print) ?? .proof
        let spine = (cover?.spineMM ?? 0) * pointsPerMM
        guard w.isFinite, h.isFinite, w > 50, h > 50, !book.pages.isEmpty,
              bleed.isFinite, bleed >= 0, safe >= 0, safe * 2 < min(w,h),
              images.ppi.isFinite, images.ppi > 0, spine.isFinite, spine >= 0 else { throw ExportError.invalidBook }
        var media = CGRect(x: 0, y: 0, width: w + bleed * 2, height: h + bleed * 2)
        var metadata: [String: Any] = [kCGPDFContextTitle as String: book.title]
        if settings != nil {
            // Quartz uses GTS_PDFX for the output-intent dictionary. The profile describes the
            // exchange RGB space; this exporter does not certify PDF/X or a press condition.
            metadata[kCGPDFContextOutputIntent as String] = [
                kCGPDFXOutputIntentSubtype as String: "GTS_PDFX",
                kCGPDFXOutputConditionIdentifier as String: "sRGB IEC61966-2.1",
                kCGPDFXInfo as String: "sRGB photographic exchange",
                kCGPDFXDestinationOutputProfile as String: rgb
            ] as [String: Any]
        }
        guard let ctx = CGContext(url as CFURL, mediaBox: &media, metadata as CFDictionary)
        else { throw ExportError.invalidBook }
        // Close the file even when a page throws, so the temporary file can be removed.
        var closed = false
        defer { if !closed { ctx.closePDF() } }
        func begin(width: Double, height: Double, bleed: Double) {
            let trim = CGRect(x: bleed, y: bleed, width: width, height: height)
            let full = trim.insetBy(dx: -bleed, dy: -bleed)
            ctx.beginPDFPage([kCGPDFContextMediaBox as String: box(full), kCGPDFContextTrimBox as String: box(trim),
                              kCGPDFContextBleedBox as String: box(full)] as CFDictionary)
            ctx.translateBy(x: bleed, y: bleed + height)
            ctx.scaleBy(x: 1, y: -1)
        }
        if let spineMM = pixartSpineMM {
            let panelW = PixartPrintProfile.panelWidth * pointsPerMM
            let panelH = PixartPrintProfile.panelHeight * pointsPerMM
            let hinge = PixartPrintProfile.hinge * pointsPerMM
            let wrap = PixartPrintProfile.wrap * pointsPerMM
            let width = 2 * (panelW + hinge) + spineMM * pointsPerMM
            begin(width: width, height: panelH, bleed: wrap)
            ctx.setFillColor(EditorialStyle.color(BookCoverGeometry(book: book, front: false).background))
            ctx.fill(CGRect(x: -wrap, y: -wrap, width: width + 2*wrap, height: panelH + 2*wrap))
            drawSpine(book, in: CGRect(x: panelW + hinge, y: 0, width: spineMM * pointsPerMM, height: panelH), context: ctx)
            for front in [false, true] {
                // The faces are laid out on the real Pixart panel, so the title is fitted where it is drawn.
                let face = BookCoverGeometry(book: book, front: front, size: CGSize(width: panelW, height: panelH))
                let outer = CGRect(x: front ? -hinge : -wrap, y: -wrap,
                                   width: panelW + hinge + wrap, height: panelH + 2*wrap)
                ctx.saveGState()
                if front { ctx.translateBy(x: width - panelW, y: 0) }
                try drawFace(face, photoID: front ? book.cover?.frontPhotoID : book.cover?.backPhotoID,
                             images: images, book: book, directory: directory, context: ctx, outer: outer)
                ctx.restoreGState()
            }
            ctx.endPDFPage()
            meter?.sheetDone()
        }
        if let cover {
            begin(width: 2 * w + spine, height: h, bleed: bleed)
            let spread = CGRect(x: 0, y: 0, width: 2 * w + spine, height: h)
            let back = BookCoverGeometry(book: book, front: false, bleed: bleed)
            ctx.setFillColor(EditorialStyle.color(back.background))
            ctx.fill(spread.insetBy(dx: -bleed, dy: -bleed))
            let backOuter = CGRect(x: -bleed, y: -bleed, width: w + bleed, height: h + 2 * bleed)
            try drawFace(back, photoID: cover.backPhotoID, images: images, book: book, directory: directory, context: ctx,
                         outer: backOuter)
            drawSpine(book, in: CGRect(x: w, y: 0, width: spine, height: h), context: ctx)
            ctx.translateBy(x: w + spine, y: 0)
            let front = BookCoverGeometry(book: book, front: true, bleed: bleed)
            let frontOuter = CGRect(x: 0, y: -bleed, width: w + bleed, height: h + 2 * bleed)
            try drawFace(front, photoID: cover.frontPhotoID, images: images, book: book, directory: directory, context: ctx,
                         outer: frontOuter)
            ctx.endPDFPage()
            meter?.sheetDone()
        } else {
            let slots = leaves(book.pages, settings: settings, pixart: pixartSpineMM != nil)
            let size = settings?.spreads == true ? 2 : 1
            for first in stride(from: 0, to: slots.count, by: size) {
                let sheet = slots[first..<(first + size)]
                try Task.checkCancellation()
                begin(width: Double(sheet.count)*w, height: h, bleed: bleed)
                try autoreleasepool {
                    for (index,slot) in sheet.enumerated() {
                        ctx.saveGState()
                        defer { ctx.restoreGState() }
                        ctx.translateBy(x: Double(index)*w, y: 0)
                        let left = index == 0 ? bleed : 0
                        let right = index == sheet.count-1 ? bleed : 0
                        let leafArea = CGRect(x: -left, y: -bleed, width: w+left+right, height: h+2*bleed)
                        guard let leaf = slot else {
                            // A compensation blank is still a page of the book: print it on the template's paper.
                            ctx.setFillColor(EditorialStyle.color(book.editorialStyle.paper))
                            ctx.fill(leafArea)
                            continue
                        }
                        ctx.clip(to: leafArea)
                        ctx.translateBy(x: -Double(leaf.half)*w, y: 0)
                        try draw(leaf.page, pageNumber: leaf.number, book: book, directory: directory,
                                 context: ctx, bleed: bleed, images: images)
                    }
                }
                ctx.endPDFPage()
                meter?.sheetDone()
            }
        }
        ctx.closePDF()
        closed = true
    }

    private static func draw(_ page: BookPage, pageNumber: Int, book: Book, directory: URL,
                             context: CGContext, bleed: Double, images: ImageOutput) throws {
        // Frames stay at the editor's size; photos reaching the trim are carried into the bleed by paint.
        let composition = PageComposition(page: page, book: book)
        let style = book.editorialStyle
        context.setFillColor(EditorialStyle.color(style.paper))
        context.fill(composition.bounds.insetBy(dx: -bleed, dy: -bleed))
        if let rule = composition.rule {
            context.setFillColor(EditorialStyle.color(style.accent))
            context.fill(rule)
        }
        if let missing = page.photoIDs.first(where: { book.photo($0) == nil }) {
            throw ExportError.missingImage(missing.uuidString)
        }
        let stitchedSlots = page.arrangement.map { $0.isFullBleed && $0.photoCapacity == composition.photos.count } == true
            && page.photoPlacements?.values.contains(where: { $0.frame != nil }) != true
        let storyBlocks = composition.storyDrawingBlocks(page: page, book: book)
        let backgrounds = composition.storyBackgroundFrames(page: page, blocks: storyBlocks)
        for layer in composition.layers {
            switch layer {
            case let .photo(id):
                guard let index = composition.photos.firstIndex(where: { $0.id == id }) else { continue }
                let slot = composition.photos[index]
                // A photo slips under the neighbors painted after it, whatever the slot order.
                let underlap = stitchedSlots ? tileUnderlap(at: index, in: composition.arrangementPhotoSlots) {
                    composition.rank(.photo(composition.photos[$0].id)) > composition.rank(layer)
                } : Underlap()
                try paint(slot.photo, rect: slot.frame, fills: slot.fills, crop: slot.crop, images: images,
                          book: book, directory: directory, context: context, underlap: underlap,
                          trim: composition.bounds, outer: composition.bounds.insetBy(dx: -bleed, dy: -bleed))
            case .story:
                if !backgrounds.isEmpty {
                    context.saveGState()
                    context.setAlpha(style.overlayOpacity)
                    context.setFillColor(EditorialStyle.color(style.overlayPaper))
                    context.addRects(backgrounds)
                    context.fillPath()
                    context.restoreGState()
                    context.setFillColor(EditorialStyle.color(style.overlayAccent))
                    context.addRects(backgrounds.compactMap { style.overlayMark(in: $0) })
                    context.fillPath()
                }
                for block in storyBlocks where block.text.length > 0 {
                    try drawText(block.text, in: block.frame, overflow: .textOverflow(pageNumber), context: context)
                }
            case let .textBox(id):
                guard let box = composition.textBoxes.first(where: { $0.id == id }),
                      box.prints(paper: style.paper, ink: style.ink) else { continue }
                let frame = box.frame.rect(in: composition.bounds)
                if let fill = box.fill(paper: style.paper) {
                    context.setFillColor(EditorialStyle.color(fill))
                    context.fill(frame)
                }
                if let border = box.border(ink: style.ink) {
                    context.setStrokeColor(EditorialStyle.color(border.color))
                    context.setLineWidth(border.width)
                    context.stroke(frame.insetBy(dx: border.width / 2, dy: border.width / 2))
                }
                let textFrame = frame.insetBy(dx: box.textInsetPoints, dy: box.textInsetPoints)
                try drawText(PageComposition.boxText(box: box, book: book),
                             in: textFrame, overflow: .textOverflow(pageNumber), context: context)
            }
        }
        if let folio = composition.folio {
            _ = EditorialTypesetter.draw(style.typography(String(pageNumber), heading: nil, mixed: false),
                                         in: folio, context: context)
        }
    }

    /// How far a photo extends under each neighbor painted after it.
    private struct Underlap: Equatable {
        var top: CGFloat = 0, left: CGFloat = 0, bottom: CGFloat = 0, right: CGFloat = 0
    }

    private static func tileUnderlap(at index: Int, in slots: [CGRect], paintedLater: (Int) -> Bool) -> Underlap {
        let frame = slots[index]
        let later = slots.indices.filter { $0 != index && paintedLater($0) }.map { slots[$0] }
        let tolerance: CGFloat = 0.000001
        func overlapsVertically(_ other: CGRect) -> Bool {
            other.maxY > frame.minY + tolerance && other.minY < frame.maxY - tolerance
        }
        func overlapsHorizontally(_ other: CGRect) -> Bool {
            other.maxX > frame.minX + tolerance && other.minX < frame.maxX - tolerance
        }
        // Cover the reader's independently antialiased photo edges, including at thumbnail scale.
        let reach: CGFloat = 7
        return Underlap(
            top: later.contains { abs($0.maxY - frame.minY) < tolerance && overlapsHorizontally($0) } ? reach : 0,
            left: later.contains { abs($0.maxX - frame.minX) < tolerance && overlapsVertically($0) } ? reach : 0,
            bottom: later.contains { abs($0.minY - frame.maxY) < tolerance && overlapsHorizontally($0) } ? reach : 0,
            right: later.contains { abs($0.minX - frame.maxX) < tolerance && overlapsVertically($0) } ? reach : 0)
    }

    private static func paint(_ photo: BookPhoto, rect: CGRect, fills: Bool, crop: PhotoCrop, images: ImageOutput,
                              book: Book, directory: URL, context: CGContext, underlap: Underlap = Underlap(),
                              trim: CGRect, outer: CGRect) throws {
        guard !rect.isEmpty else { return }
        let source = BookStorage.assetURL(filename: photo.filename, in: directory)
        let settings = book.effectiveFilm(for: photo)
        let lut = settings.lutFilename.map { BookStorage.lutURL(filename: $0, in: directory) }
        let pixels = CGSize(width: max(1, photo.pixelWidth), height: max(1, photo.pixelHeight))
        let cropped = crop.imageRect(for: pixels, in: rect, fills: fills)
        let desired = ceil(max(cropped.width, cropped.height) * images.ppi / 72)
        let maxPixels = Int(min(max(pixels.width, pixels.height), max(1, desired)))
        guard let rendered = FilmRenderer.image(from: source, maxPixelSize: maxPixels, settings: settings, lutURL: lut,
                                                adjustments: photo.adjustments)
        else { throw ExportError.missingImage(photo.name) }
        let area = fills ? bleedArea(of: rect, trim: trim, outer: outer) : rect
        let (padded, placement) = mirrorPadded(rendered, placement: cropped, toCover: area)
        let image = jpegBacked(padded, quality: images.quality)
        if underlap != Underlap() {
            // The seams run through the bleed too, where the neighbors are also carried out.
            let reach = CGRect(x: area.minX - underlap.left, y: area.minY - underlap.top,
                               width: area.width + underlap.left + underlap.right,
                               height: area.height + underlap.top + underlap.bottom)
            let seams = CGMutablePath()
            if underlap.left > 0 {
                seams.addRect(CGRect(x: reach.minX, y: reach.minY, width: 2 * underlap.left, height: reach.height))
            }
            if underlap.right > 0 {
                seams.addRect(CGRect(x: reach.maxX - 2 * underlap.right, y: reach.minY, width: 2 * underlap.right,
                                     height: reach.height))
            }
            if underlap.top > 0 {
                seams.addRect(CGRect(x: reach.minX, y: reach.minY, width: reach.width, height: 2 * underlap.top))
            }
            if underlap.bottom > 0 {
                seams.addRect(CGRect(x: reach.minX, y: reach.maxY - 2 * underlap.bottom, width: reach.width,
                                     height: 2 * underlap.bottom))
            }
            let extended = placement.union(reach)
            context.saveGState()
            context.addPath(seams)
            context.clip()
            drawImage(image, at: extended, in: context)
            context.restoreGState()
        }
        context.saveGState()
        context.clip(to: area)
        drawImage(image, at: placement, in: context)
        context.restoreGState()
    }

    /// The area a photo prints in: its frame, carried out to `outer` on every side where it reaches `trim`.
    /// The crop is computed for the frame alone, so the photo inside the trim matches the editor.
    static func bleedArea(of frame: CGRect, trim: CGRect, outer: CGRect) -> CGRect {
        let tolerance: CGFloat = 0.01
        let minX = frame.minX <= trim.minX + tolerance ? min(frame.minX, outer.minX) : frame.minX
        let minY = frame.minY <= trim.minY + tolerance ? min(frame.minY, outer.minY) : frame.minY
        let maxX = frame.maxX >= trim.maxX - tolerance ? max(frame.maxX, outer.maxX) : frame.maxX
        let maxY = frame.maxY >= trim.maxY - tolerance ? max(frame.maxY, outer.maxY) : frame.maxY
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Where the crop leaves no spare image for the bleed, extends the image by reflecting it at its own edge.
    /// The reflection is built in pixels, so the print shows no seam where it meets the photograph.
    private static func mirrorPadded(_ image: CGImage, placement: CGRect, toCover area: CGRect) -> (CGImage, CGRect) {
        guard !placement.isEmpty, image.width > 0, image.height > 0 else { return (image, placement) }
        let w = image.width, h = image.height
        let scaleX = CGFloat(w) / placement.width, scaleY = CGFloat(h) / placement.height
        func pad(_ points: CGFloat, _ scale: CGFloat, _ limit: Int) -> Int {
            points > 0.001 ? min(limit, Int(ceil(points * scale)) + 1) : 0
        }
        let left = pad(placement.minX - area.minX, scaleX, w), right = pad(area.maxX - placement.maxX, scaleX, w)
        let top = pad(placement.minY - area.minY, scaleY, h), bottom = pad(area.maxY - placement.maxY, scaleY, h)
        guard left + right + top + bottom > 0,
              let context = CGContext(data: nil, width: w + left + right, height: h + top + bottom, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: rgb,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return (image, placement) }
        context.interpolationQuality = .none
        // Bitmap rows run bottom up: the page's bottom padding is at y = 0.
        let xs: [(axis: CGFloat?, used: Bool)] = [(CGFloat(left), left > 0), (nil, true), (CGFloat(left + w), right > 0)]
        let ys: [(axis: CGFloat?, used: Bool)] = [(CGFloat(bottom), bottom > 0), (nil, true), (CGFloat(bottom + h), top > 0)]
        for x in xs where x.used {
            for y in ys where y.used {
                context.saveGState()
                if let axis = x.axis {
                    context.translateBy(x: 2 * axis, y: 0)
                    context.scaleBy(x: -1, y: 1)
                }
                if let axis = y.axis {
                    context.translateBy(x: 0, y: 2 * axis)
                    context.scaleBy(x: 1, y: -1)
                }
                context.draw(image, in: CGRect(x: left, y: bottom, width: w, height: h))
                context.restoreGState()
            }
        }
        guard let padded = context.makeImage() else { return (image, placement) }
        return (padded, CGRect(x: placement.minX - CGFloat(left) / scaleX, y: placement.minY - CGFloat(top) / scaleY,
                               width: CGFloat(padded.width) / scaleX, height: CGFloat(padded.height) / scaleY))
    }

    /// Re-encodes a render as JPEG. Quartz embeds a JPEG-backed image as DCT data, so a page of
    /// photographs costs a few megabytes instead of the lossless pixels.
    private static func jpegBacked(_ image: CGImage, quality: Double) -> CGImage {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { return image }
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: quality,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination), let provider = CGDataProvider(data: data),
              let jpeg = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true,
                                 intent: .defaultIntent)
        else { return image }
        return jpeg
    }

    private static func drawImage(_ image: CGImage, at placement: CGRect, in context: CGContext) {
        context.translateBy(x: placement.minX, y: placement.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: placement.size))
    }

    private static func drawFace(_ face: BookCoverGeometry, photoID: UUID?, images: ImageOutput, book: Book,
                                 directory: URL, context: CGContext, outer: CGRect) throws {
        if let id = photoID {
            guard let photo = book.photo(id) else { throw ExportError.missingImage(id.uuidString) }
            context.saveGState()
            defer { context.restoreGState() }
            context.clip(to: outer)
            try paint(photo, rect: face.photoFrame, fills: face.fills, crop: face.photoCrop, images: images,
                      book: book, directory: directory, context: context, trim: face.bounds, outer: outer)
        }
        // A band or rule that reaches the trim continues into the bleed, wrap and hinge like the photo.
        if let band = face.band {
            context.setFillColor(color(0.97, 0.97, 0.97, alpha: 0.94))
            context.fill(bleedArea(of: band, trim: face.bounds, outer: outer))
        }
        if let rule = face.rule {
            context.setFillColor(EditorialStyle.color(book.editorialStyle.accent))
            context.fill(bleedArea(of: rule, trim: face.bounds, outer: outer))
        }
        if let rect = face.titleFrame {
            try drawText(face.title, in: rect, overflow: .coverTextOverflow, context: context)
        }
    }

    /// The title runs top to bottom on spines of at least 5 mm, with its tops toward the front cover.
    static func spineTitle(_ book: Book, spineWidth: CGFloat) -> NSAttributedString? {
        let text = (book.cover?.title ?? book.title).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, spineWidth >= 5 * pointsPerMM else { return nil }
        let style = book.editorialStyle
        let size = min(spineWidth * 0.48, 13)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let ink: UInt32 = book.template == nil ? 0xF2F2F2 : style.titleInk
        return NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(style.titleFont as CFString, size, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): EditorialStyle.color(ink),
            .paragraphStyle: paragraph,
        ])
    }

    private static func drawSpine(_ book: Book, in spine: CGRect, context: CGContext) {
        guard let title = spineTitle(book, spineWidth: spine.width) else { return }
        let margin = min(spine.height * 0.08, 18 * pointsPerMM)
        let length = spine.height - 2 * margin
        let height = min(spine.width, EditorialTypesetter.requiredHeight(title, width: .greatestFiniteMagnitude))
        context.saveGState()
        context.translateBy(x: spine.midX, y: spine.minY + margin)
        context.rotate(by: .pi / 2)
        EditorialTypesetter.draw(title, in: CGRect(x: 0, y: -height / 2, width: length, height: height), context: context)
        context.restoreGState()
    }

    private static func drawText(_ text: NSAttributedString, in rect: CGRect, overflow: ExportError,
                                 context: CGContext) throws {
        if !EditorialTypesetter.draw(text, in: rect, context: context) { throw overflow }
    }
}
