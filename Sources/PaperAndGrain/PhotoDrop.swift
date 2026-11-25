import CoreGraphics
import Foundation

extension PageComposition {
    /// Layout slots that no photo covers for at least half their area, in slot order.
    var emptySlots: [(index: Int, frame: CGRect)] {
        arrangementPhotoSlots.enumerated().compactMap { index, slot in
            let area = slot.width * slot.height
            guard area > 0 else { return nil }
            let covered = photos.contains { photo in
                let overlap = photo.frame.intersection(slot)
                return !overlap.isNull && overlap.width * overlap.height >= area * 0.5
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
    /// Puts `new` where `old` is: the same place in the order, so the same layout slot, and the same frame.
    /// An automatic gallery reflows by aspect ratio, so its visible frames are pinned first.
    @discardableResult
    mutating func replacePhoto(_ old: UUID, with new: UUID, in composition: PageComposition) -> Bool {
        guard old != new, !photoIDs.contains(new), let index = photoIDs.firstIndex(of: old),
              composition.photos.contains(where: { $0.id == old }) else { return false }
        var placements = photoPlacements ?? [:]
        if arrangement == nil, layout == .gallery || layout == .mixed {
            for photo in composition.photos where placements[photo.id]?.frame == nil {
                placements[photo.id, default: PhotoPlacement()].frame = PageRect(photo.frame, in: composition.bounds)
            }
        }
        let frame = placements.removeValue(forKey: old)?.frame
        // The new photo fills the frame from its center; the old crop belonged to another picture.
        if let frame { placements[new] = PhotoPlacement(frame: frame) }
        photoIDs[index] = new
        photoPlacements = placements.isEmpty ? nil : placements
        layerOrder = layerOrder?.map { $0 == .photo(old) ? .photo(new) : $0 }
        return true
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
