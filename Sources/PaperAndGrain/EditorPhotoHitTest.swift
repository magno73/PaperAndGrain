import CoreGraphics
import Foundation

enum EditorPhotoHitTest {
    static func onPage(at point: CGPoint, frame: CGRect, composition: PageComposition, excluding: UUID? = nil,
                       storyFrames: [CGRect]? = nil) -> UUID? {
        let page = composition.bounds
        guard let local = localPoint(point, frame: frame, bounds: page) else { return nil }
        if let storyFrames {
            if storyFrames.contains(where: { $0.contains(local) }) { return nil }
        } else if composition.story?.contains(local) == true { return nil }
        if composition.textBoxes.contains(where: { $0.frame.rect(in: page).contains(local) }) { return nil }
        return composition.photos.last { $0.id != excluding && $0.frame.contains(local) }?.id
    }

    static func onCover(at point: CGPoint, frame: CGRect, geometry: BookCoverGeometry) -> Bool {
        guard let local = localPoint(point, frame: frame, bounds: geometry.bounds) else { return false }
        return geometry.photoFrame.contains(local) && geometry.band?.contains(local) != true
            && geometry.titleFrame?.contains(local) != true
    }

    private static func localPoint(_ point: CGPoint, frame: CGRect, bounds: CGRect) -> CGPoint? {
        guard !frame.isEmpty, frame.contains(point) else { return nil }
        return CGPoint(x: bounds.minX + (point.x - frame.minX) * bounds.width / frame.width,
                       y: bounds.minY + (point.y - frame.minY) * bounds.height / frame.height)
    }
}
