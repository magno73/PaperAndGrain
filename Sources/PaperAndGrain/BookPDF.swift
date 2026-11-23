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
        let safe = settings.safeMM * pointsPerMM
        guard w.isFinite, h.isFinite, min(w,h) > 50, safe >= 0, 2*safe < min(w,h),
              bleed.isFinite, bleed >= 0, settings.targetPPI.isFinite, settings.targetPPI > 0 else {
            return ["Dimensioni non valide · Invalid print dimensions"]
        }
        var warnings = [String]()
        func check(_ photo: BookPhoto, in rect: CGRect, fills: Bool, location: String) {
            guard rect.width > 0, rect.height > 0 else { return }
            let x = Double(photo.pixelWidth)*72/rect.width
            let y = Double(photo.pixelHeight)*72/rect.height
            let actual = fills ? min(x,y) : max(x,y)
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
            let photos = page.photoIDs.compactMap(book.photo)
            if photos.count != page.photoIDs.count { warnings.append(loc+" · Foto mancante / Missing photo") }
            switch page.layout {
            case .fullSpread, .fullPage:
                let rect = CGRect(x: 0, y: 0, width: (page.layout == .fullSpread ? 2*w : w)+2*bleed, height: h+2*bleed)
                if let photo = photos.first { check(photo, in: rect, fills: true, location: loc) }
            case .gallery, .mixed:
                let available = CGRect(x: safe, y: safe, width: w-2*safe, height: h-2*safe)
                let rect = page.layout == .mixed
                    ? BookLayoutGeometry.mixedArea(in: available, placement: page.textPlacement, spacing: 12).photo
                    : available
                let slots = BookLayoutGeometry.rectangles(for: photos.map { Double($0.pixelWidth)/Double(max(1,$0.pixelHeight)) },
                                                          in: rect, gap: 6)
                for (photo,slot) in zip(photos,slots) { check(photo, in: slot, fills: false, location: loc) }
            case .text: break
            }
        }
        if let cover = book.cover {
            for id in [cover.frontPhotoID, cover.backPhotoID].compactMap({ $0 }) {
                if let photo = book.photo(id) {
                    check(photo, in: CGRect(x: 0, y: 0, width: w+bleed, height: h+2*bleed),
                          fills: true, location: "Copertina / Cover")
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
        let safe = settings.map { $0.safeMM * pointsPerMM } ?? book.contentInsetPoints
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
            let spread = CGRect(x: 0, y: 0, width: 2*w+spine, height: h)
            ctx.setFillColor(color(0.16, 0.16, 0.16))
            ctx.fill(spread.insetBy(dx: -bleed, dy: -bleed))
            for (id,x) in [(cover.backPhotoID, 0.0), (cover.frontPhotoID, w+spine)] {
                if let id {
                    guard let photo = book.photo(id) else { throw ExportError.missingImage(id.uuidString) }
                    let rect = CGRect(x: x == 0 ? -bleed : x, y: -bleed, width: w+bleed, height: h+2*bleed)
                    try paint(photo, rect: rect, fills: true, framing: nil, ppi: ppi, book: book, directory: directory, context: ctx)
                }
            }
            if !cover.title.isEmpty {
                let band = CGRect(x: w+spine, y: h*0.63, width: w+bleed, height: h*0.37+bleed)
                ctx.setFillColor(color(0.97, 0.97, 0.97, alpha: 0.94))
                ctx.fill(band)
                try drawText(cover.title, in: CGRect(x: w+spine+safe, y: band.minY+safe, width: w-2*safe, height: h-band.minY-2*safe), pageNumber: 0, context: ctx)
            }
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
                    let bounds = CGRect(x: 0, y: 0, width: leaf.page.layout == .fullSpread ? 2*w : w, height: h)
                    try draw(leaf.page, in: bounds, pageNumber: leaf.number, book: book, directory: directory,
                             context: ctx, bleed: bleed, inset: safe, ppi: ppi)
                    ctx.restoreGState()
                }
                ctx.endPDFPage()
            }
        }
        ctx.closePDF()
        try Task.checkCancellation()
        try (output as Data).write(to: url, options: .atomic)
    }

    private static func draw(_ page: BookPage, in bounds: CGRect, pageNumber: Int,
                             book: Book, directory: URL, context: CGContext, bleed: Double, inset: Double, ppi: Double) throws {
        let outer = bounds.insetBy(dx: -bleed, dy: -bleed)
        context.setFillColor(color(0.976, 0.965, 0.935))
        context.fill(outer)
        let safe = bounds.insetBy(dx: inset, dy: inset)
        let photos = page.photoIDs.compactMap(book.photo)
        if let missing = page.photoIDs.first(where: { book.photo($0) == nil }) { throw ExportError.missingImage(missing.uuidString) }
        let textRect: CGRect
        let photoRect: CGRect
        switch page.layout {
        case .text:
            photoRect = .zero
            textRect = safe
        case .mixed:
            (photoRect, textRect) = BookLayoutGeometry.mixedArea(in: safe, placement: page.textPlacement, spacing: 12)
        case .fullPage, .fullSpread:
            photoRect = outer
            textRect = .zero
        case .gallery:
            photoRect = safe
            textRect = .zero
        }
        if !photoRect.isEmpty {
            let fillsImage = page.layout == .fullPage || page.layout == .fullSpread
            let arranged = fillsImage ? Array(photos.prefix(1)) : photos
            let slots = fillsImage ? [photoRect] : BookLayoutGeometry.rectangles(
                for: arranged.map { Double($0.pixelWidth) / Double(max(1, $0.pixelHeight)) }, in: photoRect, gap: 6
            )
            for (photo, slot) in zip(arranged, slots) {
                try paint(photo, rect: slot, fills: fillsImage, framing: page.framing, ppi: ppi,
                          book: book, directory: directory, context: context)
            }
        }
        if !page.text.isEmpty && (page.layout == .mixed || page.layout == .text) {
            try drawText(page.text, in: textRect, pageNumber: pageNumber, context: context)
        }
    }

    private static func paint(_ photo: BookPhoto, rect: CGRect, fills: Bool, framing: Double?, ppi: Double,
                              book: Book, directory: URL, context: CGContext) throws {
        let source = BookStorage.assetURL(filename: photo.filename, in: directory)
        let settings = book.effectiveFilm(for: photo)
        let lut = settings.lutFilename.map { BookStorage.lutURL(filename: $0, in: directory) }
        let width = Double(max(1, photo.pixelWidth))
        let height = Double(max(1, photo.pixelHeight))
        let zoom = fills ? max(rect.width/width, rect.height/height) : min(rect.width/width, rect.height/height)
        let maxPixels = Int(min(max(width,height), max(1,ceil(max(width,height)*zoom*ppi/72))))
        guard let image = FilmRenderer.image(from: source, maxPixelSize: maxPixels, settings: settings, lutURL: lut)
        else { throw ExportError.missingImage(photo.name) }
        drawImage(image, in: rect, fills: fills, framing: framing, context: context)
    }

    private static func drawImage(_ image: CGImage, in rect: CGRect, fills: Bool,
                                  framing: Double?, context: CGContext) {
        let width = Double(image.width)
        let height = Double(image.height)
        let scale = fills ? max(rect.width / width, rect.height / height) : min(rect.width / width, rect.height / height)
        let alignment = fills ? max(0, min(1, framing ?? 0.5)) : 0.5
        let fittedWidth = width * scale
        let fittedHeight = height * scale
        let placement = CGRect(x: rect.minX + (rect.width - fittedWidth) * alignment,
                               y: rect.minY + (rect.height - fittedHeight) * alignment,
                               width: fittedWidth, height: fittedHeight)
        context.saveGState()
        context.clip(to: rect)
        context.translateBy(x: placement.minX, y: placement.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: placement.size))
        context.restoreGState()
    }

    private static func drawText(_ text: String, in rect: CGRect, pageNumber: Int, context: CGContext) throws {
        guard rect.width > 0, rect.height > 0 else { throw ExportError.textOverflow(pageNumber) }
        let font = CTFontCreateWithName("Baskerville" as CFString, 14, nil)
        let attributed = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color(0.18, 0.18, 0.18),
        ])
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let boundary = CGPath(rect: CGRect(origin: .zero, size: rect.size), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: attributed.length),
                                            boundary, nil)
        guard CTFrameGetVisibleStringRange(frame).length == attributed.length else {
            throw ExportError.textOverflow(pageNumber)
        }
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        CTFrameDraw(frame, context)
        context.restoreGState()
    }
}
