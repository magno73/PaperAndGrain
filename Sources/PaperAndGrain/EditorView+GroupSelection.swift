import AppKit
import SwiftUI

/// The pointer state of a selection of several objects: the drag in progress and the selection rectangle.
/// It changes on every mouse move, so only the small views that show it read it (`GroupDragFollower`,
/// `GroupDragOverlay`); the editor itself does not redraw while the pointer moves.
@MainActor @Observable final class CanvasGroupDrag {
    var pageID: UUID?
    /// The selection's move, in displayed points, after clamping and snapping.
    var translation: CGSize = .zero
    var guides: [CanvasAlignment.Guide] = []
    /// The selection rectangle, in page points, on `marqueePage`.
    var marquee: CGRect?
    var marqueePage: UUID?

    func reset() {
        if pageID != nil { pageID = nil }
        if translation != .zero { translation = .zero }
        if !guides.isEmpty { guides = [] }
    }

    /// Forgets the drag and the rectangle: a gesture that never reported its end (a page turned under it,
    /// a sheet that took the pointer) leaves nothing drawn.
    func resetAll() {
        reset()
        if marquee != nil { marquee = nil }
        if marqueePage != nil { marqueePage = nil }
    }

    /// True while a selection is dragged or a selection rectangle is drawn.
    var isActive: Bool { pageID != nil || marquee != nil }
}

/// Shows an object at the selection's drag offset while the selection is dragged.
struct GroupDragFollower<Content: View>: View {
    let drag: CanvasGroupDrag
    let pageID: UUID
    let member: Bool
    let content: Content

    var body: some View {
        content.offset(member && drag.pageID == pageID ? drag.translation : .zero)
    }
}

/// The selection rectangle and the guides of a selection being dragged, over one page.
struct GroupDragOverlay: View {
    let drag: CanvasGroupDrag
    let pageID: UUID
    let scale: CGFloat
    let tint: Color

    var body: some View {
        ZStack(alignment: .topLeading) {
            if drag.marqueePage == pageID, let rect = drag.marquee {
                let shown = rect.applying(CGAffineTransform(scaleX: scale, y: scale))
                Rectangle()
                    .fill(tint.opacity(0.08))
                    .overlay { Rectangle().strokeBorder(tint, lineWidth: 1) }
                    .frame(width: shown.width, height: shown.height)
                    .position(x: shown.midX, y: shown.midY)
            }
            if drag.pageID == pageID, !drag.guides.isEmpty {
                CanvasAlignmentGuides(guides: drag.guides)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Multiple selection on one page (T5): building it, moving it, aligning and distributing it.
extension EditorView {
    /// The objects selected on a page: the group, or the single selection as one layer.
    var selectionLayers: (pageID: UUID, layers: [PageLayer])? {
        if canvasGroup.isActive, let pageID = canvasGroup.pageID { return (pageID, canvasGroup.layers) }
        return selectedLayer.map { ($0.pageID, [$0.layer]) }
    }

    /// After an edit or an undo, keeps only the selected objects still on the page.
    func pruneGroupSelection() {
        guard canvasGroup.isActive, let pageID = canvasGroup.pageID else { return }
        guard let leaf = book.pages.first(where: { $0.id == pageID }) else {
            canvasGroup = CanvasGroupSelection()
            return
        }
        let present = Set(selectableObjects(on: leaf).map(\.layer))
        let kept = canvasGroup.layers.filter(present.contains)
        guard kept != canvasGroup.layers else { return }
        if kept.count > 1 { canvasGroup.layers = kept } else { setSelection(kept, on: leaf) }
    }

    func isGroupMember(_ layer: PageLayer, on pageID: UUID) -> Bool {
        canvasGroup.contains(layer, on: pageID)
    }

    /// The selectable objects of a page with their frames in page points, back to front. The story counts
    /// when it has text: heading, story and backdrop are one object. `only` limits the work to those
    /// layers, so the story is not typeset unless it is asked for.
    func selectableObjects(on leaf: BookPage, only: Set<PageLayer>? = nil) -> [(layer: PageLayer, frame: CGRect)] {
        let composition = pageComposition(leaf)
        var result: [(layer: PageLayer, frame: CGRect)] = []
        for layer in composition.layers where only?.contains(layer) ?? true {
            switch layer {
            case let .photo(id):
                if let frame = composition.photos.first(where: { $0.id == id })?.frame { result.append((layer, frame)) }
            case .story:
                if let frame = storyExtent(of: leaf, in: composition) { result.append((layer, frame)) }
            case let .textBox(id):
                if let box = composition.textBoxes.first(where: { $0.id == id }) {
                    result.append((layer, box.frame.rect(in: composition.bounds)))
                }
            }
        }
        return result
    }

    /// How far each selected object may move: a photo as far as a single drag allows, text within the page.
    func groupMembers(_ objects: [(layer: PageLayer, frame: CGRect)], bounds: CGRect) -> [CanvasGroupGeometry.Member] {
        objects.map { object in
            let limits = if case .photo = object.layer {
                CanvasPhotoGeometry.movementBounds(for: object.frame.size, in: bounds)
            } else { bounds }
            return CanvasGroupGeometry.Member(frame: object.frame, limits: limits)
        }
    }

    func storyExtent(of leaf: BookPage, in composition: PageComposition) -> CGRect? {
        BookPage.storyExtent(of: leaf, book: book, in: composition)
    }

    /// Selects `layers` on `leaf`: two or more become the group, one the usual single selection.
    func setSelection(_ layers: [PageLayer], on leaf: BookPage) {
        switch layers.count {
        case 0:
            select(leaf)
            clearCanvasSelection()
        case 1:
            selectLayer(layers[0], on: leaf)
        default:
            clearCanvasSelection()
            select(leaf)
            canvasGroup = CanvasGroupSelection(pageID: leaf.id, layers: layers)
            editorInput.target = .canvas
            if inspector != .page { inspector = .page }
            AccessibilityNotification.Announcement(tr("%lld objects selected", layers.count)).post()
        }
    }

    func selectLayer(_ layer: PageLayer, on leaf: BookPage) {
        switch layer {
        case let .photo(id): selectCanvasPhoto(id, in: leaf)
        case let .textBox(id): selectTextBox(id, in: leaf)
        case .story:
            let composition = pageComposition(leaf)
            let blocks = composition.storyBlocks(page: leaf, book: book)
            let backings = composition.storyBackgroundFrames(page: leaf, blocks: blocks)
            if storyGroupFrame(blocks, backings: backings) != nil {
                selectEditorial(.storyGroup(leaf.id), on: leaf)
            } else if let role = blocks.first(where: { $0.text.length > 0 })?.role ?? blocks.first?.role {
                selectEditorial(.page(leaf.id, role), on: leaf)
            }
        }
    }

    /// The layer a click target stands for: a caption is its photo, a heading or story the story layer.
    func layer(for target: CanvasHitMap.Target) -> PageLayer? {
        switch target {
        case let .photo(id), let .caption(id): .photo(id)
        case let .textBox(id): .textBox(id)
        case .story, .storyGroup: .story
        case .coverText, .crop, .paper: nil
        }
    }

    /// Whether a click target is the text being typed in place: a text box, a heading or story, a caption.
    func isBeingTyped(_ target: CanvasHitMap.Target, on pageID: UUID) -> Bool {
        switch target {
        case let .textBox(id): inlineEditingBox == id
        case let .story(role): editingEditorial == .page(pageID, role)
        case let .caption(photoID): editingEditorial == .caption(page: pageID, photo: photoID)
        case .photo, .storyGroup, .coverText, .crop, .paper: false
        }
    }

    /// ⇧-click or ⌘-click on an object of a page: adds it to the selection or takes it out.
    func toggleSelection(_ target: CanvasHitMap.Target, on leaf: BookPage) {
        // An empty heading or story placeholder is not an object that can join a selection.
        guard let layer = layer(for: target), layer != .story || leaf.hasStoryText else { return }
        let current = selectionLayers
        let next = CanvasGroupSelection.toggling(layer, on: leaf.id, current: current?.layers ?? [],
                                                 currentPage: current?.pageID)
        setSelection(next, on: leaf)
    }

    /// ⌘A: every object on the page, when the canvas has the focus and nothing is typed.
    func selectAllObjects() -> Bool {
        guard editorInput.target == .canvas, coverSide == nil, cropSession == nil, inlineEditingBox == nil,
              editingEditorial == nil, let page else { return false }
        setSelection(selectableObjects(on: page).map(\.layer), on: page)
        return true
    }

    // MARK: Selection rectangle

    /// A press on blank paper of a page can start a selection rectangle.
    func canBeginMarquee(at point: CGPoint) -> Bool {
        guard coverSide == nil, cropSession == nil, inlineEditingBox == nil, editingEditorial == nil,
              dropFrames[.canvasViewport]?.contains(point) == true, !isCanvasControl(point) else { return false }
        return pageUnder(point).map { canvasTarget(at: point, on: .canvasPage($0.id)) == .paper } ?? false
    }

    func pageUnder(_ point: CGPoint) -> BookPage? {
        for case let .canvasPage(id) in canvasHits.maps.keys where dropFrames[.canvasPage(id)]?.contains(point) == true {
            return book.pages.first { $0.id == id }
        }
        return nil
    }

    /// A point of the editor in a page's points, held to the page.
    func pagePoint(_ point: CGPoint, on pageID: UUID) -> CGPoint? {
        guard let frame = dropFrames[.canvasPage(pageID)], let map = canvasHits.maps[.canvasPage(pageID)],
              frame.width > 0, frame.height > 0 else { return nil }
        let x = min(frame.maxX, max(frame.minX, point.x)), y = min(frame.maxY, max(frame.minY, point.y))
        return CGPoint(x: map.bounds.minX + (x - frame.minX) * map.bounds.width / frame.width,
                       y: map.bounds.minY + (y - frame.minY) * map.bounds.height / frame.height)
    }

    func updateMarquee(from origin: CGPoint, to point: CGPoint, ended: Bool) {
        guard let leaf = pageUnder(origin), let start = pagePoint(origin, on: leaf.id),
              let end = pagePoint(point, on: leaf.id) else {
            groupDrag.marquee = nil
            groupDrag.marqueePage = nil
            return
        }
        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                          width: abs(end.x - start.x), height: abs(end.y - start.y))
        guard ended else {
            groupDrag.marqueePage = leaf.id
            groupDrag.marquee = rect
            return
        }
        groupDrag.marquee = nil
        groupDrag.marqueePage = nil
        setSelection(CanvasGroupSelection.touched(by: rect, objects: selectableObjects(on: leaf)), on: leaf)
    }

    // MARK: Moving

    /// A drag of any selected object moves the selection. `translation` is in displayed points. On release
    /// it commits exactly the move last shown, snapping included.
    func dragGroup(by translation: CGSize, on leaf: BookPage, scale: CGFloat, ended: Bool) {
        guard canvasGroup.isActive, canvasGroup.pageID == leaf.id, scale > 0 else {
            groupDrag.reset()
            return
        }
        if ended {
            let shown = groupDrag.pageID == leaf.id ? groupDrag.translation : .zero
            groupDrag.reset()
            if shown != .zero {
                moveGroup(by: CGSize(width: shown.width / scale, height: shown.height / scale), on: leaf.id)
            }
            return
        }
        let objects = selectableObjects(on: leaf)
        let chosen = Set(canvasGroup.layers)
        let selected = objects.filter { chosen.contains($0.layer) }
        let extent = CanvasGroupGeometry.extent(selected.map(\.frame))
        guard !extent.isNull else { return }
        let page = scaled(pageComposition(leaf).bounds, by: scale)
        let members = groupMembers(selected.map { ($0.layer, scaled($0.frame, by: scale)) }, bounds: page)
        let shown = scaled(extent, by: scale)
        let clamped = CanvasGroupGeometry.clampedTranslation(translation, members: members)
        // Snapping uses the selection's bounding box against the page and the objects left out of it.
        let others = objects.filter { !chosen.contains($0.layer) }.map { scaled($0.frame, by: scale).intersection(page) }
        let result = CanvasAlignment.duringDrag(shown.offsetBy(dx: clamped.width, dy: clamped.height), to: others,
                                                edges: page, within: CanvasGroupGeometry.movementArea(members))
        let snapped = CanvasGroupGeometry.clampedTranslation(
            CGSize(width: result.frame.minX - shown.minX, height: result.frame.minY - shown.minY), members: members)
        groupDrag.pageID = leaf.id
        groupDrag.translation = snapped
        groupDrag.guides = result.guides
    }

    /// The drag handler of a selected object while two or more are selected; nil otherwise.
    func groupMove(_ layer: PageLayer, on leaf: BookPage, scale: CGFloat) -> ((CGSize, Bool) -> Void)? {
        guard isGroupMember(layer, on: leaf.id) else { return nil }
        return { translation, ended in dragGroup(by: translation, on: leaf, scale: scale, ended: ended) }
    }

    /// Moves every selected object by `translation` page points, as one step. The group stays on the page.
    func moveGroup(by translation: CGSize, on pageID: UUID, name: String? = nil) {
        guard canvasGroup.isActive, canvasGroup.pageID == pageID,
              let leaf = book.pages.first(where: { $0.id == pageID }) else { return }
        let selected = selectableObjects(on: leaf, only: Set(canvasGroup.layers))
        let delta = CanvasGroupGeometry.clampedTranslation(
            translation, members: groupMembers(selected, bounds: pageComposition(leaf).bounds))
        guard delta != .zero else { return }
        var frames: [PageLayer: CGRect] = [:]
        for object in selected { frames[object.layer] = object.frame.offsetBy(dx: delta.width, dy: delta.height) }
        applyFrames(frames, on: pageID, name: name ?? tr("Move Objects"))
    }

    /// Gives objects of a page new frames in one undo step (`BookPage.applyFrames`).
    func applyFrames(_ frames: [PageLayer: CGRect], on pageID: UUID, name: String) {
        guard !frames.isEmpty, let index = book.pages.firstIndex(where: { $0.id == pageID }) else { return }
        var updated = book.pages[index]
        updated.applyFrames(frames, book: book)
        guard updated != book.pages[index] else { return }
        editPages(name) { $0[index] = updated }
    }

    // MARK: Align, distribute, same size

    /// The selection's objects and frames on the current page, in the order they were selected. Only the
    /// selected objects are measured; call it when acting, not to enable a command.
    var selectedObjects: (leaf: BookPage, objects: [(layer: PageLayer, frame: CGRect)])? {
        guard coverSide == nil, let selection = selectionLayers,
              let leaf = book.pages.first(where: { $0.id == selection.pageID }) else { return nil }
        var frames: [PageLayer: CGRect] = [:]
        for object in selectableObjects(on: leaf, only: Set(selection.layers)) where frames[object.layer] == nil {
            frames[object.layer] = object.frame
        }
        var objects: [(layer: PageLayer, frame: CGRect)] = []
        for layer in selection.layers {
            if let frame = frames[layer] { objects.append((layer: layer, frame: frame)) }
        }
        if objects.isEmpty { return nil }
        return (leaf: leaf, objects: objects)
    }

    // The enabling checks read only the selection, never a frame: menus redraw while the author types.
    var canAlignSelection: Bool { coverSide == nil && selectionLayers != nil }

    var canDistributeSelection: Bool { coverSide == nil && canvasGroup.isActive && canvasGroup.layers.count > 2 }

    /// Two or more photos, or two or more text boxes.
    var canMakeSameSize: Bool {
        guard coverSide == nil, canvasGroup.isActive else { return false }
        let layers = canvasGroup.layers
        return layers.allSatisfy { if case .photo = $0 { true } else { false } }
            || layers.allSatisfy { if case .textBox = $0 { true } else { false } }
    }

    func alignSelection(_ alignment: CanvasGroupGeometry.Alignment) {
        guard let (leaf, objects) = selectedObjects else { return }
        let reference: CGRect
        if objects.count > 1 {
            reference = CanvasGroupGeometry.extent(objects.map(\.frame))
        } else {
            // One object aligns to the page: a photo to the safe margin, text to the area text may use,
            // which keeps it off a print service's binding margin.
            let bounds = pageComposition(leaf).bounds
            if case .photo = objects[0].layer {
                reference = PrintGuides.frames(pageSize: bounds.size, settings: book.printSettings ?? PrintSettings()).safe
            } else {
                reference = book.textSafeArea(of: leaf, bounds: bounds)
            }
        }
        let aligned = CanvasGroupGeometry.align(objects.map(\.frame), alignment, to: reference)
        applyFrames(Dictionary(uniqueKeysWithValues: zip(objects.map(\.layer), aligned)), on: leaf.id,
                    name: alignmentName(alignment))
    }

    func distributeSelection(horizontally: Bool) {
        guard let (leaf, objects) = selectedObjects, objects.count > 2 else { return }
        let spread = CanvasGroupGeometry.distribute(objects.map(\.frame), horizontally: horizontally)
        applyFrames(Dictionary(uniqueKeysWithValues: zip(objects.map(\.layer), spread)), on: leaf.id,
                    name: horizontally ? tr("Distribute Horizontally") : tr("Distribute Vertically"))
    }

    func makeSameSize(width: Bool) {
        guard canMakeSameSize, let (leaf, objects) = selectedObjects, let last = objects.last else { return }
        let photos = if case .photo = last.layer { true } else { false }
        let sized = CanvasGroupGeometry.sameSize(objects.map(\.frame), width: width, as: last.frame,
                                                 keepingProportions: photos)
        applyFrames(Dictionary(uniqueKeysWithValues: zip(objects.map(\.layer), sized)), on: leaf.id,
                    name: width ? tr("Make Same Width") : tr("Make Same Height"))
    }

    func alignmentName(_ alignment: CanvasGroupGeometry.Alignment) -> String {
        switch alignment {
        case .left: tr("Align Left")
        case .center: tr("Align Center")
        case .right: tr("Align Right")
        case .top: tr("Align Top")
        case .middle: tr("Align Middle")
        case .bottom: tr("Align Bottom")
        }
    }

    func alignmentSymbol(_ alignment: CanvasGroupGeometry.Alignment) -> String {
        switch alignment {
        case .left: "align.horizontal.left"
        case .center: "align.horizontal.center"
        case .right: "align.horizontal.right"
        case .top: "align.vertical.top"
        case .middle: "align.vertical.center"
        case .bottom: "align.vertical.bottom"
        }
    }

    // MARK: Layers, removal

    func canMoveSelectionLayers(_ move: PageLayer.Move) -> Bool {
        guard canvasGroup.isActive else { return canMoveLayer(selectedLayer, move) }
        guard let pageID = canvasGroup.pageID, let leaf = book.pages.first(where: { $0.id == pageID }) else { return false }
        let composition = pageComposition(leaf)
        return leaf.canMoveLayers(canvasGroup.layers, move, photos: composition.photos.map(\.id),
                                  boxes: composition.textBoxes.map(\.id))
    }

    /// Layer commands move the selected objects together and keep their order among themselves.
    func moveSelectionLayers(_ move: PageLayer.Move) {
        guard canvasGroup.isActive else { return moveLayer(selectedLayer, move) }
        guard let pageID = canvasGroup.pageID, let index = book.pages.firstIndex(where: { $0.id == pageID }) else { return }
        let composition = pageComposition(book.pages[index])
        var leaf = book.pages[index]
        guard leaf.moveLayers(canvasGroup.layers, move, photos: composition.photos.map(\.id),
                              boxes: composition.textBoxes.map(\.id)) else { return }
        editPages(layerMoveName(move)) { $0[index].layerOrder = leaf.layerOrder }
    }

    /// Removes the selected photos and text boxes from the page in one step. Photos stay in the Photo Library;
    /// the story is kept, as Delete never removes it.
    @discardableResult
    func removeGroupFromPage() -> Bool {
        guard canvasGroup.isActive, let pageID = canvasGroup.pageID,
              let index = book.pages.firstIndex(where: { $0.id == pageID }) else { return false }
        let layers = canvasGroup.layers
        editPages(tr("Remove from Page")) { pages in
            for layer in layers {
                switch layer {
                case let .photo(id): Self.removePhoto(id, from: &pages[index])
                case let .textBox(id):
                    pages[index].textBoxes?.removeAll { $0.id == id }
                    if pages[index].textBoxes?.isEmpty == true { pages[index].textBoxes = nil }
                case .story: break
                }
            }
        }
        clearCanvasSelection()
        return true
    }

    // MARK: Menus and inspector

    /// Align, distribute and size entries for the canvas context menu.
    var arrangeEntries: [EditorMenuEntry] {
        let canAlign = canAlignSelection
        var entries: [EditorMenuEntry] = CanvasGroupGeometry.Alignment.allCases.map { alignment in
            EditorMenuEntry(alignmentName(alignment), enabled: canAlign) { alignSelection(alignment) }
        }
        let distribute = canDistributeSelection, sameSize = canMakeSameSize
        entries += [
            .separator,
            EditorMenuEntry(tr("Distribute Horizontally"), enabled: distribute) { distributeSelection(horizontally: true) },
            EditorMenuEntry(tr("Distribute Vertically"), enabled: distribute) { distributeSelection(horizontally: false) },
            EditorMenuEntry(tr("Make Same Width"), enabled: sameSize) { makeSameSize(width: true) },
            EditorMenuEntry(tr("Make Same Height"), enabled: sameSize) { makeSameSize(width: false) },
        ]
        return entries
    }

    /// The context menu of a selection of several objects.
    var groupMenuEntries: [EditorMenuEntry] {
        var entries: [EditorMenuEntry] = arrangeEntries + [.separator]
        entries += PageLayer.Move.allCases.map { move -> EditorMenuEntry in
            EditorMenuEntry(layerMoveName(move), enabled: canMoveSelectionLayers(move)) { moveSelectionLayers(move) }
        }
        entries += [.separator, EditorMenuEntry(tr("Remove from Page")) { removeGroupFromPage() }]
        return entries
    }

    /// The Page tab's section for a selection of several objects.
    @ViewBuilder var groupInspector: some View {
        if canvasGroup.isActive {
            VStack(alignment: .leading, spacing: 9) {
                caption(tr("%lld objects selected", canvasGroup.layers.count))
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 4) {
                    ForEach(CanvasGroupGeometry.Alignment.allCases, id: \.self) { alignment in
                        Button { alignSelection(alignment) } label: {
                            Image(systemName: alignmentSymbol(alignment)).frame(width: 22, height: 18)
                        }
                        .help(alignmentName(alignment))
                        .accessibilityLabel(alignmentName(alignment))
                    }
                }
                HStack(spacing: 6) {
                    Button(tr("Distribute Horizontally")) { distributeSelection(horizontally: true) }
                        .help(tr("Equal gaps from left to right; the outer two stay"))
                    Button(tr("Distribute Vertically")) { distributeSelection(horizontally: false) }
                        .help(tr("Equal gaps from top to bottom; the outer two stay"))
                }
                .disabled(!canDistributeSelection)
                HStack(spacing: 6) {
                    Button(tr("Make Same Width")) { makeSameSize(width: true) }
                        .help(tr("The width of the object selected last"))
                    Button(tr("Make Same Height")) { makeSameSize(width: false) }
                        .help(tr("The height of the object selected last"))
                }
                .disabled(!canMakeSameSize)
                Button(role: .destructive) { removeGroupFromPage() } label: {
                    Label(tr("Remove from Page"), systemImage: "trash")
                }
                .help(tr("Remove the selected photos and text boxes from the page"))
            }
            .controlSize(.small)
        }
    }
}
