import AppKit
import CoreGraphics
import CoreText
import Foundation

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

    static func writePixart(_ book: Book, directory: URL, spineMM: Double, to destination: URL) throws {
        guard PixartPrintProfile.supports(book.format), PixartPrintProfile.isValidSpine(spineMM) else {
            throw ExportError.invalidBook
        }
        try render(book, directory: directory, settings: pixartSettings(book), cover: nil, to: destination,
                   pixartSpineMM: spineMM)
    }

    private static func pixartSettings(_ book: Book) -> PrintSettings {
        var settings = book.printSettings ?? PrintSettings()
        settings.spreads = false
        settings.bleedMM = PixartPrintProfile.bleed
        settings.targetPPI = 300
        return settings
    }

    static func printWarnings(_ book: Book, pixart: Bool = false) -> [String] {
        let settings = pixart ? pixartSettings(book) : book.printSettings ?? PrintSettings()
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
        let slots = leaves(book.pages, settings: settings, pixart: pixart)
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
            for slot in PageComposition(page: page, book: book).photos {
                check(slot.photo, frame: slot.frame, fills: slot.fills, crop: slot.crop, location: loc)
            }
        }
        if let cover = book.cover {
            for (id, front) in [(cover.frontPhotoID, true), (cover.backPhotoID, false)] {
                guard let id else { continue }
                if let photo = book.photo(id) {
                    let face = pixart
                        ? BookCoverGeometry(book: book, front: front, size: CGSize(
                            width: PixartPrintProfile.panelWidth * pointsPerMM,
                            height: PixartPrintProfile.panelHeight * pointsPerMM))
                        : BookCoverGeometry(book: book, front: front, bleed: bleed)
                    check(photo, frame: face.photoFrame, fills: face.fills, crop: face.photoCrop, location: "Copertina / Cover")
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

    private static func render(_ book: Book, directory: URL, settings: PrintSettings?, cover: BookCover?, to url: URL,
                               pixartSpineMM: Double? = nil) throws {
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
                             ppi: ppi, book: book, directory: directory, context: ctx, outer: outer)
                ctx.restoreGState()
            }
            ctx.endPDFPage()
        }
        if let cover {
            begin(width: 2 * w + spine, height: h, bleed: bleed)
            let spread = CGRect(x: 0, y: 0, width: 2 * w + spine, height: h)
            let back = BookCoverGeometry(book: book, front: false, bleed: bleed)
            ctx.setFillColor(EditorialStyle.color(back.background))
            ctx.fill(spread.insetBy(dx: -bleed, dy: -bleed))
            let backOuter = CGRect(x: -bleed, y: -bleed, width: w + bleed, height: h + 2 * bleed)
            try drawFace(back, photoID: cover.backPhotoID, ppi: ppi, book: book, directory: directory, context: ctx,
                         outer: backOuter)
            drawSpine(book, in: CGRect(x: w, y: 0, width: spine, height: h), context: ctx)
            ctx.translateBy(x: w + spine, y: 0)
            let front = BookCoverGeometry(book: book, front: true, bleed: bleed)
            let frontOuter = CGRect(x: 0, y: -bleed, width: w + bleed, height: h + 2 * bleed)
            try drawFace(front, photoID: cover.frontPhotoID, ppi: ppi, book: book, directory: directory, context: ctx,
                         outer: frontOuter)
            ctx.endPDFPage()
        } else {
            let slots = leaves(book.pages, settings: settings, pixart: pixartSpineMM != nil)
            let size = settings?.spreads == true ? 2 : 1
            for first in stride(from: 0, to: slots.count, by: size) {
                let sheet = slots[first..<(first + size)]
                try Task.checkCancellation()
                begin(width: Double(sheet.count)*w, height: h, bleed: bleed)
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
                let underlap = stitchedSlots ? tileUnderlap(at: index, in: composition.arrangementPhotoSlots) : .zero
                try paint(slot.photo, rect: slot.frame, fills: slot.fills, crop: slot.crop, ppi: ppi,
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
                      !box.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || box.border(ink: style.ink) != nil else { continue }
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

    private static func tileUnderlap(at index: Int, in slots: [CGRect]) -> CGSize {
        let frame = slots[index]
        let following = slots.dropFirst(index + 1)
        let tolerance: CGFloat = 0.000001
        let right = following.contains {
            abs($0.minX - frame.maxX) < tolerance && $0.maxY > frame.minY + tolerance && $0.minY < frame.maxY - tolerance
        }
        let below = following.contains {
            abs($0.minY - frame.maxY) < tolerance && $0.maxX > frame.minX + tolerance && $0.minX < frame.maxX - tolerance
        }
        // Cover the reader's independently antialiased photo edges, including at thumbnail scale.
        return CGSize(width: right ? 7 : 0, height: below ? 7 : 0)
    }

    private static func paint(_ photo: BookPhoto, rect: CGRect, fills: Bool, crop: PhotoCrop, ppi: Double,
                              book: Book, directory: URL, context: CGContext, underlap: CGSize = .zero,
                              trim: CGRect, outer: CGRect) throws {
        guard !rect.isEmpty else { return }
        let source = BookStorage.assetURL(filename: photo.filename, in: directory)
        let settings = book.effectiveFilm(for: photo)
        let lut = settings.lutFilename.map { BookStorage.lutURL(filename: $0, in: directory) }
        let pixels = CGSize(width: max(1, photo.pixelWidth), height: max(1, photo.pixelHeight))
        let cropped = crop.imageRect(for: pixels, in: rect, fills: fills)
        let desired = ceil(max(cropped.width, cropped.height) * ppi / 72)
        let maxPixels = Int(min(max(pixels.width, pixels.height), max(1, desired)))
        guard let rendered = FilmRenderer.image(from: source, maxPixelSize: maxPixels, settings: settings, lutURL: lut,
                                                adjustments: photo.adjustments)
        else { throw ExportError.missingImage(photo.name) }
        let area = fills ? bleedArea(of: rect, trim: trim, outer: outer) : rect
        let (image, placement) = mirrorPadded(rendered, placement: cropped, toCover: area)
        if underlap != .zero {
            let seams = CGMutablePath()
            // The seams run through the bleed too, where the neighbors are also carried out.
            if underlap.width > 0 {
                seams.addRect(CGRect(x: area.maxX - underlap.width, y: area.minY, width: 2 * underlap.width,
                                     height: area.height + underlap.height))
            }
            if underlap.height > 0 {
                seams.addRect(CGRect(x: area.minX, y: area.maxY - underlap.height, width: area.width,
                                     height: 2 * underlap.height))
            }
            let low = CGPoint(x: min(placement.minX, area.minX), y: min(placement.minY, area.minY))
            let extended = CGRect(x: low.x, y: low.y,
                                  width: max(placement.maxX, area.maxX + underlap.width) - low.x,
                                  height: max(placement.maxY, area.maxY + underlap.height) - low.y)
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

    private static func drawImage(_ image: CGImage, at placement: CGRect, in context: CGContext) {
        context.translateBy(x: placement.minX, y: placement.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: placement.size))
    }

    private static func drawFace(_ face: BookCoverGeometry, photoID: UUID?, ppi: Double, book: Book,
                                 directory: URL, context: CGContext, outer: CGRect) throws {
        if let id = photoID {
            guard let photo = book.photo(id) else { throw ExportError.missingImage(id.uuidString) }
            context.saveGState()
            defer { context.restoreGState() }
            context.clip(to: outer)
            try paint(photo, rect: face.photoFrame, fills: face.fills, crop: face.photoCrop, ppi: ppi,
                      book: book, directory: directory, context: context, trim: face.bounds, outer: outer)
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
