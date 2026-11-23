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
        let width = book.format.widthMM * pointsPerMM
        let height = book.format.heightMM * pointsPerMM
        guard width.isFinite, height.isFinite, width > 50, height > 50, !book.pages.isEmpty else {
            throw ExportError.invalidBook
        }
        let output = NSMutableData()
        var media = CGRect(x: 0, y: 0, width: width, height: height)
        guard let consumer = CGDataConsumer(data: output as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &media, [
                kCGPDFContextTitle as String: book.title
              ] as CFDictionary) else { throw ExportError.invalidBook }
        var pageNumber = 1
        for page in book.pages {
            try Task.checkCancellation()
            let halves = page.layout == .fullSpread ? 2 : 1
            for half in 0..<halves {
                context.beginPDFPage(nil)
                let pageRect = CGRect(x: 0, y: 0, width: width * Double(halves), height: height)
                context.saveGState()
                context.clip(to: media)
                context.translateBy(x: -Double(half) * width, y: height)
                context.scaleBy(x: 1, y: -1)
                try draw(page, in: pageRect, pageNumber: pageNumber, book: book, directory: directory, context: context)
                context.restoreGState()
                context.endPDFPage()
                pageNumber += 1
            }
        }
        context.closePDF()
        try (output as Data).write(to: destination, options: .atomic)
    }

    private static func draw(_ page: BookPage, in bounds: CGRect, pageNumber: Int,
                             book: Book, directory: URL, context: CGContext) throws {
        context.setFillColor(red: 0.976, green: 0.965, blue: 0.935, alpha: 1)
        context.fill(bounds)
        let inset = min(30, bounds.height * 0.11)
        let safe = bounds.insetBy(dx: inset, dy: inset)
        let photos = page.photoIDs.compactMap(book.photo)
        let textRect: CGRect
        let photoRect: CGRect
        switch page.layout {
        case .text:
            photoRect = .zero
            textRect = safe
        case .mixed:
            photoRect = CGRect(x: safe.minX, y: safe.minY, width: safe.width, height: safe.height * 0.57)
            textRect = CGRect(x: safe.minX, y: photoRect.maxY + 12, width: safe.width, height: safe.maxY - photoRect.maxY - 12)
        case .fullPage, .fullSpread:
            photoRect = bounds
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
                let source = BookStorage.assetURL(filename: photo.filename, in: directory)
                let maxPixels = min(6200, max(500, Int(max(slot.width, slot.height) / 72 * 320)))
                guard let image = LocalImages.load(source, maxPixelSize: maxPixels) else {
                    throw ExportError.missingImage(photo.name)
                }
                drawImage(image, in: slot, fills: fillsImage, framing: page.framing, context: context)
            }
        }
        if !page.text.isEmpty && !textRect.isEmpty {
            try drawText(page.text, in: textRect, pageNumber: pageNumber, context: context)
        }
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
        let font = CTFontCreateWithName("Baskerville" as CFString, 14, nil)
        let attributed = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.18, alpha: 1),
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
