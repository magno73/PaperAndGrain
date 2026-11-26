import AppKit
import SwiftUI

/// Edit › Cut, Copy, Paste and Duplicate for canvas objects (T6). The pure rules are in
/// `CanvasClipboard`; this connects them to the selection, the pasteboard, undo and notices.
extension EditorView {
    /// Nothing is typed anywhere in the window: the Edit commands then belong to the canvas.
    var isTypingText: Bool {
        inlineEditingBox != nil || editingEditorial != nil || inlineBoxFocus != nil || editorialFocus != nil
            || writing || writingBox || searchingPhotos || NSApp.keyWindow?.firstResponder is NSText
    }

    /// Objects on the canvas are selected and the canvas has the focus.
    var canCopyObjects: Bool {
        editorInput.target == .canvas && coverSide == nil && cropSession == nil && !isTypingText
            && selectionLayers != nil
    }

    var canPasteObjects: Bool {
        editorInput.target == .canvas && coverSide == nil && page != nil && cropSession == nil && !isTypingText
            && CanvasClipboard.canRead(from: .general)
    }

    /// ⌘D duplicates objects only when it adds something: a text box or the story. Photos alone cannot be on
    /// their page twice, so ⌘D then stays **Duplicate Page**.
    var canDuplicateObjects: Bool {
        canCopyObjects && selectionClipboard?.clip.duplicatesOnItsPage == true
    }

    /// The selection as clipboard objects, in drawing order.
    var selectionClipboard: (leaf: BookPage, clip: CanvasClipboard)? {
        guard let selection = selectionLayers,
              let leaf = book.pages.first(where: { $0.id == selection.pageID }),
              let clip = CanvasClipboard(layers: selection.layers, page: leaf, book: book) else { return nil }
        return (leaf, clip)
    }

    var canvasEditCommands: CanvasEditCommands {
        CanvasEditCommands(canCopy: { canCopyObjects }, canPaste: { canPasteObjects },
                           copy: { _ = copyObjects() }, cut: cutObjects, paste: pasteObjects)
    }

    @discardableResult
    func copyObjects() -> CanvasClipboard? {
        guard canCopyObjects, let (_, clip) = selectionClipboard else { return nil }
        do {
            try clip.write(to: .general)
            return clip
        } catch {
            return nil
        }
    }

    /// Copy, then the objects leave the page, as one undo step.
    func cutObjects() {
        guard let clip = copyObjects(), let index = book.pages.firstIndex(where: { $0.id == clip.pageID }),
              let selection = selectionLayers else { return }
        let layers = selection.layers
        editPages(tr("Cut")) { $0[index].removeObjects(layers) }
        clearCanvasSelection()
    }

    func pasteObjects() {
        guard canPasteObjects, let leaf = page else { return }
        switch CanvasClipboard.read(from: .general) {
        case let .objects(clip)?:
            place(clip, on: leaf, name: tr("Paste"))
        case let .text(text)?:
            let composition = pageComposition(leaf)
            let inset = book.contentInsetPoints
            let box = CanvasClipboard.textBox(for: text, in: composition.bounds,
                                              safe: composition.bounds.insetBy(dx: inset, dy: inset))
            changeTextBoxes(on: leaf.id, name: tr("Paste")) { $0.append(box) }
            if let updated = book.pages.first(where: { $0.id == leaf.id }) { setSelection([.textBox(box.id)], on: updated) }
        case nil:
            break
        }
    }

    /// A copy of the selection on the same page, without the pasteboard: text boxes move 12 pt, photos
    /// cannot be on a page twice and are skipped with a notice.
    func duplicateObjects() {
        guard canDuplicateObjects, let (leaf, clip) = selectionClipboard else { return }
        place(clip, on: leaf, name: tr("Duplicate"))
    }

    /// Pastes `clip` on `leaf` as one undo step, selects what was added and says what was left out.
    func place(_ clip: CanvasClipboard, on leaf: BookPage, name: String) {
        guard let index = book.pages.firstIndex(where: { $0.id == leaf.id }) else { return }
        let pasted = clip.paste(into: book.pages[index], book: book)
        if !pasted.layers.isEmpty {
            editPages(name) { $0[index] = pasted.page }
            endInlineTextEditing()
            setSelection(pasted.layers, on: book.pages[index])
        }
        let onPage = pasted.skipped.filter { $0 == .alreadyOnPage }.count
        let elsewhere = pasted.skipped.filter { $0 == .otherBook }.count
        let gone = pasted.skipped.filter { $0 == .notInBook }.count
        if onPage > 0 {
            showCanvasNotice(tr("%lld photos are already on this page and were not added.", onPage))
        } else if elsewhere > 0 {
            showCanvasNotice(tr("%lld photos come from another book and were not pasted.", elsewhere))
        } else if gone > 0 {
            showCanvasNotice(tr("%lld photos are no longer in this book and were not pasted.", gone))
        }
    }
}
