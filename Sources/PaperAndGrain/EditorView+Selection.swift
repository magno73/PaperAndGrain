import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension EditorView {
    func isCanvasControl(_ point: CGPoint) -> Bool {
        EditorDropTarget.canvasControls.contains { dropFrames[$0]?.contains(point) == true }
    }

    func selectObject(at point: CGPoint) {
        // Buttons floating over the page act on the selection; they must not clear it.
        guard !isCanvasControl(point) else { return }
        let insideCanvas = dropFrames[.canvasViewport]?.contains(point) == true
        guard insideCanvas else {
            if showsTray, let id = libraryHitFrames.frames.photo(at: point) {
                selectLibraryPhoto(id)
            }
            return
        }
        editorInput.target = .canvas
        if let coverSide {
            switch canvasTarget(at: point, on: .cover(front: coverSide == .front)) {
            case let .photo(id): selectCoverPhoto(id)
            case .coverText:
                if editingEditorial != .cover(coverSide) { selectEditorial(.cover(coverSide)) }
            case .crop: break
            default: clearCanvasSelection()
            }
            return
        }
        for surface in canvasHits.maps.keys {
            guard case let .canvasPage(id) = surface, let target = canvasTarget(at: point, on: surface),
                  let leaf = id == page?.id ? page : book.pages.first(where: { $0.id == id }) else { continue }
            switch target {
            case let .photo(photoID): selectCanvasPhoto(photoID, in: leaf)
            case let .textBox(boxID):
                if inlineEditingBox != boxID { selectTextBox(boxID, in: leaf) }
            case let .story(role):
                let object = EditorialObject.page(id, role)
                if editingEditorial != object { selectEditorial(object, on: leaf) }
            case .storyGroup: selectEditorial(.storyGroup(id), on: leaf)
            case .paper:
                select(leaf)
                clearCanvasSelection()
            case .coverText, .crop: break
            }
            return
        }
        clearCanvasSelection()
    }

    func canvasTarget(at point: CGPoint, on surface: EditorDropTarget) -> CanvasHitMap.Target? {
        guard let frame = dropFrames[surface] else { return nil }
        return canvasHits.maps[surface]?.target(at: point, in: frame)
    }

    func clearCanvasSelection() {
        finishCrop()
        endInlineTextEditing()
        selectedPhoto = nil
        canvasPhotoSelection = nil
        selectedBox = nil
        selectedEditorial = nil
        writing = false
        writingBox = false
        searchingPhotos = false
        filmScope = .book
    }

    func deselectCanvas() -> Bool {
        guard editorInput.target == .canvas else { return false }
        if cropSession != nil {
            cropSession = nil
            return true
        }
        if inlineEditingBox != nil || editingEditorial != nil {
            endInlineTextEditing()
            return true
        }
        guard selectedPhoto != nil || selectedBox != nil || selectedEditorial != nil else { return false }
        clearCanvasSelection()
        return true
    }

    func activateCanvas(_ select: () -> Void) {
        editorInput.target = .canvas
        select()
    }

    func nudgeFromKeyboard(_ offset: CGSize, selecting: () -> Void) -> Bool {
        activateCanvas(selecting)
        return nudgeCanvasSelection(offset)
    }

    func nudgeCanvasSelection(_ offset: CGSize) -> Bool {
        guard editorInput.target == .canvas, cropSession == nil, inlineEditingBox == nil, editingEditorial == nil
        else { return false }
        if let side = coverSide, let selection = canvasPhotoSelection,
           selection.surface == .cover(front: side == .front),
           let map = canvasHits.maps[selection.surface],
           let frame = map.regions.last(where: { $0.target == .photo(selection.photoID) })?.frame {
            let limits = CanvasPhotoGeometry.movementBounds(for: frame.size, in: map.bounds)
            let moved = CanvasPhotoGeometry.moved(frame, by: offset, within: limits)
            if moved != frame {
                changeCoverPhotoPlacement(side, name: tr("Sposta foto di copertina", "Move Cover Photo")) {
                    $0.frame = PageRect(moved, in: map.bounds).photoClamped
                }
            }
            return true
        }
        if let coverSide, selectedEditorial == .cover(coverSide),
           let map = canvasHits.maps[.cover(front: coverSide == .front)],
           let frame = map.regions.last(where: { $0.target == .coverText })?.frame {
            let moved = CanvasPhotoGeometry.moved(frame, by: offset, within: map.bounds)
            if moved != frame { moveCoverText(coverSide, to: PageRect(moved, in: map.bounds)) }
            return true
        }
        guard let page, let map = canvasHits.maps[.canvasPage(page.id)] else { return false }
        if selectedEditorial == .storyGroup(page.id) {
            moveStoryGroup(on: page.id, by: offset)
            return true
        }
        if let selectedBox, let frame = map.regions.last(where: { $0.target == .textBox(selectedBox) })?.frame {
            let moved = CanvasPhotoGeometry.moved(frame, by: offset, within: map.bounds)
            if moved != frame { updateTextBoxFrame(selectedBox, on: page.id, to: PageRect(moved, in: map.bounds)) }
            return true
        }
        if case let .page(id, role)? = selectedEditorial, id == page.id,
           let frame = map.regions.last(where: { $0.target == .story(role) })?.frame {
            let moved = CanvasPhotoGeometry.moved(frame, by: offset, within: map.bounds)
            if moved != frame { movePageText(role, on: page.id, to: PageRect(moved, in: map.bounds)) }
            return true
        }
        if let selection = canvasPhotoSelection, selection.pageID == page.id,
           let frame = map.regions.last(where: { $0.target == .photo(selection.photoID) })?.frame {
            let limits = CanvasPhotoGeometry.movementBounds(for: frame.size, in: map.bounds)
            let moved = CanvasPhotoGeometry.moved(frame, by: offset, within: limits)
            if moved != frame { updatePhotoFrame(selection.photoID, in: page, to: PageRect(moved, in: map.bounds)) }
            return true
        }
        return false
    }

    func selectCanvasPhoto(_ id: UUID, in leaf: BookPage) {
        if cropSession?.surface != .canvasPage(leaf.id) || cropSession?.photoID != id { finishCrop() }
        endInlineTextEditing()
        select(leaf)
        searchingPhotos = false
        selectedBox = nil
        selectedEditorial = nil
        selectedPhoto = id
        canvasPhotoSelection = CanvasPhotoSelection(surface: .canvasPage(leaf.id), photoID: id)
        if inspector == .film { inspector = .photo }
    }

    func selectTextBox(_ id: UUID, in leaf: BookPage) {
        finishCrop()
        if inlineEditingBox != id { endInlineTextEditing() }
        select(leaf)
        selectedBox = id
        selectedEditorial = nil
        canvasPhotoSelection = nil
        selectedPhoto = nil
        inspector = .page
    }

    func beginInlineBoxEditing(_ id: UUID, in leaf: BookPage) {
        selectTextBox(id, in: leaf)
        writing = false
        writingBox = false
        inlineEditingBox = id
    }

    func endInlineTextEditing() {
        if inlineEditingBox != nil || inlineBoxFocus != nil {
            inlineEditingBox = nil
            inlineBoxFocus = nil
        }
        if editingEditorial != nil || editorialFocus != nil {
            editingEditorial = nil
            editorialFocus = nil
        }
    }

    func selectEditorial(_ object: EditorialObject, on leaf: BookPage? = nil) {
        finishCrop()
        if editingEditorial != object { endInlineTextEditing() }
        if let leaf { select(leaf) }
        selectedEditorial = object
        if case .cover = object { coverTypographyExpanded = true }
        selectedBox = nil
        selectedPhoto = nil
        canvasPhotoSelection = nil
        searchingPhotos = false
        writing = false
        writingBox = false
        inspector = .page
    }

    func deleteEditorSelection() -> Bool {
        switch editorInput.target.deletionTarget(selectedPageID: page?.id) {
        case .none: return false
        case .canvas: return deleteSelectedCanvasObject()
        case let .navigatorPage(id): return deleteNavigatorPage(id)
        case .navigatorCover: return false
        }
    }

    /// Arrow keys move the selection: objects on the canvas first, otherwise pages.
    /// In the navigator ← → step one page and ↑ ↓ one spread; on an empty canvas ← → turn the page.
    func handleArrowKey(_ offset: CGSize) -> Bool {
        if nudgeCanvasSelection(offset) { return true }
        guard cropSession == nil, inlineEditingBox == nil, editingEditorial == nil, browsingSpread == nil else { return false }
        let horizontal = offset.width != 0
        let forward = horizontal ? offset.width > 0 : offset.height > 0
        switch editorInput.target {
        case .navigatorPage, .navigatorCover:
            if horizontal { stepPage(forward ? 1 : -1) } else { stepSpread(forward ? 1 : -1) }
            editorInput.target = page.map { .navigatorPage($0.id) } ?? .navigatorCover
            return true
        case .canvas:
            guard horizontal, canvasPhotoSelection == nil, selectedBox == nil, selectedEditorial == nil else { return false }
            turnCanvasPage(forward ? 1 : -1)
            editorInput.target = .canvas
            return true
        case .none:
            return false
        }
    }

    /// The canvas turns what it shows: a spread in two-page view, otherwise a page.
    func turnCanvasPage(_ direction: Int) {
        if showSpread && coverSide == nil { stepSpread(direction) } else { stepPage(direction) }
    }

    func stepSpread(_ direction: Int) {
        let spreads = groups
        if coverSide == .front {
            if direction > 0, let first = spreads.first?.first { select(first); clearCanvasSelection() }
            return
        }
        if coverSide == .back {
            if direction < 0, let last = spreads.last?.first { select(last); clearCanvasSelection() }
            return
        }
        guard let page, let current = spreads.firstIndex(where: { $0.contains { $0.id == page.id } }) else { return }
        let target = current + direction
        if target < 0 {
            selectCover(.front)
        } else if target >= spreads.count {
            selectCover(.back)
        } else if let first = spreads[target].first {
            select(first)
            clearCanvasSelection()
        }
    }

    /// Scrolling over the page turns it while the whole page fits; zoomed pages keep scrolling.
    func canTurnPages(at point: CGPoint) -> Bool {
        guard zoom == .fitPage, dropFrames[.canvasViewport]?.contains(point) == true, cropSession == nil,
              inlineEditingBox == nil, editingEditorial == nil, browsingSpread == nil, dragging == nil else { return false }
        return !book.pages.isEmpty
    }

    func deleteSelectedCanvasObject() -> Bool {
        guard cropSession == nil, inlineEditingBox == nil, editingEditorial == nil
        else { return false }
        if let selectedBox, let page, page.textBoxes?.contains(where: { $0.id == selectedBox }) == true {
            changeTextBoxes(on: page.id, name: tr("Rimuovi box", "Remove Box")) { boxes in
                boxes.removeAll { $0.id == selectedBox }
            }
            self.selectedBox = nil
            return true
        }
        guard let selection = canvasPhotoSelection, selectedPhoto == selection.photoID else { return false }
        switch selection.surface {
        case let .canvasPage(id) where id == page?.id:
            return deleteCanvasPhoto(selection.photoID, from: id)
        case let .cover(front) where coverSide == (front ? .front : .back):
            let side: CoverSide = front ? .front : .back
            guard coverPhotoID(side) == selection.photoID else { return false }
            setCoverPhoto(nil, side: side)
            return true
        default: return false
        }
    }
}
