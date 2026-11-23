import CoreGraphics
import Foundation

enum CanvasPhotoSwap {
    struct Target: Equatable {
        let id: UUID
        let frame: CGRect
    }

    static func target(moving id: UUID, at point: CGPoint, in bounds: CGRect,
                       composition: PageComposition) -> Target? {
        guard composition.photos.contains(where: { $0.id == id }),
              let targetID = EditorPhotoHitTest.onPage(at: point, frame: bounds, composition: composition, excluding: id),
              let photo = composition.photos.first(where: { $0.id == targetID }) else { return nil }
        let visible = photo.frame.intersection(composition.bounds)
        let frame = PageRect(visible, in: composition.bounds).rect(in: bounds)
        // Keep the edge available for arranging neighboring photos.
        guard frame.insetBy(dx: frame.width * 0.1, dy: frame.height * 0.1).contains(point) else { return nil }
        return Target(id: targetID, frame: frame)
    }
}

extension BookPage {
    @discardableResult
    mutating func swapPhotos(_ first: UUID, _ second: UUID, in composition: PageComposition) -> Bool {
        guard first != second, let firstIndex = photoIDs.firstIndex(of: first),
              let secondIndex = photoIDs.firstIndex(of: second),
              composition.photos.contains(where: { $0.id == first }),
              composition.photos.contains(where: { $0.id == second }) else { return false }

        var placements = photoPlacements ?? [:]
        if arrangement == nil && (layout == .gallery || layout == .mixed) {
            // Automatic rows depend on aspect ratios. Preserve their current rectangles.
            for item in composition.photos where placements[item.id]?.frame == nil {
                placements[item.id, default: PhotoPlacement()].frame = PageRect(item.frame, in: composition.bounds)
            }
        }
        let firstFrame = placements[first]?.frame
        let secondFrame = placements[second]?.frame
        placements[first, default: PhotoPlacement()].frame = secondFrame
        placements[second, default: PhotoPlacement()].frame = firstFrame
        for id in [first, second] where placements[id] == PhotoPlacement() {
            placements.removeValue(forKey: id)
        }
        photoPlacements = placements.isEmpty ? nil : placements
        photoIDs.swapAt(firstIndex, secondIndex)
        return true
    }
}
