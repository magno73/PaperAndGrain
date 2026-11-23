import CoreGraphics

/// Fixed slots are ordered in reading order: left to right, then top to bottom.
enum PageArrangement: String, Codable, CaseIterable, Identifiable, Sendable {
    case fullBleed, twoAcross, twoStacked, fourGrid, heroAboveTwo, twoAboveHero
    case textAbovePhoto, photoAboveText, textBesidePhoto, textOverPhoto, textOnly

    var id: Self { self }

    var layout: PageLayout {
        switch self {
        case .fullBleed: .fullPage
        case .twoAcross, .twoStacked, .fourGrid, .heroAboveTwo, .twoAboveHero: .gallery
        case .textAbovePhoto, .photoAboveText, .textBesidePhoto, .textOverPhoto: .mixed
        case .textOnly: .text
        }
    }

    var photoCapacity: Int {
        switch self {
        case .textOnly: 0
        case .fullBleed, .textAbovePhoto, .photoAboveText, .textBesidePhoto, .textOverPhoto: 1
        case .twoAcross, .twoStacked: 2
        case .heroAboveTwo, .twoAboveHero: 3
        case .fourGrid: 4
        }
    }

    struct Geometry {
        var photos: [CGRect]
        var story: CGRect? = nil
        var storyBackground: CGRect? = nil
    }

    /// All rectangles use the caller's units and a top-left origin. The bounds include the
    /// trimmed page; the safe area supplies the editorial margins for photos and text.
    func geometry(in bounds: CGRect, inside safe: CGRect, gap: CGFloat) -> Geometry {
        guard !bounds.isEmpty else { return Geometry(photos: []) }
        guard !safe.isEmpty else {
            return Geometry(photos: self == .fullBleed || self == .textOverPhoto ? [bounds] : [])
        }
        let gutter = min(max(0, gap), min(safe.width, safe.height) * 0.14)
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
        case .fullBleed:
            return Geometry(photos: [bounds])
        case .twoAcross:
            return Geometry(photos: pairAcross(safe))
        case .twoStacked:
            let (top, bottom) = split(safe, along: .minYEdge)
            return Geometry(photos: [top, bottom])
        case .fourGrid:
            let (top, bottom) = split(safe, along: .minYEdge)
            return Geometry(photos: pairAcross(top) + pairAcross(bottom))
        case .heroAboveTwo:
            let (hero, lower) = split(safe, along: .minYEdge, fraction: 0.62)
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
            let panel = CGRect(x: safe.minX, y: safe.maxY - safe.height * 0.34,
                               width: safe.width * 0.78, height: safe.height * 0.34)
            let padding = min(safe.width, safe.height) * 0.028
            return Geometry(photos: [bounds], story: panel.insetBy(dx: padding, dy: padding), storyBackground: panel)
        case .textOnly:
            return Geometry(photos: [], story: safe)
        }
    }
}
