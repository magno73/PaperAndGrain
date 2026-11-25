import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension EditorView {
    var inspectorTabs: [InspectorTab] {
        var tabs = [InspectorTab(id: .page, title: coverSide == nil ? tr("Pagina", "Page") : tr("Copertina", "Cover"))]
        if selectedPhoto != nil {
            tabs.append(InspectorTab(id: .photo, title: tr("Foto", "Photo")))
            tabs.append(InspectorTab(id: .adjust, title: tr("Regola", "Adjust")))
        }
        tabs.append(InspectorTab(id: .film, title: tr("Pellicola", "Film")))
        return tabs
    }

    var sidePanel: some View {
        let tabs = inspectorTabs
        return InspectorHost(navigation: inspectorNavigation, title: tr("Ispettore", "Inspector"), tabs: tabs,
                             finishAdjustment: finishPhotoAdjustmentEdit, finishFilm: finishFilmEdit) { tab in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch tab {
                    case .page: pageInspector
                    case .photo: selectedPhotoInspector
                    case .adjust: photoAdjustmentsInspector
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
    }

    /// Keynote-style: selecting a photo brings its tab forward, deselecting returns to the page.
    func followSelectionInInspector(previous: UUID?, current: UUID?) {
        if current != nil, previous == nil, inspector == .page { inspector = .photo }
        if current == nil, inspector == .photo || inspector == .adjust { inspector = .page }
    }

    func showInspectorTab(_ tab: Inspector) {
        showsInspector = true
        if (tab == .photo || tab == .adjust) && selectedPhoto == nil { inspector = .page; return }
        inspector = tab
    }

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
                }
            }
            selectedPhotoDetails(photo)
        } else {
            intro(tr("Seleziona una foto nella pagina o nella fototeca.",
                     "Select a photo on the page or in the photo library."))
        }
    }

    @ViewBuilder var pageInspector: some View {
        if let coverSide {
            coverInspector(coverSide)
        } else if let page {
            let visiblePhotos = Set(pageComposition(page).photos.map(\.id))
            let waiting = page.photoIDs.count - visiblePhotos.count
            VStack(alignment: .leading, spacing: 7) {
                PageArrangementPicker(selection: page.arrangement ?? (page.layout == .fullSpread ? .fullSpread : nil),
                                      language: language,
                                      pageSize: book.format.pageSize) { arrangement in
                    applyPageArrangement(arrangement, to: page.id)
                }
                if page.arrangement == nil {
                    Picker(tr("Composizione", "Layout"), selection: Binding(
                        get: { self.page?.effectiveLayout ?? .gallery },
                        set: { setLayout($0) }
                    )) {
                        ForEach(layouts, id: \.self) { layout in
                            Text(layoutName(layout)).tag(layout)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if waiting > 0 {
                    intro(tr("\(waiting) foto in attesa di un riquadro.", "\(waiting) photos waiting for a slot."))
                }
            }
            textBoxInspector(page)
            let storyLayout = page.effectiveLayout == .text || page.effectiveLayout == .mixed
            let showsBody = storyLayout || page.storyFrame != nil
            if storyLayout || page.titleFrame != nil || page.storyFrame != nil {
                VStack(alignment: .leading, spacing: 8) {
                    caption(tr("Titolo e testo", "Heading and Text"))
                    pageTypography(page, showsBody: showsBody)
                    if page.effectiveLayout == .mixed && page.arrangement == nil {
                        Picker(tr("Posizione del testo", "Text Position"), selection: Binding(
                            get: { self.page?.textPlacement ?? .below },
                            set: { placement in
                                guard let index else { return }
                                book.pages[index].textPlacement = placement
                            }
                        )) {
                            Text(tr("Sotto", "Below")).tag(PageTextPlacement.below)
                            Text(tr("A fianco", "Beside")).tag(PageTextPlacement.beside)
                        }
                        .pickerStyle(.segmented)
                    }
                    TextField(tr("Titolo della pagina", "Page Heading"), text: Binding(
                        get: { self.page?.heading ?? "" },
                        set: { value in
                            guard let index else { return }
                            book.pages[index].heading = value.isEmpty ? nil : value
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    if showsBody {
                        TextEditor(text: text)
                            .font(.system(size: 14, design: .serif))
                            .scrollContentBackground(.hidden)
                            .focused($writing)
                            .padding(5)
                            .frame(minHeight: 140)
                            .background(paper, in: RoundedRectangle(cornerRadius: 6))
                            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(writing ? pine : edge) }
                            .accessibilityLabel(tr("Racconto", "Story"))
                    }
                    if storyLayout && (page.titleFrame != nil || page.storyFrame != nil) {
                        Button(tr("Ripristina posizione di titolo e testo", "Reset Heading and Text Placement")) {
                            guard let index = book.pages.firstIndex(where: { $0.id == page.id }) else { return }
                            endInlineTextEditing()
                            selectedEditorial = nil
                            editPages(tr("Ripristina posizione del testo", "Reset Text Placement")) {
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
                        caption(tr("Foto nella pagina", "Photos on page"))
                        Spacer()
                        Button { browsePhotos() } label: {
                            Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                        }
                        .help(tr("Apri le foto disponibili", "Browse available photos"))
                    }
                    let pagePhotos = photos(on: page)
                    let destinations = pagePhotos.isEmpty ? [] : photoTransferDestinations(excluding: page.id)
                    if pagePhotos.isEmpty {
                        intro(tr("Scegli una foto dalla fototeca o trascinala nella pagina.",
                                 "Choose a photo from the photo library or drag it onto the page."))
                    }
                    ForEach(pagePhotos) { photo in
                        HStack(spacing: 8) {
                            preview(photo, small: true).frame(width: 29, height: 24).clipped()
                            VStack(alignment: .leading, spacing: 2) {
                                Text(photo.name).font(.system(size: 11)).lineLimit(1)
                                if !visiblePhotos.contains(photo.id) {
                                    Text(tr("In attesa", "Waiting")).font(.system(size: 9)).foregroundStyle(muted)
                                }
                            }
                            Spacer(minLength: 2)
                            Menu {
                                Button(tr("Sposta prima", "Move earlier")) { reorderPhoto(photo.id, by: -1) }
                                    .disabled(page.photoIDs.first == photo.id)
                                Button(tr("Sposta dopo", "Move later")) { reorderPhoto(photo.id, by: 1) }
                                    .disabled(page.photoIDs.last == photo.id)
                                photoTransferMenu(photo.id, from: page.id, destinations: destinations)
                                if !visiblePhotos.contains(photo.id) {
                                    Button(tr("Rimuovi dalla pagina", "Remove from page"), role: .destructive) {
                                        remove(photo.id, from: page.id)
                                    }
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                            .menuIndicator(.hidden)
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                            .help(tr("Opzioni della foto", "Photo options"))
                        }
                    }
                }
            }
            if page.effectiveLayout != .fullPage && page.effectiveLayout != .fullSpread,
               page.photoPlacements?.values.contains(where: { $0.frame != nil }) == true {
                Button(tr("Ripristina posizione automatica delle foto", "Reset automatic photo placement")) {
                    resetPhotoFrames(page.id)
                }
            }
            Rectangle().fill(edge).frame(height: 1)
            Button(role: .destructive) { showDelete = true } label: {
                Label(tr("Elimina pagina…", "Delete page…"), systemImage: "trash")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.destructive)
        } else {
            intro(tr("Aggiungi una pagina per impaginare foto e racconti.",
                     "Add a page to arrange photos and stories."))
        }
    }

    func textBoxInspector(_ leaf: BookPage) -> some View {
        let boxes = leaf.textBoxes ?? []
        let active = boxes.first { $0.id == selectedBox }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                caption(tr("Box di testo", "Text Boxes"))
                Spacer()
                action("plus", tr("Aggiungi box di testo", "Add Text Box"), perform: insertTextBox)
            }
            if !boxes.isEmpty {
                Picker(tr("Box di testo", "Text Box"), selection: Binding(
                    get: { selectedBox },
                    set: { if let id = $0 { selectTextBox(id, in: leaf) } else { selectedBox = nil } }
                )) {
                    Text(tr("Seleziona un box", "Select a Box")).tag(UUID?.none)
                    ForEach(Array(boxes.enumerated()), id: \.element.id) { offset, box in
                        let firstLine = box.text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
                        Text(firstLine.isEmpty ? tr("Box", "Box") + " " + String(offset + 1) : String(firstLine.prefix(24)))
                            .tag(Optional(box.id))
                    }
                }
                .labelsHidden()
            }
            if let active {
                DisclosureGroup(tr("Tipografia del box", "Box Typography")) {
                    EditorialTypographyControls(style: boxTextStyle(active.id, on: leaf.id),
                                               inherited: book.editorialStyle.defaultBodyStyle.applying(book.typography?.body),
                                               language: language, sampleText: active.text)
                        .padding(.top, 6)
                        .id(active.id)
                    let frame = active.frame.rect(in: pageComposition(leaf).bounds)
                        .insetBy(dx: active.textInsetPoints, dy: active.textInsetPoints)
                    if !EditorialTypesetter.fits(PageComposition.boxText(box: active, book: book), in: frame) {
                        typeOverflow(tr("Ingrandisci il box o riduci la dimensione del testo.",
                                        "Enlarge the box or reduce the text size."))
                    }
                }
                Toggle(tr("Usa tutta la larghezza", "Use Full Width"), isOn: Binding(
                    get: {
                        book.pages.first { $0.id == leaf.id }?.textBoxes?.first { $0.id == active.id }?.usesFullWidth == true
                    },
                    set: { fullWidth in
                        changeTextBoxes(on: leaf.id, name: tr("Modifica margini del box", "Change Text Box Insets")) { boxes in
                            guard let index = boxes.firstIndex(where: { $0.id == active.id }) else { return }
                            boxes[index].usesFullWidth = fullWidth ? true : nil
                        }
                    }
                ))
                .toggleStyle(.checkbox)
                TextEditor(text: textInBox(active.id, on: leaf.id))
                    .font(.system(size: 14, design: .serif))
                    .scrollContentBackground(.hidden)
                    .focused($writingBox)
                    .padding(5)
                    .frame(minHeight: 102)
                    .background(paper, in: RoundedRectangle(cornerRadius: 6))
                    .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(writingBox ? pine : edge) }
                    .accessibilityLabel(tr("Testo del box", "Box Text"))
                Button(tr("Rimuovi box", "Remove Box"), role: .destructive) {
                    changeTextBoxes(on: leaf.id, name: tr("Rimuovi box", "Remove Box")) { $0.removeAll { $0.id == active.id } }
                    selectedBox = nil
                }
            }
        }
    }

    func pageTypography(_ leaf: BookPage, showsBody: Bool) -> some View {
        let style = book.editorialStyle
        let defaultTitle = style.defaultTitleStyle(mixed: leaf.effectiveLayout == .mixed)
        return DisclosureGroup(tr("Tipografia", "Typography")) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(tr("Titolo", "Heading")).font(.subheadline.weight(.semibold))
                    EditorialTypographyControls(style: pageTextStyle(\.title, on: leaf.id),
                                               inherited: defaultTitle.applying(book.typography?.title),
                                               language: language, sampleText: leaf.heading ?? "")
                        .id(leaf.id)
                }
                if showsBody {
                    Divider()
                    VStack(alignment: .leading, spacing: 5) {
                        Text(tr("Testo", "Body")).font(.subheadline.weight(.semibold))
                        EditorialTypographyControls(style: pageTextStyle(\.body, on: leaf.id),
                                                   inherited: style.defaultBodyStyle.applying(book.typography?.body),
                                                   language: language, sampleText: leaf.text)
                            .id(leaf.id)
                    }
                }
                let blocks = pageComposition(leaf).storyDrawingBlocks(page: leaf, book: book)
                if blocks.contains(where: { !EditorialTypesetter.fits($0.text, in: $0.frame) }) {
                    typeOverflow(tr("Alcune righe non entrano nel riquadro.",
                                    "Some lines exceed the text frame."))
                }
            }
            .padding(.vertical, 6)
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
                editPages(tr("Modifica tipografia", "Change Typography")) { pages in
                    pages[index].typography = type.title == nil && type.body == nil ? nil : type
                }
            }
        )
    }

    func boxTextStyle(_ id: UUID, on pageID: UUID) -> Binding<EditorialTextStyle?> {
        Binding(
            get: { book.pages.first { $0.id == pageID }?.textBoxes?.first { $0.id == id }?.typography },
            set: { value in
                changeTextBoxes(on: pageID, name: tr("Modifica tipografia", "Change Typography")) { boxes in
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
            Menu(tr("Copia nella pagina", "Copy to page")) {
                ForEach(destinations) { destination in
                    Button(destination.label) {
                        transferPhoto(photo, from: source, to: destination.id, moving: false)
                    }
                }
            }
            Menu(tr("Sposta nella pagina", "Move to page")) {
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
            caption(tr("Foto suggerite", "Suggested photos"))
            if matches.isEmpty {
                if book.photos.contains(where: { $0.analysis != nil }) {
                    intro(tr("Scrivi di un luogo, un animale o un soggetto per vedere le foto abbinate.",
                             "Write about a place, animal, or subject to see matching photos."))
                } else {
                    Button(tr("Analizza le foto", "Analyze photos"), action: onAnalyze)
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
                            .help(tr("Abbina alla pagina", "Add to the page"))
                            .accessibilityLabel(tr("Abbina alla pagina", "Add to the page"))
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
        case "text": tr("Testo nella foto", "Text in photo") + " · " + evidence.value
        default: conceptName(evidence.value)
        }
    }

    func selectedPhotoDetails(_ photo: BookPhoto) -> some View {
        let assigned = isOnCurrentPage(photo.id)
        return VStack(alignment: .leading, spacing: 6) {
            if let analysis = photo.analysis {
                let labels = (!analysis.labels.isEmpty ? analysis.labels : analysis.concepts).prefix(4)
                if !labels.isEmpty { intro(labels.map(conceptName).joined(separator: " · ")) }
                if analysis.revision >= PhotoAnalysis.currentRevision {
                    photoAnalysisDetails(analysis)
                }
            }
            if !assigned {
                Button(tr("Aggiungi alla pagina", "Add to page")) { togglePhoto(photo.id) }
                    .disabled(page == nil && coverSide == nil)
            }
            HStack(spacing: 7) {
                Button(tr("Regola foto", "Adjust Photo")) { inspector = .adjust }
                if enhancingPhotos[photo.id] != nil {
                    ProgressView().controlSize(.small)
                } else {
                    action("wand.and.stars", tr("Migliora in automatico", "Auto Enhance")) { autoEnhance(photo) }
                }
            }
            Button(tr("Look pellicola", "Film look")) {
                filmScope = .photo
                inspector = .film
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(pine.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }

    func photoAnalysisDetails(_ analysis: PhotoAnalysis) -> some View {
        DisclosureGroup(tr("Dettagli analisi", "Analysis details")) {
            VStack(alignment: .leading, spacing: 5) {
                let detections = analysis.detections ?? []
                ForEach(["person", "face", "animal"], id: \.self) { kind in
                    let count = detections.filter { $0.kind == kind }.count
                    if count > 0 {
                        let title = kind == "person" ? tr("Persone", "People")
                            : kind == "face" ? tr("Volti", "Faces") : tr("Animali", "Animals")
                        intro("\(title) · \(count)")
                    }
                }
                if let lines = analysis.recognizedText?.prefix(3), !lines.isEmpty {
                    Label(lines.map(\.text).joined(separator: "\n"), systemImage: "text.viewfinder")
                        .font(.caption).foregroundStyle(muted).lineLimit(4)
                        .accessibilityLabel(tr("Testo nella foto", "Text in photo") + ": " + lines.map(\.text).joined(separator: " "))
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
                    .accessibilityLabel(tr("Colori dominanti", "Dominant colors"))
                }
            }
            .padding(.top, 4)
        }
        .controlSize(.small)
    }
}
