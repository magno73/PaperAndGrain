import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension EditorView {
    var toolbarSubtitle: String {
        let count = physicalPageCount
        let pages = tr("%lld pages", count)
        return pages + " · " + dimensions
    }

    var editorToolbar: some CustomizableToolbarContent {
        Group {
            ToolbarItem(id: "pages", placement: .navigation) {
                Button {
                    showsNavigator.toggle()
                } label: {
                    Label(tr("Pages"), systemImage: "sidebar.left")
                }
                .help(showsNavigator ? tr("Hide Pages") : tr("Show Pages"))
            }
            ToolbarItem(id: "library", placement: .navigation) {
                Button(action: actions.closeBook) {
                    Label(tr("Library"), systemImage: "books.vertical")
                }
                .help(tr("Back to your books"))
            }
            ToolbarItem(id: "insert", placement: .principal) {
                Menu {
                    insertMenuItems
                } label: {
                    Label(tr("Insert"), systemImage: "plus")
                }
                .help(tr("Insert pages, text and a title page"))
            }
            ToolbarItem(id: "template", placement: .principal) {
                Button(action: actions.showTemplates) {
                    Label(tr("Style"), systemImage: "swatchpalette")
                }
                .help(tr("Choose the book template: paper, type and margins"))
            }
            ToolbarItem(id: "layout", placement: .principal) {
                Button {
                    showLayoutPopover = true
                } label: {
                    Label(tr("Layout"), systemImage: "rectangle.3.group")
                }
                .help(tr("Choose the page layout"))
                .disabled(page == nil || coverSide != nil)
                .popover(isPresented: $showLayoutPopover, arrowEdge: .bottom) {
                    layoutPopover
                }
            }
            ToolbarItem(id: "film", placement: .principal) {
                Button {
                    if selectedPhoto != nil { showPhotoSection(film: true) } else { showInspectorTab(.film) }
                } label: {
                    Label(tr("Film"), systemImage: "camera.filters")
                }
                .help(tr("Film look for the book or photo"))
            }
            ToolbarItem(id: "issues", placement: .primaryAction) {
                Button {
                    showsIssues.toggle()
                } label: {
                    issuesButtonLabel
                }
                .help(tr("Show problems and warnings found in the book"))
                .popover(isPresented: $showsIssues, arrowEdge: .bottom) {
                    issuesPopover
                }
            }
            ToolbarItem(id: "export", placement: .primaryAction) {
                Button(action: onExport) {
                    Label(tr("Export"), systemImage: "square.and.arrow.up")
                        .labelStyle(.titleAndIcon)
                }
                .prominentToolbarButton()
                .tint(Theme.accent)
                .disabled(cropSession != nil || book.pages.isEmpty)
                .help(tr("Export the book as PDF"))
            }
            ToolbarItem(id: "tray", placement: .primaryAction) {
                Toggle(isOn: $showsTray) {
                    Label(tr("Photo Library"), systemImage: "photo.on.rectangle")
                }
                .help(showsTray ? tr("Hide Photo Library", key: "toolbar.hide_photo_library") : tr("Show Photo Library", key: "toolbar.show_photo_library"))
            }
            ToolbarItem(id: "inspector", placement: .primaryAction) {
                Toggle(isOn: $showsInspector) {
                    Label(tr("Inspector"), systemImage: "sidebar.right")
                }
                .help(showsInspector ? tr("Hide Inspector") : tr("Show Inspector"))
            }
        }
    }

    static let insertableTemplates: [PageArrangement?] = [
        nil, .textOnly, .textBesidePhoto, .photoAboveText, .textOverPhoto, .fullBleed, .fullSpread, .twoAcross, .fourGrid
    ]

    @ViewBuilder var insertMenuItems: some View {
        Button(tr("Page"), systemImage: "doc.badge.plus") { insert(.gallery) }
        Button(tr("Text Box"), systemImage: "character.textbox", action: insertTextBox)
            .disabled(page == nil)
        Button(tr("Page Heading"), systemImage: "textformat.size", action: insertPageHeading)
            .disabled(page == nil)
        Button(tr("Title Page"), systemImage: "text.alignleft", action: insertTitlePage)
        Divider()
        // The same page templates as the inspector, so new pages never use the legacy layouts.
        Menu(tr("Page with Template")) {
            ForEach(Self.insertableTemplates, id: \.self) { arrangement in
                Button(PageArrangementPicker.name(arrangement, language: language)) { insert(arrangement: arrangement) }
            }
        }
    }

    @ViewBuilder var bookTitleMenu: some View {
        Button(tr("Book Templates…"), action: actions.showTemplates)
        Button(tr("Book & Print…"), action: actions.showBookSettings)
        Divider()
        Button(actions.saveTitle, action: actions.save)
        Button(tr("Save As…"), action: actions.saveAs)
        Divider()
        Button(tr("Export PDF…"), action: onExport)
            .disabled(book.pages.isEmpty)
        Button(tr("Export for Print…"), action: actions.exportPrint)
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
                Text(tr("Choosing a layout rearranges the frames. Text, photos and crops stay on the page."))
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
        commands.showsIssues = showsIssues || showsIssuesFromMenu
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
        commands.printGuides = printGuides
        commands.canBringForward = canMoveSelectionLayers(.forward)
        commands.canSendBackward = canMoveSelectionLayers(.backward)
        commands.moveLayer = moveSelectionLayers
        commands.canAlign = canAlignSelection
        commands.canDistribute = canDistributeSelection
        commands.canMakeSameSize = canMakeSameSize
        commands.align = alignSelection
        commands.distribute = { distributeSelection(horizontally: $0) }
        commands.makeSameSize = { makeSameSize(width: $0) }
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
        commands.canDuplicatePage = canDuplicatePage
        commands.duplicatePage = { duplicatePage() }
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
        commands.canCaptionPage = coverSide == nil && page.map(canCaptionPhotos) ?? false
        commands.captionPage = captionPhotosOnPage
        commands.toggleNavigator = { showsNavigator.toggle() }
        commands.toggleInspector = { showsInspector.toggle() }
        commands.toggleTray = { showsTray.toggle() }
        commands.toggleIssues = {
            if showsIssues || showsIssuesFromMenu {
                showsIssues = false
                showsIssuesFromMenu = false
            } else {
                showsIssuesFromMenu = true
            }
        }
        commands.setSpread = { value in if coverSide == nil { showSpread = value } }
        commands.zoomIn = { stepZoom(1) }
        commands.zoomOut = { stepZoom(-1) }
        commands.zoomToFit = { zoom = .fitPage }
        commands.toggleGutter = { gutterGuide.toggle() }
        commands.togglePrintGuides = { setPrintGuides(!printGuides) }
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
