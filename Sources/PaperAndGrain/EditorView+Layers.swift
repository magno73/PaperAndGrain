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
        case .front: tr("Porta in primo piano", "Bring to Front")
        case .forward: tr("Porta avanti", "Bring Forward")
        case .backward: tr("Porta indietro", "Send Backward")
        case .back: tr("Porta in fondo", "Send to Back")
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
        selectObject(at: point)
        var entries: [EditorMenuEntry] = []
        if let coverSide {
            if case .photo = canvasTarget(at: point, on: .cover(front: coverSide == .front)) {
                entries += [
                    EditorMenuEntry(tr("Ritaglia", "Crop")) { beginCoverCrop(coverSide) },
                    EditorMenuEntry(tr("Regola foto…", "Adjust Photo…")) { showPhotoSection(film: false) },
                    .separator
                ]
            }
        } else if let (leaf, target) = pageTarget(at: point) {
            switch target {
            case let .photo(id):
                let layer = LayerTarget(pageID: leaf.id, layer: .photo(id))
                entries += [
                    EditorMenuEntry(tr("Ritaglia", "Crop")) { beginCrop(id, in: leaf) },
                    EditorMenuEntry(tr("Regola foto…", "Adjust Photo…")) { showPhotoSection(film: false) },
                    EditorMenuEntry(tr("Migliora in automatico", "Auto Enhance")) {
                        if let photo = indexedPhoto(id) { autoEnhance(photo) }
                    },
                    .separator
                ]
                entries += layerEntries(layer)
                entries += [
                    .separator,
                    EditorMenuEntry(tr("Togli dalla pagina", "Remove from Page")) { _ = remove(id, from: leaf.id) },
                    .separator
                ]
            case let .textBox(id):
                entries += [
                    EditorMenuEntry(tr("Modifica testo", "Edit Text")) { beginInlineBoxEditing(id, in: leaf) },
                    EditorMenuEntry(tr("Carattere e paragrafo…", "Font and Paragraph…")) { showInspectorTab(.page) },
                    .separator
                ]
                entries += layerEntries(LayerTarget(pageID: leaf.id, layer: .textBox(id)))
                entries += [
                    .separator,
                    EditorMenuEntry(tr("Rimuovi box", "Remove Box")) {
                        changeTextBoxes(on: leaf.id, name: tr("Rimuovi box", "Remove Box")) { $0.removeAll { $0.id == id } }
                        if selectedBox == id { selectedBox = nil }
                    },
                    .separator
                ]
            case let .story(role):
                entries += [
                    EditorMenuEntry(tr("Modifica testo", "Edit Text")) {
                        let object = EditorialObject.page(leaf.id, role)
                        selectEditorial(object, on: leaf)
                        editingEditorial = object
                    },
                    EditorMenuEntry(tr("Carattere e paragrafo…", "Font and Paragraph…")) { showInspectorTab(.page) },
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
        if coverSide == nil, page != nil {
            entries += [
                EditorMenuEntry(tr("Inserisci box di testo", "Insert Text Box"), action: insertTextBox),
                EditorMenuEntry(tr("Modello di pagina…", "Page Layout…")) { showLayoutPopover = true }
            ]
        }
        entries.append(EditorMenuEntry(tr("Sfoglia il libro", "Browse the Book"), enabled: !book.pages.isEmpty,
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
