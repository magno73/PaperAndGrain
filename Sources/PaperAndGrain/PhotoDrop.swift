import CoreGraphics
import Foundation

extension PageComposition {
    /// Layout slots with no photo in them, in slot order. A photo counts when it covers half the slot
    /// or sits centered in it, like a portrait fitted inside a landscape slot.
    var emptySlots: [(index: Int, frame: CGRect)] {
        arrangementPhotoSlots.enumerated().compactMap { index, slot in
            let area = slot.width * slot.height
            guard area > 0 else { return nil }
            let covered = photos.contains { photo in
                let overlap = photo.frame.intersection(slot)
                return slot.contains(CGPoint(x: photo.frame.midX, y: photo.frame.midY))
                    || (!overlap.isNull && overlap.width * overlap.height >= area * 0.5)
            }
            return covered ? nil : (index, slot)
        }
    }

    /// An automatic page that shows no photo yet: a dropped photo should simply join its layout.
    func acceptsFirstPhoto(on page: BookPage) -> Bool {
        page.arrangement == nil && photos.isEmpty
            && (page.layout == .gallery || page.layout == .mixed || page.layout == .fullPage)
    }
}

extension BookPage {
    /// How a replacement fitted the page, so the editor can say what happened.
    enum Replacement: Equatable {
        /// Close proportions: the new photo fills the old frame.
        case sameFrame
        /// The automatic gallery laid the page out again for the new proportions.
        case reflowed
        /// The new photo sits whole inside the old frame, which shrank to its proportions.
        case fitted
        /// Full bleed: the photo fills the slot and is cropped, as every full-bleed photo is.
        case croppedToBleed
    }

    static let sameProportionTolerance = 1.08

    /// Puts `new` where `old` is: the same place in the order, the same layout slot and layer.
    /// The photo is never cropped silently. Close proportions keep the frame. A purely automatic
    /// gallery reflows. Fixed layouts and manual frames shrink the frame to the photo, centered,
    /// so nothing else on the page moves. Full bleed fills and reports the crop.
    @discardableResult
    mutating func replacePhoto(_ old: UUID, with new: BookPhoto, in composition: PageComposition) -> Replacement? {
        guard old != new.id, !photoIDs.contains(new.id), let index = photoIDs.firstIndex(of: old),
              let current = composition.photos.first(where: { $0.id == old }) else { return nil }
        let frame = current.frame
        let frameRatio = frame.width / max(0.0001, frame.height)
        let photoRatio = Double(new.pixelWidth) / Double(max(1, new.pixelHeight))
        let close = max(photoRatio, frameRatio) / max(0.0001, min(photoRatio, frameRatio)) <= Self.sameProportionTolerance
        let fullBleed = arrangement?.isFullBleed == true || layout == .fullPage || layout == .fullSpread
        // Only a gallery that follows each photo's proportions can reflow. Template galleries
        // (Studio and Photobook families) use fixed frames that would crop the new photo.
        let automaticGallery = arrangement == nil && (layout == .gallery || layout == .mixed)
            && photoPlacements?.values.contains(where: { $0.frame != nil }) != true && !current.fills

        var placements = photoPlacements ?? [:]
        let outcome: Replacement
        var newFrame: PageRect?
        if close || fullBleed {
            outcome = close ? .sameFrame : .croppedToBleed
            if arrangement == nil, layout == .gallery || layout == .mixed {
                Self.pin(composition, into: &placements)
            }
            newFrame = placements[old]?.frame
        } else if automaticGallery {
            outcome = .reflowed
        } else {
            outcome = .fitted
            if arrangement == nil { Self.pin(composition, into: &placements) }
            let scale = min(frame.width / CGFloat(photoRatio), frame.height)
            let size = CGSize(width: scale * CGFloat(photoRatio), height: scale)
            let fitted = CGRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2,
                                width: size.width, height: size.height)
            newFrame = PageRect(fitted, in: composition.bounds)
        }
        placements.removeValue(forKey: old)
        // The new photo starts centered; the old crop belonged to another picture.
        if let newFrame { placements[new.id] = PhotoPlacement(frame: newFrame) }
        photoIDs[index] = new.id
        photoPlacements = placements.isEmpty ? nil : placements
        layerOrder = layerOrder?.map { $0 == .photo(old) ? .photo(new.id) : $0 }
        return outcome
    }

    /// Fixes every visible automatic frame, so later edits move nothing else.
    private static func pin(_ composition: PageComposition, into placements: inout [UUID: PhotoPlacement]) {
        for photo in composition.photos where placements[photo.id]?.frame == nil {
            placements[photo.id, default: PhotoPlacement()].frame = PageRect(photo.frame, in: composition.bounds)
        }
    }

    /// Places a photo in one empty slot of a fixed layout. When its position in the order already
    /// maps to that slot it stays automatic; otherwise it gets the slot as its frame.
    @discardableResult
    mutating func fillSlot(_ slot: Int, with id: UUID, in composition: PageComposition) -> Bool {
        guard arrangement != nil, composition.arrangementPhotoSlots.indices.contains(slot) else { return false }
        if !photoIDs.contains(id) { photoIDs.append(id) }
        guard let index = photoIDs.firstIndex(of: id) else { return false }
        var placements = photoPlacements ?? [:]
        if index == slot {
            placements[id]?.frame = nil
            if placements[id] == PhotoPlacement() { placements.removeValue(forKey: id) }
        } else {
            placements[id, default: PhotoPlacement()].frame =
                PageRect(composition.arrangementPhotoSlots[slot], in: composition.bounds)
        }
        photoPlacements = placements.isEmpty ? nil : placements
        return true
    }
}
