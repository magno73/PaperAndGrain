import AppKit
import CoreGraphics
import CoreText

/// Captions: the text that travels with a photo (`BookPhoto.caption`), set in the book's caption
/// style and placed per page (`PhotoPlacement.captionPosition`). `PageComposition` lays them out
/// once; the canvas, thumbnails, **Browse the Book**, the preflight and the PDF all read that result.
extension EditorialStyle {
    /// The template's caption: the body typeface at about 80 % of its size, left aligned. A few
    /// templates use another face of their family where the body face reads badly that small.
    var defaultCaptionStyle: EditorialTextStyle {
        let font: String = switch identity {
        case .japaneseInterval: "HiraMinProN-W3"
        case .monograph: "IowanOldStyle-Italic"
        case .roadLog: "AmericanTypewriter"
        default: bodyFont
        }
        let size = (bodySize * 0.8 * 4).rounded() / 4
        return EditorialTextStyle(fontName: font, pointSize: max(8.5, size), alignment: .left)
    }

    /// The template's ink at reduced strength, mixed with the paper so it prints as a solid color.
    var captionInk: UInt32 { Self.mix(ink, paper, inkShare: 0.74) }
    /// The caption ink on the panel the template uses for text over a photo.
    var overlayCaptionInk: UInt32 { Self.mix(overlayInk, overlayPaper, inkShare: 0.82) }

    /// The caption as Core Text draws it. `override` holds the book's changes (Book Typography).
    func captionTypography(_ text: String, override: EditorialTextStyle, overPhoto: Bool) -> NSAttributedString {
        let base = defaultCaptionStyle
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = (override.alignment ?? base.alignment ?? .left).paragraphAlignment
        paragraph.lineSpacing = 1
        return NSAttributedString(string: text, attributes: attributes(
            font: base.fontName ?? bodyFont, override: override, size: base.pointSize ?? bodySize,
            color: overPhoto ? overlayCaptionInk : captionInk, paragraph: paragraph,
            tracking: identity == .swissGrid || identity == .postcard ? 0.1 : 0))
    }

    /// Half a caption line: the space between a photo and its caption, and the band's padding.
    func captionGap(override: EditorialTextStyle) -> CGFloat {
        let size = override.normalizedSize ?? defaultCaptionStyle.pointSize ?? bodySize
        let font = CTFontCreateWithName((override.fontName ?? defaultCaptionStyle.fontName ?? bodyFont) as CFString, size, nil)
        let line = CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
        return (max(size, line) / 2).rounded()
    }

    static func mix(_ ink: UInt32, _ paper: UInt32, inkShare: Double) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let a = Double((ink >> shift) & 255), b = Double((paper >> shift) & 255)
            return UInt32((a * inkShare + b * (1 - inkShare)).rounded()) << shift
        }
        return channel(16) | channel(8) | channel(0)
    }
}

/// A caption written from the photo's own data, as in "Etosha, 12 May 2024".
enum CaptionText {
    /// Place and capture date in `language`, leaving out what is missing; nil when both are.
    static func automatic(place: String?, date: Date?, language: String, timeZone: TimeZone = .current) -> String? {
        let name = place?.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []
        if let name, !name.isEmpty { parts.append(name) }
        if let date {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: L10n.code(language))
            formatter.timeZone = timeZone
            formatter.dateFormat = "d MMMM y"
            parts.append(formatter.string(from: date))
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

extension PageComposition {
    /// A caption laid out on the page, in the page's points from the top left.
    struct Caption: Identifiable {
        let photoID: UUID
        var id: UUID { photoID }
        /// Where the text is set.
        let frame: CGRect
        /// The panel behind a caption on the photo; nil for a caption on the paper.
        let band: CGRect?
        let text: NSAttributedString
        /// Below, above or inside; a hidden caption is not laid out.
        let position: CaptionPosition
        /// False when it does not fit: on the photo and taller than half of it, across the trim, or
        /// taller than the band an automatic layout kept for it.
        let fits: Bool

        /// What the caption covers on the page: its band, or its text.
        var area: CGRect { band ?? frame }
    }
}

/// Lays out captions for one page. Rules (PRD T4): a caption is as wide as its photo and as tall as
/// its text; it sits half a line below or above the frame, or on a band at the bottom of the photo;
/// automatic placement prefers below and falls back to the photo when the text would cross the safe
/// line. Automatic slots give up one shared band so photos keep a common size.
struct CaptionSetter {
    let style: EditorialStyle
    let override: EditorialTextStyle
    let bounds: CGRect
    /// The print safe line: the trim inset by the book's safe margin.
    let safe: CGRect
    let spread: Bool
    let gap: CGFloat
    /// A story panel painted over the photos; a band on a photo moves to the top to stay visible.
    let storyPanel: CGRect?

    init(book: Book, page: BookPage, bounds: CGRect, storyPanel: CGRect?) {
        style = book.editorialStyle
        override = book.captionStyle
        self.bounds = bounds
        let inset = (book.printSettings ?? PrintSettings()).safeMM * 72 / 25.4
        let limit = max(0, min(bounds.width, bounds.height) / 2 - 1)
        safe = bounds.insetBy(dx: min(inset, limit), dy: min(inset, limit))
        spread = page.effectiveLayout == .fullSpread
        gap = style.captionGap(override: override)
        self.storyPanel = storyPanel
    }

    /// The position a photo asks for on this page, before automatic placement; nil prints nothing.
    static func request(_ photo: BookPhoto, _ placement: PhotoPlacement?) -> CaptionPosition?? {
        guard photo.printedCaption != nil, placement?.captionPosition != .hidden else { return nil }
        return .some(placement?.captionPosition)
    }

    func text(_ photo: BookPhoto, overPhoto: Bool) -> NSAttributedString {
        style.captionTypography(photo.printedCaption ?? "", override: override, overPhoto: overPhoto)
    }

    /// The horizontal extent of the text: the photo's, kept inside the safe line and off the gutter
    /// of a spread.
    func column(_ minX: CGFloat, _ maxX: CGFloat) -> (CGFloat, CGFloat) {
        var low = max(minX, safe.minX)
        var high = min(maxX, safe.maxX)
        if high - low < min(36, (maxX - minX) * 0.5) { (low, high) = (minX, maxX) }
        if spread, low < bounds.midX, high > bounds.midX {
            let inset = safe.minX - bounds.minX
            if bounds.midX - inset - low >= 36 { high = bounds.midX - inset } else { low = bounds.midX + inset }
        }
        return (low, max(low, high))
    }

    func paperColumn(of frame: CGRect) -> (x: CGFloat, width: CGFloat) {
        let visible = frame.intersection(bounds)
        let (low, high) = column(visible.minX, visible.maxX)
        return (low, high - low)
    }

    func height(_ text: NSAttributedString, width: CGFloat) -> CGFloat {
        EditorialTypesetter.requiredHeight(text, width: width)
    }

    /// Automatic placement for a slot of an automatic layout: below when the slot sits inside the safe
    /// line, so the band can come out of it; on the photo for a slot that bleeds.
    func automaticPosition(slot: CGRect) -> CaptionPosition {
        safe.insetBy(dx: -0.5, dy: -0.5).contains(slot) ? .below : .inside
    }

    /// Shrinks automatic slots so captions below or above fit: every slot gives up the same band, as tall
    /// as the tallest caption plus the gap. `layout(band)` returns the photo frames with that band kept.
    func carve(_ slots: [CGRect], positions: [CaptionPosition?], texts: [NSAttributedString?], cap: CGFloat,
               layout: (CGFloat) -> [CGRect]) -> (frames: [CGRect], band: CGFloat) {
        // A page without captions on the paper keeps its slots exactly.
        guard positions.contains(where: { $0 == .below || $0 == .above }), cap > 0 else { return (slots, 0) }
        var frames = slots
        func needed(_ frames: [CGRect]) -> CGFloat {
            var tallest: CGFloat = 0
            for (index, frame) in frames.enumerated() where index < positions.count {
                guard positions[index] == .below || positions[index] == .above, let text = texts[index] else { continue }
                tallest = max(tallest, height(text, width: paperColumn(of: frame).width))
            }
            return min(cap, tallest + gap)
        }
        var band: CGFloat = 0
        // Narrower photos can wrap a caption onto another line; three rounds settle any real page.
        for _ in 0..<3 {
            let next = needed(band == 0 ? frames : layout(band))
            if next <= band + 0.01 { break }
            band = next
        }
        frames = layout(band).enumerated().map { index, frame in
            index < positions.count && positions[index] == .above ? frame.offsetBy(dx: 0, dy: band) : frame
        }
        return (frames, band)
    }

    /// The caption of a photo drawn in `frame`. `position` is already resolved for automatic slots;
    /// `band` is the space an automatic layout kept, or nil for a frame placed by hand.
    func caption(_ photo: BookPhoto, frame: CGRect, requested: CaptionPosition?, band: CGFloat?) -> PageComposition.Caption? {
        let visible = frame.intersection(bounds)
        guard !visible.isNull, visible.width > 1, visible.height > 1 else { return nil }
        let onPaper = text(photo, overPhoto: false)
        let (x, width) = paperColumn(of: frame)
        let paperHeight = height(onPaper, width: width)
        let position = requested ?? (visible.maxY + gap + paperHeight <= safe.maxY + 0.5 ? .below : .inside)
        switch position {
        case .below, .above:
            let y = position == .below ? visible.maxY + gap : visible.minY - gap - paperHeight
            let rect = CGRect(x: x, y: y, width: width, height: paperHeight)
            var fits = bounds.insetBy(dx: -0.5, dy: -0.5).contains(rect)
            if let band, paperHeight > band - gap + 0.5 { fits = false }
            return PageComposition.Caption(photoID: photo.id, frame: rect, band: nil, text: onPaper,
                                           position: position, fits: fits)
        case .inside:
            return inside(photo, visible: visible)
        case .hidden:
            return nil
        }
    }

    private func inside(_ photo: BookPhoto, visible: CGRect) -> PageComposition.Caption {
        let text = text(photo, overPhoto: true)
        let padding = gap
        var (low, high) = column(visible.minX + padding * 1.5, visible.maxX - padding * 1.5)
        if high - low < 12 { (low, high) = (visible.minX, visible.maxX) }
        let textHeight = height(text, width: high - low)
        let bottomBand = { () -> (CGRect, CGRect) in
            let bottom = min(visible.maxY - padding, self.safe.maxY)
            let top = bottom - textHeight
            return (CGRect(x: low, y: top, width: high - low, height: textHeight),
                    CGRect(x: visible.minX, y: top - padding, width: visible.width, height: visible.maxY - top + padding))
        }
        let topBand = { () -> (CGRect, CGRect) in
            let top = max(visible.minY + padding, self.safe.minY)
            return (CGRect(x: low, y: top, width: high - low, height: textHeight),
                    CGRect(x: visible.minX, y: visible.minY, width: visible.width, height: top + textHeight + padding - visible.minY))
        }
        var (frame, band) = bottomBand()
        if let storyPanel, storyPanel.intersects(band) {
            let flipped = topBand()
            if !storyPanel.intersects(flipped.1) { (frame, band) = flipped }
        }
        band = band.intersection(visible)
        let fits = textHeight <= visible.height / 2 && bounds.insetBy(dx: -0.5, dy: -0.5).contains(frame)
        return PageComposition.Caption(photoID: photo.id, frame: frame, band: band, text: text,
                                       position: .inside, fits: fits)
    }
}
