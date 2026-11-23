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
}

struct PageComposition {
    struct Photo: Identifiable {
        let photo: BookPhoto
        var id: UUID { photo.id }
        let frame: CGRect
        let fills: Bool
        let crop: PhotoCrop
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
        let full = layout == .fullPage || layout == .fullSpread || page.arrangement == .textOverPhoto
        let style = book.editorialStyle
        let safe = bounds.insetBy(dx: book.contentInsetPoints, dy: book.contentInsetPoints)
        rule = style.rule && !full ? CGRect(x: safe.minX, y: safe.minY - 9, width: safe.width, height: 0.55) : nil
        folio = style.folio && !full ? CGRect(x: safe.minX, y: safe.maxY + 6, width: 45, height: 20) : nil
        let mixed = layout == .mixed
        let lookup = photoForID ?? book.photo
        textBoxes = page.textBoxes ?? []

        if let arrangement = page.arrangement {
            let geometry = arrangement.geometry(in: bounds, inside: safe, gap: style.imageGap)
            arrangementPhotoSlots = geometry.photos
            story = geometry.story.map { style.textArea(in: $0, mixed: mixed) }
            storyBackground = geometry.storyBackground != nil && page.hasStoryText ? geometry.storyBackground : nil
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
                let alignment = full ? page.framing ?? 0.5 : 0.5
                return Photo(photo: photo, frame: frame, fills: true,
                             crop: placement?.crop ?? PhotoCrop(x: alignment, y: alignment))
            }
            return
        }

        let parts = BookLayoutGeometry.mixedArea(in: safe, placement: page.textPlacement, spacing: 12)
        arrangementPhotoSlots = []
        story = mixed || layout == .text ? style.textArea(in: mixed ? parts.text : safe, mixed: mixed) : nil
        storyBackground = nil
        let images = page.photoIDs.compactMap(lookup)
        let autoImages = images.filter { page.photoPlacements?[$0.id]?.frame == nil }
        let automaticFrames: [CGRect]
        switch page.layout {
        case .fullPage, .fullSpread:
            // Converting the hero to a manual frame must keep any stored, unused photos hidden.
            let heroNeedsFrame = images.first.map { page.photoPlacements?[$0.id]?.frame == nil } ?? false
            automaticFrames = heroNeedsFrame ? [bounds.insetBy(dx: -bleed, dy: -bleed)] : []
        case .text:
            automaticFrames = []
        case .mixed, .gallery:
            automaticFrames = BookLayoutGeometry.rectangles(
                for: autoImages.map { Double($0.pixelWidth) / Double(max(1, $0.pixelHeight)) },
                in: mixed ? parts.photo : safe, gap: style.imageGap)
        }
        var slots = automaticFrames.makeIterator()
        photos = images.compactMap { photo in
            let manual = page.photoPlacements?[photo.id]
            guard let frame = manual?.frame?.photoRect(in: bounds, bleed: bleed) ?? slots.next() else { return nil }
            let alignment = full ? page.framing ?? 0.5 : 0.5
            return Photo(photo: photo, frame: frame, fills: full || manual?.frame != nil || manual?.crop != nil,
                         crop: manual?.crop ?? PhotoCrop(x: alignment, y: alignment))
        }
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
        if book.template == nil {
            background = 0x292929
            fills = true
            photoFrame = CGRect(x: front ? 0 : -bleed, y: -bleed, width: w + bleed, height: h + 2 * bleed)
            let bandTop = h * 0.63
            band = titleText.isEmpty ? nil : CGRect(x: front ? 0 : -bleed, y: bandTop, width: w + bleed, height: h - bandTop + bleed)
            titleFrame = titleText.isEmpty ? nil : CGRect(x: inset, y: bandTop + inset, width: panel.width,
                                                          height: h - bandTop - 2 * inset)
            rule = nil
            title = style.typography(titleText, heading: nil, mixed: false)
        } else {
            background = style.paper
            fills = front
            band = nil
            photoFrame = front ? style.coverPicture(in: panel, bleed: bleed)
                : CGRect(x: inset * 1.35, y: h * 0.38, width: max(0, w - 2.7 * inset), height: h * 0.28)
            rule = front && style.rule ? CGRect(x: panel.minX, y: panel.minY, width: panel.width, height: 0.8) : nil
            if front {
                let titleY = style.coverTitleBelow ? photoFrame.maxY + 22 : panel.minY + (style.rule ? 16 : 0)
                titleFrame = CGRect(x: panel.minX, y: titleY, width: panel.width,
                                    height: panel.height * (style.coverTitleBelow ? 0.28 : 0.25))
                title = style.typography("", heading: titleText, mixed: false)
            } else {
                let textTop = photoFrame.maxY + 16
                titleFrame = titleText.isEmpty ? nil : CGRect(x: photoFrame.minX, y: textTop, width: photoFrame.width,
                                                               height: max(0, panel.maxY - textTop))
                title = style.typography(titleText, heading: nil, mixed: true)
            }
        }
    }
}
