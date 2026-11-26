import CoreGraphics

/// Fixed slots are ordered in reading order: left to right, then top to bottom.
enum PageArrangement: String, Codable, CaseIterable, Identifiable, Sendable {
    case fullBleed, fullSpread, bleedTwoAcross, bleedTwoStacked, bleedThreeAcross, bleedFourGrid, bleedHeroAboveTwo
    case twoAcross, twoStacked, fourGrid, heroAboveTwo, twoAboveHero
    case textAbovePhoto, photoAboveText, textBesidePhoto, textOverPhoto, textOnly
    /// A map of the book's photo locations (`BookPage.map`): the whole page, or above the story.
    /// A book that uses one is written with `Workspace.writerVersion` 2.
    case map, mapAboveText

    var id: Self { self }

    var isFullBleed: Bool {
        switch self {
        case .fullBleed, .fullSpread, .textOverPhoto, .bleedTwoAcross, .bleedTwoStacked, .bleedThreeAcross,
             .bleedFourGrid, .bleedHeroAboveTwo:
            true
        default:
            false
        }
    }

    var layout: PageLayout {
        switch self {
        case .fullBleed: .fullPage
        case .fullSpread: .fullSpread
        case .twoAcross, .twoStacked, .fourGrid, .heroAboveTwo, .twoAboveHero,
             .bleedTwoAcross, .bleedTwoStacked, .bleedThreeAcross, .bleedFourGrid, .bleedHeroAboveTwo: .gallery
        case .textAbovePhoto, .photoAboveText, .textBesidePhoto, .textOverPhoto, .mapAboveText: .mixed
        case .textOnly: .text
        case .map: .gallery
        }
    }

    var photoCapacity: Int {
        switch self {
        case .textOnly, .map, .mapAboveText: 0
        case .fullBleed, .fullSpread, .textAbovePhoto, .photoAboveText, .textBesidePhoto, .textOverPhoto: 1
        case .twoAcross, .twoStacked, .bleedTwoAcross, .bleedTwoStacked: 2
        case .heroAboveTwo, .twoAboveHero, .bleedThreeAcross, .bleedHeroAboveTwo: 3
        case .fourGrid, .bleedFourGrid: 4
        }
    }

    var isMap: Bool { self == .map || self == .mapAboveText }

    struct Geometry {
        var photos: [CGRect]
        var story: CGRect? = nil
        var storyBackground: CGRect? = nil
        /// The map's area on a map page; `PageComposition` widens a whole-page map to the trim for some templates.
        var map: CGRect? = nil
    }

    /// All rectangles use the caller's units and a top-left origin. The bounds include the
    /// trimmed page; the safe area supplies the editorial margins for photos and text.
    func geometry(in bounds: CGRect, inside safe: CGRect, gap: CGFloat) -> Geometry {
        guard !bounds.isEmpty else { return Geometry(photos: []) }
        let photoArea = isFullBleed ? bounds : safe
        guard !photoArea.isEmpty else { return Geometry(photos: []) }
        let gutter = isFullBleed ? 0 : min(max(0, gap), min(safe.width, safe.height) * 0.14)
        func split(_ rect: CGRect, along edge: CGRectEdge, fraction: CGFloat = 0.5) -> (CGRect, CGRect) {
            let extent = edge == .minXEdge ? rect.width : rect.height
            let (first, rest) = rect.divided(atDistance: (extent - gutter) * fraction, from: edge)
            return (first, rest.divided(atDistance: gutter, from: edge).remainder)
        }
        func pairAcross(_ rect: CGRect) -> [CGRect] {
            let (left, right) = split(rect, along: .minXEdge)
            return [left, right]
        }

        switch self {
        case .fullBleed, .fullSpread:
            return Geometry(photos: [bounds])
        case .twoAcross, .bleedTwoAcross:
            return Geometry(photos: pairAcross(photoArea))
        case .bleedThreeAcross:
            let (first, otherTwo) = split(photoArea, along: .minXEdge, fraction: 1.0 / 3)
            return Geometry(photos: [first] + pairAcross(otherTwo))
        case .twoStacked, .bleedTwoStacked:
            let (top, bottom) = split(photoArea, along: .minYEdge)
            return Geometry(photos: [top, bottom])
        case .fourGrid, .bleedFourGrid:
            let (top, bottom) = split(photoArea, along: .minYEdge)
            return Geometry(photos: pairAcross(top) + pairAcross(bottom))
        case .heroAboveTwo, .bleedHeroAboveTwo:
            let (hero, lower) = split(photoArea, along: .minYEdge, fraction: 0.62)
            return Geometry(photos: [hero] + pairAcross(lower))
        case .twoAboveHero:
            let (upper, hero) = split(safe, along: .minYEdge, fraction: 0.38)
            return Geometry(photos: pairAcross(upper) + [hero])
        case .textAbovePhoto:
            let (story, photo) = split(safe, along: .minYEdge, fraction: 0.35)
            return Geometry(photos: [photo], story: story)
        case .photoAboveText:
            let (photo, story) = split(safe, along: .minYEdge, fraction: 0.65)
            return Geometry(photos: [photo], story: story)
        case .textBesidePhoto:
            let (photo, story) = split(safe, along: .minXEdge, fraction: 0.58)
            return Geometry(photos: [photo], story: story)
        case .textOverPhoto:
            guard !safe.isEmpty else { return Geometry(photos: [bounds]) }
            let panel = CGRect(x: safe.minX, y: safe.maxY - safe.height * 0.34,
                               width: safe.width * 0.78, height: safe.height * 0.34)
            let padding = min(safe.width, safe.height) * 0.028
            return Geometry(photos: [bounds], story: panel.insetBy(dx: padding, dy: padding), storyBackground: panel)
        case .textOnly:
            return Geometry(photos: [], story: safe)
        case .map:
            return Geometry(photos: [], map: safe)
        case .mapAboveText:
            let (map, story) = split(safe, along: .minYEdge, fraction: 0.62)
            return Geometry(photos: [], story: story, map: map)
        }
    }
}
