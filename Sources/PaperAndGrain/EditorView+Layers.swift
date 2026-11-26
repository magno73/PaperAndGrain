import AppKit
import SwiftUI

/// Stacking order and the canvas context menu, built when the menu opens so it always acts
/// on the object under the pointer.
extension EditorView {
    struct LayerTarget: Equatable {
        let pageID: UUID
        let layer: PageLayer
    }

    var selectedLayer: LayerTarget? {
        guard coverSide == nil else { return nil }
        if let selection = canvasPhotoSelection, let pageID = selection.pageID {
            return LayerTarget(pageID: pageID, layer: .photo(selection.photoID))
        }
        if let box = selectedBox, let page, page.textBoxes?.contains(where: { $0.id == box }) == true {
            return LayerTarget(pageID: page.id, layer: .textBox(box))
        }
        if let pageID = selectedEditorial?.pageID { return LayerTarget(pageID: pageID, layer: .story) }
        return nil
    }

    func canMoveLayer(_ target: LayerTarget?, _ move: PageLayer.Move) -> Bool {
        guard let target, let leaf = book.pages.first(where: { $0.id == target.pageID }) else { return false }
        let layers = pageComposition(leaf).layers
        guard let index = layers.firstIndex(of: target.layer) else { return false }
        switch move {
        case .front, .forward: return index < layers.count - 1
        case .back, .backward: return index > 0
        }
    }

    func moveLayer(_ target: LayerTarget?, _ move: PageLayer.Move) {
        guard let target, let index = book.pages.firstIndex(where: { $0.id == target.pageID }) else { return }
        let composition = pageComposition(book.pages[index])
        var leaf = book.pages[index]
        guard leaf.moveLayer(target.layer, move, photos: composition.photos.map(\.id),
                             boxes: composition.textBoxes.map(\.id)) else { return }
        editPages(layerMoveName(move)) { $0[index].layerOrder = leaf.layerOrder }
    }

    func layerMoveName(_ move: PageLayer.Move) -> String {
        switch move {
        case .front: tr("Bring to Front")
        case .forward: tr("Bring Forward")
        case .backward: tr("Send Backward")
        case .back: tr("Send to Back")
        }
    }

    func layerEntries(_ target: LayerTarget) -> [EditorMenuEntry] {
        PageLayer.Move.allCases.map { move in
            EditorMenuEntry(layerMoveName(move), enabled: canMoveLayer(target, move)) { moveLayer(target, move) }
        }
    }

    /// Selects the object under a secondary click and returns the menu for it.
    func canvasMenu(at point: CGPoint) -> [EditorMenuEntry]? {
        guard dropFrames[.canvasViewport]?.contains(point) == true, !isCanvasControl(point), cropSession == nil
        else { return nil }
        // A secondary click on a member of a selection of several acts on all of them.
        if canvasGroup.isActive, let (leaf, target) = pageTarget(at: point), let layer = layer(for: target),
           canvasGroup.contains(layer, on: leaf.id) {
            return groupMenuEntries
        }
        selectObject(at: point)
        var entries: [EditorMenuEntry] = []
        if let coverSide {
            if case .photo = canvasTarget(at: point, on: .cover(front: coverSide == .front)) {
                entries += [
                    EditorMenuEntry(tr("Crop")) { beginCoverCrop(coverSide) },
                    EditorMenuEntry(tr("Adjust Photo…")) { showPhotoSection(film: false) },
                    .separator
                ]
            }
        } else if let (leaf, target) = pageTarget(at: point) {
            switch target {
            case let .photo(id), let .caption(id):
                let layer = LayerTarget(pageID: leaf.id, layer: .photo(id))
                entries += relinkEntries(for: id)
                let captioned = indexedPhoto(id)?.printedCaption != nil
                entries += [
                    EditorMenuEntry(captioned ? tr("Edit Caption") : tr("Add Caption")) { beginCaptionEditing(id, in: leaf) },
                    EditorMenuEntry(tr("Crop")) { beginCrop(id, in: leaf) },
                    EditorMenuEntry(tr("Adjust Photo…")) { showPhotoSection(film: false) },
                    EditorMenuEntry(tr("Auto Enhance")) {
                        if let photo = indexedPhoto(id) { autoEnhance(photo) }
                    },
                    .separator
                ]
                entries += layerEntries(layer)
                entries += [
                    .separator,
                    EditorMenuEntry(tr("Remove from Page")) { _ = remove(id, from: leaf.id) },
                    .separator
                ]
            case let .textBox(id):
                entries += [
                    EditorMenuEntry(tr("Edit Text", key: "layers.edit_text")) { beginInlineBoxEditing(id, in: leaf) },
                    // The inspector's Text tab, for this box.
                    EditorMenuEntry(tr("Font and Paragraph…")) {
                        selectTextBox(id, in: leaf)
                        showsInspector = true
                        showInspectorTab(.text)
                    },
                    .separator
                ]
                entries += layerEntries(LayerTarget(pageID: leaf.id, layer: .textBox(id)))
                entries += [
                    .separator,
                    EditorMenuEntry(tr("Remove Box")) {
                        changeTextBoxes(on: leaf.id, name: tr("Remove Box")) { $0.removeAll { $0.id == id } }
                        if selectedBox == id { selectedBox = nil }
                    },
                    .separator
                ]
            case let .story(role):
                entries += [
                    EditorMenuEntry(tr("Edit Text", key: "layers.edit_text")) {
                        let object = EditorialObject.page(leaf.id, role)
                        selectEditorial(object, on: leaf)
                        editingEditorial = object
                    },
                    EditorMenuEntry(tr("Font and Paragraph…")) {
                        selectEditorial(.page(leaf.id, role), on: leaf)
                        showsInspector = true
                        showInspectorTab(.text)
                    },
                    .separator
                ]
                entries += layerEntries(LayerTarget(pageID: leaf.id, layer: .story))
                entries.append(.separator)
            case .storyGroup:
                entries += layerEntries(LayerTarget(pageID: leaf.id, layer: .story))
                entries.append(.separator)
            case .paper, .coverText, .crop:
                break
            }
        }
        // One object aligns to the page's safe area.
        if coverSide == nil, selectedObjects != nil {
            entries += CanvasGroupGeometry.Alignment.allCases.map { alignment in
                EditorMenuEntry(alignmentName(alignment)) { alignSelection(alignment) }
            }
            entries.append(.separator)
        }
        if coverSide == nil, page != nil {
            entries += [
                EditorMenuEntry(tr("Insert Text Box"), action: insertTextBox),
                EditorMenuEntry(tr("Page Layout…")) { showLayoutPopover = true }
            ]
        }
        entries.append(EditorMenuEntry(tr("Browse the Book"), enabled: !book.pages.isEmpty,
                                       action: openBrowser))
        return entries
    }

    func pageTarget(at point: CGPoint) -> (BookPage, CanvasHitMap.Target)? {
        for surface in canvasHits.maps.keys {
            guard case let .canvasPage(id) = surface, let target = canvasTarget(at: point, on: surface),
                  let leaf = book.pages.first(where: { $0.id == id }) else { continue }
            return (leaf, target)
        }
        return nil
    }
}

/// One row of an AppKit context menu; a nil title is a separator.
struct EditorMenuEntry {
    let title: String?
    var enabled = true
    var action: () -> Void = {}

    init(_ title: String, enabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.enabled = enabled
        self.action = action
    }

    private init() { title = nil }

    static var separator: EditorMenuEntry { EditorMenuEntry() }

    static func menu(_ entries: [EditorMenuEntry]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        var previousWasSeparator = true
        for entry in entries {
            if let title = entry.title {
                let item = ClosureMenuItem(title: title, handler: entry.action)
                item.isEnabled = entry.enabled
                menu.addItem(item)
                previousWasSeparator = false
            } else if !previousWasSeparator {
                menu.addItem(.separator())
                previousWasSeparator = true
            }
        }
        if menu.items.last?.isSeparatorItem == true { menu.removeItem(at: menu.items.count - 1) }
        return menu
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func run() { handler() }
}
