import CoreGraphics
import Foundation

/// A rectangle relative to a trimmed page (or both leaves of a panorama), measured from the top left.
struct PageRect: Codable, Hashable, Sendable {
    static let maximumPhotoScale = 4.0
    static let photoOverlapFraction = 0.05

    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(_ frame: CGRect, in bounds: CGRect) {
        self.init(x: (frame.minX - bounds.minX) / bounds.width,
                  y: (frame.minY - bounds.minY) / bounds.height,
                  width: frame.width / bounds.width, height: frame.height / bounds.height)
    }

    var clamped: Self {
        let w = min(1, max(0.001, width))
        let h = min(1, max(0.001, height))
        return Self(x: min(1 - w, max(0, x)), y: min(1 - h, max(0, y)), width: w, height: h)
    }

    var photoClamped: Self {
        let w = width.isFinite ? min(Self.maximumPhotoScale, max(0.001, width)) : 1
        let h = height.isFinite ? min(Self.maximumPhotoScale, max(0.001, height)) : 1
        let visibleWidth = min(w, Self.photoOverlapFraction)
        let visibleHeight = min(h, Self.photoOverlapFraction)
        let left = min(1 - visibleWidth, max(visibleWidth - w, x.isFinite ? x : 0))
        let top = min(1 - visibleHeight, max(visibleHeight - h, y.isFinite ? y : 0))
        return Self(x: left, y: top, width: w, height: h)
    }

    func rect(in bounds: CGRect) -> CGRect {
        clamped.denormalized(in: bounds)
    }

    /// Extend a frame that reaches an outside trim edge into the printer's bleed.
    func photoRect(in bounds: CGRect, bleed: Double = 0) -> CGRect {
        Self.extendingToBleed(photoClamped.denormalized(in: bounds), in: bounds, bleed: bleed)
    }

    fileprivate static func extendingToBleed(_ frame: CGRect, in bounds: CGRect, bleed: Double) -> CGRect {
        guard bleed > 0 else { return frame }
        let epsilon = 0.000001
        let left = frame.minX <= bounds.minX + epsilon ? max(0, bleed - abs(frame.minX - bounds.minX)) : 0
        let right = frame.maxX >= bounds.maxX - epsilon ? max(0, bleed - abs(frame.maxX - bounds.maxX)) : 0
        let top = frame.minY <= bounds.minY + epsilon ? max(0, bleed - abs(frame.minY - bounds.minY)) : 0
        let bottom = frame.maxY >= bounds.maxY - epsilon ? max(0, bleed - abs(frame.maxY - bounds.maxY)) : 0
        return CGRect(x: frame.minX - left, y: frame.minY - top, width: frame.width + left + right,
                      height: frame.height + top + bottom)
    }

    private func denormalized(in bounds: CGRect) -> CGRect {
        CGRect(x: bounds.minX + x * bounds.width, y: bounds.minY + y * bounds.height,
               width: width * bounds.width, height: height * bounds.height)
    }
}

struct PhotoCrop: Codable, Hashable, Sendable {
    var x: Double = 0.5
    var y: Double = 0.5
    var zoom: Double = 1

    func imageRect(for source: CGSize, in frame: CGRect, fills: Bool) -> CGRect {
        guard source.width > 0, source.height > 0, !frame.isEmpty else { return .zero }
        let sx = frame.width / source.width
        let sy = frame.height / source.height
        let scale = fills ? max(sx, sy) * min(12, max(1, zoom)) : min(sx, sy)
        let w = source.width * scale
        let h = source.height * scale
        return CGRect(x: frame.minX + (frame.width - w) * (fills ? min(1, max(0, x)) : 0.5),
                      y: frame.minY + (frame.height - h) * (fills ? min(1, max(0, y)) : 0.5),
                      width: w, height: h)
    }
}

struct PhotoPlacement: Codable, Hashable, Sendable {
    var frame: PageRect? = nil
    var crop: PhotoCrop? = nil
}

struct PageTextBox: Identifiable, Codable, Hashable, Sendable {
    static let textInset: Double = 9
    var id = UUID()
    var text = ""
    var frame: PageRect
    var typography: EditorialTextStyle? = nil
    var usesFullWidth: Bool? = nil
    var textInsetPoints: Double { usesFullWidth == true ? 0 : Self.textInset }
}

struct PageComposition {
    enum TextRole: String, Identifiable, Sendable {
        case title, body, combined
        var id: Self { self }
    }

    struct TextBlock: Identifiable {
        let role: TextRole
        let frame: CGRect
        let text: NSAttributedString
        var id: TextRole { role }
    }

    /// The untouched story is one Core Text frame so old paragraph flow and clipping remain exact.
    func storyDrawingBlocks(page: BookPage, book: Book) -> [TextBlock] {
        if page.titleFrame == nil && page.storyFrame == nil {
            guard let story else { return [] }
            return [TextBlock(role: .combined, frame: story, text: Self.storyText(
                page: page, book: book, width: story.width, overPhoto: storyBackground != nil
            ))]
        }
        return storyBlocks(page: page, book: book)
    }

    func storyBackgroundFrames(page: BookPage, blocks: [TextBlock]) -> [CGRect] {
        guard let storyBackground else { return [] }
        if let stored = page.storyBackdropFrames { return stored.map { $0.rect(in: bounds) } }
        if page.titleFrame == nil && page.storyFrame == nil { return [storyBackground] }
        return blocks.filter { $0.text.length > 0 }.map { $0.frame.insetBy(dx: -9, dy: -9).intersection(bounds) }
    }

    /// Text measurement is performed only for editing or for a manually composed page.
    func storyBlocks(page: BookPage, book: Book) -> [TextBlock] {
        guard story != nil || page.titleFrame != nil || page.storyFrame != nil else { return [] }
        let area = story ?? bounds
        let mixed = page.effectiveLayout == .mixed
        let style = book.editorialStyle
        let overPhoto = storyBackground != nil
        let titleWidth = page.titleFrame?.rect(in: bounds).width ?? area.width
        let titleStyle = style.fittedTitleStyle(page.heading, width: titleWidth, mixed: mixed, override: book.titleStyle(for: page))
        let title = style.typography("", heading: page.heading, mixed: mixed, titleStyle: titleStyle, overPhoto: overPhoto)
        let body = style.typography(page.text, heading: nil, mixed: mixed, bodyStyle: book.bodyStyle(for: page), overPhoto: overPhoto)
        var blocks: [TextBlock] = []
        let titleHeight = EditorialTypesetter.requiredHeight(title, width: titleWidth)
        if (title.length > 0 && story != nil) || page.titleFrame != nil {
            let frame = page.titleFrame?.rect(in: bounds) ?? CGRect(x: area.minX, y: area.minY, width: area.width,
                                                                    height: min(area.height, titleHeight))
            blocks.append(TextBlock(role: .title, frame: frame, text: title))
        }
        if (story != nil && (body.length > 0 || title.length == 0)) || page.storyFrame != nil {
            let frame: CGRect
            if let manual = page.storyFrame {
                frame = manual.rect(in: bounds)
            } else {
                var offset: CGFloat = 0
                if title.length > 0 && body.length > 0 {
                    let joined = Self.storyText(page: page, book: book, width: area.width, overPhoto: overPhoto)
                    // The body is a new paragraph in the legacy frame. Compare the original first
                    // baseline with the same line drawn as its own paragraph, including font leading.
                    let combinedBaseline = EditorialTypesetter.baseline(joined, at: title.length + 1, in: area)
                    let bodyBaseline = EditorialTypesetter.baseline(body, at: 0, in: area)
                    offset = min(area.height, max(0, combinedBaseline.flatMap { original in
                        bodyBaseline.map { original - $0 }
                    } ?? area.height))
                }
                let height = body.length == 0 ? area.height : EditorialTypesetter.requiredHeight(body, width: area.width)
                frame = CGRect(x: area.minX, y: area.minY + offset, width: area.width, height: min(area.height - offset, height))
            }
            blocks.append(TextBlock(role: .body, frame: frame, text: body))
        }
        return blocks
    }

    struct Photo: Identifiable {
        let photo: BookPhoto
        var id: UUID { photo.id }
        let frame: CGRect
        let fills: Bool
        let crop: PhotoCrop
    }

    static func storyText(page: BookPage, book: Book, width: CGFloat? = nil, overPhoto: Bool = false) -> NSAttributedString {
        let mixed = page.effectiveLayout == .mixed
        let style = book.editorialStyle
        let override = book.titleStyle(for: page)
        let title = width.map { style.fittedTitleStyle(page.heading, width: $0, mixed: mixed, override: override) } ?? override
        return style.typography(page.text, heading: page.heading, mixed: mixed,
                                titleStyle: title, bodyStyle: book.bodyStyle(for: page), overPhoto: overPhoto)
    }

    static func boxText(box: PageTextBox, book: Book) -> NSAttributedString {
        book.editorialStyle.typography(box.text, heading: nil, mixed: true, bodyStyle: book.bodyStyle(for: box))
    }

    let bounds: CGRect
    let photos: [Photo]
    let arrangementPhotoSlots: [CGRect]
    let story: CGRect?
    let storyBackground: CGRect?
    let textBoxes: [PageTextBox]
    let rule: CGRect?
    let folio: CGRect?

    init(page: BookPage, book: Book, bleed: Double = 0, photoForID: ((UUID) -> BookPhoto?)? = nil) {
        let size = book.format.pageSize
        let layout = page.effectiveLayout
        let bounds = CGRect(x: 0, y: 0, width: layout == .fullSpread ? size.width * 2 : size.width,
                            height: size.height)
        self.bounds = bounds
        let full = layout == .fullPage || layout == .fullSpread || page.arrangement?.isFullBleed == true
        let style = book.editorialStyle
        let safe = bounds.insetBy(dx: book.contentInsetPoints, dy: book.contentInsetPoints)
        rule = full ? nil : style.pageRule(in: safe)
        folio = style.folio && !full ? CGRect(x: safe.minX, y: safe.maxY + 6, width: 45, height: 20) : nil
        let mixed = layout == .mixed
        let alignedRoles = [page.heading?.isEmpty == false ? book.titleStyle(for: page).alignment : nil,
                            page.text.isEmpty ? nil : book.bodyStyle(for: page).alignment]
        let fullColumn = alignedRoles.contains(.center) || alignedRoles.contains(.right)
        let lookup = photoForID ?? book.photo
        textBoxes = page.textBoxes ?? []

        if let arrangement = page.arrangement {
            let geometry = arrangement.geometry(in: bounds, inside: safe, gap: style.imageGap)
            arrangementPhotoSlots = geometry.photos
            if arrangement == .textOverPhoto, let panel = book.template?.storyOverlayPanel(in: safe) {
                let padding = min(safe.width, safe.height) * 0.043
                story = panel.insetBy(dx: padding, dy: padding)
                storyBackground = page.hasStoryText ? panel : nil
            } else {
                story = geometry.story.map { style.textArea(in: $0, mixed: mixed, fullColumn: fullColumn) }
                storyBackground = geometry.storyBackground != nil && page.hasStoryText ? geometry.storyBackground : nil
            }
            photos = page.photoIDs.enumerated().compactMap { index, id in
                guard let photo = lookup(id) else { return nil }
                let placement = page.photoPlacements?[id]
                let frame: CGRect
                if let manual = placement?.frame {
                    frame = manual.photoRect(in: bounds, bleed: bleed)
                } else if geometry.photos.indices.contains(index) {
                    let slot = geometry.photos[index]
                    frame = PageRect.extendingToBleed(slot, in: bounds, bleed: bleed)
                } else {
                    return nil
                }
                let alignment = full && geometry.photos.count == 1 ? page.framing ?? 0.5 : 0.5
                return Photo(photo: photo, frame: frame, fills: true,
                             crop: placement?.crop ?? PhotoCrop(x: alignment, y: alignment))
            }
            return
        }

        let parts = BookLayoutGeometry.mixedArea(in: safe, placement: page.textPlacement, spacing: 12)
        arrangementPhotoSlots = []
        story = mixed || layout == .text ? style.textArea(in: mixed ? parts.text : safe, mixed: mixed, fullColumn: fullColumn) : nil
        storyBackground = nil
        let images = page.photoIDs.compactMap(lookup)
        let autoImages = images.filter { page.photoPlacements?[$0.id]?.frame == nil }
        let studioGallery = layout == .gallery
            ? book.template?.studioGallery(count: autoImages.count, in: safe, gap: style.imageGap)
            : nil
        let automaticFrames: [CGRect]
        switch page.layout {
        case .fullPage, .fullSpread:
            // Converting the hero to a manual frame must keep any stored, unused photos hidden.
            let heroNeedsFrame = images.first.map { page.photoPlacements?[$0.id]?.frame == nil } ?? false
            automaticFrames = heroNeedsFrame ? [bounds.insetBy(dx: -bleed, dy: -bleed)] : []
        case .text:
            automaticFrames = []
        case .mixed, .gallery:
            automaticFrames = studioGallery ?? BookLayoutGeometry.rectangles(
                for: autoImages.map { Double($0.pixelWidth) / Double(max(1, $0.pixelHeight)) },
                in: mixed ? parts.photo : safe, gap: style.imageGap)
        }
        var slots = automaticFrames.makeIterator()
        photos = images.compactMap { photo in
            let manual = page.photoPlacements?[photo.id]
            guard let frame = manual?.frame?.photoRect(in: bounds, bleed: bleed) ?? slots.next() else { return nil }
            let alignment = full ? page.framing ?? 0.5 : 0.5
            return Photo(photo: photo, frame: frame,
                         fills: full || studioGallery != nil || manual?.frame != nil || manual?.crop != nil,
                         crop: manual?.crop ?? PhotoCrop(x: alignment, y: alignment))
        }
    }
}

private extension BookTemplate {
    func studioGallery(count: Int, in safe: CGRect, gap: CGFloat) -> [CGRect]? {
        guard count > 0, !safe.isEmpty else { return nil }
        func place(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
            CGRect(x: safe.minX + x * safe.width, y: safe.minY + y * safe.height,
                   width: width * safe.width, height: height * safe.height)
        }
        switch self {
        case .swissGrid:
            if count == 1 { return [place(1 / 6, 0.06, 5 / 6, 0.88)] }
            let columns = count > 4 ? 3 : 2
            let rows = (count + columns - 1) / columns
            let area = place(0, 0.06, 1, 0.88)
            return (0..<count).map { index in
                let cellWidth = area.width / CGFloat(columns)
                let cellHeight = area.height / CGFloat(rows)
                return CGRect(x: area.minX + CGFloat(index % columns) * cellWidth,
                              y: area.minY + CGFloat(index / columns) * cellHeight,
                              width: cellWidth - min(gap, cellWidth * 0.12),
                              height: cellHeight - min(gap, cellHeight * 0.12))
            }
        case .berlinQuarter:
            guard count > 1 else { return [place(0, 0.04, 1, 0.92)] }
            let stripHeight = 0.90 / CGFloat(count - 1)
            return [place(0, 0.04, 0.71, 0.92)] + (0..<(count - 1)).map { index in
                place(0.75, 0.045 + CGFloat(index) * stripHeight, 0.25, stripHeight * 0.94)
            }
        case .japaneseInterval:
            switch count {
            case 1: return [place(0.30, 0.21, 0.62, 0.56)]
            case 2: return [place(0.43, 0.07, 0.51, 0.38), place(0.05, 0.62, 0.50, 0.29)]
            case 3: return [place(0.40, 0.04, 0.56, 0.40), place(0.06, 0.61, 0.35, 0.28),
                            place(0.54, 0.58, 0.34, 0.25)]
            default: return nil
            }
        default: return nil
        }
    }

    func storyOverlayPanel(in safe: CGRect) -> CGRect? {
        let panel: CGRect
        switch self {
        case .swissGrid: panel = CGRect(x: 0, y: 0.70, width: 0.90, height: 0.30)
        case .berlinQuarter: panel = CGRect(x: 0.12, y: 0.035, width: 0.88, height: 0.31)
        case .japaneseInterval: panel = CGRect(x: 0.33, y: 0.66, width: 0.67, height: 0.34)
        default: return nil
        }
        guard !safe.isEmpty else { return nil }
        return CGRect(x: safe.minX + panel.minX * safe.width, y: safe.minY + panel.minY * safe.height,
                      width: panel.width * safe.width, height: panel.height * safe.height)
    }
}

extension BookFormat {
    var pageSize: CGSize {
        CGSize(width: widthMM * (72.0 / 25.4), height: heightMM * (72.0 / 25.4))
    }
}

/// One face of the wraparound cover, in local coordinates. Its spine edge has no bleed.
struct BookCoverGeometry {
    let bounds: CGRect
    let photoFrame: CGRect
    let fills: Bool
    let background: UInt32
    let rule: CGRect?
    let band: CGRect?
    let titleFrame: CGRect?
    let title: NSAttributedString

    init(book: Book, front: Bool, bleed: Double = 0) {
        let size = book.format.pageSize
        bounds = CGRect(origin: .zero, size: size)
        let w = size.width
        let h = size.height
        let inset = book.contentInsetPoints
        let panel = bounds.insetBy(dx: inset, dy: inset)
        let style = book.editorialStyle
        let titleText = front ? book.cover?.title ?? book.title : book.cover?.backText ?? ""
        let override = book.coverTextStyle(front: front)
        let manual = (front ? book.cover?.frontTitleFrame : book.cover?.backTextFrame)?.rect(in: bounds)
        let custom = manual == nil && override != EditorialTextStyle()
        let automaticTitleFrame: CGRect?
        if book.template == nil {
            title = style.typography(titleText, heading: nil, mixed: false, bodyStyle: override)
            background = 0x292929
            fills = true
            photoFrame = CGRect(x: front ? 0 : -bleed, y: -bleed, width: w + bleed, height: h + 2 * bleed)
            var bandTop = h * 0.63
            if custom {
                bandTop = max(0, min(bandTop, panel.maxY - EditorialTypesetter.requiredHeight(title, width: panel.width) - inset))
            }
            band = titleText.isEmpty ? nil : manual?.insetBy(dx: -4, dy: -4).intersection(bounds) ?? CGRect(x: front ? 0 : -bleed, y: bandTop, width: w + bleed, height: h - bandTop + bleed)
            automaticTitleFrame = titleText.isEmpty ? nil : CGRect(x: inset, y: bandTop + inset, width: panel.width,
                                                          height: h - bandTop - 2 * inset)
            rule = nil
        } else {
            background = style.paper
            fills = front
            band = nil
            rule = front ? style.coverRule(in: panel) : nil
            if front {
                let adapted = style.fittedTitleStyle(titleText, width: manual?.width ?? panel.width,
                                                     mixed: false, override: override)
                title = style.typography("", heading: titleText, mixed: false, titleStyle: adapted)
                var picture = style.coverPicture(in: panel, bleed: bleed)
                let defaultHeight = panel.height * (style.coverTitleBelow ? 0.28 : 0.25)
                let needed = custom ? EditorialTypesetter.requiredHeight(title, width: panel.width) : 0
                if style.coverTitleBelow {
                    if needed > defaultHeight {
                        picture.size.height = max(0, min(picture.height, panel.maxY - needed - 22 - picture.minY))
                    }
                    let titleY = picture.maxY + 22
                    automaticTitleFrame = CGRect(x: panel.minX, y: titleY, width: panel.width,
                                        height: custom ? max(0, panel.maxY - titleY) : defaultHeight)
                } else {
                    let titleY = panel.minY + (style.rule ? 16 : 0)
                    if needed > defaultHeight {
                        let bottom = picture.maxY
                        picture.origin.y = min(bottom, max(picture.minY, titleY + needed + 8))
                        picture.size.height = bottom - picture.minY
                    }
                    automaticTitleFrame = CGRect(x: panel.minX, y: titleY, width: panel.width,
                                        height: custom ? max(0, min(panel.maxY, picture.minY) - titleY) : defaultHeight)
                }
                photoFrame = picture
            } else {
                title = style.typography(titleText, heading: nil, mixed: true, bodyStyle: override)
                var picture = CGRect(x: inset * 1.35, y: h * 0.38, width: max(0, w - 2.7 * inset), height: h * 0.28)
                if custom {
                    let needed = EditorialTypesetter.requiredHeight(title, width: picture.width)
                    let photoBottom = min(picture.maxY, max(panel.minY, panel.maxY - needed - 16))
                    picture.origin.y = max(panel.minY, photoBottom - picture.height)
                    picture.size.height = photoBottom - picture.minY
                }
                photoFrame = picture
                let textTop = picture.maxY + 16
                automaticTitleFrame = titleText.isEmpty ? nil : CGRect(x: picture.minX, y: textTop, width: picture.width,
                                                               height: max(0, panel.maxY - textTop))
            }
        }
        titleFrame = manual ?? automaticTitleFrame
    }
}
