import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension EditorView {
    var toolbarSubtitle: String {
        let count = physicalPageCount
        let pages = count == 1 ? tr("1 pagina", "1 page") : tr("\(count) pagine", "\(count) pages")
        return pages + " · " + dimensions
    }

    var editorToolbar: some CustomizableToolbarContent {
        Group {
            ToolbarItem(id: "pages", placement: .navigation) {
                Button {
                    showsNavigator.toggle()
                } label: {
                    Label(tr("Pagine", "Pages"), systemImage: "sidebar.left")
                }
                .help(showsNavigator ? tr("Nascondi pagine", "Hide Pages") : tr("Mostra pagine", "Show Pages"))
            }
            ToolbarItem(id: "library", placement: .navigation) {
                Button(action: actions.closeBook) {
                    Label(tr("Libreria", "Library"), systemImage: "books.vertical")
                }
                .help(tr("Torna ai tuoi libri", "Back to your books"))
            }
            ToolbarItem(id: "insert", placement: .principal) {
                Menu {
                    insertMenuItems
                } label: {
                    Label(tr("Inserisci", "Insert"), systemImage: "plus")
                }
                .help(tr("Inserisci pagine, testi e frontespizio", "Insert pages, text and a title page"))
            }
            ToolbarItem(id: "template", placement: .principal) {
                Button(action: actions.showTemplates) {
                    Label(tr("Stile", "Style"), systemImage: "swatchpalette")
                }
                .help(tr("Scegli il modello del libro: carta, caratteri e margini", "Choose the book template: paper, type and margins"))
            }
            ToolbarItem(id: "layout", placement: .principal) {
                Button {
                    showLayoutPopover = true
                } label: {
                    Label(tr("Impagina", "Layout"), systemImage: "rectangle.3.group")
                }
                .help(tr("Scegli il modello della pagina", "Choose the page layout"))
                .disabled(page == nil || coverSide != nil)
                .popover(isPresented: $showLayoutPopover, arrowEdge: .bottom) {
                    layoutPopover
                }
            }
            ToolbarItem(id: "film", placement: .principal) {
                Button {
                    showInspectorTab(.film)
                } label: {
                    Label(tr("Pellicola", "Film"), systemImage: "camera.filters")
                }
                .help(tr("Look pellicola del libro o della foto", "Film look for the book or photo"))
            }
            ToolbarItem(id: "export", placement: .primaryAction) {
                Button(action: onExport) {
                    Label(tr("Esporta", "Export"), systemImage: "square.and.arrow.up")
                        .labelStyle(.titleAndIcon)
                }
                .prominentToolbarButton()
                .tint(Theme.accent)
                .disabled(cropSession != nil || book.pages.isEmpty)
                .help(tr("Esporta il libro in PDF", "Export the book as PDF"))
            }
            ToolbarItem(id: "tray", placement: .primaryAction) {
                Toggle(isOn: $showsTray) {
                    Label(tr("Fototeca", "Photo Library"), systemImage: "photo.on.rectangle")
                }
                .help(showsTray ? tr("Nascondi la fototeca", "Hide Photo Library") : tr("Mostra la fototeca", "Show Photo Library"))
            }
            ToolbarItem(id: "inspector", placement: .primaryAction) {
                Toggle(isOn: $showsInspector) {
                    Label(tr("Ispettore", "Inspector"), systemImage: "sidebar.right")
                }
                .help(showsInspector ? tr("Nascondi ispettore", "Hide Inspector") : tr("Mostra ispettore", "Show Inspector"))
            }
        }
    }

    @ViewBuilder var insertMenuItems: some View {
        Button(tr("Pagina", "Page"), systemImage: "doc.badge.plus") { insert(.gallery) }
        Button(tr("Box di testo", "Text Box"), systemImage: "character.textbox", action: insertTextBox)
            .disabled(page == nil)
        Button(tr("Titolo di pagina", "Page Heading"), systemImage: "textformat.size", action: insertPageHeading)
            .disabled(page == nil)
        Button(tr("Frontespizio", "Title Page"), systemImage: "text.alignleft", action: insertTitlePage)
        Divider()
        Menu(tr("Pagina con composizione", "Page with Layout")) {
            ForEach(layouts, id: \.self) { layout in
                Button(layoutName(layout), systemImage: layoutIcon(layout)) { insert(layout) }
            }
        }
    }

    @ViewBuilder var bookTitleMenu: some View {
        Button(tr("Modelli del libro…", "Book Templates…"), action: actions.showTemplates)
        Button(tr("Libro e stampa…", "Book & Print…"), action: actions.showBookSettings)
        Divider()
        Button(actions.saveTitle, action: actions.save)
        Button(tr("Salva con nome…", "Save As…"), action: actions.saveAs)
        Divider()
        Button(tr("Esporta PDF…", "Export PDF…"), action: onExport)
            .disabled(book.pages.isEmpty)
        Button(tr("Esporta per la stampa…", "Export for Print…"), action: actions.exportPrint)
            .disabled(book.pages.isEmpty)
    }

    var layoutPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let page {
                PageArrangementChoices(selection: page.arrangement ?? (page.layout == .fullSpread ? .fullSpread : nil),
                                       language: language,
                                       pageSize: book.format.pageSize,
                                       layout: page.effectiveLayout) { arrangement in
                    applyPageArrangement(arrangement, to: page.id)
                    showLayoutPopover = false
                }
                Text(tr("Scegliere un modello ridistribuisce le cornici. Testi, foto e ritagli restano nella pagina.",
                        "Choosing a layout rearranges the frames. Text, photos and crops stay on the page."))
                    .font(.caption)
                    .foregroundStyle(muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
            }
        }
        .padding(.bottom, 12)
        .frame(width: 350)
    }

    // MARK: Menu bar

    var editorCommands: EditorCommandSet {
        var commands = EditorCommandSet()
        let current = index
        commands.hasPage = page != nil
        commands.hasPhotoSelection = canvasPhotoSelection != nil
        commands.canMoveEarlier = current.map { $0 > 0 } ?? false
        commands.canMoveLater = current.map { $0 < book.pages.count - 1 } ?? false
        commands.canGoBack = coverSide == .back || (current.map { $0 > 0 } ?? false) || (coverSide == nil && !book.pages.isEmpty)
        commands.canGoForward = coverSide == .front || (current.map { $0 < book.pages.count - 1 } ?? false) || (coverSide == nil && !book.pages.isEmpty)
        commands.showsNavigator = showsNavigator
        commands.showsInspector = showsInspector
        commands.showsTray = showsTray
        commands.showsSpread = showSpread
        commands.gutterGuide = gutterGuide
        let layer = selectedLayer
        commands.canBringForward = canMoveLayer(layer, .forward)
        commands.canSendBackward = canMoveLayer(layer, .backward)
        commands.moveLayer = { moveLayer(layer, $0) }
        commands.insertPage = { insert(.gallery) }
        commands.insertTextBox = insertTextBox
        commands.insertHeading = insertPageHeading
        commands.insertTitlePage = insertTitlePage
        commands.chooseLayout = {
            if coverSide == nil, page != nil { showLayoutPopover = true }
        }
        commands.previousPage = { stepPage(-1) }
        commands.nextPage = { stepPage(1) }
        commands.moveEarlier = { move(-1) }
        commands.moveLater = { move(1) }
        commands.deletePage = { if page != nil { showDelete = true } }
        commands.crop = cropSelection
        commands.adjust = { showPhotoSection(film: false) }
        commands.autoEnhance = {
            if let id = canvasPhotoSelection?.photoID, let photo = indexedPhoto(id) { autoEnhance(photo) }
        }
        commands.film = {
            if selectedPhoto != nil { showPhotoSection(film: true) } else { showInspectorTab(.film) }
        }
        commands.removePhoto = { _ = deleteSelectedCanvasObject() }
        commands.toggleNavigator = { showsNavigator.toggle() }
        commands.toggleInspector = { showsInspector.toggle() }
        commands.toggleTray = { showsTray.toggle() }
        commands.setSpread = { value in if coverSide == nil { showSpread = value } }
        commands.zoomIn = { stepZoom(1) }
        commands.zoomOut = { stepZoom(-1) }
        commands.zoomToFit = { zoom = .fitPage }
        commands.toggleGutter = { gutterGuide.toggle() }
        commands.browse = openBrowser
        return commands
    }

    func cropSelection() {
        guard let selection = canvasPhotoSelection else { return }
        if case let .cover(front) = selection.surface {
            beginCoverCrop(front ? .front : .back)
        } else if let id = selection.pageID, let leaf = book.pages.first(where: { $0.id == id }) {
            beginCrop(selection.photoID, in: leaf)
        }
    }

    func stepPage(_ offset: Int) {
        if let coverSide {
            if coverSide == .front, offset > 0, let first = book.pages.first { select(first) }
            if coverSide == .back, offset < 0, let last = book.pages.last { select(last) }
            clearCanvasSelection()
            return
        }
        guard let current = index else { return }
        let target = current + offset
        if target < 0 {
            selectCover(.front)
        } else if target >= book.pages.count {
            selectCover(.back)
        } else {
            select(book.pages[target])
            clearCanvasSelection()
        }
    }

    func stepZoom(_ direction: Int) {
        let steps = [25, 50, 75, 100, 150, 200]
        let current: Int = if case let .percent(value) = zoom { value } else { 100 }
        if direction > 0 {
            zoom = .percent(steps.first { $0 > current } ?? 200)
        } else {
            zoom = .percent(steps.last { $0 < current } ?? 25)
        }
    }
}
