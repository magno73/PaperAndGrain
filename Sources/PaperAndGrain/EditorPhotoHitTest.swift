import SwiftUI

/// The same geometry used to draw the artboard, in back-to-front order.
struct CanvasHitMap: Equatable {
    enum Target: Equatable {
        case photo(UUID), textBox(UUID), story(PageComposition.TextRole), storyGroup, coverText, crop, paper
    }

    struct Region: Equatable {
        let frame: CGRect
        let target: Target
    }

    let bounds: CGRect
    let regions: [Region]

    func target(at point: CGPoint, in frame: CGRect) -> Target? {
        guard let local = Self.localPoint(point, frame: frame, bounds: bounds) else { return nil }
        return regions.last(where: { $0.frame.contains(local) })?.target ?? .paper
    }

    static func localPoint(_ point: CGPoint, frame: CGRect, bounds: CGRect) -> CGPoint? {
        guard !frame.isEmpty, frame.contains(point) else { return nil }
        return CGPoint(x: bounds.minX + (point.x - frame.minX) * bounds.width / frame.width,
                       y: bounds.minY + (point.y - frame.minY) * bounds.height / frame.height)
    }

    static func cover(_ geometry: BookCoverGeometry, photoID: UUID?, cropFrame: CGRect? = nil) -> Self {
        var regions: [Region] = []
        if let photoID { regions.append(Region(frame: geometry.photoFrame, target: .photo(photoID))) }
        if let band = geometry.band { regions.append(Region(frame: band, target: .paper)) }
        if let text = geometry.titleFrame { regions.append(Region(frame: text, target: .coverText)) }
        if let cropFrame { regions.append(Region(frame: cropFrame, target: .crop)) }
        return Self(bounds: geometry.bounds, regions: regions)
    }
}

enum EditorPhotoHitTest {
    static func onPage(at point: CGPoint, frame: CGRect, composition: PageComposition, excluding: UUID? = nil,
                       storyFrames: [CGRect]? = nil) -> UUID? {
        let bounds = composition.bounds
        guard let local = CanvasHitMap.localPoint(point, frame: frame, bounds: bounds) else { return nil }
        if let storyFrames {
            if storyFrames.contains(where: { $0.contains(local) }) { return nil }
        } else if composition.story?.contains(local) == true { return nil }
        if composition.textBoxes.contains(where: { $0.frame.rect(in: bounds).contains(local) }) { return nil }
        return composition.photos.last { $0.id != excluding && $0.frame.contains(local) }?.id
    }
}

struct CanvasHitMaps: PreferenceKey {
    static let defaultValue: [EditorDropTarget: CanvasHitMap] = [:]

    static func reduce(value: inout [EditorDropTarget: CanvasHitMap], nextValue: () -> [EditorDropTarget: CanvasHitMap]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

final class CanvasHitStorage {
    var maps: [EditorDropTarget: CanvasHitMap] = [:]
}
