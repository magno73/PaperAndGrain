import CoreGraphics
import Foundation

/// Several objects selected on one page (decision D3), as the layers they are drawn in. The order is
/// the order of selection: the last one sets the size for **Make Same Width / Height**. A selection of
/// one object is not kept here; the editor's single selection handles it exactly as before.
struct CanvasGroupSelection: Equatable, Sendable {
    var pageID: UUID?
    var layers: [PageLayer] = []

    /// True when two or more objects are selected.
    var isActive: Bool { pageID != nil && layers.count > 1 }

    func contains(_ layer: PageLayer, on page: UUID) -> Bool { isActive && pageID == page && layers.contains(layer) }

    /// ⇧-click or ⌘-click: `current` is what is selected now (the group, or the single object), and the
    /// result is the new list. A click on another page starts over there.
    static func toggling(_ layer: PageLayer, on page: UUID, current: [PageLayer], currentPage: UUID?) -> [PageLayer] {
        guard currentPage == page else { return [layer] }
        if current.contains(layer) { return current.filter { $0 != layer } }
        return current + [layer]
    }

    /// The objects a selection rectangle touches, in drawing order. A rectangle of no size touches nothing.
    static func touched(by rect: CGRect, objects: [(layer: PageLayer, frame: CGRect)]) -> [PageLayer] {
        let area = rect.standardized
        guard area.width > 0 || area.height > 0 else { return [] }
        return objects.filter { !$0.frame.isEmpty && $0.frame.intersects(area) }.map(\.layer)
    }
}

/// The geometry of acting on several frames at once. Every function is pure, in one coordinate system.
enum CanvasGroupGeometry {
    /// Limits a move so the group stays on the page as a whole, like `BookPage.moveStoryGroup`: an extent
    /// inside the page cannot leave it, and one already past an edge (a bleeding photo) can only come back.
    static func clampedTranslation(_ translation: CGSize, extent: CGRect, bounds: CGRect) -> CGSize {
        guard !extent.isNull, !bounds.isEmpty else { return .zero }
        func limit(_ delta: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
            min(max(0, upper), max(min(0, lower), delta))
        }
        return CGSize(width: limit(translation.width, lower: bounds.minX - extent.minX, upper: bounds.maxX - extent.maxX),
                      height: limit(translation.height, lower: bounds.minY - extent.minY, upper: bounds.maxY - extent.maxY))
    }

    /// The rectangle the extent may occupy while it moves, for snapping.
    static func movementArea(extent: CGRect, bounds: CGRect) -> CGRect {
        let low = clampedTranslation(CGSize(width: -1e9, height: -1e9), extent: extent, bounds: bounds)
        let high = clampedTranslation(CGSize(width: 1e9, height: 1e9), extent: extent, bounds: bounds)
        return CGRect(x: extent.minX + low.width, y: extent.minY + low.height,
                      width: extent.width + high.width - low.width, height: extent.height + high.height - low.height)
    }

    static func extent(_ frames: [CGRect]) -> CGRect {
        frames.filter { !$0.isNull }.reduce(CGRect.null) { $0.union($1) }
    }

    enum Alignment: CaseIterable, Sendable {
        case left, center, right, top, middle, bottom
    }

    /// Aligns each frame to `reference`: the bounding box of the selection, or the page's safe area for one object.
    static func align(_ frames: [CGRect], _ alignment: Alignment, to reference: CGRect) -> [CGRect] {
        frames.map { frame in
            switch alignment {
            case .left: frame.offsetBy(dx: reference.minX - frame.minX, dy: 0)
            case .center: frame.offsetBy(dx: reference.midX - frame.midX, dy: 0)
            case .right: frame.offsetBy(dx: reference.maxX - frame.maxX, dy: 0)
            case .top: frame.offsetBy(dx: 0, dy: reference.minY - frame.minY)
            case .middle: frame.offsetBy(dx: 0, dy: reference.midY - frame.midY)
            case .bottom: frame.offsetBy(dx: 0, dy: reference.maxY - frame.maxY)
            }
        }
    }

    /// Equal gaps between frames along one axis; the first and last (by position) stay where they are.
    /// Fewer than three frames are returned unchanged. Overlapping frames get a negative gap.
    static func distribute(_ frames: [CGRect], horizontally: Bool) -> [CGRect] {
        guard frames.count > 2 else { return frames }
        let order = frames.indices.sorted {
            let a = horizontally ? frames[$0].minX : frames[$0].minY
            let b = horizontally ? frames[$1].minX : frames[$1].minY
            return a == b ? $0 < $1 : a < b
        }
        let first = frames[order[0]], last = frames[order[order.count - 1]]
        let span = horizontally ? last.maxX - first.minX : last.maxY - first.minY
        let lengths = order.map { horizontally ? frames[$0].width : frames[$0].height }.reduce(0, +)
        let gap = (span - lengths) / CGFloat(frames.count - 1)
        var result = frames
        var position = horizontally ? first.minX : first.minY
        for index in order {
            let frame = frames[index]
            result[index] = horizontally ? CGRect(x: position, y: frame.minY, width: frame.width, height: frame.height)
                                         : CGRect(x: frame.minX, y: position, width: frame.width, height: frame.height)
            position += (horizontally ? frame.width : frame.height) + gap
        }
        // The last one is placed by the sum; put it back exactly, so rounding never moves an outer frame.
        result[order[order.count - 1]] = last
        return result
    }

    /// Gives every frame the width (or height) of `reference`, keeping its top left corner. Photos keep their
    /// proportions, as when they are resized by a corner.
    static func sameSize(_ frames: [CGRect], width: Bool, as reference: CGRect, keepingProportions: Bool) -> [CGRect] {
        frames.map { frame in
            guard frame.width > 0, frame.height > 0 else { return frame }
            if width {
                let height = keepingProportions ? frame.height * reference.width / frame.width : frame.height
                return CGRect(x: frame.minX, y: frame.minY, width: reference.width, height: height)
            }
            let newWidth = keepingProportions ? frame.width * reference.height / frame.height : frame.width
            return CGRect(x: frame.minX, y: frame.minY, width: newWidth, height: reference.height)
        }
    }
}

extension BookPage {
    /// The story's extent on the page: its visible blocks with text and their backdrop; nil without text.
    static func storyExtent(of page: BookPage, book: Book, in composition: PageComposition) -> CGRect? {
        guard page.hasStoryText else { return nil }
        let blocks = composition.storyBlocks(page: page, book: book)
        let backings = composition.storyBackgroundFrames(page: page, blocks: blocks)
        let extent = CanvasGroupGeometry.extent(blocks.filter { $0.text.length > 0 && !$0.frame.isEmpty }.map(\.frame) + backings)
        return extent.isNull ? nil : extent
    }

    /// Gives objects of the page new frames, in page points. A photo in an automatic slot gets a manual
    /// frame (in an automatic gallery every visible frame is fixed first, as a single drag does); text boxes
    /// take their frame; the story moves as one group by the change of its extent. Ids never change.
    mutating func applyFrames(_ frames: [PageLayer: CGRect], book: Book) {
        let composition = PageComposition(page: self, book: book)
        let bounds = composition.bounds
        let photos = frames.keys.compactMap { layer -> UUID? in if case let .photo(id) = layer { id } else { nil } }
        var placements = photoPlacements ?? [:]
        if arrangement == nil, layout == .gallery || layout == .mixed,
           photos.contains(where: { placements[$0]?.frame == nil }) {
            for image in composition.photos where placements[image.id]?.frame == nil {
                placements[image.id, default: PhotoPlacement()].frame = PageRect(image.frame, in: bounds)
            }
        }
        for id in photos {
            guard let frame = frames[.photo(id)] else { continue }
            placements[id, default: PhotoPlacement()].frame = PageRect(frame, in: bounds).photoClamped
        }
        photoPlacements = placements.isEmpty ? nil : placements
        if var boxes = textBoxes {
            for index in boxes.indices {
                if let frame = frames[.textBox(boxes[index].id)] { boxes[index].frame = PageRect(frame, in: bounds).clamped }
            }
            textBoxes = boxes
        }
        if let target = frames[.story], let from = Self.storyExtent(of: self, book: book, in: composition) {
            let blocks = composition.storyBlocks(page: self, book: book)
            let backings = composition.storyBackgroundFrames(page: self, blocks: blocks)
            moveStoryGroup(by: CGSize(width: target.minX - from.minX, height: target.minY - from.minY),
                           blocks: blocks, backdrops: backings, in: bounds)
        }
    }

    /// Moves several layers together and keeps their order among themselves. Returns false when nothing moves.
    @discardableResult
    mutating func moveLayers(_ selected: [PageLayer], _ move: PageLayer.Move, photos: [UUID], boxes: [UUID]) -> Bool {
        let order = stackingOrder(photos: photos, boxes: boxes)
        let chosen = Set(selected).intersection(order)
        guard !chosen.isEmpty else { return false }
        var next = order
        switch move {
        case .front: next = order.filter { !chosen.contains($0) } + order.filter { chosen.contains($0) }
        case .back: next = order.filter { chosen.contains($0) } + order.filter { !chosen.contains($0) }
        case .forward:
            // Each selected run steps over the object just above it.
            var index = next.count - 2
            while index >= 0 {
                if chosen.contains(next[index]), !chosen.contains(next[index + 1]) {
                    var run = index
                    while run > 0, chosen.contains(next[run - 1]) { run -= 1 }
                    let above = next.remove(at: index + 1)
                    next.insert(above, at: run)
                    index = run - 1
                } else {
                    index -= 1
                }
            }
        case .backward:
            var index = 1
            while index < next.count {
                if chosen.contains(next[index]), !chosen.contains(next[index - 1]) {
                    var run = index
                    while run < next.count - 1, chosen.contains(next[run + 1]) { run += 1 }
                    let below = next.remove(at: index - 1)
                    next.insert(below, at: run)
                    index = run + 1
                } else {
                    index += 1
                }
            }
        }
        guard next != order else { return false }
        layerOrder = next
        return true
    }

    /// Whether `moveLayers` would change anything.
    func canMoveLayers(_ selected: [PageLayer], _ move: PageLayer.Move, photos: [UUID], boxes: [UUID]) -> Bool {
        var copy = self
        return copy.moveLayers(selected, move, photos: photos, boxes: boxes)
    }
}
