import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension EditorView {
    var inspectorTabs: [InspectorTab] {
        var tabs = [InspectorTab(id: .page, title: coverSide == nil ? tr("Page") : tr("Cover"))]
        if selectedText != nil {
            tabs.append(InspectorTab(id: .text, title: tr("Text")))
        }
        if selectedPhoto != nil {
            // The photo's film look is a section of this tab; the Film tab is the book's look.
            tabs.append(InspectorTab(id: .photo, title: tr("Photo")))
        } else {
            tabs.append(InspectorTab(id: .film, title: tr("Film")))
        }
        return tabs
    }

    var sidePanel: some View {
        let tabs = inspectorTabs
        return InspectorHost(navigation: inspectorNavigation, title: tr("Inspector"), tabs: tabs,
                             finishAdjustment: finishPhotoAdjustmentEdit, finishFilm: finishFilmEdit) { tab in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch tab {
                    case .page: pageInspector
                    case .text: textInspector
                    case .photo: selectedPhotoInspector
                    case .film: filmInspector
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(ink)
        .tint(pine)
        .disabled(cropSession != nil)
        .onChange(of: tabs.map(\.id)) { _, ids in
            if !ids.contains(inspector) { inspector = .page }
        }
        .onChange(of: inspector, initial: true) { _, _ in syncFilmScope() }
        .onChange(of: filmAppliesToBook) { _, _ in syncFilmScope() }
    }

    /// Keynote-style: selecting a photo brings its tab forward, deselecting returns to the page.
    func followSelectionInInspector(previous: UUID?, current: UUID?) {
        if current != nil, previous == nil, inspector == .page { inspector = .photo }
        if current == nil, inspector == .photo { inspector = .page }
    }

    /// The Photo tab edits the selected photo's look unless “whole book” is ticked; the Film tab edits the book.
    func syncFilmScope() {
        let scope: FilmScope = inspector == .photo && !filmAppliesToBook ? .photo : .book
        if filmScope != scope { filmScope = scope }
    }

    /// Opens the Photo tab with the adjustments or the film look expanded.
    func showPhotoSection(film: Bool) {
        if film { showsPhotoFilmSection = true } else { showsAdjustSection = true }
        showInspectorTab(.photo)
    }

    func showInspectorTab(_ tab: Inspector) {
        showsInspector = true
        if tab == .photo && selectedPhoto == nil { inspector = .page; return }
        inspector = tab
    }

    /// Everything about the selected photo in one place: placement, adjustments and its film look.
    @ViewBuilder var selectedPhotoInspector: some View {
        if let selectedPhoto, let photo = indexedPhoto(selectedPhoto) {
            HStack(spacing: 10) {
                preview(photo, small: true, fills: false)
                    .frame(width: 64, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                VStack(alignment: .leading, spacing: 2) {
                    Text(photo.name).font(.callout.weight(.semibold)).lineLimit(1)
                    Text("\(photo.pixelWidth) × \(photo.pixelHeight) · \(photoOrientation(photo).label)")
                        .font(.caption).foregroundStyle(muted)
                    photoResolutionRow
                }
            }
            missingPhotoRow(photo)
            if !isOnCurrentPage(photo.id) {
                Button(tr("Add to page")) { togglePhoto(photo.id) }
                    .disabled(page == nil && coverSide == nil)
            }
            // The cover shows no captions, so a cover photo has no caption field.
            if canvasPhotoSelection?.pageID != nil || canvasPhotoSelection == nil {
                captionInspector(photo)
            }
            inspectorSection(tr("Adjust"), expanded: $showsAdjustSection) {
                photoAdjustmentsInspector
            }
            inspectorSection(tr("Film"),
                             detail: filmName(book.effectiveFilm(for: photo).preset)
                                 + (photo.film == nil ? " · " + tr("from book") : ""),
                             expanded: $showsPhotoFilmSection) {
                photoFilmSection(photo)
            }
            if let selection = canvasPhotoSelection, let pageID = selection.pageID, selection.photoID == photo.id {
                layerButtons(LayerTarget(pageID: pageID, layer: .photo(photo.id)))
            }
            if let analysis = photo.analysis {
                let labels = (!analysis.labels.isEmpty ? analysis.labels : analysis.concepts).prefix(4)
                if !labels.isEmpty || analysis.revision >= PhotoAnalysis.currentRevision {
                    inspectorSection(tr("Analysis"), expanded: $showsAnalysisSection) {
                        VStack(alignment: .leading, spacing: 6) {
                            if !labels.isEmpty { intro(labels.map(conceptName).joined(separator: " · ")) }
                            if analysis.revision >= PhotoAnalysis.currentRevision { photoAnalysisDetails(analysis) }
                        }
                    }
                }
            }
        } else {
            intro(tr("Select a photo on the page or in the photo library."))
        }
    }

    /// A collapsible group with a bold header, like the sections of Keynote's Format inspector.
    func inspectorSection<Content: View>(_ title: String, detail: String? = nil, expanded: Binding<Bool>,
                                         @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Button {
                withAnimation(.snappy(duration: 0.2)) { expanded.wrappedValue.toggle() }
            } label: {
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    if let detail, !expanded.wrappedValue {
                        Text(detail).font(.caption).foregroundStyle(muted).lineLimit(1)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(muted)
                        .rotationEffect(.degrees(expanded.wrappedValue ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded.wrappedValue ? tr("Expanded") : tr("Collapsed"))
            if expanded.wrappedValue { content() }
        }
    }

    /// The book's template, one click from the page it styles.
    var bookTemplateRow: some View {
        Button(action: actions.showTemplates) {
            HStack(spacing: 9) {
                Image(systemName: "swatchpalette")
                    .font(.system(size: 15))
                    .foregroundStyle(pine)
                    .frame(width: 35, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("Book Template")).font(.system(size: 11, weight: .semibold))
                    Text(book.template?.name(language: language) ?? tr("Basic"))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 3)
                Text(tr("Change…")).font(.system(size: 11)).foregroundStyle(pine)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(pine.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(pine.opacity(0.24)) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr("Book Template"))
        .accessibilityValue(book.template?.name(language: language) ?? tr("Basic"))
        .help(tr("Paper, type and margins for the whole book"))
    }

    @ViewBuilder var pageInspector: some View {
        bookTemplateRow
        if let coverSide {
            coverInspector(coverSide)
        } else if let page {
            let visiblePhotos = Set(pageComposition(page).photos.map(\.id))
            let waiting = page.photoIDs.count - visiblePhotos.count
            VStack(alignment: .leading, spacing: 7) {
                // One control for the page type: automatic gallery, fixed layouts and full bleed.
                PageArrangementPicker(selection: page.arrangement ?? (page.layout == .fullSpread ? .fullSpread : nil),
                                      language: language,
                                      pageSize: book.format.pageSize,
                                      layout: page.effectiveLayout) { arrangement in
                    applyPageArrangement(arrangement, to: page.id)
                }
                if waiting > 0 {
                    intro(tr("%lld photos waiting for a slot.", waiting))
                }
            }
            textBoxInspector(page)
            let storyLayout = page.effectiveLayout == .text || page.effectiveLayout == .mixed
            let showsBody = storyLayout || page.storyFrame != nil
            if storyLayout || page.titleFrame != nil || page.storyFrame != nil {
                VStack(alignment: .leading, spacing: 8) {
                    caption(tr("Heading and Text"))
                    // Formatting lives in the Text tab only; this tab edits the words.
                    Button {
                        selectEditorial(showsBody ? .storyGroup(page.id) : .page(page.id, .title), on: page)
                        showInspectorTab(.text)
                    } label: {
                        Label(tr("Font and Paragraph"), systemImage: "textformat")
                    }
                    if page.effectiveLayout == .mixed && page.arrangement == nil {
                        Picker(tr("Text Position"), selection: Binding(
                            get: { self.page?.textPlacement ?? .below },
                            set: { placement in
                                guard let index else { return }
                                book.pages[index].textPlacement = placement
                            }
                        )) {
                            Text(tr("Below")).tag(PageTextPlacement.below)
                            Text(tr("Beside")).tag(PageTextPlacement.beside)
                        }
                        .pickerStyle(.segmented)
                    }
                    TextField(tr("Page Heading", key: "inspector.page_heading"), text: Binding(
                        get: { self.page?.heading ?? "" },
                        set: { value in
                            guard let index else { return }
                            book.pages[index].heading = value.isEmpty ? nil : value
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .focused($headingFocused)
                    .checksSpelling()
                    if showsBody {
                        TextEditor(text: text)
                            .font(.system(size: 14, design: .serif))
                            .scrollContentBackground(.hidden)
                            .focused($writing)
                            .checksSpelling()
                            .padding(5)
                            .frame(minHeight: 140)
                            .background(paper, in: RoundedRectangle(cornerRadius: 6))
                            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(writing ? pine : edge) }
                            .accessibilityLabel(tr("Story"))
                    }
                    if storyLayout && (page.titleFrame != nil || page.storyFrame != nil) {
                        Button(tr("Reset Heading and Text Placement")) {
                            guard let index = book.pages.firstIndex(where: { $0.id == page.id }) else { return }
                            endInlineTextEditing()
                            selectedEditorial = nil
                            editPages(tr("Reset Text Placement")) {
                                $0[index].titleFrame = nil
                                $0[index].storyFrame = nil
                                $0[index].storyBackdropFrames = nil
                            }
                        }
                    }
                }
                if showsBody { suggestions }
            }
            if page.effectiveLayout != .text || !page.photoIDs.isEmpty {
                LazyVStack(alignment: .leading, spacing: 8) {
                    HStack {
                        caption(tr("Photos on page"))
                        Spacer()
                        Button { browsePhotos() } label: {
                            Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                        }
                        .help(tr("Browse available photos"))
                    }
                    let pagePhotos = photos(on: page)
                    let destinations = pagePhotos.isEmpty ? [] : photoTransferDestinations(excluding: page.id)
                    if pagePhotos.isEmpty {
                        intro(tr("Choose a photo from the photo library or drag it onto the page."))
                    }
                    ForEach(pagePhotos) { photo in
                        HStack(spacing: 8) {
                            preview(photo, small: true).frame(width: 29, height: 24).clipped()
                            VStack(alignment: .leading, spacing: 2) {
                                Text(photo.name).font(.system(size: 11)).lineLimit(1)
                                if !visiblePhotos.contains(photo.id) {
                                    Text(tr("Waiting")).font(.system(size: 9)).foregroundStyle(muted)
                                }
                            }
                            Spacer(minLength: 2)
                            Menu {
                                Button(tr("Move earlier")) { reorderPhoto(photo.id, by: -1) }
                                    .disabled(page.photoIDs.first == photo.id)
                                Button(tr("Move later")) { reorderPhoto(photo.id, by: 1) }
                                    .disabled(page.photoIDs.last == photo.id)
                                photoTransferMenu(photo.id, from: page.id, destinations: destinations)
                                if !visiblePhotos.contains(photo.id) {
                                    Button(tr("Remove from page"), role: .destructive) {
                                        remove(photo.id, from: page.id)
                                    }
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                            .menuIndicator(.hidden)
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                            .help(tr("Photo options"))
                        }
                    }
                }
            }
            if page.effectiveLayout != .fullPage && page.effectiveLayout != .fullSpread,
               page.photoPlacements?.values.contains(where: { $0.frame != nil }) == true {
                Button(tr("Reset automatic photo placement")) {
                    resetPhotoFrames(page.id)
                }
            }
            Rectangle().fill(edge).frame(height: 1)
            Button(role: .destructive) { showDelete = true } label: {
                Label(tr("Delete page…"), systemImage: "trash")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.destructive)
        } else {
            intro(tr("Add a page to arrange photos and stories."))
        }
    }

    func textBoxInspector(_ leaf: BookPage) -> some View {
        let boxes = leaf.textBoxes ?? []
        let active = boxes.first { $0.id == selectedBox }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                caption(tr("Text Boxes"))
                Spacer()
                action("plus", tr("Add Text Box"), perform: insertTextBox)
            }
            if !boxes.isEmpty {
                Picker(tr("Text Box"), selection: Binding(
                    get: { selectedBox },
                    set: { if let id = $0 { selectTextBox(id, in: leaf) } else { selectedBox = nil } }
                )) {
                    Text(tr("Select a Box")).tag(UUID?.none)
                    ForEach(Array(boxes.enumerated()), id: \.element.id) { offset, box in
                        let firstLine = box.text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
                        Text(firstLine.isEmpty ? tr("Box") + " " + String(offset + 1) : String(firstLine.prefix(24)))
                            .tag(Optional(box.id))
                    }
                }
                .labelsHidden()
            }
            if let active {
                Button {
                    showInspectorTab(.text)
                } label: {
                    Label(tr("Font and Paragraph"), systemImage: "textformat")
                }
                TextEditor(text: textInBox(active.id, on: leaf.id))
                    .font(.system(size: 14, design: .serif))
                    .scrollContentBackground(.hidden)
                    .focused($writingBox)
                    .checksSpelling()
                    .padding(5)
                    .frame(minHeight: 102)
                    .background(paper, in: RoundedRectangle(cornerRadius: 6))
                    .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(writingBox ? pine : edge) }
                    .accessibilityLabel(tr("Box Text"))
                Button(tr("Remove Box"), role: .destructive) {
                    changeTextBoxes(on: leaf.id, name: tr("Remove Box")) { $0.removeAll { $0.id == active.id } }
                    selectedBox = nil
                }
            }
        }
    }

    // MARK: Text tab

    enum TextSelection: Equatable {
        case box(page: UUID, box: UUID)
        case heading(page: UUID)
        case story(page: UUID)
        case cover(CoverSide)
    }

    var selectedText: TextSelection? {
        if let coverSide {
            return selectedEditorial == .cover(coverSide) ? .cover(coverSide) : nil
        }
        guard let page else { return nil }
        if let box = selectedBox, page.textBoxes?.contains(where: { $0.id == box }) == true {
            return .box(page: page.id, box: box)
        }
        switch selectedEditorial {
        case let .page(id, .title)? where id == page.id: return .heading(page: id)
        case let .page(id, _)? where id == page.id: return .story(page: id)
        case let .storyGroup(id)? where id == page.id: return .story(page: id)
        default: return nil
        }
    }

    /// Keynote's Format › Text, for the box, heading or story selected on the page.
    @ViewBuilder var textInspector: some View {
        let style = book.editorialStyle
        let palette = [style.titleInk, style.ink, style.accent, 0x000000, 0xFFFFFF]
        switch selectedText {
        case let .box(pageID, boxID)?:
            if let leaf = book.pages.first(where: { $0.id == pageID }),
               let box = leaf.textBoxes?.first(where: { $0.id == boxID }) {
                caption(tr("Text Box"))
                EditorialTypographyControls(style: boxTextStyle(boxID, on: pageID),
                                           inherited: style.defaultBodyStyle.applying(book.typography?.body),
                                           language: language, sampleText: box.text,
                                           defaultInk: style.ink, palette: palette)
                    .id(boxID)
                let frame = box.frame.rect(in: pageComposition(leaf).bounds)
                    .insetBy(dx: box.textInsetPoints, dy: box.textInsetPoints)
                if !EditorialTypesetter.fits(PageComposition.boxText(box: box, book: book), in: frame) {
                    typeOverflow(tr("Enlarge the box or reduce the text size."))
                }
                Divider()
                Toggle(tr("Use Full Width"), isOn: Binding(
                    get: { box.usesFullWidth == true },
                    set: { fullWidth in
                        changeTextBoxes(on: pageID, name: tr("Change Text Box Insets")) { boxes in
                            guard let index = boxes.firstIndex(where: { $0.id == boxID }) else { return }
                            boxes[index].usesFullWidth = fullWidth ? true : nil
                        }
                    }
                ))
                .toggleStyle(.checkbox)
                boxFrameControls(box, on: pageID, palette: palette)
                layerButtons(LayerTarget(pageID: pageID, layer: .textBox(boxID)))
            }
        case let .heading(pageID)?:
            if let leaf = book.pages.first(where: { $0.id == pageID }) {
                headingFormat(leaf, palette: palette)
                layerButtons(LayerTarget(pageID: pageID, layer: .story))
            }
        case let .story(pageID)?:
            if let leaf = book.pages.first(where: { $0.id == pageID }) {
                headingFormat(leaf, palette: palette)
                Divider()
                caption(tr("Story"))
                EditorialTypographyControls(style: pageTextStyle(\.body, on: pageID),
                                           inherited: style.defaultBodyStyle.applying(book.typography?.body),
                                           language: language, sampleText: leaf.text,
                                           defaultInk: leaf.arrangement == .textOverPhoto ? style.overlayInk : style.ink,
                                           palette: palette)
                    .id(pageID)
                let blocks = pageComposition(leaf).storyDrawingBlocks(page: leaf, book: book)
                if blocks.contains(where: { !EditorialTypesetter.fits($0.text, in: $0.frame) }) {
                    typeOverflow(tr("Some lines exceed the text frame."))
                }
                layerButtons(LayerTarget(pageID: pageID, layer: .story))
            }
        case let .cover(side)?:
            let front = side == .front
            let defaultStyle = front && book.template != nil ? style.defaultTitleStyle(mixed: false) : style.defaultBodyStyle
            caption(front ? tr("Cover Title") : tr("Back Cover Text"))
            EditorialTypographyControls(style: coverTextStyle(front ? \.title : \.body),
                                       inherited: defaultStyle.applying(front ? book.typography?.title : book.typography?.body),
                                       language: language, sampleText: coverEditorialValue(side).wrappedValue,
                                       defaultInk: front ? style.titleInk : style.ink, palette: palette)
                .id(side)
            let face = BookCoverGeometry(book: book, front: front)
            if let frame = face.titleFrame, !EditorialTypesetter.fits(face.title, in: frame) {
                typeOverflow(tr("The text exceeds the cover space."))
            }
        case nil:
            intro(tr("Select a text box, heading or story on the page."))
        }
    }

    enum BoxFillChoice: Hashable { case none, paper, color }

    /// Background and border of a text box, like Keynote's Fill and Border.
    func boxFrameControls(_ box: PageTextBox, on pageID: UUID, palette: [UInt32]) -> some View {
        let style = book.editorialStyle
        let fillChoice: BoxFillChoice = box.hidesBackground == true ? .none : (box.backgroundColor == nil ? .paper : .color)
        func change(_ name: String, _ update: @escaping (inout PageTextBox) -> Void) {
            changeTextBoxes(on: pageID, name: name) { boxes in
                guard let index = boxes.firstIndex(where: { $0.id == box.id }) else { return }
                update(&boxes[index])
            }
        }
        let fillName = tr("Change Box Background")
        let borderName = tr("Change Box Border")
        let borderWidth = box.borderWidth ?? 0
        return VStack(alignment: .leading, spacing: 9) {
            Divider()
            caption(tr("Box", key: "inspector.box_frame"))
            Text(tr("Background")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            Picker(tr("Background"), selection: Binding(
                get: { fillChoice },
                set: { choice in
                    change(fillName) { item in
                        switch choice {
                        case .none: item.hidesBackground = true
                        case .paper:
                            item.hidesBackground = nil
                            item.backgroundColor = nil
                        case .color:
                            item.hidesBackground = nil
                            item.backgroundColor = item.backgroundColor ?? style.accent
                        }
                    }
                }
            )) {
                Text(tr("None")).tag(BoxFillChoice.none)
                Text(tr("Paper")).tag(BoxFillChoice.paper)
                Text(tr("Color")).tag(BoxFillChoice.color)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if fillChoice == .color {
                ColorSwatches(colors: [style.paper, 0xFFFFFF, style.accent, style.overlayPaper, style.ink] + palette,
                              selected: box.backgroundColor ?? style.paper,
                              label: tr("Background Color")) { value in
                    change(fillName) { $0.backgroundColor = value }
                }
            }
            HStack {
                Text(tr("Border")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Stepper(value: Binding(
                    get: { borderWidth },
                    set: { value in
                        let width = min(PageTextBox.borderWidthRange.upperBound, max(0, (value * 2).rounded() / 2))
                        change(borderName) { $0.borderWidth = width == 0 ? nil : width }
                    }
                ), in: PageTextBox.borderWidthRange, step: 0.5) {
                    Text(borderWidth == 0 ? tr("None")
                         : borderWidth.formatted(.number.precision(.fractionLength(0...1))
                             .locale(Locale(identifier: language))) + " pt")
                        .font(.system(size: 11).monospacedDigit())
                }
                .accessibilityLabel(tr("Border Width"))
            }
            if borderWidth > 0 {
                ColorSwatches(colors: [style.ink, style.titleInk, style.accent, 0x000000, 0xFFFFFF] + palette,
                              selected: box.borderColor ?? style.ink,
                              label: tr("Border Color")) { value in
                    change(borderName) { $0.borderColor = value == style.ink ? nil : value }
                }
            }
        }
        .controlSize(.small)
    }

    func headingFormat(_ leaf: BookPage, palette: [UInt32]) -> some View {
        let style = book.editorialStyle
        return VStack(alignment: .leading, spacing: 10) {
            caption(tr("Heading"))
            TextField(tr("Page Heading", key: "inspector.page_heading"), text: Binding(
                get: { book.pages.first { $0.id == leaf.id }?.heading ?? "" },
                set: { value in
                    guard let index = book.pages.firstIndex(where: { $0.id == leaf.id }) else { return }
                    book.pages[index].heading = value.isEmpty ? nil : value
                }
            ))
            .textFieldStyle(.roundedBorder)
            .focused($headingFocused)
            .checksSpelling()
            EditorialTypographyControls(style: pageTextStyle(\.title, on: leaf.id),
                                       inherited: style.defaultTitleStyle(mixed: leaf.effectiveLayout == .mixed)
                                           .applying(book.typography?.title),
                                       language: language, sampleText: leaf.heading ?? "",
                                       defaultInk: leaf.arrangement == .textOverPhoto ? style.overlayTitleInk : style.titleInk,
                                       palette: palette)
                .id(leaf.id)
        }
    }

    func layerButtons(_ target: LayerTarget) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Divider()
            caption(tr("Arrange", key: "inspector.arrange"))
            HStack(spacing: 6) {
                Button(tr("Front", key: "layers.front")) { moveLayer(target, .front) }
                    .disabled(!canMoveLayer(target, .front))
                Button(tr("Back", key: "layers.back")) { moveLayer(target, .back) }
                    .disabled(!canMoveLayer(target, .back))
            }
            .controlSize(.small)
        }
    }


    func typeOverflow(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(Theme.destructive)
            .fixedSize(horizontal: false, vertical: true)
    }

    func pageTextStyle(_ key: WritableKeyPath<EditorialTypography, EditorialTextStyle?>,
                               on pageID: UUID) -> Binding<EditorialTextStyle?> {
        Binding(
            get: { book.pages.first { $0.id == pageID }?.typography?[keyPath: key] },
            set: { value in
                guard let index = book.pages.firstIndex(where: { $0.id == pageID }) else { return }
                var type = book.pages[index].typography ?? EditorialTypography()
                guard type[keyPath: key] != value else { return }
                type[keyPath: key] = value
                editPages(tr("Change Typography")) { pages in
                    pages[index].typography = type.title == nil && type.body == nil ? nil : type
                }
            }
        )
    }

    func boxTextStyle(_ id: UUID, on pageID: UUID) -> Binding<EditorialTextStyle?> {
        Binding(
            get: { book.pages.first { $0.id == pageID }?.textBoxes?.first { $0.id == id }?.typography },
            set: { value in
                changeTextBoxes(on: pageID, name: tr("Change Typography")) { boxes in
                    guard let index = boxes.firstIndex(where: { $0.id == id }) else { return }
                    boxes[index].typography = value
                }
            }
        )
    }

    struct PhotoTransferDestination: Identifiable {
        let id: UUID
        let label: String
        let photoIDs: [UUID]
    }

    func photoTransferDestinations(excluding source: UUID) -> [PhotoTransferDestination] {
        var number = 1
        return book.pages.compactMap { page in
            let start = number
            let isSpread = page.effectiveLayout == .fullSpread
            number += isSpread ? 2 : 1
            guard page.id != source else { return nil }
            let label = isSpread ? "\(start)–\(start + 1)" : String(start)
            return PhotoTransferDestination(id: page.id, label: label, photoIDs: page.photoIDs)
        }
    }

    @ViewBuilder func photoTransferMenu(_ photo: UUID, from source: UUID,
                                                destinations: [PhotoTransferDestination]) -> some View {
        let destinations = destinations.filter { !$0.photoIDs.contains(photo) }
        if !destinations.isEmpty {
            Menu(tr("Copy to page")) {
                ForEach(destinations) { destination in
                    Button(destination.label) {
                        transferPhoto(photo, from: source, to: destination.id, moving: false)
                    }
                }
            }
            Menu(tr("Move to page")) {
                ForEach(destinations) { destination in
                    Button(destination.label) {
                        transferPhoto(photo, from: source, to: destination.id, moving: true)
                    }
                }
            }
        }
    }

    var suggestions: some View {
        let page = page
        let query = PhotoSuggestionQuery(story: [page?.heading ?? "", page?.text ?? ""].joined(separator: "\n"),
                                         assigned: Set(page?.photoIDs ?? []), photos: book.photos)
        let matches = suggestedPhotos.filter { !query.assigned.contains($0.id) }
        return VStack(alignment: .leading, spacing: 8) {
            caption(tr("Suggested photos"))
            if matches.isEmpty {
                if book.photos.contains(where: { $0.analysis != nil }) {
                    intro(tr("Write about a place, animal, or subject to see matching photos."))
                } else {
                    Button(tr("Analyze photos"), action: onAnalyze)
                        .disabled(isAnalyzing || book.photos.isEmpty)
                }
            } else {
                ForEach(matches) { match in
                    if let photo = indexedPhoto(match.id) {
                        HStack(spacing: 8) {
                            preview(photo, small: true).frame(width: 42, height: 34).clipped()
                            VStack(alignment: .leading, spacing: 2) {
                                Text(photo.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                                Text(analysisEvidence(match.evidence))
                                    .font(.system(size: 10)).foregroundStyle(muted).lineLimit(1)
                            }
                            Spacer(minLength: 3)
                            Button {
                                assign(photo.id)
                            } label: {
                                Image(systemName: "plus.circle").foregroundStyle(pine)
                            }
                            .buttonStyle(.plain)
                            .help(tr("Add to the page"))
                            .accessibilityLabel(tr("Add to the page"))
                        }
                        .padding(4)
                        .background(.white.opacity(0.34), in: RoundedRectangle(cornerRadius: 5))
                    }
                }
            }
        }
        .task(id: query) {
            if !suggestedPhotos.isEmpty { suggestedPhotos = [] }
            let work = Task.detached(priority: .userInitiated) { query.findMatches() }
            let matches = await withTaskCancellationHandler {
                await work.value
            } onCancel: {
                work.cancel()
            }
            if !Task.isCancelled { suggestedPhotos = matches }
        }
    }

    func analysisEvidence(_ evidence: PhotoMatchEvidence) -> String {
        switch evidence.source {
        case "concept": conceptName(evidence.value)
        case "text": tr("Text in photo") + " · " + evidence.value
        default: conceptName(evidence.value)
        }
    }

    func photoAnalysisDetails(_ analysis: PhotoAnalysis) -> some View {
        DisclosureGroup(tr("Analysis details")) {
            VStack(alignment: .leading, spacing: 5) {
                let detections = analysis.detections ?? []
                ForEach(["person", "face", "animal"], id: \.self) { kind in
                    let count = detections.filter { $0.kind == kind }.count
                    if count > 0 {
                        let title = kind == "person" ? tr("People")
                            : kind == "face" ? tr("Faces") : tr("Animals")
                        intro("\(title) · \(count)")
                    }
                }
                if let lines = analysis.recognizedText?.prefix(3), !lines.isEmpty {
                    Label(lines.map(\.text).joined(separator: "\n"), systemImage: "text.viewfinder")
                        .font(.caption).foregroundStyle(muted).lineLimit(4)
                        .accessibilityLabel(tr("Text in photo") + ": " + lines.map(\.text).joined(separator: " "))
                }
                if let colors = analysis.visual?.dominantColors, !colors.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(colors, id: \.self) { color in
                            if let value = UInt32(color.replacingOccurrences(of: "#", with: ""), radix: 16) {
                                RoundedRectangle(cornerRadius: 3).fill(Color(cgColor: EditorialStyle.color(value)))
                                    .frame(width: 18, height: 12)
                                    .help(color).accessibilityLabel(color)
                            }
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(tr("Dominant colors"))
                }
            }
            .padding(.top, 4)
        }
        .controlSize(.small)
    }
}
