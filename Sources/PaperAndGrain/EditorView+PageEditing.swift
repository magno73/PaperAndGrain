import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension EditorView {
    func pageEditorialText(_ role: PageComposition.TextRole, on pageID: UUID) -> Binding<String> {
        Binding(
            get: {
                guard let leaf = book.pages.first(where: { $0.id == pageID }) else { return "" }
                return role == .title ? leaf.heading ?? "" : leaf.text
            },
            set: { value in
                guard let index = book.pages.firstIndex(where: { $0.id == pageID }) else { return }
                if role == .title { book.pages[index].heading = value.isEmpty ? nil : value }
                else { book.pages[index].text = value }
            }
        )
    }

    func movePageText(_ role: PageComposition.TextRole, on pageID: UUID, to frame: PageRect) {
        guard let index = book.pages.firstIndex(where: { $0.id == pageID }) else { return }
        let leaf = book.pages[index]
        let composition = pageComposition(leaf)
        let current = composition.storyBlocks(page: leaf, book: book)
        let backings = composition.storyBackgroundFrames(page: leaf, blocks: current)
        editPages(tr("Sposta o ridimensiona testo", "Move or Resize Text")) { pages in
            pages[index].freezeStoryBackdrop(backings, in: composition.bounds)
            for block in current where !block.frame.isEmpty {
                let original = PageRect(block.frame, in: composition.bounds).clamped
                if block.role == .title && pages[index].titleFrame == nil { pages[index].titleFrame = original }
                if block.role == .body && pages[index].storyFrame == nil { pages[index].storyFrame = original }
            }
            if role == .title { pages[index].titleFrame = frame.clamped }
            else { pages[index].storyFrame = frame.clamped }
        }
    }

    func moveStoryGroup(on pageID: UUID, by translation: CGSize) {
        guard let index = book.pages.firstIndex(where: { $0.id == pageID }) else { return }
        let leaf = book.pages[index]
        let composition = pageComposition(leaf)
        let blocks = composition.storyBlocks(page: leaf, book: book)
        let backings = composition.storyBackgroundFrames(page: leaf, blocks: blocks)
        editPages(tr("Sposta blocco di testo", "Move Story Group")) { pages in
            pages[index].moveStoryGroup(by: translation, blocks: blocks, backdrops: backings, in: composition.bounds)
        }
    }

    func setLayout(_ layout: PageLayout) {
        finishCrop()
        guard let index, book.pages[index].layout != layout || book.pages[index].arrangement != nil else { return }
        editPages(tr("Cambia composizione", "Change Layout")) { pages in
            pages[index].layout = layout
            pages[index].arrangement = nil
        }
    }

    func applyPageArrangement(_ arrangement: PageArrangement?, to pageID: UUID) {
        finishCrop()
        endInlineTextEditing()
        guard let index = book.pages.firstIndex(where: { $0.id == pageID }) else { return }
        editPages(tr("Cambia modello della pagina", "Change Page Template")) { pages in
            let wasSpread = pages[index].effectiveLayout == .fullSpread
            pages[index].arrangement = arrangement
            if let arrangement {
                pages[index].layout = arrangement.layout
                pages[index].photoPlacements = Self.photoCrops(from: pages[index].photoPlacements)
            } else if wasSpread {
                pages[index].layout = .gallery
            }
        }
        if let selection = canvasPhotoSelection, selection.pageID == pageID,
           !pageComposition(book.pages[index]).photos.contains(where: { $0.id == selection.photoID }) {
            canvasPhotoSelection = nil
            selectedPhoto = nil
        }
    }

    func insert(_ layout: PageLayout, at position: Int? = nil) {
        let newPage = BookPage(layout: layout)
        let insertionIndex = position ?? index.map { $0 + 1 } ?? book.pages.endIndex
        editPages(tr("Inserisci pagina", "Insert Page")) { $0.insert(newPage, at: insertionIndex) }
        select(newPage)
        inspector = .page
    }

    func insertTitlePage() {
        let titlePage = BookPage(layout: .text, heading: book.title)
        editPages(tr("Inserisci frontespizio", "Insert Title Page")) { $0.insert(titlePage, at: 0) }
        select(titlePage)
        inspector = .page
    }

    func insertPageHeading() {
        guard let leaf = page, let index else { return }
        let object = EditorialObject.page(leaf.id, .title)
        let composition = pageComposition(leaf)
        if !composition.storyBlocks(page: leaf, book: book).contains(where: { $0.role == .title }) {
            let safe = composition.story ?? composition.bounds.insetBy(dx: book.contentInsetPoints, dy: book.contentInsetPoints)
            let frame = CGRect(x: safe.minX, y: safe.minY, width: safe.width,
                               height: min(safe.height, max(44, composition.bounds.height * 0.16)))
            editPages(tr("Inserisci titolo", "Insert Heading")) { pages in
                pages[index].titleFrame = PageRect(frame, in: composition.bounds).clamped
            }
        }
        selectEditorial(object, on: book.pages[index])
        editingEditorial = object
    }

    func insertTextBox() {
        guard let page else { return }
        let inset = book.contentInsetPoints
        let bounds = pageComposition(page).bounds
        let safe = bounds.insetBy(dx: inset, dy: inset)
        let width = min(safe.width, book.format.pageSize.width * 0.62)
        let height = min(safe.height, bounds.height * 0.19)
        let count = page.textBoxes?.count ?? 0
        let offset = CGFloat(count % 4) * 16
        let x = min(safe.maxX - width, safe.minX + offset)
        let y = max(safe.minY, safe.maxY - height - offset)
        let box = PageTextBox(frame: PageRect(CGRect(x: x, y: y, width: width, height: height), in: bounds))
        changeTextBoxes(on: page.id, name: tr("Inserisci box di testo", "Insert Text Box")) { $0.append(box) }
        beginInlineBoxEditing(box.id, in: page)
    }

    func changeTextBoxes(on pageID: UUID, name: String, change: (inout [PageTextBox]) -> Void) {
        guard let index = book.pages.firstIndex(where: { $0.id == pageID }) else { return }
        editPages(name) { pages in
            var boxes = pages[index].textBoxes ?? []
            change(&boxes)
            pages[index].textBoxes = boxes.isEmpty ? nil : boxes
        }
    }

    func textInBox(_ id: UUID, on pageID: UUID) -> Binding<String> {
        Binding(
            get: { book.pages.first { $0.id == pageID }?.textBoxes?.first { $0.id == id }?.text ?? "" },
            set: { value in
                guard let index = book.pages.firstIndex(where: { $0.id == pageID }),
                      let boxIndex = book.pages[index].textBoxes?.firstIndex(where: { $0.id == id }) else { return }
                book.pages[index].textBoxes?[boxIndex].text = value
            }
        )
    }

    func updateTextBoxFrame(_ id: UUID, on pageID: UUID, to frame: PageRect) {
        changeTextBoxes(on: pageID, name: tr("Sposta o ridimensiona box", "Move or Resize Text Box")) { boxes in
            guard let index = boxes.firstIndex(where: { $0.id == id }) else { return }
            boxes[index].frame = frame.clamped
        }
    }
}
