import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension EditorView {
    func editorDrag(_ item: EditorDragItem) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(EditorDropTarget.coordinateSpace))
            .updating($dragging) { value, preview, _ in
                preview = EditorDragPreview(item: item, location: value.location)
            }
            .onEnded { value in
                switch item {
                case let .page(id):
                    guard let destination = pageInsertion(at: value.location) else { return }
                    reorderPage(id, relativeTo: destination.id, after: destination.after)
                case let .photo(id):
                    placeDraggedPhoto(id, at: value.location)
                }
            }
    }

    @ViewBuilder var dragPreview: some View {
        if let dragging {
            Group {
                switch dragging.item {
                case let .photo(id):
                    if let photo = indexedPhoto(id) { preview(photo, small: true) }
                case let .page(id):
                    if let leaf = book.pages.first(where: { $0.id == id }) { mini(leaf) }
                }
            }
            .frame(width: 64, height: 47)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .shadow(color: .black.opacity(0.24), radius: 6, y: 2)
            .opacity(0.82)
            .position(x: dragging.location.x + 20, y: dragging.location.y + 16)
        }
    }

    func isPhotoDropTarget(_ target: EditorDropTarget) -> Bool {
        guard let dragging, case .photo = dragging.item else { return false }
        return dropFrames[.canvasViewport]?.contains(dragging.location) == true
            && dropFrames[target]?.contains(dragging.location) == true
    }

    func placeDraggedPhoto(_ id: UUID, at location: CGPoint) {
        guard dropFrames[.canvasViewport]?.contains(location) == true else { return }
        if let coverSide {
            let key = EditorDropTarget.cover(front: coverSide == .front)
            if dropFrames[key]?.contains(location) == true {
                activateCanvas { setCoverPhoto(id, side: coverSide) }
            }
        } else {
            for leaf in book.pages {
                guard let rect = dropFrames[.canvasPage(leaf.id)], rect.contains(location) else { continue }
                let local = CGPoint(x: location.x - rect.minX, y: location.y - rect.minY)
                activateCanvas {
                    dropPhoto(id, on: leaf, at: local, in: CGRect(origin: .zero, size: rect.size))
                }
                break
            }
        }
    }

    func isOnCurrentPage(_ id: UUID) -> Bool {
        if let coverSide { return coverPhotoID(coverSide) == id }
        return page?.photoIDs.contains(id) == true
    }

    func togglePhoto(_ id: UUID) {
        canvasPhotoSelection = nil
        if let coverSide {
            setCoverPhoto(isOnCurrentPage(id) ? nil : id, side: coverSide)
        } else if isOnCurrentPage(id) {
            remove(id)
        } else {
            assign(id)
        }
    }

    func assign(_ id: UUID) {
        guard let index else { return }
        let leaf = book.pages[index]
        guard !leaf.photoIDs.contains(id) else { return }
        editPages(tr("Aggiungi foto", "Add Photo")) { pages in
            Self.placePhoto(id, on: &pages[index])
        }
        selectedPhoto = id
        selectedBox = nil
    }

    func incomingPhotoPlacement(on leaf: BookPage, composition: PageComposition,
                                        bounds: CGRect, textFrames: [CGRect]) -> IncomingPhotoPlacement? {
        guard let dragging, case let .photo(id) = dragging.item, let photo = indexedPhoto(id),
              isPhotoDropTarget(.canvasPage(leaf.id)), let screenFrame = dropFrames[.canvasPage(leaf.id)] else { return nil }
        if leaf.effectiveLayout == .fullSpread {
            return .position(CanvasAlignment.Result(frame: bounds, guides: []))
        }
        let location = CGPoint(x: dragging.location.x - screenFrame.minX, y: dragging.location.y - screenFrame.minY)
        if let target = photoSwapTarget(id, at: location, in: bounds, composition: composition, textFrames: textFrames) {
            return .swap(target)
        }
        return .position(photoPlacement(photo, in: composition, at: location, bounds: bounds))
    }

    func photoSwapTarget(_ id: UUID, at point: CGPoint, in bounds: CGRect,
                                 composition: PageComposition, textFrames: [CGRect]) -> CanvasPhotoSwap.Target? {
        guard !NSEvent.modifierFlags.contains(.option) else { return nil }
        return CanvasPhotoSwap.target(moving: id, at: point, in: bounds, composition: composition, storyFrames: textFrames)
    }

    func photoPlacement(_ photo: BookPhoto, in composition: PageComposition, at location: CGPoint,
                                bounds: CGRect) -> CanvasAlignment.Result {
        let existing = composition.photos.first { $0.id == photo.id }
        let scale = bounds.width / composition.bounds.width
        let ratio = Double(photo.pixelWidth) / Double(max(1, photo.pixelHeight))
        let frameWidth = existing.map { $0.frame.width * scale }
            ?? min(bounds.width * 0.48, max(1, bounds.height * 0.48 * ratio))
        let frameHeight = existing.map { $0.frame.height * scale }
            ?? min(bounds.height * 0.48, frameWidth / max(0.01, ratio))
        let frame = CGRect(x: location.x - frameWidth / 2, y: location.y - frameHeight / 2,
                           width: frameWidth, height: frameHeight)
        let normalized = PageRect(frame, in: bounds)
        let proposed = existing == nil ? normalized.rect(in: bounds) : normalized.photoRect(in: bounds)
        let limit = existing == nil ? bounds : CanvasPhotoGeometry.movementBounds(for: proposed.size, in: bounds)
        let targets = alignmentTargets(in: composition, at: scale, excluding: .photo(photo.id))
        return CanvasAlignment.duringDrag(proposed, to: targets, within: limit)
    }

    func dropPhoto(_ id: UUID, on leaf: BookPage, at location: CGPoint, in bounds: CGRect) {
        guard let photo = indexedPhoto(id), let index = book.pages.firstIndex(where: { $0.id == leaf.id }) else { return }
        let current = book.pages[index]
        if current.effectiveLayout == .fullSpread {
            editPages(tr("Posiziona foto su due pagine", "Place Photo Across Both Pages")) {
                $0[index].placePhotoAcrossSpread(id)
            }
            selectCanvasPhoto(id, in: leaf)
            return
        }
        let composition = pageComposition(current)
        let blocks = composition.storyBlocks(page: current, book: book)
        let textFrames = blocks.map(\.frame) + composition.storyBackgroundFrames(page: current, blocks: blocks)
        if let target = photoSwapTarget(id, at: location, in: bounds, composition: composition, textFrames: textFrames) {
            swapPhoto(id, with: target.id, on: leaf.id)
            return
        }
        let result = photoPlacement(photo, in: composition, at: location, bounds: bounds)
        let normalized = PageRect(result.frame, in: bounds).photoClamped
        if current.photoIDs.contains(id) {
            updatePhotoFrame(id, in: leaf, to: normalized)
        } else {
            editPages(tr("Posiziona foto", "Place Photo")) { pages in
                pages[index].photoIDs.append(id)
                var placements = pages[index].photoPlacements ?? [:]
                placements[id] = PhotoPlacement(frame: normalized)
                pages[index].photoPlacements = placements
            }
        }
        selectCanvasPhoto(id, in: leaf)
    }

    func swapPhoto(_ id: UUID, with target: UUID, on pageID: UUID) {
        guard let index = book.pages.firstIndex(where: { $0.id == pageID }) else { return }
        var leaf = book.pages[index]
        guard leaf.swapPhotos(id, target, in: pageComposition(leaf)) else { return }
        editPages(tr("Scambia foto", "Swap Photos")) { $0[index] = leaf }
        selectCanvasPhoto(id, in: leaf)
    }

    func updatePhotoFrame(_ id: UUID, in leaf: BookPage, to frame: PageRect) {
        guard let index = book.pages.firstIndex(where: { $0.id == leaf.id }),
              book.pages[index].photoIDs.contains(id) else { return }
        let current = book.pages[index]
        editPages(tr("Sposta o ridimensiona foto", "Move or Resize Photo")) { pages in
            var placements = current.photoPlacements ?? [:]
            freezeAutomaticFrames(of: current, moving: id, placements: &placements)
            placements[id, default: PhotoPlacement()].frame = frame.photoClamped
            pages[index].photoPlacements = placements
        }
    }

    func resetPhotoFrames(_ pageID: UUID) {
        guard let index = book.pages.firstIndex(where: { $0.id == pageID }),
              let placements = book.pages[index].photoPlacements else { return }
        editPages(tr("Ripristina posizioni foto", "Reset Photo Placement")) { pages in
            pages[index].photoPlacements = Self.photoCrops(from: placements)
            if pages[index].arrangement == nil, pages[index].layout == .text, !pages[index].photoIDs.isEmpty {
                pages[index].layout = .mixed
            }
        }
    }

    static func photoCrops(from placements: [UUID: PhotoPlacement]?) -> [UUID: PhotoPlacement]? {
        let crops = placements?.compactMapValues { $0.crop.map { PhotoPlacement(crop: $0) } } ?? [:]
        return crops.isEmpty ? nil : crops
    }

    func beginCrop(_ photoID: UUID, in leaf: BookPage) {
        finishCrop()
        guard let current = book.pages.first(where: { $0.id == leaf.id }) else { return }
        let composition = pageComposition(current)
        guard let item = composition.photos.first(where: { $0.id == photoID }) else { return }
        selectCanvasPhoto(photoID, in: current)
        let frame = PageRect(item.frame, in: composition.bounds)
        cropSession = CropSession(surface: .canvasPage(leaf.id), photoID: photoID, initialFrame: frame,
                                  initialCrop: item.crop,
                                  frame: frame, crop: item.crop)
    }

    func magnifyCrop(_ factor: Double) {
        guard let session = cropSession else { return }
        cropSession?.crop.zoom = min(12, max(1, session.crop.zoom * factor))
    }

    func finishCrop() {
        guard let session = cropSession else { return }
        cropSession = nil
        let changedFrame = session.frame != session.initialFrame
        let changedCrop = session.crop != session.initialCrop
        guard changedFrame || changedCrop else { return }
        if case let .cover(front) = session.surface {
            let side: CoverSide = front ? .front : .back
            guard coverPhotoID(side) == session.photoID else { return }
            changeCoverPhotoPlacement(side, name: tr("Ritaglia foto", "Crop Photo")) {
                if changedFrame { $0.frame = session.frame }
                $0.crop = session.crop
            }
            return
        }
        guard case let .canvasPage(pageID) = session.surface,
              let index = book.pages.firstIndex(where: { $0.id == pageID }),
              book.pages[index].photoIDs.contains(session.photoID) else { return }
        let current = book.pages[index]
        editPages(tr("Ritaglia foto", "Crop Photo")) { pages in
            var placements = current.photoPlacements ?? [:]
            if changedFrame {
                freezeAutomaticFrames(of: current, moving: session.photoID, placements: &placements)
                placements[session.photoID, default: PhotoPlacement()].frame = session.frame
            }
            placements[session.photoID, default: PhotoPlacement()].crop = session.crop
            pages[index].photoPlacements = placements
        }
    }

    func freezeAutomaticFrames(of page: BookPage, moving id: UUID,
                                       placements: inout [UUID: PhotoPlacement]) {
        guard page.arrangement == nil, (page.layout == .gallery || page.layout == .mixed),
              placements[id]?.frame == nil else { return }
        let composition = pageComposition(page)
        for image in composition.photos where placements[image.id]?.frame == nil {
            placements[image.id, default: PhotoPlacement()].frame = PageRect(image.frame, in: composition.bounds)
        }
    }

    func transferPhoto(_ id: UUID, from sourceID: UUID, to destinationID: UUID, moving: Bool) {
        guard sourceID != destinationID,
              let source = book.pages.firstIndex(where: { $0.id == sourceID }),
              let destination = book.pages.firstIndex(where: { $0.id == destinationID }),
              book.pages[source].photoIDs.contains(id),
              !book.pages[destination].photoIDs.contains(id) else { return }
        let name = moving ? tr("Sposta foto", "Move Photo") : tr("Copia foto", "Copy Photo")
        editPages(name) { pages in
            let placement = pages[source].photoPlacements?[id]
            Self.placePhoto(id, on: &pages[destination])
            if let placement {
                var placements = pages[destination].photoPlacements ?? [:]
                placements[id] = placement
                pages[destination].photoPlacements = placements
            }
            if moving { Self.removePhoto(id, from: &pages[source]) }
        }
        select(book.pages[destination])
        selectedPhoto = id
    }

    static func placePhoto(_ id: UUID, on page: inout BookPage) {
        if let arrangement = page.arrangement {
            if arrangement.photoCapacity == 1 { page.photoIDs.insert(id, at: 0) }
            else { page.photoIDs.append(id) }
            return
        }
        switch page.layout {
        case .fullPage, .fullSpread:
            page.photoIDs.insert(id, at: 0)
        case .text:
            page.layout = .mixed
            page.photoIDs.append(id)
        case .gallery, .mixed:
            page.photoIDs.append(id)
        }
    }

    @discardableResult
    func remove(_ id: UUID, from pageID: UUID? = nil) -> Bool {
        guard let target = pageID ?? page?.id,
              let index = book.pages.firstIndex(where: { $0.id == target }),
              book.pages[index].photoIDs.contains(id) else { return false }
        editPages(tr("Rimuovi foto", "Remove Photo")) { pages in
            Self.removePhoto(id, from: &pages[index])
        }
        return true
    }

    @discardableResult
    func deleteCanvasPhoto(_ id: UUID, from pageID: UUID) -> Bool {
        guard cropSession == nil, inlineBoxFocus == nil, editorialFocus == nil,
              remove(id, from: pageID) else { return false }
        if canvasPhotoSelection?.photoID == id { canvasPhotoSelection = nil }
        if selectedPhoto == id { selectedPhoto = nil }
        return true
    }

    static func removePhoto(_ id: UUID, from page: inout BookPage) {
        page.photoIDs.removeAll { $0 == id }
        page.photoPlacements?.removeValue(forKey: id)
        if page.photoPlacements?.isEmpty == true { page.photoPlacements = nil }
    }

    func reorderPhoto(_ id: UUID, by offset: Int) {
        guard let index, let current = book.pages[index].photoIDs.firstIndex(of: id),
              book.pages[index].photoIDs.indices.contains(current + offset) else { return }
        editPages(tr("Sposta foto", "Move Photo")) { pages in
            pages[index].photoIDs.swapAt(current, current + offset)
        }
    }
}
