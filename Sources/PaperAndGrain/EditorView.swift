import AppKit
import UniformTypeIdentifiers
import SwiftUI

struct EditorView: View {
    @Binding var book: Book
    let directory: URL
    let language: String
    let analysisStatus: String
    let isAnalyzing: Bool
    let onAnalyze: () -> Void
    let onExport: () -> Void

    @Environment(\.undoManager) private var undoManager
    @FocusState private var writing: Bool
    @FocusState private var writingBox: Bool
    @FocusState private var inlineBoxFocus: UUID?
    @State private var selection: UUID?
    @State private var selectedPhoto: UUID?
    @State private var canvasPhotoSelection: CanvasPhotoSelection?
    @State private var photoIndices: [UUID: Int] = [:]
    @State private var selectedBox: UUID?
    @State private var inlineEditingBox: UUID?
    @State private var coverSide: CoverSide?
    @State private var zoom: CanvasZoom = .fitPage
    @State private var dropFrames = [EditorDropTarget: CGRect]()
    @GestureState private var dragging: EditorDragPreview?
    @State private var showSpread = true
    @State private var gutterGuide = false
    @State private var showDelete = false
    @State private var inspector: Inspector = .page
    @State private var photoPanelMode: PhotoPanelMode = .library
    @State private var filmScope: FilmScope = .book
    @State private var compareOriginal = false
    @State private var comparePhotoOriginal: UUID?
    @State private var enhancingPhotos: [UUID: UUID] = [:]
    @State private var adjustmentErrors: [UUID: String] = [:]
    @State private var adjustmentEdit: AdjustmentEdit?
    @State private var adjustmentPreviewTask: Task<Void, Never>?
    @State private var lutImportError: String?
    @State private var concept: String?
    @State private var search = ""
    @State private var undoTarget = EditorUndo()
    @State private var cropSession: CropSession?

    private enum Inspector: String, CaseIterable {
        case page, photos, film
    }

    private enum PhotoPanelMode: Hashable {
        case library, adjust
    }

    private struct CanvasPhotoSelection {
        let pageID: UUID
        let photoID: UUID
    }

    private struct AdjustmentEdit {
        let photoID: UUID
        var draft: PhotoAdjustments
        var preview: PhotoAdjustments
    }

    private struct NavigatorSpread: Identifiable {
        let id: UUID
        let pages: [BookPage]
        let blankLeft: Bool

        var paired: Bool { blankLeft || pages.count == 2 }
    }

    private enum FilmScope: Hashable {
        case book, photo
    }

    private enum CoverSide: Hashable {
        case front, back
    }

    private enum AlignmentElement: Equatable {
        case photo(UUID), textBox(UUID)
    }

    private struct CropSession {
        let pageID: UUID
        let photoID: UUID
        let initialFrame: PageRect
        let initialCrop: PhotoCrop
        var frame: PageRect
        var crop: PhotoCrop
    }

    private enum CanvasZoom: Hashable {
        case fitPage, fitWidth, percent(Int)

        static let all: [Self] = [.fitPage, .fitWidth, .percent(25), .percent(50), .percent(75),
                                  .percent(100), .percent(150), .percent(200)]

        func scale(viewport: CGSize, artboard: CGSize) -> CGFloat {
            let width = max(1, viewport.width - 40) / artboard.width
            let height = max(1, viewport.height - 48) / artboard.height
            switch self {
            case .fitPage: return min(width, height)
            case .fitWidth: return width
            case let .percent(value): return CGFloat(value) / 100
            }
        }
    }

    private let ink = Color(red: 0.14, green: 0.17, blue: 0.14)
    private let pine = Color(red: 0.14, green: 0.31, blue: 0.23)
    private let muted = Color(red: 0.33, green: 0.37, blue: 0.33)
    private let paper = Color(red: 0.98, green: 0.97, blue: 0.93)
    private let panel = Color(red: 0.95, green: 0.95, blue: 0.91)
    private let edge = Color(red: 0.82, green: 0.83, blue: 0.78)

    private var page: BookPage? {
        guard coverSide == nil else { return nil }
        return book.pages.first { $0.id == selection } ?? book.pages.first
    }

    private var index: Int? {
        guard let page else { return nil }
        return book.pages.firstIndex { $0.id == page.id }
    }

    private var text: Binding<String> {
        Binding(
            get: { page?.text ?? "" },
            set: { value in
                guard let index else { return }
                book.pages[index].text = value
            }
        )
    }

    private var groups: [[BookPage]] {
        var spreads: [[BookPage]] = []
        var partner: BookPage?
        for (index, page) in book.pages.enumerated() {
            if page.layout == .fullSpread {
                if let previous = partner { spreads.append([previous]) }
                partner = nil
                spreads.append([page])
            } else if index == 0 && book.printSettings?.firstPageOnRight == true {
                spreads.append([page])
            } else if let previous = partner {
                spreads.append([previous, page])
                partner = nil
            } else {
                partner = page
            }
        }
        if let partner { spreads.append([partner]) }
        return spreads
    }

    private var navigatorSpreads: [NavigatorSpread] {
        groups.compactMap { row in
            guard let first = row.first else { return nil }
            let blankLeft = row.count == 1 && first.layout != .fullSpread
                && first.id == book.pages.first?.id && book.printSettings?.firstPageOnRight == true
            return NavigatorSpread(id: first.id, pages: row, blankLeft: blankLeft)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            masthead
            Rectangle().fill(edge).frame(height: 1)
            HStack(spacing: 0) {
                navigator.frame(width: 158)
                Rectangle().fill(edge).frame(width: 1)
                canvas.frame(maxWidth: .infinity, maxHeight: .infinity)
                Rectangle().fill(edge).frame(width: 1)
                sidePanel.frame(width: 260)
            }
        }
        .background(panel)
        .background(alignment: .topLeading) {
            CanvasDeleteShortcut(onDelete: deleteSelectedCanvasPhoto)
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .foregroundStyle(ink)
        .tint(pine)
        .coordinateSpace(name: EditorDropTarget.coordinateSpace)
        .onPreferenceChange(EditorDropFrames.self) { dropFrames = $0 }
        .onChange(of: book.photos.map(\.id), initial: true) { _, ids in
            photoIndices = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($0.element, $0.offset) })
        }
        .onChange(of: inlineBoxFocus) { previous, current in
            if previous != nil && current == nil && inlineEditingBox == previous { inlineEditingBox = nil }
        }
        .onChange(of: selectedPhoto) { _, id in
            if canvasPhotoSelection?.photoID != id { canvasPhotoSelection = nil }
            if comparePhotoOriginal != id { comparePhotoOriginal = nil }
            if let adjustmentEdit, adjustmentEdit.photoID != id { finishPhotoAdjustmentEdit() }
        }
        .onChange(of: inspector) { _, mode in
            if mode != .photos { finishPhotoAdjustmentEdit() }
        }
        .onChange(of: photoPanelMode) { _, mode in
            if mode != .adjust { finishPhotoAdjustmentEdit() }
        }
        .onDisappear { adjustPreviewCleanup() }
        .overlay(alignment: .topLeading) {
            dragPreview.allowsHitTesting(false).accessibilityHidden(true)
        }
        .preferredColorScheme(.light)
        .alert(tr("Eliminare la pagina?", "Delete the page?"), isPresented: $showDelete) {
            Button(tr("Annulla", "Cancel"), role: .cancel) {}
            Button(tr("Elimina", "Delete"), role: .destructive, action: deletePage)
        } message: {
            Text(tr("Le foto della pagina resteranno disponibili nel libro.",
                    "The page’s photos will remain available in the book."))
        }
    }

    private var masthead: some View {
        HStack(spacing: 14) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(pine)
                .frame(width: 35, height: 35)
                .background(pine.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title).font(.system(size: 19, weight: .medium, design: .serif)).lineLimit(1)
                Text(dimensions).font(.system(size: 11, design: .monospaced)).foregroundStyle(muted)
            }
            Spacer()
            HStack(spacing: 4) {
                action("arrow.uturn.backward", tr("Annulla", "Undo")) {
                    if cropSession != nil {
                        cropSession = nil
                        return
                    }
                    if writing || writingBox || inlineBoxFocus != nil,
                       NSApp.sendAction(Selector(("undo:")), to: nil, from: nil) { return }
                    undoManager?.undo()
                }
                action("arrow.uturn.forward", tr("Ripristina", "Redo")) {
                    if writing || writingBox || inlineBoxFocus != nil,
                       NSApp.sendAction(Selector(("redo:")), to: nil, from: nil) { return }
                    undoManager?.redo()
                }
                .disabled(cropSession != nil)
            }
            Divider().frame(height: 23)
            Menu {
                Button(tr("Box di testo", "Text Box"), systemImage: "character.textbox", action: insertTextBox)
                    .disabled(page == nil)
                Button(tr("Frontespizio", "Title Page"), systemImage: "text.alignleft", action: insertTitlePage)
                Divider()
                ForEach(layouts, id: \.self) { layout in
                    Button(layoutName(layout), systemImage: layoutIcon(layout)) { insert(layout) }
                }
            } label: {
                Label(tr("Inserisci", "Insert"), systemImage: "plus")
            }
            .fixedSize()
            Button(action: onExport) {
                Label(tr("Esporta PDF", "Export PDF"), systemImage: "square.and.arrow.up")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(cropSession != nil)
        }
        .padding(.horizontal, 17)
        .frame(height: 63)
    }

    private var navigator: some View {
        let insertion = previewPageInsertion
        return VStack(spacing: 0) {
            HStack {
                caption(tr("Pagine", "Pages"))
                Spacer()
                Text(String(physicalPageCount))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(muted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(spacing: 7) {
                        coverItem(.front).id(CoverSide.front)
                        ForEach(navigatorSpreads) { spread in
                            HStack(spacing: 3) {
                                if spread.blankLeft {
                                    navigatorBlankPage
                                }
                                ForEach(spread.pages) { leaf in
                                    navigatorItem(leaf, paired: spread.paired,
                                                  insertionAfter: insertion?.id == leaf.id ? insertion?.after : nil)
                                        .id(leaf.id)
                                }
                            }
                        }
                        coverItem(.back).id(CoverSide.back)
                    }
                    .padding(.horizontal, 9).padding(.bottom, 8)
                }
                .editorDropFrame(.navigatorViewport)
                .task(id: navigatorScrollDirection) {
                    await scrollWhileDragging(scroll)
                }
                .onChange(of: selection) { _, selected in
                    if let selected { withAnimation(.easeOut(duration: 0.2)) { scroll.scrollTo(selected, anchor: .center) } }
                }
                .onChange(of: coverSide) { _, side in
                    if let side { withAnimation(.easeOut(duration: 0.2)) { scroll.scrollTo(side, anchor: .center) } }
                }
            }
            Rectangle().fill(edge).frame(height: 1)
            HStack(spacing: 10) {
                action("plus", tr("Aggiungi pagina", "Add page")) { insert(.gallery) }
                action("chevron.up", tr("Sposta prima", "Move earlier")) { move(-1) }
                    .disabled(index.map { $0 < 1 } ?? true)
                action("chevron.down", tr("Sposta dopo", "Move later")) { move(1) }
                    .disabled(index.map { $0 >= book.pages.count - 1 } ?? true)
            }
            .padding(.vertical, 8)
        }
        .background(Color(red: 0.93, green: 0.93, blue: 0.89))
    }

    private func navigatorItem(_ leaf: BookPage, paired: Bool, insertionAfter: Bool?) -> some View {
        let active = leaf.id == page?.id
        let first = leaf.id == book.pages.first?.id
        let ratio = aspect * (leaf.layout == .fullSpread ? 2 : 1)
        let width = min(paired ? 63 : 115, 47 * ratio)
        let number = spreadNumber([leaf])
        let label = first && !paired ? tr("Prima pagina", "First Page") : number
        return navigatorCard(label, active: active) {
            select(leaf)
        } preview: {
            mini(leaf).frame(width: width, height: width / ratio)
        }
        .accessibilityLabel(first ? tr("Prima pagina", "First Page") : tr("Pagina", "Page") + " " + number)
        .help(tr("Trascina per riordinare la pagina", "Drag to reorder the page"))
        .editorDropFrame(.navigatorPage(leaf.id))
        .simultaneousGesture(editorDrag(.page(leaf.id)))
        .overlay(alignment: navigatorInsertionAlignment(paired: paired, after: insertionAfter == true)) {
            if insertionAfter != nil {
                Capsule().fill(pine).frame(width: paired ? 3 : nil, height: paired ? nil : 3)
                    .padding(paired ? .vertical : .horizontal, 4)
                    .allowsHitTesting(false)
            }
        }
    }

    private func navigatorInsertionAlignment(paired: Bool, after: Bool) -> Alignment {
        if paired { return after ? .trailing : .leading }
        return after ? .bottom : .top
    }

    private var navigatorBlankPage: some View {
        let width = min(63, 47 * aspect)
        return Color(cgColor: EditorialStyle.color(book.editorialStyle.paper))
            .frame(width: width, height: width / aspect)
            .overlay { Rectangle().strokeBorder(.black.opacity(0.09)) }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 16)
            .accessibilityHidden(true)
    }

    private func coverItem(_ side: CoverSide) -> some View {
        let width = min(88, 47 * aspect)
        return navigatorCard(coverName(side), active: coverSide == side) {
            selectCover(side)
        } preview: {
            coverCanvas(side, scale: width / book.format.pageSize.width, thumbnail: true)
                .shadow(color: .black.opacity(0.11), radius: 2, y: 1)
        }
    }

    private func navigatorCard<Thumbnail: View>(_ label: String, active: Bool,
                                                  action: @escaping () -> Void,
                                                  @ViewBuilder preview: () -> Thumbnail) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                preview().frame(height: 48)
                Text(label)
                    .font(.system(size: 10, weight: active ? .semibold : .regular))
                    .foregroundStyle(active ? pine : muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 74)
            .contentShape(Rectangle())
            .background(active ? pine.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(active ? pine.opacity(0.65) : .clear)
                    .allowsHitTesting(false)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func mini(_ leaf: BookPage) -> some View {
        let composition = pageComposition(leaf)
        let style = book.editorialStyle
        return GeometryReader { geometry in
            let scale = max(0.001, min(geometry.size.width / composition.bounds.width,
                                       geometry.size.height / composition.bounds.height))
            let bounds = scaled(composition.bounds, by: scale)
            ZStack(alignment: .topLeading) {
                Color(cgColor: EditorialStyle.color(style.paper))
                if let rule = composition.rule {
                    positioned(Color(cgColor: EditorialStyle.color(style.accent)), in: scaled(rule, by: scale))
                }
                ForEach(composition.photos) { item in
                    positioned(preview(item.photo, small: true, crop: item.crop, fills: item.fills),
                               in: scaled(item.frame, by: scale))
                }
                if let story = composition.story, !leaf.text.isEmpty || leaf.heading?.isEmpty == false {
                    let text = style.typography(leaf.text, heading: leaf.heading, mixed: leaf.layout == .mixed)
                    positioned(editorialText(text, scale: scale), in: scaled(story, by: scale))
                }
                ForEach(composition.textBoxes.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { box in
                    let frame = box.frame.rect(in: composition.bounds)
                    positioned(Color(cgColor: EditorialStyle.color(style.paper)), in: scaled(frame, by: scale))
                    let text = style.typography(box.text, heading: nil, mixed: true)
                    let inset = PageTextBox.textInset
                    positioned(editorialText(text, scale: scale), in: scaled(frame.insetBy(dx: inset, dy: inset), by: scale))
                }
                if let folio = composition.folio {
                    let number = style.typography(String(number(of: leaf)), heading: nil, mixed: true)
                    positioned(editorialText(number, scale: scale), in: scaled(folio, by: scale))
                }
            }
            .frame(width: bounds.width, height: bounds.height)
            .clipped()
            .overlay { Rectangle().strokeBorder(.black.opacity(0.14)) }
            .shadow(color: .black.opacity(0.11), radius: 2, y: 1)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .accessibilityHidden(true)
    }

    private var canvas: some View {
        VStack(spacing: 0) {
            HStack {
                if let coverSide {
                    caption(coverName(coverSide))
                } else if let page {
                    caption(page.id == book.pages.first?.id
                            ? tr("Prima pagina", "First Page")
                            : tr("Pagina", "Page") + " " + spreadNumber([page]))
                }
                Spacer()
                if compareOriginal {
                    Button(tr("Torna alle regolazioni", "Return to Edits")) { compareOriginal = false }
                        .controlSize(.small)
                } else if comparePhotoOriginal != nil {
                    Button(tr("Torna alle regolazioni", "Return to Edits")) { comparePhotoOriginal = nil }
                        .controlSize(.small)
                }
                Picker(tr("Zoom della pagina", "Page Zoom"), selection: $zoom) {
                    ForEach(CanvasZoom.all, id: \.self) { level in
                        Text(zoomName(level)).tag(level)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .help(tr("Zoom della pagina", "Page Zoom"))
                Picker(tr("Vista", "View"), selection: $showSpread) {
                    Image(systemName: "rectangle.portrait").tag(false)
                        .accessibilityLabel(tr("Pagina singola", "Single Page"))
                    Image(systemName: "book").tag(true)
                        .accessibilityLabel(tr("Doppia pagina", "Two-Page View"))
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 82)
                .disabled(coverSide != nil)
            }
            .padding(.horizontal, 22)
            .padding(.top, 16)
            GeometryReader { geometry in
                if let coverSide {
                    let scale = zoom.scale(viewport: geometry.size, artboard: book.format.pageSize)
                    canvasViewport(geometry.size) { coverCanvas(coverSide, scale: scale) }
                } else if let page {
                    canvasViewport(geometry.size) { canvasSpread(page, viewport: geometry.size) }
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: "book").font(.system(size: 33, weight: .ultraLight)).foregroundStyle(pine)
                        Text(tr("Il libro comincia qui", "Your book starts here"))
                            .font(.system(size: 28, design: .serif))
                        Button(tr("Aggiungi una pagina", "Add a page")) { insert(.gallery) }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            if let page {
                VStack(spacing: 10) {
                    if let cropSession {
                        cropToolbar(cropSession)
                    } else {
                        layoutChoices(page)
                        if page.layout == .fullSpread || (showSpread && groups.contains { $0.count == 2 && $0.contains { $0.id == page.id } }) {
                            Toggle(tr("Guida della piega", "Gutter Guide"), isOn: $gutterGuide)
                                .toggleStyle(.checkbox)
                                .font(.system(size: 11))
                                .foregroundStyle(muted)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 21)
            }
        }
        .background {
            LinearGradient(colors: [
                Color(red: 0.90, green: 0.91, blue: 0.86),
                Color(red: 0.83, green: 0.85, blue: 0.79)
            ], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private func zoomName(_ level: CanvasZoom) -> String {
        switch level {
        case .fitPage: tr("Riempi pagina", "Fit Page")
        case .fitWidth: tr("Adatta alla larghezza", "Fit Width")
        case let .percent(value): "\(value)%"
        }
    }

    private func canvasViewport<Artboard: View>(_ viewport: CGSize, @ViewBuilder content: () -> Artboard) -> some View {
        ScrollView([.horizontal, .vertical]) {
            content()
                .shadow(color: .black.opacity(0.16), radius: 12, x: 0, y: 7)
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(minWidth: viewport.width, minHeight: viewport.height)
        }
        .defaultScrollAnchor(.center)
        .editorDropFrame(.canvasViewport)
    }

    private func canvasSpread(_ page: BookPage, viewport: CGSize) -> some View {
        let spread = showSpread ? groups.first { $0.contains { $0.id == page.id } } ?? [page] : [page]
        let wide = page.layout == .fullSpread
        let blankLeft = showSpread && !wide && spread.count == 1 && page.id == book.pages.first?.id
            && book.printSettings?.firstPageOnRight == true
        let count = wide || blankLeft ? 2 : spread.count
        let size = book.format.pageSize
        let artboard = CGSize(width: size.width * CGFloat(count), height: size.height)
        let scale = zoom.scale(viewport: viewport, artboard: artboard)
        return HStack(spacing: 0) {
            if blankLeft {
                Color(cgColor: EditorialStyle.color(book.editorialStyle.paper))
                    .frame(width: size.width * scale, height: size.height * scale)
                    .accessibilityHidden(true)
            }
            ForEach(spread) { leaf in
                canvasPage(leaf, scale: scale)
            }
        }
        .overlay {
            ZStack {
                if count == 2 {
                    LinearGradient(colors: [.clear, .black.opacity(0.18), .white.opacity(0.24), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: 12)
                    if gutterGuide {
                        Rectangle()
                            .fill(.white.opacity(0.23))
                            .overlay {
                                Rectangle().strokeBorder(pine.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            }
                            .frame(width: size.width * scale * 0.075)
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func layoutChoices(_ page: BookPage) -> some View {
        HStack(spacing: 2) {
            ForEach(layouts, id: \.self) { layout in
                Button {
                    setLayout(layout)
                } label: {
                    Image(systemName: layoutIcon(layout))
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 29, height: 28)
                        .foregroundStyle(page.layout == layout ? pine : muted)
                        .background(page.layout == layout ? paper : .clear, in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help(layoutName(layout))
                .accessibilityLabel(layoutName(layout))
                .accessibilityAddTraits(page.layout == layout ? .isSelected : [])
            }
            Divider().frame(height: 17).padding(.horizontal, 3)
            Text(layoutName(page.layout))
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .padding(.trailing, 8)
            if let selectedPhoto,
               pageComposition(page).photos.contains(where: { $0.id == selectedPhoto }) {
                Divider().frame(height: 17).padding(.horizontal, 2)
                action("crop", tr("Ritaglia foto", "Crop Photo")) { beginCrop(selectedPhoto, in: page) }
            }
        }
        .padding(3)
        .background(pine.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    private func cropToolbar(_ session: CropSession) -> some View {
        HStack(spacing: 8) {
            Label(tr("Ritaglia", "Crop"), systemImage: "crop")
                .font(.system(size: 11, weight: .semibold))
            Divider().frame(height: 17)
            action("minus", tr("Riduci immagine", "Zoom Out Photo")) { magnifyCrop(1 / 1.15) }
                .disabled(session.crop.zoom <= 1)
            Text(session.crop.zoom.formatted(.percent.precision(.fractionLength(0))))
                .font(.system(size: 11).monospacedDigit())
                .frame(minWidth: 43)
            action("plus", tr("Ingrandisci immagine", "Zoom In Photo")) { magnifyCrop(1.15) }
                .disabled(session.crop.zoom >= 12)
            Divider().frame(height: 17)
            Button(tr("Annulla", "Cancel")) { cropSession = nil }
                .keyboardShortcut(.cancelAction)
            Button(tr("Fine", "Done")) { finishCrop() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .controlSize(.small)
        .padding(5)
        .background(paper, in: RoundedRectangle(cornerRadius: 8))
    }

    private func canvasPage(_ leaf: BookPage, scale: CGFloat) -> some View {
        let composition = pageComposition(leaf)
        let bounds = scaled(composition.bounds, by: scale)
        let style = book.editorialStyle
        let incomingPhoto = incomingPhotoPlacement(on: leaf, composition: composition, bounds: bounds)
        return ZStack(alignment: .topLeading) {
            Color(cgColor: EditorialStyle.color(style.paper)).onTapGesture {
                finishCrop()
                endInlineBoxEditing()
                select(leaf)
                canvasPhotoSelection = nil
                selectedPhoto = nil
                selectedBox = nil
                filmScope = .book
            }
            if composition.photos.isEmpty && leaf.layout != .text {
                let margin = leaf.layout == .gallery || leaf.layout == .mixed ? book.contentInsetPoints * scale : 0
                placeholder
                    .frame(width: max(1, bounds.width - 2 * margin),
                           height: max(1, bounds.height - 2 * margin) * (leaf.layout == .mixed ? 0.53 : 1))
                    .padding(margin)
                    .allowsHitTesting(false)
            }
            if let rule = composition.rule {
                positioned(Color(cgColor: EditorialStyle.color(style.accent)), in: scaled(rule, by: scale))
                    .allowsHitTesting(false)
            }
            ForEach(composition.photos) { item in
                if cropSession?.pageID != leaf.id || cropSession?.photoID != item.id {
                    let targets = alignmentTargets(in: composition, at: scale, excluding: .photo(item.id))
                    canvasPhoto(item, leaf: leaf, bounds: bounds, scale: scale, alignmentTargets: targets)
                }
            }
            if let story = composition.story {
                positioned(prose(leaf, scale: scale), in: scaled(story, by: scale))
            }
            ForEach(composition.textBoxes) { box in
                let targets = alignmentTargets(in: composition, at: scale, excluding: .textBox(box.id))
                canvasTextBox(box, leaf: leaf, bounds: bounds, scale: scale, alignmentTargets: targets)
            }
            if let folio = composition.folio {
                let label = style.typography(String(number(of: leaf)), heading: nil, mixed: true)
                positioned(editorialText(label, scale: scale), in: scaled(folio, by: scale))
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            if let session = cropSession, session.pageID == leaf.id,
               let item = composition.photos.first(where: { $0.id == session.photoID }) {
                let targets = alignmentTargets(in: composition, at: scale, excluding: .photo(item.id))
                canvasCrop(session, item: item, bounds: bounds, scale: scale, alignmentTargets: targets)
            }
        }
        .frame(width: bounds.width, height: bounds.height)
        .clipped()
        .contentShape(Rectangle())
        .overlay {
            if leaf.id == page?.id {
                Rectangle().strokeBorder(pine.opacity(0.56), lineWidth: 1.4).allowsHitTesting(false)
            }
        }
        .overlayPreferenceValue(CanvasGuidePreference.self) { guides in
            ZStack(alignment: .topLeading) {
                if let incomingPhoto {
                    let border = Rectangle().strokeBorder(pine, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                    positioned(border, in: incomingPhoto.frame)
                }
                let visibleGuides = guides + (incomingPhoto?.guides ?? [])
                if !visibleGuides.isEmpty {
                    CanvasAlignmentGuides(guides: visibleGuides)
                }
            }
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .editorDropFrame(.canvasPage(leaf.id))
    }

    private func alignmentTargets(in composition: PageComposition, at scale: CGFloat,
                                  excluding element: AlignmentElement) -> [CGRect] {
        let photos = composition.photos.compactMap { item in
            element == .photo(item.id) ? nil : scaled(item.frame, by: scale)
        }
        let textBoxes = composition.textBoxes.compactMap { box in
            element == .textBox(box.id) ? nil : scaled(box.frame.rect(in: composition.bounds), by: scale)
        }
        return photos + textBoxes
    }

    private var placeholder: some View {
        Rectangle().fill(pine.opacity(0.06))
            .overlay {
                Image(systemName: "photo")
                    .font(.system(size: 25, weight: .ultraLight))
                    .foregroundStyle(pine.opacity(0.65))
                    .accessibilityLabel(tr("Nessuna foto", "No photo"))
            }
    }

    private func canvasPhoto(_ item: PageComposition.Photo, leaf: BookPage, bounds: CGRect, scale: CGFloat,
                             alignmentTargets: [CGRect]) -> some View {
        let frame = scaled(item.frame, by: scale)
        let active = leaf.id == page?.id && item.id == selectedPhoto && selectedBox == nil
        return CanvasObjectControl(frame: frame, bounds: bounds, selected: active,
                                   minimumSize: CGSize(width: 40 * scale, height: 40 * scale),
                                   accessibilityName: item.photo.name, alignmentTargets: alignmentTargets,
                                   allowsPhotoOverflow: true, preservesAspectRatio: true,
                                   onDoubleClick: { beginCrop(item.id, in: leaf) },
                                   onSelect: { selectCanvasPhoto(item.id, in: leaf) },
                                   onChange: { updatePhotoFrame(item.id, in: leaf, to: PageRect($0, in: bounds)) }) { _ in
            preview(item.photo, crop: item.crop, fills: item.fills)
        }
        .accessibilityAction(named: Text(tr("Ritaglia foto", "Crop Photo"))) { beginCrop(item.id, in: leaf) }
        .accessibilityAction(named: Text(tr("Rimuovi dalla pagina", "Remove from Page"))) {
            deleteCanvasPhoto(item.id, from: leaf.id)
        }
    }

    private func canvasCrop(_ session: CropSession, item: PageComposition.Photo, bounds: CGRect, scale: CGFloat,
                            alignmentTargets: [CGRect]) -> some View {
        let frame = session.frame.photoRect(in: bounds)
        let size = CGSize(width: item.photo.pixelWidth, height: item.photo.pixelHeight)
        return CanvasCropControl(frame: frame, bounds: bounds, sourceSize: size, crop: session.crop,
                                 minimumSize: CGSize(width: 40 * scale, height: 40 * scale),
                                 alignmentTargets: alignmentTargets,
                                 onChange: { nextFrame, nextCrop in
            guard cropSession?.photoID == session.photoID, cropSession?.pageID == session.pageID else { return }
            if nextFrame != frame { cropSession?.frame = PageRect(nextFrame, in: bounds).photoClamped }
            cropSession?.crop = nextCrop
        }, image: {
            preview(item.photo, fills: false)
        })
    }

    private func prose(_ leaf: BookPage, scale: CGFloat) -> some View {
        let heading = leaf.heading ?? ""
        let empty = leaf.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && heading.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let style = book.editorialStyle
        let label = tr("Scrivi qui il tuo racconto…", "Write your story here…")
        return Button {
            finishCrop()
            endInlineBoxEditing()
            select(leaf)
            selectedPhoto = nil
            selectedBox = nil
            inspector = .page
            Task { @MainActor in
                await Task.yield()
                if NSApp.isActive && page?.id == leaf.id && inspector == .page { writing = true }
            }
        } label: {
            if empty {
                Text(label)
                    .font(.custom(style.bodyFont, size: max(10, style.bodySize * scale)))
                    .foregroundStyle(Color(cgColor: EditorialStyle.color(style.accent)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .contentShape(Rectangle())
            } else {
                editorialText(style.typography(leaf.text, heading: heading, mixed: leaf.layout == .mixed), scale: scale)
                    .contentShape(Rectangle())
            }
        }
        .accessibilityLabel(empty ? label : [heading, leaf.text].filter { !$0.isEmpty }.joined(separator: ", "))
        .buttonStyle(.plain)
    }

    @ViewBuilder private func canvasTextBox(_ box: PageTextBox, leaf: BookPage, bounds: CGRect, scale: CGFloat,
                                            alignmentTargets: [CGRect]) -> some View {
        let active = selectedBox == box.id && leaf.id == page?.id
        let style = book.editorialStyle
        let empty = box.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let label = tr("Box di testo", "Text Box")
        let frame = box.frame.rect(in: bounds)
        if inlineEditingBox == box.id && leaf.id == page?.id {
            positioned(inlineBoxEditor(box, leaf: leaf, scale: scale), in: frame)
                .zIndex(1)
        } else {
            CanvasObjectControl(frame: frame, bounds: bounds, selected: active,
                                   minimumSize: CGSize(width: 88 * scale, height: 40 * scale),
                                   accessibilityName: empty ? label : box.text,
                                   alignmentTargets: alignmentTargets,
                                   onDoubleClick: { beginInlineBoxEditing(box.id, in: leaf) },
                                   onSelect: { selectTextBox(box.id, in: leaf) },
                                   onChange: { updateTextBoxFrame(box.id, on: leaf.id, to: PageRect($0, in: bounds)) }) { _ in
                Group {
                    if empty {
                        Text(label)
                            .font(.custom(style.bodyFont, size: max(9, style.bodySize * scale)))
                            .foregroundStyle(Color(cgColor: EditorialStyle.color(style.accent)))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    } else {
                        editorialText(style.typography(box.text, heading: nil, mixed: true), scale: scale)
                    }
                }
                .padding(PageTextBox.textInset * scale)
                .background(Color(cgColor: EditorialStyle.color(style.paper)).opacity(empty ? 0.82 : 1))
                .overlay {
                    if empty && !active {
                        Rectangle().strokeBorder(pine.opacity(0.48), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
            }
            .accessibilityAction(named: Text(tr("Modifica il testo", "Edit Text"))) {
                beginInlineBoxEditing(box.id, in: leaf)
            }
        }
    }

    private func inlineBoxEditor(_ box: PageTextBox, leaf: BookPage, scale: CGFloat) -> some View {
        let style = book.editorialStyle
        return TextEditor(text: textInBox(box.id, on: leaf.id))
            .font(.custom(style.bodyFont, size: max(1, style.bodySize * scale)))
            .foregroundStyle(Color(cgColor: EditorialStyle.color(style.ink)))
            .scrollContentBackground(.hidden)
            .focused($inlineBoxFocus, equals: box.id)
            .padding(max(0, PageTextBox.textInset * scale - 4))
            .background(Color(cgColor: EditorialStyle.color(style.paper)))
            .overlay { Rectangle().strokeBorder(pine, lineWidth: 1.5).allowsHitTesting(false) }
            .onExitCommand(perform: endInlineBoxEditing)
            .accessibilityLabel(tr("Testo del box in pagina", "Text Box on Page"))
            .task(id: box.id) {
                await Task.yield()
                if NSApp.isActive && inlineEditingBox == box.id { inlineBoxFocus = box.id }
            }
    }

    @ViewBuilder private func coverCanvas(_ side: CoverSide, scale: CGFloat, thumbnail: Bool = false) -> some View {
        let page = BookCoverGeometry(book: book, front: side == .front)
        let bounds = scaled(page.bounds, by: scale)
        let photo = coverPhotoID(side).flatMap(indexedPhoto)
        let content = ZStack(alignment: .topLeading) {
            Color(cgColor: EditorialStyle.color(page.background))
            if let photo {
                positioned(preview(photo, small: thumbnail, fills: page.fills), in: scaled(page.photoFrame, by: scale))
            } else if !thumbnail {
                positioned(placeholder, in: scaled(page.photoFrame, by: scale))
            } else if side == .back {
                Image(systemName: "book.closed")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(cgColor: EditorialStyle.color(book.editorialStyle.accent)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let band = page.band {
                positioned(Color(white: 0.97, opacity: 0.94), in: scaled(band, by: scale))
            }
            if let rule = page.rule {
                positioned(Color(cgColor: EditorialStyle.color(book.editorialStyle.accent)), in: scaled(rule, by: scale))
            }
            if let title = page.titleFrame {
                positioned(editorialText(page.title, scale: scale), in: scaled(title, by: scale))
            }
        }
        .frame(width: bounds.width, height: bounds.height)
        .clipped()
        if thumbnail {
            content.accessibilityHidden(true)
        } else {
            let label = coverName(side)
            content
                .contentShape(Rectangle())
                .onTapGesture { inspector = .page }
                .accessibilityLabel(label)
                .editorDropFrame(.cover(front: side == .front))
                .overlay {
                    if isPhotoDropTarget(.cover(front: side == .front)) {
                        Rectangle().strokeBorder(pine, lineWidth: 2).allowsHitTesting(false)
                    }
                }
        }
    }

    private func editorialText(_ contents: NSAttributedString, scale: CGFloat) -> some View {
        Canvas { graphics, size in
            graphics.withCGContext { context in
                context.scaleBy(x: scale, y: scale)
                let bounds = CGRect(x: 0, y: 0, width: size.width / scale, height: size.height / scale)
                EditorialTypesetter.draw(contents, in: bounds, context: context)
            }
        }
        .clipped()
    }

    private func positioned<Content: View>(_ content: Content, in rect: CGRect) -> some View {
        content.frame(width: max(0, rect.width), height: max(0, rect.height))
            .position(x: rect.midX, y: rect.midY)
    }

    private func scaled(_ rect: CGRect, by scale: CGFloat) -> CGRect {
        rect.applying(CGAffineTransform(scaleX: scale, y: scale))
    }

    private var sidePanel: some View {
        VStack(spacing: 0) {
            Picker(tr("Ispettore", "Inspector"), selection: $inspector) {
                Text(tr("Pagina", "Page")).tag(Inspector.page)
                Text(tr("Foto", "Photos")).tag(Inspector.photos)
                Text(tr("Pellicola", "Film")).tag(Inspector.film)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(14)
            Rectangle().fill(edge).frame(height: 1)
            if inspector == .photos {
                photoInspector
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 21) {
                        if inspector == .page { pageInspector }
                        else { filmInspector }
                    }
                    .padding(15)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .background(panel)
        .disabled(cropSession != nil)
    }

    @ViewBuilder private var pageInspector: some View {
        if let coverSide {
            coverInspector(coverSide)
        } else if let page {
            VStack(alignment: .leading, spacing: 7) {
                caption(tr("Composizione", "Layout"))
                Picker(tr("Composizione", "Layout"), selection: Binding(
                    get: { self.page?.layout ?? .gallery },
                    set: { setLayout($0) }
                )) {
                    ForEach(layouts, id: \.self) { layout in
                        Text(layoutName(layout)).tag(layout)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            textBoxInspector(page)
            if page.layout == .text || page.layout == .mixed {
                VStack(alignment: .leading, spacing: 8) {
                    caption(tr("Racconto", "Story"))
                    if page.layout == .mixed {
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
                suggestions
            }
            if page.layout != .text {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        caption(tr("Foto nella pagina", "Photos on page"))
                        Spacer()
                        Button { inspector = .photos } label: {
                            Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                        }
                        .help(tr("Apri le foto disponibili", "Browse available photos"))
                    }
                    if photos(on: page).isEmpty {
                        intro(tr("Scegli una foto dalla libreria o trascinala nella pagina.",
                                 "Choose a photo from the library or drag it onto the page."))
                    }
                    ForEach(photos(on: page)) { photo in
                        HStack(spacing: 8) {
                            preview(photo, small: true).frame(width: 29, height: 24).clipped()
                            Text(photo.name).font(.system(size: 11)).lineLimit(1)
                            Spacer(minLength: 2)
                            Menu {
                                Button(tr("Sposta prima", "Move earlier")) { reorderPhoto(photo.id, by: -1) }
                                    .disabled(page.photoIDs.first == photo.id)
                                Button(tr("Sposta dopo", "Move later")) { reorderPhoto(photo.id, by: 1) }
                                    .disabled(page.photoIDs.last == photo.id)
                                photoTransferMenu(photo, from: page)
                                Button(tr("Rimuovi dalla pagina", "Remove from page"), role: .destructive) { remove(photo.id) }
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
            if page.layout != .fullPage && page.layout != .fullSpread,
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
            .foregroundStyle(Color(red: 0.61, green: 0.27, blue: 0.16))
        } else {
            intro(tr("Aggiungi una pagina per impaginare foto e racconti.",
                     "Add a page to arrange photos and stories."))
        }
    }

    private func textBoxInspector(_ leaf: BookPage) -> some View {
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

    private func coverInspector(_ side: CoverSide) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            caption(coverName(side))
            if side == .front {
                TextField(tr("Titolo in copertina", "Cover Title"), text: Binding(
                    get: { book.cover?.title ?? book.title },
                    set: { value in changeCover { $0.title = value } }
                ))
                .textFieldStyle(.roundedBorder)
            } else {
                TextEditor(text: Binding(
                    get: { book.cover?.backText ?? "" },
                    set: { value in changeCover { $0.backText = value.isEmpty ? nil : value } }
                ))
                .font(.system(size: 14, design: .serif))
                .scrollContentBackground(.hidden)
                .focused($writing)
                .padding(5)
                .frame(minHeight: 100)
                .background(paper, in: RoundedRectangle(cornerRadius: 6))
                .accessibilityLabel(tr("Testo del retro", "Back Cover Text"))
            }
            if let photo = coverPhotoID(side).flatMap(indexedPhoto) {
                HStack(spacing: 8) {
                    preview(photo, small: true).frame(width: 38, height: 30).clipped()
                    Text(photo.name).font(.callout).lineLimit(1)
                }
                Button(tr("Rimuovi foto", "Remove Photo"), role: .destructive) { setCoverPhoto(nil, side: side) }
            }
            Button(tr("Scegli foto", "Choose Photo"), systemImage: "photo.on.rectangle") { inspector = .photos }
            if book.cover == nil {
                Button(tr("Aggiungi copertina al libro", "Add Cover to Book")) { changeCover { _ in } }
            }
        }
    }

    @ViewBuilder private func photoTransferMenu(_ photo: BookPhoto, from source: BookPage) -> some View {
        let destinations = book.pages.filter { $0.id != source.id && !$0.photoIDs.contains(photo.id) }
        if !destinations.isEmpty {
            Menu(tr("Copia nella pagina", "Copy to page")) {
                ForEach(destinations) { destination in
                    Button(spreadNumber([destination])) {
                        transferPhoto(photo.id, from: source.id, to: destination.id, moving: false)
                    }
                }
            }
            Menu(tr("Sposta nella pagina", "Move to page")) {
                ForEach(destinations) { destination in
                    Button(spreadNumber([destination])) {
                        transferPhoto(photo.id, from: source.id, to: destination.id, moving: true)
                    }
                }
            }
        }
    }

    private var suggestions: some View {
        let matches = book.photos.compactMap { photo -> (BookPhoto, Double)? in
            guard let analysis = photo.analysis, page?.photoIDs.contains(photo.id) != true else { return nil }
            let score = PhotoAnalyzer.score(analysis, for: text.wrappedValue)
            return score > 0 ? (photo, score) : nil
        }.sorted { $0.1 > $1.1 }.prefix(4).map(\.0)
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
                ForEach(matches) { photo in
                    HStack(spacing: 8) {
                        preview(photo, small: true).frame(width: 42, height: 34).clipped()
                        VStack(alignment: .leading, spacing: 2) {
                            Text(photo.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                            if let labels = photo.analysis?.concepts.prefix(2), !labels.isEmpty {
                                Text(labels.map(conceptName).joined(separator: " · "))
                                    .font(.system(size: 10)).foregroundStyle(muted).lineLimit(1)
                            }
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

    private var photoInspector: some View {
        VStack(spacing: 0) {
            Picker(tr("Pannello foto", "Photo Panel"), selection: $photoPanelMode) {
                Text(tr("Libreria", "Library")).tag(PhotoPanelMode.library)
                Text(tr("Regola", "Adjust")).tag(PhotoPanelMode.adjust)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .padding(.horizontal, 15)
            .padding(.top, 11)
            if photoPanelMode == .adjust {
                ScrollView {
                    photoAdjustmentsInspector
                        .padding(15)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                photoLibrary
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder private var photoAdjustmentsInspector: some View {
        if let selectedPhoto, let photo = indexedPhoto(selectedPhoto) {
            VStack(alignment: .leading, spacing: 10) {
                caption(tr("Regolazioni foto", "Photo Adjustments"))
                Text(photo.name).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                intro(tr("Le regolazioni seguono la foto in tutto il libro.",
                         "Adjustments follow this photo throughout the book."))
                if let message = adjustmentErrors[photo.id] {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                }
                PhotoAdjustmentsPanel(adjustments: Binding(
                    get: { currentPhotoAdjustmentDraft(for: photo.id) },
                    set: { value in updatePhotoAdjustmentDraft(value, for: photo.id) }
                ), language: language, isEnhancing: enhancingPhotos[photo.id] != nil,
                comparingOriginal: Binding(
                    get: { comparePhotoOriginal == photo.id },
                    set: { comparePhotoOriginal = $0 ? photo.id : nil }
                ), onAutomatic: {
                    autoEnhance(photo)
                }, onReset: {
                    discardPhotoAdjustmentDraft()
                    setPhotoAdjustments(PhotoAdjustments(), for: photo.id)
                }, onEditingChanged: { started in
                    if started {
                        finishPhotoAdjustmentEdit()
                        let values = currentPhotoAdjustmentDraft(for: photo.id)
                        adjustmentEdit = AdjustmentEdit(photoID: photo.id, draft: values, preview: values)
                    } else {
                        finishPhotoAdjustmentEdit()
                    }
                })
                .id(photo.id)
            }
        } else {
            intro(tr("Seleziona una foto nella pagina o nella libreria.",
                     "Select a photo on the page or in the library."))
        }
    }

    private var photoLibrary: some View {
        VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    caption(tr("Foto disponibili", "Available photos"))
                    Spacer()
                    Text(String(book.photos.count))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(muted)
                }
                if !analysisStatus.isEmpty { intro(analysisStatus) }
                HStack(spacing: 6) {
                    if isAnalyzing { ProgressView().controlSize(.small) }
                    Button(action: onAnalyze) {
                        Label(tr("Analizza foto", "Analyze photos"), systemImage: "viewfinder")
                    }
                    .disabled(isAnalyzing || book.photos.isEmpty)
                }
                if !book.photos.isEmpty {
                    TextField(tr("Cerca foto", "Search photos"), text: $search)
                        .textFieldStyle(.roundedBorder)
                    conceptFilter
                }
            }
            .padding(.horizontal, 15)
            .padding(.top, 15)
            if !book.photos.isEmpty {
                ScrollView {
                    photoGrid.padding(.horizontal, 15).padding(.bottom, 8)
                }
                .frame(maxHeight: .infinity)
                if let selectedPhoto, let photo = indexedPhoto(selectedPhoto) {
                    ViewThatFits(in: .vertical) {
                        selectedPhotoDetails(photo)
                        ScrollView { selectedPhotoDetails(photo) }
                    }
                    .frame(maxHeight: 230)
                    .padding(.horizontal, 15)
                    .padding(.bottom, 15)
                }
            } else {
                intro(tr("Il libro non contiene ancora foto.", "This book doesn’t have any photos yet.")).padding(.horizontal, 15)
                Spacer(minLength: 0)
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var conceptFilter: some View {
        let counts = book.photos.reduce(into: [String: Int]()) { result, photo in
            for item in Set(photo.analysis?.concepts ?? []) { result[item, default: 0] += 1 }
        }
        let concepts = counts.keys.sorted {
            let left = counts[$0, default: 0]
            let right = counts[$1, default: 0]
            return left == right ? conceptName($0) < conceptName($1) : left > right
        }
        return Picker(tr("Concetto", "Concept"), selection: $concept) {
            Text(tr("Tutti i concetti", "All concepts")).tag(nil as String?)
            ForEach(concepts, id: \.self) { item in
                Text(conceptName(item) + " · " + String(counts[item, default: 0])).tag(Optional(item))
            }
        }
        .labelsHidden()
        .disabled(concepts.isEmpty)
    }

    private func selectedPhotoDetails(_ photo: BookPhoto) -> some View {
        let assigned = isOnCurrentPage(photo.id)
        return VStack(alignment: .leading, spacing: 6) {
            Text(photo.name).font(.system(size: 12, weight: .semibold)).lineLimit(2)
            if let concepts = photo.analysis?.concepts, !concepts.isEmpty {
                intro(concepts.map(conceptName).joined(separator: " · "))
            }
            Button(assigned ? tr("Rimuovi dalla pagina", "Remove from page") : tr("Aggiungi alla pagina", "Add to page")) {
                togglePhoto(photo.id)
            }
            .disabled(page == nil && coverSide == nil)
            HStack(spacing: 7) {
                Button(tr("Regola foto", "Adjust Photo")) { photoPanelMode = .adjust }
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

    private var photoGrid: some View {
        let filtered = filteredLibraryPhotos
        let assigned = Set(coverSide.map { [coverPhotoID($0)].compactMap { $0 } } ?? page?.photoIDs ?? [])
        return VStack(alignment: .leading, spacing: 7) {
            if filtered.isEmpty { intro(tr("Nessuna foto corrispondente.", "No matching photos.")) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 67), spacing: 7)], spacing: 7) {
                ForEach(filtered) { photo in
                    let active = photo.id == selectedPhoto
                    let used = assigned.contains(photo.id)
                    preview(photo, small: true)
                        .frame(height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(alignment: .bottomTrailing) {
                            if used {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white, pine)
                                    .padding(3)
                            }
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 4).strokeBorder(active ? pine : .clear, lineWidth: 2)
                        }
                        .contentShape(Rectangle())
                        .gesture(editorDrag(.photo(photo.id)).exclusively(before: TapGesture().onEnded {
                            selectLibraryPhoto(photo.id)
                        }))
                        .simultaneousGesture(TapGesture(count: 2).onEnded {
                            selectLibraryPhoto(photo.id)
                            togglePhoto(photo.id)
                        })
                        .help(photo.name)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(photo.name)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAddTraits(used ? .isSelected : [])
                        .accessibilityAction { selectLibraryPhoto(photo.id) }
                        .accessibilityAction(named: Text(used ? tr("Rimuovi dalla pagina", "Remove from page")
                                                             : tr("Aggiungi alla pagina", "Add to page"))) {
                            togglePhoto(photo.id)
                        }
                        .contextMenu {
                            Button(used ? tr("Rimuovi dalla pagina", "Remove from page")
                                        : tr("Aggiungi alla pagina", "Add to page")) { togglePhoto(photo.id) }
                            .disabled(page == nil && coverSide == nil)
                        }
                }
            }
        }
    }

    private var filteredLibraryPhotos: [BookPhoto] {
        guard concept != nil || !search.isEmpty else { return book.photos }
        return book.photos.filter { photo in
            let concepts = photo.analysis?.concepts ?? []
            if let concept, !concepts.contains(concept) { return false }
            return search.isEmpty || photo.name.localizedStandardContains(search)
                || concepts.contains { conceptName($0).localizedStandardContains(search) }
                || photo.analysis?.labels.contains { $0.localizedStandardContains(search) } == true
        }
    }

    private func selectLibraryPhoto(_ id: UUID) {
        canvasPhotoSelection = nil
        selectedPhoto = id
        selectedBox = nil
    }

    private var filmPhoto: BookPhoto? {
        selectedPhoto.flatMap(indexedPhoto)
    }

    private var currentFilm: FilmSettings {
        if filmScope == .photo, let photo = filmPhoto { return book.effectiveFilm(for: photo) }
        return book.film ?? FilmSettings()
    }

    private var filmInspector: some View {
        VStack(alignment: .leading, spacing: 15) {
            VStack(alignment: .leading, spacing: 8) {
                caption(tr("Look pellicola", "Film look"))
                Picker(tr("Applica a", "Apply to"), selection: $filmScope) {
                    Text(tr("Libro", "Book")).tag(FilmScope.book)
                    Text(tr("Foto selezionata", "Selected photo"))
                        .tag(FilmScope.photo)
                        .disabled(filmPhoto == nil)
                }
                .pickerStyle(.menu)
                .onChange(of: selectedPhoto) { _, id in
                    if id == nil { filmScope = .book }
                }
                if filmScope == .photo, let photo = filmPhoto {
                    Text(photo.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(2)
                    Toggle(tr("Usa il look del libro", "Use book look"), isOn: Binding(
                        get: { filmPhoto?.film == nil },
                        set: { inherit in
                            if inherit {
                                setPhotoFilm(nil, for: photo.id)
                            } else {
                                setPhotoFilm(book.effectiveFilm(for: photo), for: photo.id)
                            }
                        }
                    ))
                }
            }
            VStack(alignment: .leading, spacing: 9) {
                filmSwatches
                if let resources = Bundle.main.resourceURL, let sample = FujifilmFilmLook.all.first,
                   (try? sample.url(in: resources).checkResourceIsReachable()) == true {
                    fujifilmLookMenu(resources: resources)
                }
                Button {
                    importFilmLUT()
                } label: {
                    Label(tr("Importa LUT", "Import LUT"), systemImage: "square.and.arrow.down")
                }
                if let lutImportError {
                    Text(lutImportError).font(.callout).foregroundStyle(.secondary)
                    Button(tr("Chiudi avviso", "Dismiss Message")) { self.lutImportError = nil }
                        .buttonStyle(.link)
                }
                if currentFilm.preset == .custom, let filename = currentFilm.lutFilename {
                    let builtIn = FujifilmFilmLook.importedLook(filename: filename)
                    Text(builtIn?.name ?? filmLUTName(filename))
                        .font(.system(size: 10))
                        .foregroundStyle(muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let builtIn {
                        intro(fujifilmInputDescription(builtIn.input))
                    }
                }
            }
            .disabled(filmScope == .photo && filmPhoto?.film == nil)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                filmSlider(tr("Intensità", "Intensity"), value: \.strength)
                    .disabled(currentFilm.preset == .original)
                filmSlider(tr("Grana", "Grain"), value: \.grain)
                filmSlider(tr("Dimensione grana", "Grain size"), value: \.grainSize)
                    .disabled(currentFilm.grain == 0)
            }
            .disabled(filmScope == .photo && filmPhoto?.film == nil)
            Divider()
            Toggle(tr("Confronta con l’originale", "Compare with original"), isOn: $compareOriginal)
                .disabled(book.photos.isEmpty)
        }
    }

    private func fujifilmLookMenu(resources: URL) -> some View {
        let selected = currentFilm.preset == .custom
            ? currentFilm.lutFilename.flatMap(FujifilmFilmLook.importedLook) : nil
        return Menu {
            Section(tr("Da Provia", "From Provia")) {
                fujifilmLooks(.provia, selected: selected, resources: resources)
            }
            Section(tr("Base a contrasto lineare", "Linear-Contrast Input")) {
                fujifilmLooks(.linear, selected: selected, resources: resources)
            }
            Divider()
            Link(tr("Fonte e licenza", "Source and License"),
                 destination: URL(string: "https://github.com/abpy/FujifilmCameraProfiles#licensing")!)
        } label: {
            Label(tr("LUT Fujifilm", "Fujifilm LUTs"), systemImage: "camera.filters")
        }
    }

    private func fujifilmLooks(_ input: FujifilmFilmLook.Input, selected: FujifilmFilmLook?,
                               resources: URL) -> some View {
        ForEach(FujifilmFilmLook.all.filter { $0.input == input }) { look in
            Button {
                applyBuiltInLUT(look, resources: resources)
            } label: {
                if look == selected { Label(look.name, systemImage: "checkmark") }
                else { Text(look.name) }
            }
        }
    }

    private func fujifilmInputDescription(_ input: FujifilmFilmLook.Input) -> String {
        switch input {
        case .linear:
            tr("Per immagini sviluppate con contrasto lineare.", "For images developed with linear contrast.")
        case .provia:
            tr("Per immagini già sviluppate con Provia.", "For images already developed with Provia.")
        }
    }

    private func applyBuiltInLUT(_ look: FujifilmFilmLook, resources: URL) {
        do {
            let filename = try BookStorage.importBuiltInLUT(look, resources: resources, in: directory)
            setFilm {
                $0.preset = .custom
                $0.lutFilename = filename
            }
            lutImportError = nil
        } catch {
            lutImportError = tr("Impossibile aggiungere questa LUT al progetto.",
                                "Couldn’t add this LUT to the project.")
        }
    }

    private var filmSwatches: some View {
        let reference = filmPhoto ?? page.flatMap { photos(on: $0).first } ?? book.photos.first
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(FilmPreset.allCases, id: \.self) { preset in
                let active = preset == currentFilm.preset
                let swatch = FilmSettings(preset: preset, lutFilename: preset == .custom ? currentFilm.lutFilename : nil)
                Button {
                    setFilm { $0.preset = preset }
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        ZStack {
                            if let reference, preset != .custom || swatch.lutFilename != nil {
                                preview(reference, small: true, settings: swatch)
                            } else {
                                Rectangle().fill(pine.opacity(0.08))
                                Image(systemName: preset == .custom ? "square.and.arrow.down" : "photo")
                                    .foregroundStyle(pine)
                                    .accessibilityHidden(true)
                            }
                        }
                        .frame(height: 45)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        Text(filmName(preset))
                            .font(.system(size: 10, weight: active ? .semibold : .regular))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(5)
                    .background(active ? pine.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 7))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7).strokeBorder(active ? pine : edge)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(preset == .custom && swatch.lutFilename == nil)
                .accessibilityLabel(filmName(preset))
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
    }

    private func filmName(_ preset: FilmPreset) -> String {
        switch preset {
        case .original: tr("Originale", "Original")
        case .documentary: tr("Documentario", "Documentary")
        case .warmNegative: tr("Negativo caldo", "Warm Negative")
        case .monochrome: tr("Monocromatico", "Monochrome")
        case .custom: tr("LUT personalizzata", "Custom LUT")
        }
    }

    private func filmSlider(_ label: String, value: WritableKeyPath<FilmSettings, Double>) -> some View {
        let amount = currentFilm[keyPath: value]
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.system(size: 11))
                Spacer()
                Text(amount.formatted(.percent.precision(.fractionLength(0))))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(muted)
            }
            .accessibilityHidden(true)
            Slider(value: Binding(
                get: { currentFilm[keyPath: value] },
                set: { amount in setFilm { $0[keyPath: value] = amount } }
            ), in: 0...1, step: 0.02)
                .accessibilityLabel(label)
        }
    }

    private func setFilm(_ edit: (inout FilmSettings) -> Void) {
        var settings = currentFilm
        edit(&settings)
        guard settings != currentFilm else { return }
        if filmScope == .photo, let photo = filmPhoto, photo.film != nil {
            setPhotoFilm(settings, for: photo.id)
        } else if filmScope == .book {
            book.film = settings
        }
    }

    private func setPhotoFilm(_ settings: FilmSettings?, for id: UUID) {
        guard let index = photoIndex(id) else { return }
        book.photos[index].film = settings
    }

    private func setPhotoAdjustments(_ value: PhotoAdjustments, for id: UUID,
                                     actionName: String? = nil) {
        guard let index = photoIndex(id) else { return }
        enhancingPhotos.removeValue(forKey: id)
        adjustmentErrors.removeValue(forKey: id)
        if comparePhotoOriginal == id { comparePhotoOriginal = nil }
        let normalized = value == PhotoAdjustments() ? nil : value
        let previous = book.photos[index].adjustments
        guard previous != normalized else { return }
        book.photos[index].adjustments = normalized
        if let undoManager {
            let name = actionName ?? tr("Regola foto", "Adjust Photo")
            undoTarget.registerPhotoAdjustments(undoManager, binding: $book, bookID: book.id,
                                                photoID: id, previous: previous, name: name)
        }
    }

    private func currentPhotoAdjustmentDraft(for id: UUID) -> PhotoAdjustments {
        if let adjustmentEdit, adjustmentEdit.photoID == id { return adjustmentEdit.draft }
        return indexedPhoto(id)?.adjustments ?? PhotoAdjustments()
    }

    private func updatePhotoAdjustmentDraft(_ value: PhotoAdjustments, for id: UUID) {
        guard let adjustmentEdit, adjustmentEdit.photoID == id else {
            setPhotoAdjustments(value, for: id)
            return
        }
        guard adjustmentEdit.draft != value else { return }
        enhancingPhotos.removeValue(forKey: id)
        adjustmentErrors.removeValue(forKey: id)
        if comparePhotoOriginal == id { comparePhotoOriginal = nil }
        self.adjustmentEdit?.draft = value
        guard adjustmentPreviewTask == nil else { return }
        adjustmentPreviewTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(55)) } catch { return }
            adjustmentPreviewTask = nil
            guard let edit = self.adjustmentEdit, edit.photoID == id, edit.preview != edit.draft else { return }
            self.adjustmentEdit?.preview = edit.draft
        }
    }

    private func finishPhotoAdjustmentEdit() {
        guard let edit = adjustmentEdit else { return }
        discardPhotoAdjustmentDraft()
        setPhotoAdjustments(edit.draft, for: edit.photoID)
    }

    private func discardPhotoAdjustmentDraft() {
        adjustPreviewCleanup()
        adjustmentEdit = nil
    }

    private func adjustPreviewCleanup() {
        adjustmentPreviewTask?.cancel()
        adjustmentPreviewTask = nil
    }

    private func autoEnhance(_ photo: BookPhoto) {
        finishPhotoAdjustmentEdit()
        guard enhancingPhotos[photo.id] == nil else { return }
        let operation = UUID()
        let bookID = book.id
        let photoID = photo.id
        let url = BookStorage.assetURL(filename: photo.filename, in: directory)
        enhancingPhotos[photoID] = operation
        adjustmentErrors.removeValue(forKey: photoID)
        Task { @MainActor in
            let suggested = await Task.detached(priority: .userInitiated) {
                PhotoAdjustments.automatic(from: url)
            }.value
            guard book.id == bookID, enhancingPhotos[photoID] == operation,
                  let current = indexedPhoto(photoID) else { return }
            enhancingPhotos.removeValue(forKey: photoID)
            guard let suggested else {
                adjustmentErrors[photoID] = tr("Impossibile analizzare questa foto.", "Couldn’t analyze this photo.")
                return
            }
            let adjustments = (current.adjustments ?? PhotoAdjustments()).applyingAutomatic(suggested)
            setPhotoAdjustments(adjustments, for: photoID,
                                actionName: tr("Migliora in automatico", "Auto Enhance"))
        }
    }

    private func importFilmLUT() {
        let panel = NSOpenPanel()
        panel.title = tr("Importa LUT", "Import LUT")
        panel.message = tr("Scegli un file .cube 3D o un PNG Hald CLUT.",
                           "Choose a 3D .cube file or a Hald CLUT PNG.")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "cube"), .png].compactMap { $0 }
        let bookID = book.id
        let targetScope = filmScope
        let targetPhoto = filmPhoto?.id
        EditorFilePanels.present(panel) { response in
            guard response == .OK, let url = panel.url, book.id == bookID,
                  filmScope == targetScope, targetScope == .book || filmPhoto?.id == targetPhoto else { return }
            do {
                let filename = try BookStorage.importLUT(url, in: directory)
                setFilm {
                    $0.preset = .custom
                    $0.lutFilename = filename
                }
            } catch {
                lutImportError = tr("Verifica che il file sia una LUT .cube 3D o un PNG Hald CLUT valido.",
                                    "Check that the file is a valid 3D .cube LUT or Hald CLUT PNG.")
            }
        }
    }

    private func filmLUTName(_ filename: String) -> String {
        filename.replacingOccurrences(of: "-[0-9a-f]{16}(?=\\.)", with: "", options: .regularExpression)
    }

    private func preview(_ photo: BookPhoto, small: Bool = false, crop: PhotoCrop = PhotoCrop(),
                         fills: Bool = true, settings: FilmSettings? = nil) -> some View {
        let url = BookStorage.assetURL(filename: photo.filename, in: directory)
        let original = settings == nil && (compareOriginal || comparePhotoOriginal == photo.id)
        let look = settings ?? (original ? FilmSettings() : book.effectiveFilm(for: photo))
        let lutURL = look.lutFilename.map { BookStorage.lutURL(filename: $0, in: directory) }
        let draft = adjustmentEdit?.photoID == photo.id && !small && settings == nil && !original
            ? adjustmentEdit?.preview : nil
        let isLive = draft.map { $0 != (photo.adjustments ?? PhotoAdjustments()) } ?? false
        let limit = small ? 180 : (isLive ? 640 : 1440)
        let corrections = isLive ? draft : photo.adjustments
        let request = EditorPreviewRequest(url: url, limit: limit, look: look, lutURL: lutURL,
                                           adjustments: original ? nil : corrections)
        return EditorPreview(request: request, crop: crop, fills: fills) {
            placeholder
        }
    }

    private var dimensions: String {
        let style = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...2))
            .locale(Locale(identifier: language))
        return "\((book.format.widthMM / 10).formatted(style)) × \((book.format.heightMM / 10).formatted(style)) cm"
    }

    private var aspect: CGFloat {
        CGFloat(max(0.1, min(10, book.format.widthMM / max(1, book.format.heightMM))))
    }

    private var physicalPageCount: Int {
        book.pages.reduce(0) { $0 + ($1.layout == .fullSpread ? 2 : 1) }
    }

    private func number(of leaf: BookPage) -> Int {
        book.pages.prefix { $0.id != leaf.id }.reduce(1) { $0 + ($1.layout == .fullSpread ? 2 : 1) }
    }

    private func spreadNumber(_ spread: [BookPage]) -> String {
        guard let first = spread.first, let last = spread.last else { return "" }
        let start = number(of: first)
        let end = number(of: last) + (last.layout == .fullSpread ? 1 : 0)
        return start == end ? String(start) : "\(start)–\(end)"
    }

    private var layouts: [PageLayout] { [.gallery, .text, .mixed, .fullPage, .fullSpread] }

    private func layoutName(_ layout: PageLayout) -> String {
        switch layout {
        case .gallery: tr("Galleria", "Gallery")
        case .text: tr("Pagina di testo", "Text Page")
        case .mixed: tr("Foto e testo", "Photo and Text")
        case .fullPage: tr("Tutta pagina", "Full Page")
        case .fullSpread: tr("Due pagine", "Full Spread")
        }
    }

    private func layoutIcon(_ layout: PageLayout) -> String {
        switch layout {
        case .gallery: "square.grid.2x2"
        case .text: "text.alignleft"
        case .mixed: "rectangle.split.1x2"
        case .fullPage: "photo"
        case .fullSpread: "rectangle.split.2x1"
        }
    }

    private func caption(_ value: String) -> some View {
        Text(value.uppercased(with: Locale(identifier: language)))
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(1.1)
            .foregroundStyle(pine)
    }

    private func intro(_ value: String) -> some View {
        Text(value).font(.system(size: 11)).foregroundStyle(muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func action(_ symbol: String, _ label: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    private func tr(_ italian: String, _ english: String) -> String {
        language.hasPrefix("it") ? italian : english
    }

    private func conceptName(_ value: String) -> String {
        PhotoAnalyzer.displayName(for: value, language: language)
    }

    private func photos(on page: BookPage) -> [BookPhoto] {
        page.photoIDs.compactMap(indexedPhoto)
    }

    private func photoIndex(_ id: UUID) -> Int? {
        if let index = photoIndices[id], book.photos.indices.contains(index), book.photos[index].id == id {
            return index
        }
        return book.photos.firstIndex { $0.id == id }
    }

    private func indexedPhoto(_ id: UUID) -> BookPhoto? {
        photoIndex(id).map { book.photos[$0] }
    }

    private func pageComposition(_ page: BookPage) -> PageComposition {
        PageComposition(page: page, book: book, photoForID: indexedPhoto)
    }

    private func coverName(_ side: CoverSide) -> String {
        side == .front ? tr("Copertina", "Front Cover") : tr("Retro copertina", "Back Cover")
    }

    private func coverPhotoID(_ side: CoverSide) -> UUID? {
        side == .front ? book.cover?.frontPhotoID : book.cover?.backPhotoID
    }

    private func selectCover(_ side: CoverSide) {
        guard coverSide != side else { return }
        finishCrop()
        endInlineBoxEditing()
        coverSide = side
        canvasPhotoSelection = nil
        selectedPhoto = nil
        selectedBox = nil
        writing = false
        writingBox = false
        filmScope = .book
        inspector = .page
    }

    private func changeCover(_ change: (inout BookCover) -> Void) {
        var cover = book.cover ?? BookCover(title: book.title)
        change(&cover)
        book.cover = cover
    }

    private func setCoverPhoto(_ id: UUID?, side: CoverSide) {
        changeCover {
            switch side {
            case .front: $0.frontPhotoID = id
            case .back: $0.backPhotoID = id
            }
        }
        selectedPhoto = id
    }

    private func select(_ leaf: BookPage) {
        if cropSession?.pageID != leaf.id { finishCrop() }
        if leaf.id != page?.id {
            endInlineBoxEditing()
            canvasPhotoSelection = nil
            selectedPhoto = nil
            selectedBox = nil
            filmScope = .book
            writing = false
            writingBox = false
        }
        coverSide = nil
        selection = leaf.id
    }

    private func selectCanvasPhoto(_ id: UUID, in leaf: BookPage) {
        if cropSession?.photoID != id { finishCrop() }
        endInlineBoxEditing()
        select(leaf)
        selectedBox = nil
        selectedPhoto = id
        canvasPhotoSelection = CanvasPhotoSelection(pageID: leaf.id, photoID: id)
        if inspector == .film {
            filmScope = .photo
        } else if inspector == .page {
            inspector = .photos
            photoPanelMode = .adjust
        }
    }

    private func selectTextBox(_ id: UUID, in leaf: BookPage) {
        finishCrop()
        if inlineEditingBox != id { endInlineBoxEditing() }
        select(leaf)
        selectedBox = id
        selectedPhoto = nil
        inspector = .page
    }

    private func beginInlineBoxEditing(_ id: UUID, in leaf: BookPage) {
        selectTextBox(id, in: leaf)
        writing = false
        writingBox = false
        inlineEditingBox = id
    }

    private func endInlineBoxEditing() {
        guard inlineEditingBox != nil || inlineBoxFocus != nil else { return }
        inlineEditingBox = nil
        inlineBoxFocus = nil
    }

    private func setLayout(_ layout: PageLayout) {
        finishCrop()
        guard let index, book.pages[index].layout != layout else { return }
        editPages(tr("Cambia composizione", "Change Layout")) { pages in
            pages[index].layout = layout
        }
    }

    private func insert(_ layout: PageLayout) {
        let newPage = BookPage(layout: layout)
        let insertionIndex = (index ?? (book.pages.count - 1)) + 1
        editPages(tr("Inserisci pagina", "Insert Page")) { $0.insert(newPage, at: insertionIndex) }
        select(newPage)
        inspector = .page
    }

    private func insertTitlePage() {
        let titlePage = BookPage(layout: .text, heading: book.title)
        editPages(tr("Inserisci frontespizio", "Insert Title Page")) { $0.insert(titlePage, at: 0) }
        select(titlePage)
        inspector = .page
    }

    private func insertTextBox() {
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

    private func changeTextBoxes(on pageID: UUID, name: String, change: (inout [PageTextBox]) -> Void) {
        guard let index = book.pages.firstIndex(where: { $0.id == pageID }) else { return }
        editPages(name) { pages in
            var boxes = pages[index].textBoxes ?? []
            change(&boxes)
            pages[index].textBoxes = boxes.isEmpty ? nil : boxes
        }
    }

    private func textInBox(_ id: UUID, on pageID: UUID) -> Binding<String> {
        Binding(
            get: { book.pages.first { $0.id == pageID }?.textBoxes?.first { $0.id == id }?.text ?? "" },
            set: { value in
                guard let index = book.pages.firstIndex(where: { $0.id == pageID }),
                      let boxIndex = book.pages[index].textBoxes?.firstIndex(where: { $0.id == id }) else { return }
                book.pages[index].textBoxes?[boxIndex].text = value
            }
        )
    }

    private func updateTextBoxFrame(_ id: UUID, on pageID: UUID, to frame: PageRect) {
        changeTextBoxes(on: pageID, name: tr("Sposta o ridimensiona box", "Move or Resize Text Box")) { boxes in
            guard let index = boxes.firstIndex(where: { $0.id == id }) else { return }
            boxes[index].frame = frame.clamped
        }
    }

    private func deletePage() {
        guard let index else { return }
        endInlineBoxEditing()
        editPages(tr("Elimina pagina", "Delete Page")) { $0.remove(at: index) }
        selection = book.pages.isEmpty ? nil : book.pages[min(index, book.pages.count - 1)].id
        selectedPhoto = nil
        selectedBox = nil
        filmScope = .book
    }

    private func move(_ offset: Int) {
        guard let index, book.pages.indices.contains(index + offset) else { return }
        if let page { selection = page.id }
        editPages(tr("Sposta pagina", "Move Page")) { $0.swapAt(index, index + offset) }
    }

    private func editorDrag(_ item: EditorDragItem) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(EditorDropTarget.coordinateSpace))
            .updating($dragging) { value, preview, _ in
                preview = EditorDragPreview(item: item, location: value.location)
            }
            .onEnded { value in
                switch item {
                case let .page(id):
                    guard let destination = pageInsertion(at: value.location) else { return }
                    reorderPage(id, relativeTo: destination.id, after: destination.after)
                case let .photo(id):
                    placeDraggedPhoto(id, at: value.location)
                }
            }
    }

    @ViewBuilder private var dragPreview: some View {
        if let dragging {
            Group {
                switch dragging.item {
                case let .photo(id):
                    if let photo = indexedPhoto(id) { preview(photo, small: true) }
                case let .page(id):
                    if let leaf = book.pages.first(where: { $0.id == id }) { mini(leaf) }
                }
            }
            .frame(width: 64, height: 47)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .shadow(color: .black.opacity(0.24), radius: 6, y: 2)
            .opacity(0.82)
            .position(x: dragging.location.x + 20, y: dragging.location.y + 16)
        }
    }

    private func pageInsertion(at location: CGPoint) -> (id: UUID, after: Bool)? {
        guard dropFrames[.navigatorViewport]?.contains(location) == true else { return nil }
        for spread in navigatorSpreads {
            for leaf in spread.pages {
                guard let rect = dropFrames[.navigatorPage(leaf.id)],
                      rect.insetBy(dx: spread.paired ? -1.5 : 0, dy: -3.5).contains(location) else { continue }
                let after = spread.paired ? location.x >= rect.midX : location.y >= rect.midY
                return (leaf.id, after)
            }
        }
        return nil
    }

    private var previewPageInsertion: (id: UUID, after: Bool)? {
        guard let dragging, case let .page(sourceID) = dragging.item,
              let insertion = pageInsertion(at: dragging.location), insertion.id != sourceID else { return nil }
        return insertion
    }

    private var navigatorScrollDirection: Int? {
        guard let dragging, case .page = dragging.item,
              let viewport = dropFrames[.navigatorViewport], viewport.contains(dragging.location) else { return nil }
        if dragging.location.y - viewport.minY < 28 { return -1 }
        if viewport.maxY - dragging.location.y < 28 { return 1 }
        return nil
    }

    @MainActor private func scrollWhileDragging(_ scroll: ScrollViewProxy) async {
        guard let direction = navigatorScrollDirection else { return }
        while !Task.isCancelled && navigatorScrollDirection == direction {
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            guard let viewport = dropFrames[.navigatorViewport] else { return }
            let visible = book.pages.indices.filter {
                dropFrames[.navigatorPage(book.pages[$0].id)]?.intersects(viewport) == true
            }
            guard let end = direction < 0 ? visible.first : visible.last,
                  book.pages.indices.contains(end + direction) else { continue }
            scroll.scrollTo(book.pages[end + direction].id, anchor: direction < 0 ? .top : .bottom)
        }
    }

    private func isPhotoDropTarget(_ target: EditorDropTarget) -> Bool {
        guard let dragging, case .photo = dragging.item else { return false }
        return dropFrames[.canvasViewport]?.contains(dragging.location) == true
            && dropFrames[target]?.contains(dragging.location) == true
    }

    private func placeDraggedPhoto(_ id: UUID, at location: CGPoint) {
        guard dropFrames[.canvasViewport]?.contains(location) == true else { return }
        if let coverSide {
            let key = EditorDropTarget.cover(front: coverSide == .front)
            if dropFrames[key]?.contains(location) == true {
                setCoverPhoto(id, side: coverSide)
            }
        } else {
            for leaf in book.pages {
                guard let rect = dropFrames[.canvasPage(leaf.id)], rect.contains(location) else { continue }
                let local = CGPoint(x: location.x - rect.minX, y: location.y - rect.minY)
                dropPhoto(id, on: leaf, at: local, in: CGRect(origin: .zero, size: rect.size))
                break
            }
        }
    }

    private func reorderPage(_ sourceID: UUID, relativeTo targetID: UUID, after: Bool) {
        guard sourceID != targetID,
              let source = book.pages.firstIndex(where: { $0.id == sourceID }),
              book.pages.contains(where: { $0.id == targetID }) else { return }
        let leaf = book.pages[source]
        editPages(tr("Riordina pagina", "Reorder Page")) { pages in
            pages.remove(at: source)
            guard let target = pages.firstIndex(where: { $0.id == targetID }) else { return }
            pages.insert(leaf, at: target + (after ? 1 : 0))
        }
        select(leaf)
    }

    private func isOnCurrentPage(_ id: UUID) -> Bool {
        if let coverSide { return coverPhotoID(coverSide) == id }
        return page?.photoIDs.contains(id) == true
    }

    private func togglePhoto(_ id: UUID) {
        canvasPhotoSelection = nil
        if let coverSide {
            setCoverPhoto(isOnCurrentPage(id) ? nil : id, side: coverSide)
        } else if isOnCurrentPage(id) {
            remove(id)
        } else {
            assign(id)
        }
    }

    private func assign(_ id: UUID) {
        guard let index else { return }
        let leaf = book.pages[index]
        guard !leaf.photoIDs.contains(id) else { return }
        editPages(tr("Aggiungi foto", "Add Photo")) { pages in
            Self.placePhoto(id, on: &pages[index])
        }
        selectedPhoto = id
        selectedBox = nil
    }

    private func incomingPhotoPlacement(on leaf: BookPage, composition: PageComposition,
                                        bounds: CGRect) -> CanvasAlignment.Result? {
        guard let dragging, case let .photo(id) = dragging.item, let photo = indexedPhoto(id),
              isPhotoDropTarget(.canvasPage(leaf.id)), let screenFrame = dropFrames[.canvasPage(leaf.id)] else { return nil }
        let location = CGPoint(x: dragging.location.x - screenFrame.minX, y: dragging.location.y - screenFrame.minY)
        return photoPlacement(photo, in: composition, at: location, bounds: bounds)
    }

    private func photoPlacement(_ photo: BookPhoto, in composition: PageComposition, at location: CGPoint,
                                bounds: CGRect) -> CanvasAlignment.Result {
        let existing = composition.photos.first { $0.id == photo.id }
        let scale = bounds.width / composition.bounds.width
        let ratio = Double(photo.pixelWidth) / Double(max(1, photo.pixelHeight))
        let frameWidth = existing.map { $0.frame.width * scale }
            ?? min(bounds.width * 0.48, max(1, bounds.height * 0.48 * ratio))
        let frameHeight = existing.map { $0.frame.height * scale }
            ?? min(bounds.height * 0.48, frameWidth / max(0.01, ratio))
        let frame = CGRect(x: location.x - frameWidth / 2, y: location.y - frameHeight / 2,
                           width: frameWidth, height: frameHeight)
        let normalized = PageRect(frame, in: bounds)
        let proposed = existing == nil ? normalized.rect(in: bounds) : normalized.photoRect(in: bounds)
        let limit = existing == nil ? bounds : CanvasPhotoGeometry.movementBounds(for: proposed.size, in: bounds)
        let targets = alignmentTargets(in: composition, at: scale, excluding: .photo(photo.id))
        return CanvasAlignment.duringDrag(proposed, to: targets, within: limit)
    }

    private func dropPhoto(_ id: UUID, on leaf: BookPage, at location: CGPoint, in bounds: CGRect) {
        guard let photo = indexedPhoto(id), let index = book.pages.firstIndex(where: { $0.id == leaf.id }) else { return }
        let current = book.pages[index]
        let composition = pageComposition(current)
        let result = photoPlacement(photo, in: composition, at: location, bounds: bounds)
        let normalized = PageRect(result.frame, in: bounds).photoClamped
        if current.photoIDs.contains(id) {
            updatePhotoFrame(id, in: leaf, to: normalized)
        } else {
            editPages(tr("Posiziona foto", "Place Photo")) { pages in
                pages[index].photoIDs.append(id)
                var placements = pages[index].photoPlacements ?? [:]
                placements[id] = PhotoPlacement(frame: normalized)
                pages[index].photoPlacements = placements
            }
        }
        selectCanvasPhoto(id, in: leaf)
    }

    private func updatePhotoFrame(_ id: UUID, in leaf: BookPage, to frame: PageRect) {
        guard let index = book.pages.firstIndex(where: { $0.id == leaf.id }),
              book.pages[index].photoIDs.contains(id) else { return }
        let current = book.pages[index]
        editPages(tr("Sposta o ridimensiona foto", "Move or Resize Photo")) { pages in
            var placements = current.photoPlacements ?? [:]
            freezeAutomaticFrames(of: current, moving: id, placements: &placements)
            placements[id, default: PhotoPlacement()].frame = frame.photoClamped
            pages[index].photoPlacements = placements
        }
    }

    private func resetPhotoFrames(_ pageID: UUID) {
        guard let index = book.pages.firstIndex(where: { $0.id == pageID }),
              let placements = book.pages[index].photoPlacements else { return }
        editPages(tr("Ripristina posizioni foto", "Reset Photo Placement")) { pages in
            let crops = placements.compactMapValues { $0.crop.map { PhotoPlacement(crop: $0) } }
            pages[index].photoPlacements = crops.isEmpty ? nil : crops
            if pages[index].layout == .text && !pages[index].photoIDs.isEmpty {
                pages[index].layout = .mixed
            }
        }
    }

    private func beginCrop(_ photoID: UUID, in leaf: BookPage) {
        finishCrop()
        guard let current = book.pages.first(where: { $0.id == leaf.id }) else { return }
        let composition = pageComposition(current)
        guard let item = composition.photos.first(where: { $0.id == photoID }) else { return }
        selectCanvasPhoto(photoID, in: current)
        let frame = PageRect(item.frame, in: composition.bounds)
        cropSession = CropSession(pageID: leaf.id, photoID: photoID, initialFrame: frame, initialCrop: item.crop,
                                  frame: frame, crop: item.crop)
    }

    private func magnifyCrop(_ factor: Double) {
        guard let session = cropSession else { return }
        cropSession?.crop.zoom = min(12, max(1, session.crop.zoom * factor))
    }

    private func finishCrop() {
        guard let session = cropSession else { return }
        cropSession = nil
        let changedFrame = session.frame != session.initialFrame
        let changedCrop = session.crop != session.initialCrop
        guard changedFrame || changedCrop,
              let index = book.pages.firstIndex(where: { $0.id == session.pageID }),
              book.pages[index].photoIDs.contains(session.photoID) else { return }
        let current = book.pages[index]
        editPages(tr("Ritaglia foto", "Crop Photo")) { pages in
            var placements = current.photoPlacements ?? [:]
            if changedFrame {
                freezeAutomaticFrames(of: current, moving: session.photoID, placements: &placements)
                placements[session.photoID, default: PhotoPlacement()].frame = session.frame
            }
            placements[session.photoID, default: PhotoPlacement()].crop = session.crop
            pages[index].photoPlacements = placements
        }
    }

    private func freezeAutomaticFrames(of page: BookPage, moving id: UUID,
                                       placements: inout [UUID: PhotoPlacement]) {
        guard (page.layout == .gallery || page.layout == .mixed), placements[id]?.frame == nil else { return }
        let composition = pageComposition(page)
        for image in composition.photos where placements[image.id]?.frame == nil {
            placements[image.id, default: PhotoPlacement()].frame = PageRect(image.frame, in: composition.bounds)
        }
    }

    private func transferPhoto(_ id: UUID, from sourceID: UUID, to destinationID: UUID, moving: Bool) {
        guard sourceID != destinationID,
              let source = book.pages.firstIndex(where: { $0.id == sourceID }),
              let destination = book.pages.firstIndex(where: { $0.id == destinationID }),
              book.pages[source].photoIDs.contains(id),
              !book.pages[destination].photoIDs.contains(id) else { return }
        let name = moving ? tr("Sposta foto", "Move Photo") : tr("Copia foto", "Copy Photo")
        editPages(name) { pages in
            let placement = pages[source].photoPlacements?[id]
            Self.placePhoto(id, on: &pages[destination])
            if let placement {
                var placements = pages[destination].photoPlacements ?? [:]
                placements[id] = placement
                pages[destination].photoPlacements = placements
            }
            if moving { Self.removePhoto(id, from: &pages[source]) }
        }
        select(book.pages[destination])
        selectedPhoto = id
    }

    private static func placePhoto(_ id: UUID, on page: inout BookPage) {
        switch page.layout {
        case .fullPage, .fullSpread:
            page.photoIDs.insert(id, at: 0)
        case .text:
            page.layout = .mixed
            page.photoIDs.append(id)
        case .gallery, .mixed:
            page.photoIDs.append(id)
        }
    }

    @discardableResult
    private func remove(_ id: UUID, from pageID: UUID? = nil) -> Bool {
        guard let target = pageID ?? page?.id,
              let index = book.pages.firstIndex(where: { $0.id == target }),
              book.pages[index].photoIDs.contains(id) else { return false }
        editPages(tr("Rimuovi foto", "Remove Photo")) { pages in
            Self.removePhoto(id, from: &pages[index])
        }
        return true
    }

    @discardableResult
    private func deleteCanvasPhoto(_ id: UUID, from pageID: UUID) -> Bool {
        guard cropSession == nil, inlineBoxFocus == nil, remove(id, from: pageID) else { return false }
        if canvasPhotoSelection?.photoID == id { canvasPhotoSelection = nil }
        if selectedPhoto == id { selectedPhoto = nil }
        return true
    }

    private func deleteSelectedCanvasPhoto() -> Bool {
        guard let selection = canvasPhotoSelection, page?.id == selection.pageID,
              selectedPhoto == selection.photoID, selectedBox == nil else { return false }
        return deleteCanvasPhoto(selection.photoID, from: selection.pageID)
    }

    private static func removePhoto(_ id: UUID, from page: inout BookPage) {
        page.photoIDs.removeAll { $0 == id }
        page.photoPlacements?.removeValue(forKey: id)
        if page.photoPlacements?.isEmpty == true { page.photoPlacements = nil }
    }

    private func reorderPhoto(_ id: UUID, by offset: Int) {
        guard let index, let current = book.pages[index].photoIDs.firstIndex(of: id),
              book.pages[index].photoIDs.indices.contains(current + offset) else { return }
        editPages(tr("Sposta foto", "Move Photo")) { pages in
            pages[index].photoIDs.swapAt(current, current + offset)
        }
    }

    private func editPages(_ name: String, change: (inout [BookPage]) -> Void) {
        let previous = book.pages
        change(&book.pages)
        registerUndo(previous, name: name)
    }

    private func registerUndo(_ previous: [BookPage], name: String) {
        guard previous != book.pages, let undoManager else { return }
        undoTarget.register(undoManager, binding: $book, bookID: book.id, pages: previous, name: name)
    }

}

private final class EditorUndo {
    func register(_ manager: UndoManager, binding: Binding<Book>, bookID: UUID, pages: [BookPage], name: String) {
        manager.registerUndo(withTarget: self) { [weak manager] target in
            guard let manager, binding.wrappedValue.id == bookID else { return }
            let current = binding.wrappedValue.pages
            let currentByID = Dictionary(current.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            binding.wrappedValue.pages = pages.map { page in
                guard let latest = currentByID[page.id] else { return page }
                var restored = page
                restored.text = latest.text
                restored.heading = latest.heading
                restored.textBoxes = page.textBoxes?.map { box in
                    var restoredBox = box
                    restoredBox.text = latest.textBoxes?.first { $0.id == box.id }?.text ?? box.text
                    return restoredBox
                }
                return restored
            }
            target.register(manager, binding: binding, bookID: bookID, pages: current, name: name)
        }
        manager.setActionName(name)
    }

    func registerPhotoAdjustments(_ manager: UndoManager, binding: Binding<Book>, bookID: UUID,
                                  photoID: UUID, previous: PhotoAdjustments?, name: String) {
        manager.registerUndo(withTarget: self) { [weak manager] target in
            guard let manager, binding.wrappedValue.id == bookID,
                  let index = binding.wrappedValue.photos.firstIndex(where: { $0.id == photoID }) else { return }
            let current = binding.wrappedValue.photos[index].adjustments
            binding.wrappedValue.photos[index].adjustments = previous
            target.registerPhotoAdjustments(manager, binding: binding, bookID: bookID, photoID: photoID,
                                            previous: current, name: name)
        }
        manager.setActionName(name)
    }
}

private struct EditorPreview<Placeholder: View>: View {
    let request: EditorPreviewRequest
    let crop: PhotoCrop
    let fills: Bool
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: NSImage?
    @State private var displayedURL: URL?

    var body: some View {
        GeometryReader { geometry in
            if let image, displayedURL == request.url {
                let frame = crop.imageRect(for: image.size, in: CGRect(origin: .zero, size: geometry.size), fills: fills)
                Image(nsImage: image)
                    .resizable()
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    .accessibilityHidden(true)
            } else {
                placeholder()
            }
        }
        .clipped()
        .task(id: request) {
            let request = request
            let pixels = await EditorPreviewLoader.image(for: request)
            guard !Task.isCancelled else { return }
            image = pixels.map {
                NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height))
            }
            displayedURL = request.url
        }
    }
}
