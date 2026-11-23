import CoreGraphics
import CoreText
import Foundation

enum BookPDF {
    private static let pointsPerMM = 72.0 / 25.4

    enum ExportError: LocalizedError {
        case invalidBook
        case missingImage(String)
        case textOverflow(Int)

        var errorDescription: String? {
            switch self {
            case .invalidBook: "Impossibile creare il PDF · Could not create the PDF"
            case let .missingImage(name): "Foto non disponibile · Photo unavailable — \(name)"
            case let .textOverflow(number): "Il testo eccede lo spazio a pagina \(number) · Text overflows on page \(number)"
            }
        }
    }

    static func write(_ book: Book, directory: URL, to destination: URL) throws {
        try render(book, directory: directory, settings: nil, cover: nil, to: destination)
    }

    static func writePrint(_ book: Book, directory: URL, to destination: URL) throws {
        let settings = book.printSettings ?? PrintSettings()
        let fm = FileManager.default
        let scratch = destination.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: scratch) }
        try render(book, directory: directory, settings: settings, cover: nil,
                   to: scratch.appendingPathComponent("Interior.pdf"))
        if let cover = book.cover {
            try render(book, directory: directory, settings: settings, cover: cover,
                       to: scratch.appendingPathComponent("Cover.pdf"))
        }
        try Task.checkCancellation()
        if fm.fileExists(atPath: destination.path) {
            guard try fm.contentsOfDirectory(atPath: destination.path).isEmpty else { throw CocoaError(.fileWriteFileExists) }
            _ = try fm.replaceItemAt(destination, withItemAt: scratch)
        } else {
            try fm.moveItem(at: scratch, to: destination)
        }
    }

    static func printWarnings(_ book: Book) -> [String] {
        let settings = book.printSettings ?? PrintSettings()
        let w = book.format.widthMM * pointsPerMM
        let h = book.format.heightMM * pointsPerMM
        let bleed = settings.bleedMM * pointsPerMM
        let safe = book.contentInsetPoints
        guard w.isFinite, h.isFinite, min(w,h) > 50, safe >= 0, 2*safe < min(w,h),
              bleed.isFinite, bleed >= 0, settings.targetPPI.isFinite, settings.targetPPI > 0 else {
            return ["Dimensioni non valide · Invalid print dimensions"]
        }
        var warnings = [String]()
        func check(_ photo: BookPhoto, frame: CGRect, fills: Bool, crop: PhotoCrop, location: String) {
            let pixels = CGSize(width: photo.pixelWidth, height: photo.pixelHeight)
            let drawn = crop.imageRect(for: pixels, in: frame, fills: fills)
            guard drawn.width > 0 else { return }
            let actual = pixels.width * 72 / drawn.width
            if actual < settings.targetPPI {
                warnings.append(String(format: "%@ · %@ · %.0f ppi < %.0f ppi", location, photo.name, actual, settings.targetPPI))
            }
        }
        let slots = leaves(book.pages, settings: settings)
        let blanks = slots.indices.filter { slots[$0] == nil }.map { String($0 + 1) }
        if !blanks.isEmpty {
            warnings.append("Pagine bianche di compensazione / Blank pages for alignment · " + blanks.joined(separator: ", "))
        }
        for leaf in slots.compactMap({ $0 }) where leaf.half == 0 {
            let page = leaf.page
            let loc = "p. "+String(leaf.number)
            if page.photoIDs.contains(where: { book.photo($0) == nil }) {
                warnings.append(loc + " · Foto mancante / Missing photo")
            }
            for slot in PageComposition(page: page, book: book, bleed: bleed).photos {
                check(slot.photo, frame: slot.frame, fills: slot.fills, crop: slot.crop, location: loc)
            }
        }
        if let cover = book.cover {
            for (id, front) in [(cover.frontPhotoID, true), (cover.backPhotoID, false)] {
                guard let id else { continue }
                if let photo = book.photo(id) {
                    let face = BookCoverGeometry(book: book, front: front, bleed: bleed)
                    check(photo, frame: face.photoFrame, fills: face.fills, crop: PhotoCrop(), location: "Copertina / Cover")
                } else { warnings.append("Copertina / Cover · Foto mancante / Missing photo") }
            }
        }
        return warnings
    }

    private struct Leaf {
        let page: BookPage
        let half: Int
        let number: Int
    }

    private static func leaves(_ pages: [BookPage], settings: PrintSettings?) -> [Leaf?] {
        var leaves = [Leaf?]()
        if settings?.firstPageOnRight == true { leaves.append(nil) }
        for page in pages {
            if page.layout == .fullSpread && settings != nil && !leaves.count.isMultiple(of: 2) {
                leaves.append(nil)
            }
            leaves.append(Leaf(page: page, half: 0, number: leaves.count + 1))
            if page.layout == .fullSpread {
                leaves.append(Leaf(page: page, half: 1, number: leaves.count + 1))
            }
        }
        if settings?.spreads == true && !leaves.count.isMultiple(of: 2) { leaves.append(nil) }
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

    private static func render(_ book: Book, directory: URL, settings: PrintSettings?, cover: BookCover?, to url: URL) throws {
        let w = book.format.widthMM * pointsPerMM
        let h = book.format.heightMM * pointsPerMM
        let bleed = (settings?.bleedMM ?? 0) * pointsPerMM
        let safe = book.contentInsetPoints
        let ppi = settings?.targetPPI ?? 320
        let spine = (cover?.spineMM ?? 0) * pointsPerMM
        guard w.isFinite, h.isFinite, w > 50, h > 50, !book.pages.isEmpty,
              bleed.isFinite, bleed >= 0, safe >= 0, safe * 2 < min(w,h),
              ppi.isFinite, ppi > 0, spine.isFinite, spine >= 0 else { throw ExportError.invalidBook }
        let output = NSMutableData()
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
        guard let consumer = CGDataConsumer(data: output as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &media, metadata as CFDictionary)
        else { throw ExportError.invalidBook }
        func begin(width: Double) {
            let trim = CGRect(x: bleed, y: bleed, width: width, height: h)
            let full = trim.insetBy(dx: -bleed, dy: -bleed)
            ctx.beginPDFPage([kCGPDFContextMediaBox as String: box(full), kCGPDFContextTrimBox as String: box(trim),
                              kCGPDFContextBleedBox as String: box(full)] as CFDictionary)
            ctx.translateBy(x: bleed, y: bleed + h)
            ctx.scaleBy(x: 1, y: -1)
        }
        if let cover {
            begin(width: 2 * w + spine)
            let spread = CGRect(x: 0, y: 0, width: 2 * w + spine, height: h)
            let back = BookCoverGeometry(book: book, front: false, bleed: bleed)
            ctx.setFillColor(EditorialStyle.color(back.background))
            ctx.fill(spread.insetBy(dx: -bleed, dy: -bleed))
            try drawFace(back, photoID: cover.backPhotoID, ppi: ppi, book: book, directory: directory, context: ctx)
            ctx.translateBy(x: w + spine, y: 0)
            let front = BookCoverGeometry(book: book, front: true, bleed: bleed)
            try drawFace(front, photoID: cover.frontPhotoID, ppi: ppi, book: book, directory: directory, context: ctx)
            ctx.endPDFPage()
        } else {
            let slots = leaves(book.pages, settings: settings)
            let size = settings?.spreads == true ? 2 : 1
            for first in stride(from: 0, to: slots.count, by: size) {
                let sheet = slots[first..<(first + size)]
                try Task.checkCancellation()
                begin(width: Double(sheet.count)*w)
                for (index,slot) in sheet.enumerated() {
                    guard let leaf = slot else { continue }
                    ctx.saveGState()
                    ctx.translateBy(x: Double(index)*w, y: 0)
                    let left = index == 0 ? bleed : 0
                    let right = index == sheet.count-1 ? bleed : 0
                    ctx.clip(to: CGRect(x: -left, y: -bleed, width: w+left+right, height: h+2*bleed))
                    ctx.translateBy(x: -Double(leaf.half)*w, y: 0)
                    try draw(leaf.page, pageNumber: leaf.number, book: book, directory: directory,
                             context: ctx, bleed: bleed, ppi: ppi)
                    ctx.restoreGState()
                }
                ctx.endPDFPage()
            }
        }
        ctx.closePDF()
        try Task.checkCancellation()
        try (output as Data).write(to: url, options: .atomic)
    }

    private static func draw(_ page: BookPage, pageNumber: Int, book: Book, directory: URL,
                             context: CGContext, bleed: Double, ppi: Double) throws {
        let composition = PageComposition(page: page, book: book, bleed: bleed)
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
        for slot in composition.photos {
            try paint(slot.photo, rect: slot.frame, fills: slot.fills, crop: slot.crop, ppi: ppi,
                      book: book, directory: directory, context: context)
        }
        if let story = composition.story {
            try drawText(style.typography(page.text, heading: page.heading, mixed: page.layout == .mixed),
                         in: story, pageNumber: pageNumber, context: context)
        }
        for box in composition.textBoxes where !box.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let frame = box.frame.rect(in: composition.bounds)
            context.setFillColor(EditorialStyle.color(style.paper))
            context.fill(frame)
            let textFrame = frame.insetBy(dx: PageTextBox.textInset, dy: PageTextBox.textInset)
            try drawText(style.typography(box.text, heading: nil, mixed: true),
                         in: textFrame, pageNumber: pageNumber, context: context)
        }
        if let folio = composition.folio {
            _ = EditorialTypesetter.draw(style.typography(String(pageNumber), heading: nil, mixed: false),
                                         in: folio, context: context)
        }
    }

    private static func paint(_ photo: BookPhoto, rect: CGRect, fills: Bool, crop: PhotoCrop, ppi: Double,
                              book: Book, directory: URL, context: CGContext) throws {
        guard !rect.isEmpty else { return }
        let source = BookStorage.assetURL(filename: photo.filename, in: directory)
        let settings = book.effectiveFilm(for: photo)
        let lut = settings.lutFilename.map { BookStorage.lutURL(filename: $0, in: directory) }
        let pixels = CGSize(width: max(1, photo.pixelWidth), height: max(1, photo.pixelHeight))
        let placement = crop.imageRect(for: pixels, in: rect, fills: fills)
        let desired = ceil(max(placement.width, placement.height) * ppi / 72)
        let maxPixels = Int(min(max(pixels.width, pixels.height), max(1, desired)))
        guard let image = FilmRenderer.image(from: source, maxPixelSize: maxPixels, settings: settings, lutURL: lut)
        else { throw ExportError.missingImage(photo.name) }
        context.saveGState()
        context.clip(to: rect)
        context.translateBy(x: placement.minX, y: placement.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: placement.size))
        context.restoreGState()
    }

    private static func drawFace(_ face: BookCoverGeometry, photoID: UUID?, ppi: Double, book: Book,
                                 directory: URL, context: CGContext) throws {
        if let id = photoID {
            guard let photo = book.photo(id) else { throw ExportError.missingImage(id.uuidString) }
            try paint(photo, rect: face.photoFrame, fills: face.fills, crop: PhotoCrop(), ppi: ppi,
                      book: book, directory: directory, context: context)
        }
        if let band = face.band {
            context.setFillColor(color(0.97, 0.97, 0.97, alpha: 0.94))
            context.fill(band)
        }
        if let rule = face.rule {
            context.setFillColor(EditorialStyle.color(book.editorialStyle.accent))
            context.fill(rule)
        }
        if let rect = face.titleFrame {
            try drawText(face.title, in: rect, pageNumber: 0, context: context)
        }
    }

    private static func drawText(_ text: NSAttributedString, in rect: CGRect, pageNumber: Int, context: CGContext) throws {
        if !EditorialTypesetter.draw(text, in: rect, context: context) { throw ExportError.textOverflow(pageNumber) }
    }
}
