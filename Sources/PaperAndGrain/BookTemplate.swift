import AppKit
import CoreGraphics
import CoreText

enum BookTemplate: String, Codable, CaseIterable, Identifiable, Sendable {
    case diary, atlas, gallery, essential, swissGrid, berlinQuarter, japaneseInterval

    var id: Self { self }

    func name(language: String) -> String {
        switch self {
        case .diary: language == "it" ? "Diario" : "Journal"
        case .atlas: language == "it" ? "Atlante" : "Atlas"
        case .gallery: language == "it" ? "Galleria" : "Gallery"
        case .swissGrid: language == "it" ? "Griglia svizzera" : "Swiss Grid"
        case .berlinQuarter: language == "it" ? "Quaderno berlinese" : "Berlin Notebook"
        case .japaneseInterval: language == "it" ? "Intervallo giapponese" : "Japanese Interval"
        case .essential: language == "it" ? "Essenziale" : "Essential"
        }
    }

    func description(language: String) -> String {
        switch self {
        case .diary:
            language == "it" ? "Carta avorio e titoli in grande. Per alternare il racconto alle fotografie."
                : "Ivory paper and generous headlines. For alternating stories with photographs."
        case .atlas:
            language == "it" ? "Griglia, carta chiara e folio. Per paesaggi, tappe e sequenze."
                : "A grid, light paper and page numbers. For landscapes, stops and sequences."
        case .gallery:
            language == "it" ? "Fondo carbone e margini larghi. Una foto alla volta."
                : "Charcoal paper and generous margins. One image at a time."
        case .swissGrid: language == "it" ? "Griglia a sei colonne, neretto compatto e cartiglio segnato in rosso." : "Six-column grid, compact bold type and a caption panel marked in red."
        case .berlinQuarter: language == "it" ? "Blu notte, titoli cedro e una fascia fotografica sopra la testata." : "Midnight blue, citron headlines and a strip of photography above the masthead."
        case .japaneseInterval: language == "it" ? "Piccola stampa decentrata, titoli Mincho e una didascalia su carta calda." : "An off-centre print, Mincho headings and a caption on warm paper."
        case .essential:
            language == "it" ? "Bianco netto, titoli leggeri e fotografia a piena pagina."
                : "Pure white, light typography and edge-to-edge photography."
        }
    }

    var style: EditorialStyle {
        switch self {
        case .diary:
            EditorialStyle(paper: 0xF6EEDF, ink: 0x272321, accent: 0x8C4B35, titleFont: "Didot",
                           bodyFont: "Baskerville", titleSize: 44, bodySize: 15, insetFraction: 0.090,
                           columnFraction: 0.78, imageGap: 11, rule: false, folio: false, titleTracking: -0.9)
        case .atlas:
            EditorialStyle(paper: 0xF4F2E9, ink: 0x252D26, accent: 0x53634F, titleFont: "AvenirNext-DemiBold",
                           bodyFont: "AvenirNext-Regular", titleSize: 33, bodySize: 12.3, insetFraction: 0.063,
                           columnFraction: 0.96, imageGap: 14, rule: true, folio: true, titleTracking: -0.6)
        case .gallery:
            EditorialStyle(paper: 0x232422, ink: 0xF3ECDE, accent: 0xC4A083, titleFont: "Baskerville-Italic",
                           bodyFont: "Optima-Regular", titleSize: 41, bodySize: 12.5, insetFraction: 0.115,
                           columnFraction: 0.78, imageGap: 12, rule: false, folio: false,
                           coverTitleBelow: true, titleTracking: -0.55)
        case .swissGrid:
            EditorialStyle(paper: 0xF8F7F1, ink: 0x171819, accent: 0xC33023, titleFont: "HelveticaNeue-Bold",
                           bodyFont: "HelveticaNeue", titleSize: 28, bodySize: 12, insetFraction: 0.064,
                           columnFraction: 5.0 / 6, imageGap: 8, rule: true, folio: true, titleTracking: -0.65,
                           coverWindow: CGRect(x: 2.0 / 6, y: 0.32, width: 4.0 / 6, height: 0.68), identity: self)
        case .berlinQuarter:
            EditorialStyle(paper: 0x172439, ink: 0xF5F4E9, accent: 0xD8EC63, titleFont: "AvenirNextCondensed-Heavy",
                           bodyFont: "Georgia", titleSize: 33, bodySize: 13, insetFraction: 0.052,
                           columnFraction: 1, imageGap: 5, rule: false, folio: true, coverTitleBelow: true,
                           titleTracking: -0.55, textTopFraction: 0.32,
                           coverWindow: CGRect(x: 0, y: 0, width: 1, height: 0.64), identity: self)
        case .japaneseInterval:
            EditorialStyle(paper: 0xF4EEE1, ink: 0x373930, accent: 0x737956, titleFont: "HiraMinProN-W3",
                           bodyFont: "Palatino-Roman", titleSize: 20, bodySize: 12.5, insetFraction: 0.115,
                           columnFraction: 0.80, imageGap: 27, rule: false, folio: false, titleTracking: 0.3,
                           textTopFraction: 0.20, coverWindow: CGRect(x: 0.48, y: 0.35, width: 0.52, height: 0.48),
                           identity: self)
        case .essential:
            EditorialStyle(paper: 0xFFFFFF, ink: 0x1B1B1D, accent: 0x717174, titleFont: "HelveticaNeue-Light",
                           bodyFont: "HelveticaNeue", titleSize: 50, bodySize: 13.5, insetFraction: 0.096,
                           columnFraction: 0.73, imageGap: 10, rule: false, folio: false,
                           titleTracking: -1.8, textTopFraction: 0.10, coverWideImage: true)
        }
    }
}

struct EditorialStyle {
    var paper: UInt32
    var ink: UInt32
    var accent: UInt32
    var titleFont: String
    var bodyFont: String
    var titleSize: Double
    var bodySize: Double
    var insetFraction: Double
    var columnFraction: Double
    var imageGap: Double
    var rule: Bool
    var folio: Bool
    var coverTitleBelow = false
    var titleTracking: Double = 0
    var textTopFraction: Double = 0
    var coverWideImage = false

    var coverWindow: CGRect?
    var identity: BookTemplate?

    var overlayOpacity: Double { identity == nil ? 0.90 : 1 }
    var overlayPaper: UInt32 { paper }
    var overlayInk: UInt32 { ink }
    var titleInk: UInt32 { identity == .berlinQuarter ? accent : ink }
    var overlayTitleInk: UInt32 { titleInk }
    var overlayAccent: UInt32 { accent }

    func overlayMark(in panel: CGRect) -> CGRect? {
        switch identity {
        case .swissGrid: CGRect(x: panel.minX, y: panel.minY, width: min(4, panel.width), height: panel.height)
        case .berlinQuarter: CGRect(x: panel.minX, y: panel.minY, width: panel.width, height: min(5, panel.height))
        case .japaneseInterval: CGRect(x: panel.minX, y: panel.minY, width: panel.width * 0.22, height: min(1, panel.height))
        default: nil
        }
    }

    func coverRule(in panel: CGRect) -> CGRect? {
        guard rule else { return nil }
        let swiss = identity == .swissGrid
        return CGRect(x: panel.minX, y: panel.minY, width: panel.width * (swiss ? 1.0 / 3 : 1), height: swiss ? 6 : 0.8)
    }

    func pageRule(in safe: CGRect) -> CGRect? {
        guard rule else { return nil }
        let swiss = identity == .swissGrid
        return CGRect(x: safe.minX, y: safe.minY - 9, width: safe.width * (swiss ? 1.0 / 6 : 1), height: swiss ? 4 : 0.55)
    }

    static let classic = EditorialStyle(paper: 0xF9F6EE, ink: 0x2E2E2E, accent: 0x586357,
                                        titleFont: "Baskerville", bodyFont: "Baskerville", titleSize: 30, bodySize: 14,
                                        insetFraction: 0, columnFraction: 1, imageGap: 6, rule: false, folio: false)

    private var mixedTitleScale: Double { identity == nil ? 0.61 : 0.75 }

    func defaultTitleStyle(mixed: Bool) -> EditorialTextStyle {
        EditorialTextStyle(fontName: titleFont, pointSize: titleSize * (mixed ? mixedTitleScale : 1), alignment: .left)
    }

    /// A short editorial heading can borrow a few points of scale before wrapping.
    /// Deliberate returns, explicit sizes and long titles retain their normal paragraph flow.
    func fittedTitleStyle(_ heading: String?, width: CGFloat, mixed: Bool,
                          override: EditorialTextStyle) -> EditorialTextStyle {
        let floor: CGFloat
        switch identity {
        case .swissGrid: floor = 20
        case .berlinQuarter: floor = 24
        case .japaneseInterval: floor = 16
        default: return override
        }
        guard override.pointSize == nil, width > 0, let heading, !heading.isEmpty,
              heading.count <= 48, heading.rangeOfCharacter(from: .newlines) == nil else { return override }
        let line = CTLineCreateWithAttributedString(typography("", heading: heading, mixed: mixed, titleStyle: override))
        let measured = CTLineGetTypographicBounds(line, nil, nil, nil)
        guard measured > width else { return override }
        let scale = mixed ? mixedTitleScale : 1.0
        let size = titleSize * scale * max(0, width - 1) / measured
        guard size >= floor * scale else { return override }
        var fitted = override
        fitted.pointSize = (size * 4).rounded(.down) / 4
        return fitted
    }

    var defaultBodyStyle: EditorialTextStyle {
        EditorialTextStyle(fontName: bodyFont, pointSize: bodySize, alignment: .left)
    }

    func textArea(in safe: CGRect, mixed: Bool, fullColumn: Bool = false) -> CGRect {
        guard !mixed else { return safe }
        let top = (rule ? 11.0 : 0) + safe.height * textTopFraction
        let width = safe.width * (fullColumn ? 1 : columnFraction)
        let left = identity == .japaneseInterval ? safe.maxX - width : safe.minX
        return CGRect(x: left, y: safe.minY + top, width: width, height: max(0, safe.height - top))
    }

    static func color(_ rgb: UInt32) -> CGColor {
        let r = CGFloat((rgb >> 16) & 255) / 255
        let g = CGFloat((rgb >> 8) & 255) / 255
        let b = CGFloat(rgb & 255) / 255
        return CGColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    func typography(_ text: String, heading: String?, mixed: Bool,
                    titleStyle: EditorialTextStyle? = nil, bodyStyle: EditorialTextStyle? = nil, overPhoto: Bool = false) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let title = heading?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !title.isEmpty {
            let titleParagraph = NSMutableParagraphStyle()
            switch identity {
            case .swissGrid: titleParagraph.paragraphSpacing = mixed ? 5 : 9
            case .berlinQuarter: titleParagraph.paragraphSpacing = mixed ? 6 : 12
            case .japaneseInterval: titleParagraph.paragraphSpacing = mixed ? 9 : 22
            default: titleParagraph.paragraphSpacing = mixed ? 7 : 17
            }
            titleParagraph.lineSpacing = 1
            if let alignment = titleStyle?.alignment { titleParagraph.alignment = alignment.paragraphAlignment }
            result.append(NSAttributedString(string: text.isEmpty ? title : title + "\n", attributes: attributes(
                font: titleFont, override: titleStyle, size: titleSize * (mixed ? mixedTitleScale : 1), color: overPhoto ? overlayTitleInk : titleInk, paragraph: titleParagraph,
                tracking: titleTracking * (mixed ? mixedTitleScale : 1)
            )))
        }
        let paragraph = NSMutableParagraphStyle()
        if let alignment = bodyStyle?.alignment { paragraph.alignment = alignment.paragraphAlignment }
        if insetFraction > 0 {
            paragraph.lineSpacing = bodyFont == "HelveticaNeue" ? 3.2 : 3.8
            paragraph.paragraphSpacing = 6
        }
        result.append(NSAttributedString(string: text, attributes: attributes(
            font: bodyFont, override: bodyStyle, size: bodySize, color: overPhoto ? overlayInk : ink, paragraph: paragraph
        )))
        return result
    }

    func coverPicture(in panel: CGRect, bleed: Double) -> CGRect {
        if let window = coverWindow {
            return CGRect(x: panel.minX + panel.width * window.minX, y: panel.minY + panel.height * window.minY,
                          width: panel.width * window.width, height: panel.height * window.height)
        }
        if coverWideImage {
            let inset = panel.minY
            return CGRect(x: panel.minX - inset, y: panel.minY + panel.height * 0.28,
                          width: panel.width + 2 * inset + bleed, height: panel.height * 0.72 + inset + bleed)
        }
        let top = coverTitleBelow ? panel.minY : panel.minY + panel.height * 0.31
        let bottom = coverTitleBelow ? panel.minY + panel.height * 0.64 : panel.maxY
        return CGRect(x: panel.minX, y: top, width: panel.width, height: bottom - top)
    }

    private func attributes(font: String, override: EditorialTextStyle?, size: Double, color: UInt32, paragraph: NSParagraphStyle,
                            tracking: Double = 0) -> [NSAttributedString.Key: Any] {
        let pointSize = override?.normalizedSize ?? size
        let available = override?.fontName.flatMap { NSFont(name: $0, size: pointSize) }
        let name = available?.fontName ?? font
        return [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(name as CFString, pointSize, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): Self.color(color),
            NSAttributedString.Key(kCTKernAttributeName as String): tracking,
            .paragraphStyle: paragraph,
        ]
    }
}

enum EditorialTypesetter {
    static func requiredHeight(_ attributed: NSAttributedString, width: CGFloat) -> CGFloat {
        guard attributed.length > 0, width > 0 else { return 0 }
        let setter = CTFramesetterCreateWithAttributedString(attributed)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(location: 0, length: 0), nil,
                                                               CGSize(width: width, height: .greatestFiniteMagnitude), nil)
        return ceil(size.height) + 2
    }

    private static func textFrame(_ attributed: NSAttributedString, in rect: CGRect) -> CTFrame? {
        guard rect.width > 0, rect.height > 0 else { return nil }
        return CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(attributed),
                                        CFRange(location: 0, length: attributed.length),
                                        CGPath(rect: CGRect(origin: .zero, size: rect.size), transform: nil), nil)
    }

    /// Baseline distance from the top edge of the same frame used by draw().
    static func baseline(_ attributed: NSAttributedString, at index: Int, in rect: CGRect) -> CGFloat? {
        guard index >= 0, index < attributed.length, let frame = textFrame(attributed, in: rect) else { return nil }
        let lines = CTFrameGetLines(frame) as! [CTLine]
        for (number, line) in lines.enumerated() {
            let range = CTLineGetStringRange(line)
            guard index >= range.location && index < range.location + range.length else { continue }
            var origin = CGPoint.zero
            CTFrameGetLineOrigins(frame, CFRange(location: number, length: 1), &origin)
            return rect.height - origin.y
        }
        return nil
    }

    static func fits(_ attributed: NSAttributedString, in rect: CGRect) -> Bool {
        if attributed.length == 0 { return true }
        guard let frame = textFrame(attributed, in: rect) else { return false }
        return CTFrameGetVisibleStringRange(frame).length == attributed.length
    }

    /// Draws into a top-left coordinate system. The return value reports text overflow.
    @discardableResult
    static func draw(_ attributed: NSAttributedString, in rect: CGRect, context: CGContext) -> Bool {
        if attributed.length == 0 { return true }
        guard let frame = textFrame(attributed, in: rect) else { return false }
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        CTFrameDraw(frame, context)
        context.restoreGState()
        return CTFrameGetVisibleStringRange(frame).length == attributed.length
    }
}
