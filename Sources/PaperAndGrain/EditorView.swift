import AppKit
import Observation
import UniformTypeIdentifiers
import SwiftUI

struct EditorView: View {
    @Binding var book: Book
    let directory: URL
    let language: String
    let analysisStatus: String
    let isAnalyzing: Bool
    let onAnalyze: () -> Void
    let onDropPhotos: ([NSItemProvider], @escaping (UUID) -> Void) -> Bool
    let onDropPhotoPromises: ([NSFilePromiseReceiver], @escaping (UUID) -> Void) -> Bool
    let onExport: () -> Void

    @Environment(\.undoManager) private var undoManager
    @FocusState private var writing: Bool
    @FocusState private var writingBox: Bool
    @FocusState private var inlineBoxFocus: UUID?
    @FocusState private var editorialFocus: EditorialObject?
    @FocusState private var searchingPhotos: Bool
    @State private var selection: UUID?
    @State private var selectedPhoto: UUID?
    @State private var canvasPhotoSelection: CanvasPhotoSelection?
    @State private var photoIndices: [UUID: Int] = [:]
    @State private var selectedBox: UUID?
    @State private var inlineEditingBox: UUID?
    @State private var selectedEditorial: EditorialObject?
    @State private var editingEditorial: EditorialObject?
    @State private var coverSide: CoverSide?
    @State private var coverTypographyExpanded = false
    @State private var zoom: CanvasZoom = .fitPage
    @State private var dropFrames = [EditorDropTarget: CGRect]()
    @State private var canvasHits = CanvasHitStorage()
    @State private var canvasInput = CanvasInput()
    @AppStorage("editorShowsPages") private var showsNavigator = true
    @AppStorage("editorShowsInspector") private var showsInspector = true
    @State private var libraryHitFrames = LibraryHitFrames()
    @State private var hoveringPhotoDrop = false
    @State private var hoveringPhotoPromise = false
    @State private var importedPhotoToReveal: UUID?
    @GestureState private var dragging: EditorDragPreview?
    @State private var showSpread = true
    @State private var gutterGuide = false
    @State private var showDelete = false
    @State private var inspectorNavigation = InspectorNavigation()
    @State private var filmScope: FilmScope = .book
    @State private var filmEdit = FilmEdit()
    @State private var filmPreviewTask: Task<Void, Never>?
    @State private var compareOriginal = false
    @State private var comparePhotoOriginal: UUID?
    @State private var enhancingPhotos: [UUID: UUID] = [:]
    @State private var adjustmentErrors: [UUID: String] = [:]
    @State private var adjustmentEdit: AdjustmentEdit?
    @State private var adjustmentPreviewTask: Task<Void, Never>?
    @State private var lutImportError: String?
    @State private var concept: String?
    @State private var search = ""
    @State private var photoLibraryCache = InspectorPhotoLibraryCache()
    @State private var photoUsageIndex = PhotoUsageIndex()
    @AppStorage("libraryPhotoOrder") private var photoOrder: PhotoLibraryOrder = .date
    @State private var libraryOrdering = PhotoLibraryOrdering()
    @State private var placesRead: [UUID: PhotoLocation] = [:]
    @State private var scannedPlaceAssets: Set<PlaceAsset> = []
    @State private var suggestedPhotos: [PhotoSuggestion] = []
    @State private var undoTarget = EditorUndo()
    @State private var cropSession: CropSession?

    fileprivate enum Inspector: String, CaseIterable {
        case page, photos, film
    }

    fileprivate enum PhotoPanelMode: Hashable {
        case library, adjust
    }

    @Observable fileprivate final class InspectorNavigation {
        var tab: Inspector = .page
        var photos: PhotoPanelMode = .library
    }

    private final class CanvasInput {
        var ownsKeyboard = false
    }

    private final class LibraryHitFrames {
        var frames = LibraryPhotoFrames()
    }

    private var inspector: Inspector {
        get { inspectorNavigation.tab }
        nonmutating set { inspectorNavigation.tab = newValue }
    }

    private var photoPanelMode: PhotoPanelMode {
        get { inspectorNavigation.photos }
        nonmutating set { inspectorNavigation.photos = newValue }
    }

    private struct InspectorHost<Content: View>: View {
        @Bindable var navigation: InspectorNavigation
        let title: String
        let pageTitle: String
        let photosTitle: String
        let filmTitle: String
        let edge: Color
        let finishAdjustment: () -> Void
        let finishFilm: () -> Void
        @ViewBuilder let content: (Inspector, PhotoPanelMode) -> Content

        var body: some View {
            VStack(spacing: 0) {
                Picker(title, selection: $navigation.tab) {
                    Text(pageTitle).tag(Inspector.page)
                    Text(photosTitle).tag(Inspector.photos)
                    Text(filmTitle).tag(Inspector.film)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(14)
                Rectangle().fill(edge).frame(height: 1)
                content(navigation.tab, navigation.photos)
            }
            .onChange(of: navigation.tab) { _, tab in
                if tab != .photos { finishAdjustment() }
                if tab != .film { finishFilm() }
            }
            .onChange(of: navigation.photos) { _, mode in
                if mode != .adjust { finishAdjustment() }
            }
        }
    }

    private struct CanvasPhotoSelection {
        let surface: EditorDropTarget
        let photoID: UUID

        var pageID: UUID? {
            if case let .canvasPage(id) = surface { return id }
            return nil
        }
    }

    private struct AdjustmentEdit {
        let photoID: UUID
        var draft: PhotoAdjustments
        var preview: PhotoAdjustments
    }

    private struct PlaceAsset: Hashable, Sendable {
        let id: UUID
        let filename: String
        let sourceID: String?
    }

    private struct PhotoSuggestion: Identifiable, Sendable {
        let id: UUID
        let score: Double
        let evidence: PhotoMatchEvidence
    }

    private struct PhotoSuggestionQuery: Equatable, Sendable {
        let story: String
        let assigned: Set<UUID>
        let photos: [BookPhoto]

        func findMatches() -> [PhotoSuggestion] {
            guard !story.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
            var matches: [PhotoSuggestion] = []
            for photo in photos {
                guard !Task.isCancelled else { return [] }
                guard let analysis = photo.analysis, !assigned.contains(photo.id) else { continue }
                let evidence = PhotoAnalyzer.matches(analysis, for: story)
                guard let mostSpecific = evidence.first(where: { $0.source != "concept" }) ?? evidence.first else { continue }
                matches.append(PhotoSuggestion(id: photo.id, score: evidence.reduce(0) { $0 + $1.score },
                                               evidence: mostSpecific))
            }
            return Array(matches.sorted { $0.score > $1.score }.prefix(4))
        }
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

    private enum EditorialObject: Hashable {
        case page(UUID, PageComposition.TextRole)
        case storyGroup(UUID)
        case cover(CoverSide)
    }

    private enum AlignmentElement: Equatable {
        case photo(UUID), textBox(UUID), editorial(PageComposition.TextRole)
    }

    private enum IncomingPhotoPlacement {
        case position(CanvasAlignment.Result)
        case swap(CanvasPhotoSwap.Target)
    }

    private struct CropSession {
        let surface: EditorDropTarget
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
            if page.effectiveLayout == .fullSpread {
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
            let blankLeft = row.count == 1 && first.effectiveLayout != .fullSpread
                && first.id == book.pages.first?.id && book.printSettings?.firstPageOnRight == true
            return NavigatorSpread(id: first.id, pages: row, blankLeft: blankLeft)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            masthead
            Rectangle().fill(edge).frame(height: 1)
            HStack(spacing: 0) {
                if showsNavigator {
                    navigator.frame(width: 158)
                    Rectangle().fill(edge).frame(width: 1)
                }
                canvas.frame(maxWidth: .infinity, maxHeight: .infinity)
                if showsInspector {
                    Rectangle().fill(edge).frame(width: 1)
                    sidePanel.frame(width: 260)
                }
            }
        }
        .background(panel)
        .background(alignment: .topLeading) {
            CanvasDeleteShortcut(onDelete: deleteSelectedCanvasObject, onDeselect: deselectCanvas,
                                 onNudge: nudgeCanvasSelection, onClick: selectObject(at:),
                                 onPointerDown: { point in
                canvasInput.ownsKeyboard = dropFrames[.canvasViewport]?.contains(point) == true
            }, onKeyboardTraversal: { canvasInput.ownsKeyboard = false })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .foregroundStyle(ink)
        .tint(pine)
        .coordinateSpace(name: EditorDropTarget.coordinateSpace)
        .onPreferenceChange(EditorDropFrames.self) { dropFrames = $0 }
        .onPreferenceChange(CanvasHitMaps.self) { canvasHits.maps = $0 }
        .onChange(of: book.photos.map(\.id), initial: true) { _, ids in
            photoIndices = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($0.element, $0.offset) })
        }
        .onChange(of: inlineBoxFocus) { previous, current in
            if previous != nil && current == nil && inlineEditingBox == previous { inlineEditingBox = nil }
        }
        .onChange(of: editorialFocus) { previous, current in
            if let previous, current == nil, editingEditorial == previous { editingEditorial = nil }
        }
        .onChange(of: selectedPhoto) { _, id in
            if canvasPhotoSelection?.photoID != id { canvasPhotoSelection = nil }
            if comparePhotoOriginal != id { comparePhotoOriginal = nil }
            if let adjustmentEdit, adjustmentEdit.photoID != id { finishPhotoAdjustmentEdit() }
            if case let .photo(target)? = filmEdit.target, target != id { finishFilmEdit() }
        }
        .onChange(of: filmScope) { _, _ in finishFilmEdit() }
        .onDisappear {
            adjustmentPreviewTask?.cancel()
            filmPreviewTask?.cancel()
            undoManager?.removeAllActions(withTarget: undoTarget)
        }
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
            action("sidebar.left", showsNavigator ? localized("editor.pages.hide", fallback: "Hide Pages")
                                                   : localized("editor.pages.show", fallback: "Show Pages")) {
                showsNavigator.toggle()
            }
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
                    if writing || writingBox || inlineBoxFocus != nil || editorialFocus != nil,
                       NSApp.sendAction(Selector(("undo:")), to: nil, from: nil) { return }
                    undoManager?.undo()
                }
                action("arrow.uturn.forward", tr("Ripristina", "Redo")) {
                    if writing || writingBox || inlineBoxFocus != nil || editorialFocus != nil,
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
                Button(tr("Titolo di pagina", "Page Heading"), systemImage: "textformat.size", action: insertPageHeading)
                    .disabled(page == nil)
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
            action("sidebar.right", showsInspector ? localized("editor.inspector.hide", fallback: "Hide Inspector")
                                                    : localized("editor.inspector.show", fallback: "Show Inspector")) {
                if showsInspector {
                    finishPhotoAdjustmentEdit()
                    finishFilmEdit()
                }
                showsInspector.toggle()
            }
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
        let ratio = aspect * (leaf.effectiveLayout == .fullSpread ? 2 : 1)
        let width = min(paired ? 63 : 115, 47 * ratio)
        let number = spreadNumber([leaf])
        let label = first && !paired ? tr("Prima pagina", "First Page") : number
        return navigatorCard(label, active: active) {
            select(leaf)
        } preview: {
            navigatorPreview(for: .navigatorPage(leaf.id)) {
                mini(leaf)
            }
            .frame(width: width, height: width / ratio)
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
            navigatorPreview(for: .cover(front: side == .front)) {
                coverCanvas(side, scale: width / book.format.pageSize.width, thumbnail: true)
            }
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

    private func navigatorPreview<Content: View>(for target: EditorDropTarget,
                                                  @ViewBuilder content: @escaping () -> Content) -> some View {
        NavigatorPreview(target: target, book: book, directory: directory, original: compareOriginal,
                         originalPhoto: comparePhotoOriginal, content: content)
            .equatable()
    }

    private func mini(_ leaf: BookPage) -> some View {
        let composition = pageComposition(leaf)
        let style = book.editorialStyle
        let blocks = composition.storyDrawingBlocks(page: leaf, book: book)
        let backings = composition.storyBackgroundFrames(page: leaf, blocks: blocks)
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
                storyBacking(backings, scale: scale)
                ForEach(blocks) { block in
                    positioned(editorialText(block.text, scale: scale), in: scaled(block.frame, by: scale))
                }
                ForEach(composition.textBoxes.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { box in
                    let frame = box.frame.rect(in: composition.bounds)
                    positioned(Color(cgColor: EditorialStyle.color(style.paper)), in: scaled(frame, by: scale))
                    let text = PageComposition.boxText(box: box, book: book)
                    let inset = box.textInsetPoints
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
            VStack(spacing: 10) {
                if let cropSession {
                    cropToolbar(cropSession)
                } else if let coverSide {
                    coverTools(coverSide)
                } else if let page {
                    canvasTools(page)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 21)
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
        let wide = page.effectiveLayout == .fullSpread
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

    private func canvasTools(_ page: BookPage) -> some View {
        let hasFold = page.effectiveLayout == .fullSpread
            || (showSpread && groups.contains { $0.count == 2 && $0.contains { $0.id == page.id } })
        return HStack(spacing: 10) {
            if hasFold {
                Toggle(tr("Guida della piega", "Gutter Guide"), isOn: $gutterGuide)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                    .foregroundStyle(muted)
            }
            if let photo = canvasPhotoSelection, photo.pageID == page.id {
                Button(tr("Ritaglia", "Crop"), systemImage: "crop") { beginCrop(photo.photoID, in: page) }
                    .controlSize(.small)
            }
        }
        .frame(height: 26)
    }

    private func coverTools(_ side: CoverSide) -> some View {
        HStack(spacing: 10) {
            if let selection = canvasPhotoSelection, selection.surface == .cover(front: side == .front) {
                Button(tr("Ritaglia", "Crop"), systemImage: "crop") { beginCoverCrop(side) }
                    .controlSize(.small)
            }
            if coverEditorialValue(side).wrappedValue.isEmpty {
                Button(localized("editor.cover.add_text", fallback: "Add Text"), systemImage: "textformat") {
                    showsInspector = true
                    inspector = .page
                    Task { @MainActor in
                        await Task.yield()
                        if coverSide == side { writing = true }
                    }
                }
                .controlSize(.small)
            }
        }
        .frame(height: 26)
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
        let blocks = composition.storyBlocks(page: leaf, book: book)
        let backings = composition.storyBackgroundFrames(page: leaf, blocks: blocks)
        let textFrames = blocks.map(\.frame) + backings
        let incomingPhoto = incomingPhotoPlacement(on: leaf, composition: composition, bounds: bounds, textFrames: textFrames)
        return ZStack(alignment: .topLeading) {
            Color(cgColor: EditorialStyle.color(style.paper))
            if leaf.arrangement != nil {
                ForEach(Array(composition.arrangementPhotoSlots.dropFirst(leaf.photoIDs.count).enumerated()), id: \.offset) { _, slot in
                    positioned(placeholder, in: scaled(slot, by: scale))
                        .allowsHitTesting(false)
                }
            } else if composition.photos.isEmpty && leaf.effectiveLayout != .text {
                let margin = leaf.effectiveLayout == .gallery || leaf.effectiveLayout == .mixed ? book.contentInsetPoints * scale : 0
                placeholder
                    .frame(width: max(1, bounds.width - 2 * margin),
                           height: max(1, bounds.height - 2 * margin) * (leaf.effectiveLayout == .mixed ? 0.53 : 1))
                    .padding(margin)
                    .allowsHitTesting(false)
            }
            if let rule = composition.rule {
                positioned(Color(cgColor: EditorialStyle.color(style.accent)), in: scaled(rule, by: scale))
                    .allowsHitTesting(false)
            }
            ForEach(composition.photos) { item in
                if cropSession?.surface != .canvasPage(leaf.id) || cropSession?.photoID != item.id {
                    let targets = alignmentTargets(in: composition, at: scale, excluding: .photo(item.id), blocks: blocks)
                    canvasPhoto(item, leaf: leaf, composition: composition, bounds: bounds, scale: scale,
                                alignmentTargets: targets, textFrames: textFrames)
                }
            }
            canvasStory(leaf, composition: composition, blocks: blocks, backings: backings, bounds: bounds, scale: scale)
            ForEach(composition.textBoxes) { box in
                let targets = alignmentTargets(in: composition, at: scale, excluding: .textBox(box.id), blocks: blocks)
                canvasTextBox(box, leaf: leaf, bounds: bounds, scale: scale, alignmentTargets: targets)
            }
            if let folio = composition.folio {
                let label = style.typography(String(number(of: leaf)), heading: nil, mixed: true)
                positioned(editorialText(label, scale: scale), in: scaled(folio, by: scale))
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            if let session = cropSession, session.surface == .canvasPage(leaf.id),
               let item = composition.photos.first(where: { $0.id == session.photoID }) {
                let targets = alignmentTargets(in: composition, at: scale, excluding: .photo(item.id), blocks: blocks)
                canvasCrop(session, photo: item.photo, bounds: bounds, scale: scale, alignmentTargets: targets)
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
                if case let .position(placement) = incomingPhoto {
                    let border = Rectangle().strokeBorder(pine, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                    positioned(border, in: placement.frame)
                    CanvasAlignmentGuides(guides: guides + placement.guides)
                } else if !guides.isEmpty {
                    CanvasAlignmentGuides(guides: guides)
                }
            }
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .overlayPreferenceValue(CanvasSwapTargetPreference.self) { target in
            ZStack(alignment: .topLeading) {
                if case let .swap(incoming) = incomingPhoto {
                    photoSwapIndicator(incoming)
                } else if let target {
                    photoSwapIndicator(target)
                }
            }
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .coordinateSpace(name: leaf.id)
        .editorDropFrame(.canvasPage(leaf.id))
        .preference(key: CanvasHitMaps.self, value: [.canvasPage(leaf.id): pageHitMap(
            leaf, composition: composition, blocks: blocks, backings: backings, bounds: bounds, scale: scale
        )])
    }

    private func photoSwapIndicator(_ target: CanvasPhotoSwap.Target) -> some View {
        let indicator = Rectangle()
            .strokeBorder(.white, lineWidth: 4)
            .overlay {
                Rectangle().strokeBorder(pine, style: StrokeStyle(lineWidth: 2, dash: [6, 3]))
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(pine, in: RoundedRectangle(cornerRadius: 4))
                    .padding(5)
            }
        return positioned(indicator, in: target.frame)
    }

    private func alignmentTargets(in composition: PageComposition, at scale: CGFloat,
                                  excluding element: AlignmentElement, blocks: [PageComposition.TextBlock] = []) -> [CGRect] {
        let photos = composition.photos.compactMap { item in
            element == .photo(item.id) ? nil : scaled(item.frame, by: scale)
        }
        let textBoxes = composition.textBoxes.compactMap { box in
            element == .textBox(box.id) ? nil : scaled(box.frame.rect(in: composition.bounds), by: scale)
        }
        let editorial = blocks.compactMap { block in
            element == .editorial(block.role) || block.text.length == 0 ? nil : scaled(block.frame, by: scale)
        }
        return photos + textBoxes + editorial
    }

    @ViewBuilder private func canvasStory(_ leaf: BookPage, composition: PageComposition,
                                          blocks: [PageComposition.TextBlock], backings: [CGRect],
                                          bounds: CGRect, scale: CGFloat) -> some View {
        if let group = storyGroupFrame(blocks, backings: backings) {
            let object = EditorialObject.storyGroup(leaf.id)
            CanvasStoryGroup(frame: scaled(group, by: scale), bounds: bounds,
                             backdrops: backings.map { scaled($0, by: scale) },
                             alignmentTargets: composition.photos.map { scaled($0.frame.intersection(composition.bounds), by: scale) }
                                + composition.textBoxes.map { scaled($0.frame.rect(in: composition.bounds), by: scale) },
                             selected: selectedEditorial == object,
                             moveLabel: tr("Sposta blocco", "Move Story Group"),
                             onSelect: { activateCanvas { selectEditorial(object, on: leaf) } },
                             onNudge: { nudgeFromKeyboard($0) { selectEditorial(object, on: leaf) } },
                             onMove: { delta in moveStoryGroup(on: leaf.id, by: CGSize(width: delta.width / scale,
                                                                                     height: delta.height / scale)) }) {
                canvasStoryContents(leaf, composition: composition, blocks: blocks, backings: backings,
                                    bounds: bounds, scale: scale)
            }
        } else {
            canvasStoryContents(leaf, composition: composition, blocks: blocks, backings: backings,
                                bounds: bounds, scale: scale)
        }
    }

    private func storyGroupFrame(_ blocks: [PageComposition.TextBlock], backings: [CGRect]) -> CGRect? {
        let visible = blocks.filter { !$0.frame.isEmpty }
        let occupied = visible.lazy.filter { $0.text.length > 0 }.count
        guard occupied > 1 || (occupied > 0 && !backings.isEmpty) else { return nil }
        return (visible.map(\.frame) + backings).reduce(CGRect.null) { $0.union($1) }
    }

    private func pageHitMap(_ leaf: BookPage, composition: PageComposition, blocks: [PageComposition.TextBlock],
                            backings: [CGRect], bounds: CGRect, scale: CGFloat) -> CanvasHitMap {
        typealias Region = CanvasHitMap.Region
        var regions = composition.photos.map { Region(frame: $0.frame, target: .photo($0.id)) }
        let group = storyGroupFrame(blocks, backings: backings)
        regions += backings.map { Region(frame: $0, target: group == nil ? .paper : .storyGroup) }
        regions += blocks.map { Region(frame: $0.frame, target: .story($0.role)) }
        if let group {
            let grip = CanvasStoryGrip.frame(for: scaled(group, by: scale), in: bounds)
            regions.append(Region(frame: scaled(grip, by: 1 / scale), target: .storyGroup))
        }
        regions += composition.textBoxes.map { Region(frame: $0.frame.rect(in: composition.bounds), target: .textBox($0.id)) }
        // Inline editors sit above other text, while the active crop intercepts clicks within its frame.
        if let editingEditorial, case let .page(id, role) = editingEditorial, id == leaf.id,
           let block = blocks.first(where: { $0.role == role }) {
            regions.append(Region(frame: block.frame, target: .story(role)))
        }
        if let inlineEditingBox, let box = composition.textBoxes.first(where: { $0.id == inlineEditingBox }) {
            regions.append(Region(frame: box.frame.rect(in: composition.bounds), target: .textBox(box.id)))
        }
        if let cropSession, cropSession.surface == .canvasPage(leaf.id) {
            regions.append(Region(frame: cropSession.frame.photoRect(in: composition.bounds), target: .crop))
        }
        return CanvasHitMap(bounds: composition.bounds, regions: regions)
    }

    @ViewBuilder private func canvasStoryContents(_ leaf: BookPage, composition: PageComposition,
                                                  blocks: [PageComposition.TextBlock], backings: [CGRect],
                                                  bounds: CGRect, scale: CGFloat) -> some View {
        storyBacking(backings, scale: scale)
        ForEach(blocks) { block in
            let targets = alignmentTargets(in: composition, at: scale, excluding: .editorial(block.role), blocks: blocks)
            canvasEditorialText(block, in: leaf, bounds: bounds, scale: scale, targets: targets)
        }
    }

    @ViewBuilder private func storyBacking(_ rects: [CGRect], scale: CGFloat) -> some View {
        if !rects.isEmpty {
            let style = book.editorialStyle
            Path { path in path.addRects(rects.map { scaled($0, by: scale) }) }
                .fill(Color(cgColor: EditorialStyle.color(style.overlayPaper)).opacity(style.overlayOpacity))
                .overlay {
                    Path { path in path.addRects(rects.compactMap { style.overlayMark(in: $0) }.map { scaled($0, by: scale) }) }
                        .fill(Color(cgColor: EditorialStyle.color(style.overlayAccent)))
                }
                .allowsHitTesting(false)
        }
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

    private func canvasPhoto(_ item: PageComposition.Photo, leaf: BookPage, composition: PageComposition,
                             bounds: CGRect, scale: CGFloat, alignmentTargets: [CGRect], textFrames: [CGRect]) -> some View {
        let frame = scaled(item.frame, by: scale)
        let active = canvasPhotoSelection?.pageID == leaf.id && canvasPhotoSelection?.photoID == item.id
        let swapTargetAt: (CGPoint) -> CanvasPhotoSwap.Target? = { location in
            guard let pageFrame = dropFrames[.canvasPage(leaf.id)] else { return nil }
            let editorPoint = CGPoint(x: pageFrame.minX + location.x, y: pageFrame.minY + location.y)
            guard dropFrames[.canvasViewport]?.contains(editorPoint) == true else { return nil }
            return photoSwapTarget(item.id, at: location, in: bounds, composition: composition, textFrames: textFrames)
        }
        return CanvasObjectControl(frame: frame, bounds: bounds, selected: active,
                                   minimumSize: CGSize(width: 40 * scale, height: 40 * scale),
                                   accessibilityName: item.photo.name, alignmentTargets: alignmentTargets,
                                   allowsPhotoOverflow: true, preservesAspectRatio: true,
                                   moveSpace: .named(leaf.id), swapTargetAt: swapTargetAt,
                                   onSwap: { swapPhoto(item.id, with: $0, on: leaf.id) },
                                   onDoubleClick: { beginCrop(item.id, in: leaf) },
                                   onSelect: { activateCanvas { selectCanvasPhoto(item.id, in: leaf) } },
                                   onNudge: { nudgeFromKeyboard($0) { selectCanvasPhoto(item.id, in: leaf) } },
                                   onChange: { updatePhotoFrame(item.id, in: leaf, to: PageRect($0, in: bounds)) }) { _ in
            preview(item.photo, crop: item.crop, fills: item.fills)
        }
        .accessibilityAction(named: Text(tr("Ritaglia foto", "Crop Photo"))) { beginCrop(item.id, in: leaf) }
        .accessibilityAction(named: Text(tr("Rimuovi dalla pagina", "Remove from Page"))) {
            deleteCanvasPhoto(item.id, from: leaf.id)
        }
    }

    private func canvasCrop(_ session: CropSession, photo: BookPhoto, bounds: CGRect, scale: CGFloat,
                            alignmentTargets: [CGRect]) -> some View {
        let frame = session.frame.photoRect(in: bounds)
        let size = CGSize(width: photo.pixelWidth, height: photo.pixelHeight)
        return CanvasCropControl(frame: frame, bounds: bounds, sourceSize: size, crop: session.crop,
                                 minimumSize: CGSize(width: 40 * scale, height: 40 * scale),
                                 alignmentTargets: alignmentTargets,
                                 onChange: { nextFrame, nextCrop in
            guard cropSession?.photoID == session.photoID, cropSession?.surface == session.surface else { return }
            if nextFrame != frame { cropSession?.frame = PageRect(nextFrame, in: bounds).photoClamped }
            cropSession?.crop = nextCrop
        }, image: {
            preview(photo, fills: false)
        })
    }

    private func canvasEditorialText(_ block: PageComposition.TextBlock, in leaf: BookPage, bounds: CGRect,
                                     scale: CGFloat, targets: [CGRect]) -> some View {
        let title = block.role == .title
        let style = book.editorialStyle
        let mixed = leaf.effectiveLayout == .mixed
        let overPhoto = leaf.arrangement == .textOverPhoto
        let type = title
            ? style.defaultTitleStyle(mixed: mixed).applying(
                style.fittedTitleStyle(leaf.heading, width: block.frame.width, mixed: mixed, override: book.titleStyle(for: leaf))
            )
            : style.defaultBodyStyle.applying(book.bodyStyle(for: leaf))
        let object = EditorialObject.page(leaf.id, block.role)
        return editableEditorialObject(object, content: block.text, value: pageEditorialText(block.role, on: leaf.id),
                                       type: type, label: title ? tr("Titolo", "Heading") : tr("Racconto", "Story"),
                                       frame: scaled(block.frame, by: scale), bounds: bounds, scale: scale, targets: targets,
                                       textInk: title ? (overPhoto ? style.overlayTitleInk : style.titleInk)
                                           : (overPhoto ? style.overlayInk : style.ink),
                                       textPaper: overPhoto ? style.overlayPaper : style.paper,
                                       onSelect: { selectEditorial(object, on: leaf) },
                                       onChange: { movePageText(block.role, on: leaf.id, to: PageRect($0, in: bounds)) })
    }

    @ViewBuilder private func editableEditorialObject(
        _ object: EditorialObject, content: NSAttributedString, value: Binding<String>, type: EditorialTextStyle,
        label: String, frame: CGRect, bounds: CGRect, scale: CGFloat, targets: [CGRect],
        textInk: UInt32? = nil, textPaper: UInt32? = nil,
        onSelect: @escaping () -> Void, onChange: @escaping (CGRect) -> Void
    ) -> some View {
        let style = book.editorialStyle
        let name = content.length == 0 ? label : content.string
        if editingEditorial == object {
            let alignment: TextAlignment = type.alignment == .center ? .center : (type.alignment == .right ? .trailing : .leading)
            let font = type.fontName.flatMap { NSFont(name: $0, size: 12)?.fontName } ?? style.bodyFont
            let editor = TextEditor(text: value)
                .font(.custom(font, size: max(1, (type.pointSize ?? style.bodySize) * scale)))
                .multilineTextAlignment(alignment)
                .foregroundStyle(Color(cgColor: EditorialStyle.color(textInk ?? style.ink)))
                .scrollContentBackground(.hidden)
                .background(Color(cgColor: EditorialStyle.color(textPaper ?? style.paper)))
                .overlay { Rectangle().strokeBorder(pine, lineWidth: 1.5).allowsHitTesting(false) }
                .focused($editorialFocus, equals: object)
                .accessibilityLabel(label)
                .onExitCommand(perform: endInlineTextEditing)
                .task(id: object) {
                    await Task.yield()
                    if NSApp.isActive && editingEditorial == object { editorialFocus = object }
                }
            positioned(editor, in: frame).zIndex(1)
        } else if !frame.isEmpty {
            let beginEditing = {
                onSelect()
                editingEditorial = object
            }
            CanvasObjectControl(frame: frame, bounds: bounds, selected: selectedEditorial == object,
                                minimumSize: CGSize(width: 55 * scale, height: 22 * scale), accessibilityName: name,
                                alignmentTargets: targets, showsWidthHandles: true, onDoubleClick: beginEditing,
                                onSelect: { activateCanvas(onSelect) },
                                onNudge: { nudgeFromKeyboard($0, selecting: onSelect) }, onChange: onChange) { _ in
                if content.length == 0 {
                    Text(label)
                        .font(.custom(type.fontName ?? style.bodyFont, size: max(9, (type.pointSize ?? style.bodySize) * scale)))
                        .foregroundStyle(Color(cgColor: EditorialStyle.color(style.accent)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    editorialText(content, scale: scale)
                }
            }
            .accessibilityAction(named: Text(tr("Modifica il testo", "Edit Text")), beginEditing)
        }
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
                                   alignmentTargets: alignmentTargets, showsWidthHandles: true,
                                   onDoubleClick: { beginInlineBoxEditing(box.id, in: leaf) },
                                   onSelect: { activateCanvas { selectTextBox(box.id, in: leaf) } },
                                   onNudge: { nudgeFromKeyboard($0) { selectTextBox(box.id, in: leaf) } },
                                   onChange: { updateTextBoxFrame(box.id, on: leaf.id, to: PageRect($0, in: bounds)) }) { _ in
                Group {
                    if empty {
                        Text(label)
                            .font(.custom(style.bodyFont, size: max(9, style.bodySize * scale)))
                            .foregroundStyle(Color(cgColor: EditorialStyle.color(style.accent)))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    } else {
                        editorialText(PageComposition.boxText(box: box, book: book), scale: scale)
                    }
                }
                .padding(box.textInsetPoints * scale)
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
        let type = style.defaultBodyStyle.applying(book.bodyStyle(for: box))
        let font = type.fontName.flatMap { NSFont(name: $0, size: 12)?.fontName } ?? style.bodyFont
        let alignment: TextAlignment = type.alignment == .center ? .center : (type.alignment == .right ? .trailing : .leading)
        return TextEditor(text: textInBox(box.id, on: leaf.id))
            .font(.custom(font, size: max(1, (type.pointSize ?? style.bodySize) * scale)))
            .multilineTextAlignment(alignment)
            .foregroundStyle(Color(cgColor: EditorialStyle.color(style.ink)))
            .scrollContentBackground(.hidden)
            .focused($inlineBoxFocus, equals: box.id)
            .padding(max(0, box.textInsetPoints * scale - 4))
            .background(Color(cgColor: EditorialStyle.color(style.paper)))
            .overlay { Rectangle().strokeBorder(pine, lineWidth: 1.5).allowsHitTesting(false) }
            .onExitCommand(perform: endInlineTextEditing)
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
        let surface = EditorDropTarget.cover(front: side == .front)
        let activeCrop = thumbnail || cropSession?.surface != surface ? nil : cropSession
        let photoTargets = [page.titleFrame, page.band].compactMap { $0 }.map { scaled($0, by: scale) }
        let content = ZStack(alignment: .topLeading) {
            Color(cgColor: EditorialStyle.color(page.background))
            if let photo {
                if thumbnail {
                    positioned(preview(photo, small: true, crop: page.photoCrop, fills: page.fills),
                               in: scaled(page.photoFrame, by: scale))
                } else if activeCrop == nil {
                    coverPhotoControl(photo, side: side, geometry: page, bounds: bounds, scale: scale,
                                      targets: photoTargets)
                }
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
                    .allowsHitTesting(false)
            }
            if let rule = page.rule {
                positioned(Color(cgColor: EditorialStyle.color(book.editorialStyle.accent)), in: scaled(rule, by: scale))
            }
            if let title = page.titleFrame {
                if thumbnail {
                    positioned(editorialText(page.title, scale: scale), in: scaled(title, by: scale))
                } else {
                    coverEditorialText(side, geometry: page, frame: scaled(title, by: scale), bounds: bounds, scale: scale)
                }
            }
            if let activeCrop, let photo {
                canvasCrop(activeCrop, photo: photo, bounds: bounds, scale: scale, alignmentTargets: photoTargets)
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
                .accessibilityLabel(label)
                .overlayPreferenceValue(CanvasGuidePreference.self) { guides in
                    CanvasAlignmentGuides(guides: guides).allowsHitTesting(false)
                }
                .editorDropFrame(surface)
                .preference(key: CanvasHitMaps.self, value: [surface: .cover(
                    page, photoID: photo?.id, cropFrame: activeCrop?.frame.photoRect(in: page.bounds)
                )])
                .overlay {
                    if isPhotoDropTarget(.cover(front: side == .front)) {
                        Rectangle().strokeBorder(pine, lineWidth: 2).allowsHitTesting(false)
                    }
                }
        }
    }

    private func coverPhotoControl(_ photo: BookPhoto, side: CoverSide, geometry: BookCoverGeometry,
                                   bounds: CGRect, scale: CGFloat, targets: [CGRect]) -> some View {
        let active = canvasPhotoSelection?.surface == .cover(front: side == .front)
            && canvasPhotoSelection?.photoID == photo.id
        return CanvasObjectControl(frame: scaled(geometry.photoFrame, by: scale), bounds: bounds, selected: active,
                                   minimumSize: CGSize(width: 40 * scale, height: 40 * scale),
                                   accessibilityName: photo.name, alignmentTargets: targets,
                                   allowsPhotoOverflow: true, preservesAspectRatio: true,
                                   onDoubleClick: { beginCoverCrop(side) },
                                   onSelect: { activateCanvas { selectCoverPhoto(photo.id) } },
                                   onNudge: { nudgeFromKeyboard($0) { selectCoverPhoto(photo.id) } },
                                   onChange: { frame in
            changeCoverPhotoPlacement(side, name: tr("Sposta o ridimensiona foto", "Move or Resize Photo")) {
                $0.frame = PageRect(frame, in: bounds).photoClamped
            }
        }) { _ in
            preview(photo, crop: geometry.photoCrop, fills: geometry.fills)
        }
        .accessibilityAction(named: Text(tr("Ritaglia foto", "Crop Photo"))) { beginCoverCrop(side) }
    }

    private func coverEditorialText(_ side: CoverSide, geometry: BookCoverGeometry, frame: CGRect,
                                    bounds: CGRect, scale: CGFloat) -> some View {
        let style = book.editorialStyle
        let front = side == .front
        let defaults = front && book.template != nil ? style.defaultTitleStyle(mixed: false) : style.defaultBodyStyle
        let override = book.coverTextStyle(front: front)
        let value = coverEditorialValue(side)
        let type = defaults.applying(front && book.template != nil
            ? style.fittedTitleStyle(value.wrappedValue, width: frame.width / scale, mixed: false, override: override)
            : override)
        return editableEditorialObject(.cover(side), content: geometry.title, value: value,
                                       type: type, label: front ? tr("Titolo", "Title") : tr("Testo del retro", "Back Cover Text"),
                                       frame: frame, bounds: bounds, scale: scale,
                                       targets: [scaled(geometry.photoFrame.intersection(geometry.bounds), by: scale)],
                                       textInk: front ? style.titleInk : style.ink,
                                       onSelect: { selectEditorial(.cover(side)) },
                                       onChange: { moveCoverText(side, to: PageRect($0, in: bounds)) })
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
        InspectorHost(navigation: inspectorNavigation, title: tr("Ispettore", "Inspector"),
                      pageTitle: tr("Pagina", "Page"), photosTitle: tr("Foto", "Photos"),
                      filmTitle: tr("Pellicola", "Film"), edge: edge,
                      finishAdjustment: finishPhotoAdjustmentEdit, finishFilm: finishFilmEdit) { tab, photoMode in
            if tab == .photos {
                photoInspector(mode: photoMode)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 21) {
                        if tab == .page { pageInspector }
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
            let visiblePhotos = Set(pageComposition(page).photos.map(\.id))
            let waiting = page.photoIDs.count - visiblePhotos.count
            VStack(alignment: .leading, spacing: 7) {
                PageArrangementPicker(selection: page.arrangement, language: language,
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
                        intro(tr("Scegli una foto dalla libreria o trascinala nella pagina.",
                                 "Choose a photo from the library or drag it onto the page."))
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

    private func coverInspector(_ side: CoverSide) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            caption(coverName(side))
            if side == .front {
                TextField(tr("Titolo in copertina", "Cover Title"), text: Binding(
                    get: { book.cover?.title ?? book.title },
                    set: { value in changeCover { $0.title = value } }
                ))
                .textFieldStyle(.roundedBorder)
                .focused($writing)
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
            DisclosureGroup(tr("Tipografia", "Typography"), isExpanded: $coverTypographyExpanded) {
                let style = book.editorialStyle
                let front = side == .front
                let defaultStyle = front && book.template != nil ? style.defaultTitleStyle(mixed: false) : style.defaultBodyStyle
                EditorialTypographyControls(style: coverTextStyle(front ? \.title : \.body),
                                           inherited: defaultStyle.applying(front ? book.typography?.title : book.typography?.body),
                                           language: language, sampleText: coverEditorialValue(side).wrappedValue)
                    .padding(.top, 6)
                    .id(side)
                let face = BookCoverGeometry(book: book, front: front)
                if let frame = face.titleFrame, !EditorialTypesetter.fits(face.title, in: frame) {
                    typeOverflow(tr("Il testo supera lo spazio della copertina.", "The text exceeds the cover space."))
                }
            }
            if (side == .front ? book.cover?.frontTitleFrame : book.cover?.backTextFrame) != nil {
                Button(tr("Ripristina posizione del testo", "Reset Text Placement")) { moveCoverText(side, to: nil) }
            }
            if let photo = coverPhotoID(side).flatMap(indexedPhoto) {
                HStack(spacing: 8) {
                    preview(photo, small: true).frame(width: 38, height: 30).clipped()
                    Text(photo.name).font(.callout).lineLimit(1)
                }
                HStack {
                    Button(tr("Regola foto", "Adjust Photo")) {
                        selectCoverPhoto(photo.id)
                        photoPanelMode = .adjust
                        inspector = .photos
                    }
                    Button(tr("Pellicola", "Film")) {
                        selectCoverPhoto(photo.id)
                        inspector = .film
                    }
                }
                if coverPhotoPlacement(side) != nil {
                    Button(localized("editor.cover.reset_photo", fallback: "Reset Photo Placement and Crop")) {
                        changeCoverPhotoPlacement(side, name: tr("Ripristina foto di copertina", "Reset Cover Photo")) {
                            $0 = PhotoPlacement()
                        }
                    }
                }
            }
            Button(tr("Scegli foto", "Choose Photo"), systemImage: "photo.on.rectangle", action: browsePhotos)
            if book.cover == nil {
                Button(tr("Aggiungi copertina al libro", "Add Cover to Book")) { changeCover { _ in } }
            }
        }
    }

    private func pageTypography(_ leaf: BookPage, showsBody: Bool) -> some View {
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

    private func typeOverflow(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(Color(red: 0.61, green: 0.27, blue: 0.16))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func pageTextStyle(_ key: WritableKeyPath<EditorialTypography, EditorialTextStyle?>,
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

    private func coverTextStyle(_ key: WritableKeyPath<EditorialTypography, EditorialTextStyle?>)
        -> Binding<EditorialTextStyle?> {
        Binding(
            get: { book.cover?.typography?[keyPath: key] },
            set: { value in
                var type = book.cover?.typography ?? EditorialTypography()
                guard type[keyPath: key] != value else { return }
                type[keyPath: key] = value
                let previous = book.cover?.typography
                changeCover { $0.typography = type.title == nil && type.body == nil ? nil : type }
                if let undoManager {
                    undoTarget.registerCoverValue(undoManager, binding: $book, bookID: book.id, key: \.typography,
                                                  previous: previous, name: tr("Modifica tipografia", "Change Typography"))
                }
            }
        )
    }

    private func boxTextStyle(_ id: UUID, on pageID: UUID) -> Binding<EditorialTextStyle?> {
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

    private struct PhotoTransferDestination: Identifiable {
        let id: UUID
        let label: String
        let photoIDs: [UUID]
    }

    private func photoTransferDestinations(excluding source: UUID) -> [PhotoTransferDestination] {
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

    @ViewBuilder private func photoTransferMenu(_ photo: UUID, from source: UUID,
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

    private var suggestions: some View {
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

    private func analysisEvidence(_ evidence: PhotoMatchEvidence) -> String {
        switch evidence.source {
        case "concept": conceptName(evidence.value)
        case "text": tr("Testo nella foto", "Text in photo") + " · " + evidence.value
        default: conceptName(evidence.value)
        }
    }

    private func photoInspector(mode: PhotoPanelMode) -> some View {
        VStack(spacing: 0) {
            Picker(tr("Pannello foto", "Photo Panel"), selection: Binding(
                get: { photoPanelMode }, set: { photoPanelMode = $0 }
            )) {
                Text(tr("Libreria", "Library")).tag(PhotoPanelMode.library)
                Text(tr("Regola", "Adjust")).tag(PhotoPanelMode.adjust)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .padding(.horizontal, 15)
            .padding(.top, 11)
            photoDropZone.padding(.horizontal, 15).padding(.top, 8)
            if mode == .adjust {
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
        .background(pine.opacity(hoveringPhotoDrop || hoveringPhotoPromise ? 0.06 : 0))
        .contentShape(Rectangle())
        .onDrop(of: [UTType.fileURL, UTType.image], isTargeted: $hoveringPhotoDrop) { providers in
            acceptPhotoDrop(onDropPhotos(providers, { importedPhotoToReveal = $0 }))
        }
        .overlay {
            if hoveringPhotoDrop || hoveringPhotoPromise {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(pine, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .padding(5)
                    .overlay {
                        Label(tr("Rilascia per aggiungere", "Drop to Add"), systemImage: "photo.badge.plus")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(pine)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(paper, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .onDisappear { hoveringPhotoPromise = false }
    }

    private var photoDropZone: some View {
        Label(tr("Trascina foto qui", "Drop Photos Here"), systemImage: "photo.badge.plus")
            .font(.caption.weight(.medium))
            .foregroundStyle(pine)
            .frame(maxWidth: .infinity, minHeight: 27)
            .background(pine.opacity(0.045), in: RoundedRectangle(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(pine.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .allowsHitTesting(false)
            }
            .overlay {
                PhotoPromiseDropTarget(onTargeted: { hoveringPhotoPromise = $0 }) { promises in
                    acceptPhotoDrop(onDropPhotoPromises(promises, { importedPhotoToReveal = $0 }))
                }
                .accessibilityHidden(true)
            }
    }

    private func acceptPhotoDrop(_ accepted: Bool) -> Bool {
        guard accepted else { return false }
        search = ""
        concept = nil
        photoPanelMode = .library
        return true
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
        let results = photoLibraryCache.results(photos: book.photos, language: language, search: search, concept: concept)
        let photoLocations = photoUsageIndex.locations(in: book)
        let sections = libraryOrdering.groups(
            for: results.photos, order: photoOrder, locale: Locale(identifier: language),
            places: placesRead, used: photoOrder == .usage ? Set(photoLocations.keys) : []
        )
        let pendingPlaces = placeAssetsToRead
        let needsAnalysis = book.photos.contains { ($0.analysis?.revision ?? 0) < PhotoAnalysis.currentRevision }
        let hasOlderAnalysis = book.photos.contains { $0.analysis.map { $0.revision < PhotoAnalysis.currentRevision } == true }
        return VStack(alignment: .leading, spacing: 13) {
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
                        Label(hasOlderAnalysis ? tr("Aggiorna analisi", "Update analysis") : tr("Analizza foto", "Analyze photos"),
                              systemImage: "viewfinder")
                    }
                    .disabled(isAnalyzing || !needsAnalysis)
                }
                if !book.photos.isEmpty {
                    TextField(tr("Cerca foto", "Search photos"), text: $search)
                        .textFieldStyle(.roundedBorder)
                        .focused($searchingPhotos)
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.arrow.down")
                            .foregroundStyle(muted)
                            .accessibilityHidden(true)
                        Picker(libraryLabel("sort", "Ordina per", "Sort by"), selection: $photoOrder) {
                            ForEach(PhotoLibraryOrder.allCases) { order in
                                Text(photoOrderLabel(order)).tag(order)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .help(libraryLabel("sort", "Ordina per", "Sort by"))
                        if !pendingPlaces.isEmpty {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityLabel(libraryLabel("reading_places", "Lettura dei luoghi", "Reading locations"))
                        }
                    }
                    conceptFilter(results.concepts)
                }
            }
            .padding(.horizontal, 15)
            .padding(.top, 15)
            if !book.photos.isEmpty {
                ScrollViewReader { scroll in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            Color.clear.frame(height: 0).id("photoLibraryTop").accessibilityHidden(true)
                            photoGrid(sections, locations: photoLocations)
                        }
                        .padding(.horizontal, 15)
                        .padding(.bottom, 8)
                    }
                    .onChange(of: photoOrder) { _, _ in scroll.scrollTo("photoLibraryTop", anchor: .top) }
                    .task(id: importedPhotoToReveal) {
                        guard let id = importedPhotoToReveal else { return }
                        await Task.yield()
                        guard !Task.isCancelled else { return }
                        scroll.scrollTo(id, anchor: .center)
                        importedPhotoToReveal = nil
                    }
                }
                .frame(maxHeight: .infinity)
                // Native photo hit testing reads these frames without updating the editor.
                .libraryPhotoFrame()
                .onPreferenceChange(LibraryPhotoFrames.self) { libraryHitFrames.frames = $0 }
                .onDisappear { libraryHitFrames.frames = .init() }
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
                intro(tr("Il libro non contiene ancora foto.", "This book doesn’t have any photos yet."))
                    .padding(.horizontal, 15)
                Spacer(minLength: 0)
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .task(id: pendingPlaces) { await readPhotoPlaces(pendingPlaces) }
    }

    private var placeAssetsToRead: [PlaceAsset] {
        guard photoOrder == .place else { return [] }
        return book.photos.compactMap { photo in
            guard photo.location == nil else { return nil }
            let asset = PlaceAsset(id: photo.id, filename: photo.filename, sourceID: photo.sourceID)
            return scannedPlaceAssets.contains(asset) ? nil : asset
        }
    }

    private func readPhotoPlaces(_ pending: [PlaceAsset]) async {
        guard !pending.isEmpty else { return }
        let directory = directory
        let work = Task.detached(priority: .utility) {
            var locations: [UUID: PhotoLocation] = [:]
            for asset in pending {
                if Task.isCancelled { return locations }
                if let location = LocalImages.location(at: BookStorage.assetURL(filename: asset.filename, in: directory)) {
                    locations[asset.id] = location
                }
            }
            let missing = pending.filter { locations[$0.id] == nil }
            let fromPhotos = PhotoLibrary.locations(for: missing.compactMap(\.sourceID))
            for asset in missing {
                locations[asset.id] = asset.sourceID.flatMap { fromPhotos[$0] }
            }
            return locations
        }
        let locations = await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }
        guard !Task.isCancelled else { return }
        placesRead.merge(locations, uniquingKeysWith: { _, latest in latest })
        scannedPlaceAssets.formUnion(pending)
    }

    private func libraryLabel(_ key: String, _ italian: String, _ english: String) -> String {
        localized("editor.photo_library." + key, fallback: tr(italian, english))
    }

    private func photoOrderLabel(_ order: PhotoLibraryOrder) -> String {
        switch order {
        case .date: libraryLabel("date", "Data", "Date")
        case .place: libraryLabel("place", "Luogo", "Place")
        case .subject: libraryLabel("subject", "Argomento", "Subject")
        case .usage: libraryLabel("usage", "Non usate prima", "Unused First")
        }
    }

    private func photoSectionTitle(_ section: PhotoLibraryOrdering.Section.Key) -> String {
        let locale = Locale(identifier: language)
        switch section {
        case let .day(day):
            return day.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale))
        case let .place(name):
            return name
        case let .area(lat, lon):
            let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(2)).locale(locale)
            let latitude = (Double(abs(lat)) / 20).formatted(format) + (lat < 0 ? "° S" : "° N")
            let longitude = (Double(abs(lon)) / 20).formatted(format) + (lon < 0 ? "° " + tr("O", "W") : "° E")
            return latitude + " · " + longitude
        case let .subject(topic):
            return conceptName(topic)
        case .unused:
            return libraryLabel("unused", "Non usate", "Unused")
        case .used:
            return libraryLabel("used", "Già usate", "Already Used")
        case .unknown:
            switch photoOrder {
            case .date: return libraryLabel("unknown_date", "Senza data", "No Date")
            case .place: return libraryLabel("unknown_place", "Senza luogo", "No Location")
            case .subject, .usage: return libraryLabel("unknown_subject", "Senza argomento", "No Subject")
            }
        }
    }

    private func conceptFilter(_ concepts: [InspectorPhotoLibraryCache.Concept]) -> some View {
        Picker(tr("Concetto", "Concept"), selection: $concept) {
            Text(tr("Tutti i concetti", "All concepts")).tag(nil as String?)
            ForEach(concepts) { item in
                Text(item.name + " · " + String(item.count)).tag(Optional(item.id))
            }
        }
        .labelsHidden()
        .disabled(concepts.isEmpty)
    }

    private func selectedPhotoDetails(_ photo: BookPhoto) -> some View {
        let assigned = isOnCurrentPage(photo.id)
        return VStack(alignment: .leading, spacing: 6) {
            Text(photo.name).font(.system(size: 12, weight: .semibold)).lineLimit(2)
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

    private func photoAnalysisDetails(_ analysis: PhotoAnalysis) -> some View {
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

    private func photoGrid(_ sections: [PhotoLibraryOrdering.Section],
                           locations: [UUID: [PhotoUsageIndex.Location]]) -> some View {
        let assigned = Set(coverSide.map { [coverPhotoID($0)].compactMap { $0 } } ?? page?.photoIDs ?? [])
        return LazyVStack(alignment: .leading, spacing: 11) {
            if sections.isEmpty { intro(tr("Nessuna foto corrispondente.", "No matching photos.")) }
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 6) {
                    Text(photoSectionTitle(section.id))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(muted)
                        .accessibilityAddTraits(.isHeader)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 67), spacing: 7)], spacing: 7) {
                        ForEach(section.photos) { photo in
                            photoLibraryTile(photo, used: assigned.contains(photo.id), locations: locations[photo.id] ?? [])
                        }
                    }
                }
            }
        }
    }

    private func photoLibraryTile(_ photo: BookPhoto, used: Bool, locations: [PhotoUsageIndex.Location]) -> some View {
        let active = photo.id == selectedPhoto
        let usage = locations.map(usageDescription).joined(separator: ", ")
        return preview(photo, small: true)
            .frame(height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(alignment: .bottomTrailing) {
                if let first = locations.first {
                    let additional = locations.count - 1
                    Text(usageBadge(first) + (additional > 0 ? " +\(additional)" : ""))
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(used ? pine : .black.opacity(0.80), in: Capsule())
                        .padding(3)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 4).strokeBorder(active ? pine : .clear, lineWidth: 2)
            }
            .contentShape(Rectangle())
            .gesture(editorDrag(.photo(photo.id)))
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                selectLibraryPhoto(photo.id)
                togglePhoto(photo.id)
            })
            .help(usage.isEmpty ? photo.name : photo.name + "\n" + usage)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(photo.name)
            .accessibilityValue(usage)
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(active ? .isSelected : [])
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
            .libraryPhotoFrame(photo.id)
            .id(photo.id)
    }

    private func usageBadge(_ location: PhotoUsageIndex.Location) -> String {
        switch location {
        case let .page(numbers):
            numbers.lowerBound == numbers.upperBound ? "\(numbers.lowerBound)" : "\(numbers.lowerBound)–\(numbers.upperBound)"
        case .frontCover:
            tr("C", "F")
        case .backCover:
            tr("R", "B")
        }
    }

    private func usageDescription(_ location: PhotoUsageIndex.Location) -> String {
        switch location {
        case let .page(numbers):
            (numbers.lowerBound == numbers.upperBound ? tr("Pagina", "Page") : tr("Pagine", "Pages"))
                + " " + usageBadge(location)
        case .frontCover:
            coverName(.front)
        case .backCover:
            coverName(.back)
        }
    }

    private func selectLibraryPhoto(_ id: UUID) {
        endInlineTextEditing()
        canvasPhotoSelection = nil
        selectedPhoto = id
        selectedBox = nil
        selectedEditorial = nil
    }

    private func browsePhotos() {
        showsInspector = true
        photoPanelMode = .library
        inspector = .photos
    }

    private func selectObject(at point: CGPoint) {
        let insideCanvas = dropFrames[.canvasViewport]?.contains(point) == true
        canvasInput.ownsKeyboard = insideCanvas
        guard insideCanvas else {
            if inspector == .photos, photoPanelMode == .library,
               let id = libraryHitFrames.frames.photo(at: point) {
                selectLibraryPhoto(id)
            }
            return
        }
        if let coverSide {
            switch canvasTarget(at: point, on: .cover(front: coverSide == .front)) {
            case let .photo(id): selectCoverPhoto(id)
            case .coverText:
                if editingEditorial != .cover(coverSide) { selectEditorial(.cover(coverSide)) }
            case .crop: break
            default: clearCanvasSelection()
            }
            return
        }
        for surface in canvasHits.maps.keys {
            guard case let .canvasPage(id) = surface, let target = canvasTarget(at: point, on: surface),
                  let leaf = id == page?.id ? page : book.pages.first(where: { $0.id == id }) else { continue }
            switch target {
            case let .photo(photoID): selectCanvasPhoto(photoID, in: leaf)
            case let .textBox(boxID):
                if inlineEditingBox != boxID { selectTextBox(boxID, in: leaf) }
            case let .story(role):
                let object = EditorialObject.page(id, role)
                if editingEditorial != object { selectEditorial(object, on: leaf) }
            case .storyGroup: selectEditorial(.storyGroup(id), on: leaf)
            case .paper:
                select(leaf)
                clearCanvasSelection()
            case .coverText, .crop: break
            }
            return
        }
        clearCanvasSelection()
    }

    private func canvasTarget(at point: CGPoint, on surface: EditorDropTarget) -> CanvasHitMap.Target? {
        guard let frame = dropFrames[surface] else { return nil }
        return canvasHits.maps[surface]?.target(at: point, in: frame)
    }

    private func clearCanvasSelection() {
        finishCrop()
        endInlineTextEditing()
        selectedPhoto = nil
        canvasPhotoSelection = nil
        selectedBox = nil
        selectedEditorial = nil
        writing = false
        writingBox = false
        searchingPhotos = false
        filmScope = .book
    }

    private func deselectCanvas() -> Bool {
        guard canvasInput.ownsKeyboard else { return false }
        if cropSession != nil {
            cropSession = nil
            return true
        }
        if inlineEditingBox != nil || editingEditorial != nil {
            endInlineTextEditing()
            return true
        }
        guard selectedPhoto != nil || selectedBox != nil || selectedEditorial != nil else { return false }
        clearCanvasSelection()
        return true
    }

    private func activateCanvas(_ select: () -> Void) {
        canvasInput.ownsKeyboard = true
        select()
    }

    private func nudgeFromKeyboard(_ offset: CGSize, selecting: () -> Void) -> Bool {
        activateCanvas(selecting)
        return nudgeCanvasSelection(offset)
    }

    private func nudgeCanvasSelection(_ offset: CGSize) -> Bool {
        guard canvasInput.ownsKeyboard, cropSession == nil, inlineEditingBox == nil, editingEditorial == nil
        else { return false }
        if let side = coverSide, let selection = canvasPhotoSelection,
           selection.surface == .cover(front: side == .front),
           let map = canvasHits.maps[selection.surface],
           let frame = map.regions.last(where: { $0.target == .photo(selection.photoID) })?.frame {
            let limits = CanvasPhotoGeometry.movementBounds(for: frame.size, in: map.bounds)
            let moved = CanvasPhotoGeometry.moved(frame, by: offset, within: limits)
            if moved != frame {
                changeCoverPhotoPlacement(side, name: tr("Sposta foto di copertina", "Move Cover Photo")) {
                    $0.frame = PageRect(moved, in: map.bounds).photoClamped
                }
            }
            return true
        }
        if let coverSide, selectedEditorial == .cover(coverSide),
           let map = canvasHits.maps[.cover(front: coverSide == .front)],
           let frame = map.regions.last(where: { $0.target == .coverText })?.frame {
            let moved = CanvasPhotoGeometry.moved(frame, by: offset, within: map.bounds)
            if moved != frame { moveCoverText(coverSide, to: PageRect(moved, in: map.bounds)) }
            return true
        }
        guard let page, let map = canvasHits.maps[.canvasPage(page.id)] else { return false }
        if selectedEditorial == .storyGroup(page.id) {
            moveStoryGroup(on: page.id, by: offset)
            return true
        }
        if let selectedBox, let frame = map.regions.last(where: { $0.target == .textBox(selectedBox) })?.frame {
            let moved = CanvasPhotoGeometry.moved(frame, by: offset, within: map.bounds)
            if moved != frame { updateTextBoxFrame(selectedBox, on: page.id, to: PageRect(moved, in: map.bounds)) }
            return true
        }
        if case let .page(id, role)? = selectedEditorial, id == page.id,
           let frame = map.regions.last(where: { $0.target == .story(role) })?.frame {
            let moved = CanvasPhotoGeometry.moved(frame, by: offset, within: map.bounds)
            if moved != frame { movePageText(role, on: page.id, to: PageRect(moved, in: map.bounds)) }
            return true
        }
        if let selection = canvasPhotoSelection, selection.pageID == page.id,
           let frame = map.regions.last(where: { $0.target == .photo(selection.photoID) })?.frame {
            let limits = CanvasPhotoGeometry.movementBounds(for: frame.size, in: map.bounds)
            let moved = CanvasPhotoGeometry.moved(frame, by: offset, within: limits)
            if moved != frame { updatePhotoFrame(selection.photoID, in: page, to: PageRect(moved, in: map.bounds)) }
            return true
        }
        return false
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
                            finishFilmEdit()
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
                filmLUTMenu
                if let lutImportError {
                    Text(lutImportError).font(.callout).foregroundStyle(.secondary)
                    Button(tr("Chiudi avviso", "Dismiss Message")) { self.lutImportError = nil }
                        .buttonStyle(.link)
                }
                if currentFilm.preset == .custom,
                   let selected = currentFilm.lutFilename.flatMap(FujifilmFilmLook.importedLook) {
                    intro(fujifilmInputDescription(selected.input))
                }
            }
            .disabled(filmScope == .photo && filmPhoto == nil)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                filmSlider(tr("Intensità", "Intensity"), value: \.strength)
                    .disabled(currentFilm.preset == .original)
                filmSlider(tr("Grana", "Grain"), value: \.grain)
                filmSlider(tr("Dimensione grana", "Grain size"), value: \.grainSize)
                    .disabled(currentFilm.grain == 0)
            }
            .disabled(filmScope == .photo && filmPhoto == nil)
            Divider()
            Toggle(tr("Confronta con l’originale", "Compare with original"), isOn: $compareOriginal)
                .disabled(book.photos.isEmpty)
        }
    }

    private var filmLUTMenu: some View {
        let filename = currentFilm.lutFilename
        let builtIn = filename.flatMap(FujifilmFilmLook.importedLook)
        let name = builtIn?.name ?? filename.map(filmLUTName)
        let active = currentFilm.preset == .custom
        let prompt = localized("editor.lut.choose", fallback: "Choose LUT")
        let title = active ? name ?? prompt : prompt
        return Menu {
            if let filename, builtIn == nil {
                Button {
                    setFilm {
                        $0.preset = .custom
                        $0.lutFilename = filename
                    }
                } label: {
                    if active {
                        Label(name ?? filename, systemImage: "checkmark")
                    } else {
                        Text(name ?? filename)
                    }
                }
                Divider()
            }
            if let resources = Bundle.main.resourceURL, let sample = FujifilmFilmLook.all.first,
               (try? sample.url(in: resources).checkResourceIsReachable()) == true {
                Section(tr("Da Provia", "From Provia")) {
                    fujifilmLooks(.provia, selected: active ? builtIn : nil, resources: resources)
                }
                Section(tr("Base a contrasto lineare", "Linear-Contrast Input")) {
                    fujifilmLooks(.linear, selected: active ? builtIn : nil, resources: resources)
                }
                Link(tr("Fonte e licenza", "Source and License"),
                     destination: URL(string: "https://github.com/abpy/FujifilmCameraProfiles#licensing")!)
                Divider()
            }
            Button(action: importFilmLUT) {
                Label(tr("Importa LUT…", "Import LUT…"), systemImage: "square.and.arrow.down")
            }
        } label: {
            Label {
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(systemName: "camera.filters")
            }
        }
        .help(title)
        .accessibilityLabel(prompt)
        .accessibilityValue(active ? name ?? "" : "")
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

    private var filmTarget: FilmTarget? {
        if filmScope == .book { return .book }
        return filmPhoto.map { .photo($0.id) }
    }

    private func filmSlider(_ label: String, value: WritableKeyPath<FilmSettings, Double>) -> some View {
        FilmSlider(label: label, value: value, target: filmTarget, committed: currentFilm, edit: filmEdit,
                   change: { amount in updateFilmDraft(value, to: amount) },
                   editingChanged: { editing in
            finishFilmEdit()
            if editing, let target = filmTarget {
                filmEdit.start(bookID: book.id, target: target, settings: currentFilm)
            }
        })
    }

    private func updateFilmDraft(_ key: WritableKeyPath<FilmSettings, Double>, to amount: Double) {
        guard filmEdit.target == filmTarget, let draft = filmEdit.draft else {
            setFilm { $0[keyPath: key] = amount }
            return
        }
        guard draft[keyPath: key] != amount else { return }
        filmEdit.draft?[keyPath: key] = amount
        guard filmPreviewTask == nil else { return }
        filmPreviewTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(55)) } catch { return }
            filmPreviewTask = nil
            if filmEdit.preview != filmEdit.draft { filmEdit.preview = filmEdit.draft }
        }
    }

    private func finishFilmEdit() {
        filmPreviewTask?.cancel()
        filmPreviewTask = nil
        guard let target = filmEdit.target, let draft = filmEdit.draft else { return }
        let shouldCommit = filmEdit.bookID == book.id && draft != filmEdit.initial
        filmEdit.clear()
        if shouldCommit { commitFilm(draft, to: target) }
    }

    private func setFilm(_ edit: (inout FilmSettings) -> Void) {
        finishFilmEdit()
        guard let target = filmTarget else { return }
        let previous = currentFilm
        var settings = previous
        edit(&settings)
        if settings != previous { commitFilm(settings, to: target) }
    }

    private func commitFilm(_ settings: FilmSettings, to target: FilmTarget) {
        switch target {
        case .book:
            let previous = book.film
            guard settings != previous else { return }
            book.film = settings
            if let undoManager {
                undoTarget.registerBookFilm(undoManager, binding: $book, bookID: book.id, previous: previous,
                                            name: tr("Modifica pellicola", "Change Film Look"))
            }
        case let .photo(id):
            setPhotoFilm(settings, for: id)
        }
    }

    private func setPhotoFilm(_ settings: FilmSettings?, for id: UUID) {
        guard let index = photoIndex(id) else { return }
        let previous = book.photos[index].film
        guard settings != previous else { return }
        book.photos[index].film = settings
        if let undoManager {
            undoTarget.registerPhotoValue(undoManager, binding: $book, bookID: book.id, photoID: id,
                                         key: \.film, previous: previous, name: tr("Modifica pellicola", "Change Film Look"))
        }
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
            undoTarget.registerPhotoValue(undoManager, binding: $book, bookID: book.id,
                                         photoID: id, key: \.adjustments, previous: previous, name: name)
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
                                           adjustments: original ? nil : corrections,
                                           isFilmSwatch: settings != nil)
        return EditorPreview(request: request, crop: crop, fills: fills,
                             filmEdit: !small && settings == nil && !original ? filmEdit : nil,
                             photoID: photo.id, inheritsBookFilm: photo.film == nil) {
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
        book.pages.reduce(0) { $0 + ($1.effectiveLayout == .fullSpread ? 2 : 1) }
    }

    private func number(of leaf: BookPage) -> Int {
        book.pages.prefix { $0.id != leaf.id }.reduce(1) { $0 + ($1.effectiveLayout == .fullSpread ? 2 : 1) }
    }

    private func spreadNumber(_ spread: [BookPage]) -> String {
        guard let first = spread.first, let last = spread.last else { return "" }
        let start = number(of: first)
        let end = number(of: last) + (last.effectiveLayout == .fullSpread ? 1 : 0)
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

    private func localized(_ key: String, fallback: String) -> String {
        let bundle = Bundle.main.url(forResource: language, withExtension: "lproj").flatMap(Bundle.init(url:))
        return (bundle ?? .main).localizedString(forKey: key, value: fallback, table: nil)
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
        endInlineTextEditing()
        coverSide = side
        coverTypographyExpanded = false
        canvasPhotoSelection = nil
        selectedPhoto = nil
        selectedBox = nil
        selectedEditorial = nil
        writing = false
        writingBox = false
        filmScope = .book
        inspector = .page
    }

    private func selectCoverPhoto(_ id: UUID) {
        endInlineTextEditing()
        writing = false
        writingBox = false
        selectedPhoto = id
        selectedBox = nil
        selectedEditorial = nil
        if let coverSide {
            canvasPhotoSelection = CanvasPhotoSelection(surface: .cover(front: coverSide == .front), photoID: id)
        }
        searchingPhotos = false
        filmScope = .photo
    }

    private func changeCover(_ change: (inout BookCover) -> Void) {
        var cover = book.cover ?? BookCover(title: book.title)
        change(&cover)
        book.cover = cover
    }

    private func coverPlacementKey(_ side: CoverSide) -> WritableKeyPath<BookCover, PhotoPlacement?> {
        side == .front ? \.frontPhotoPlacement : \.backPhotoPlacement
    }

    private func coverPhotoPlacement(_ side: CoverSide) -> PhotoPlacement? {
        book.cover?[keyPath: coverPlacementKey(side)]
    }

    private func changeCoverPhotoPlacement(_ side: CoverSide, name: String,
                                           _ edit: (inout PhotoPlacement) -> Void) {
        let key = coverPlacementKey(side)
        let previous = coverPhotoPlacement(side)
        var placement = previous ?? PhotoPlacement()
        edit(&placement)
        let next = placement == PhotoPlacement() ? nil : placement
        guard next != previous else { return }
        changeCover { $0[keyPath: key] = next }
        if let undoManager {
            undoTarget.registerCoverValue(undoManager, binding: $book, bookID: book.id, key: key, previous: previous, name: name)
        }
    }

    private func setCoverPhoto(_ id: UUID?, side: CoverSide) {
        finishCrop()
        let key: WritableKeyPath<BookCover, UUID?> = side == .front ? \.frontPhotoID : \.backPhotoID
        let placement = coverPlacementKey(side)
        let previous = CoverImage(id: coverPhotoID(side), placement: coverPhotoPlacement(side))
        if previous.id != id {
            changeCover {
                $0[keyPath: key] = id
                $0[keyPath: placement] = nil
            }
            if let undoManager {
                undoTarget.registerCoverImage(undoManager, binding: $book, bookID: book.id,
                                             idKey: key, placementKey: placement, previous: previous,
                                             name: id == nil ? tr("Rimuovi foto di copertina", "Remove Cover Photo")
                                                 : tr("Imposta foto di copertina", "Set Cover Photo"))
            }
        }
        if let id { selectCoverPhoto(id) }
        else { clearCanvasSelection() }
    }

    private func select(_ leaf: BookPage) {
        if cropSession?.surface != .canvasPage(leaf.id) { finishCrop() }
        if coverSide != nil || leaf.id != page?.id {
            endInlineTextEditing()
            canvasPhotoSelection = nil
            selectedPhoto = nil
            selectedBox = nil
            selectedEditorial = nil
            filmScope = .book
            writing = false
            writingBox = false
        }
        coverSide = nil
        selection = leaf.id
    }

    private func selectCanvasPhoto(_ id: UUID, in leaf: BookPage) {
        if cropSession?.surface != .canvasPage(leaf.id) || cropSession?.photoID != id { finishCrop() }
        endInlineTextEditing()
        select(leaf)
        searchingPhotos = false
        selectedBox = nil
        selectedEditorial = nil
        selectedPhoto = id
        canvasPhotoSelection = CanvasPhotoSelection(surface: .canvasPage(leaf.id), photoID: id)
        if inspector == .film {
            filmScope = .photo
        }
    }

    private func selectTextBox(_ id: UUID, in leaf: BookPage) {
        finishCrop()
        if inlineEditingBox != id { endInlineTextEditing() }
        select(leaf)
        selectedBox = id
        selectedEditorial = nil
        canvasPhotoSelection = nil
        selectedPhoto = nil
        inspector = .page
    }

    private func beginInlineBoxEditing(_ id: UUID, in leaf: BookPage) {
        selectTextBox(id, in: leaf)
        writing = false
        writingBox = false
        inlineEditingBox = id
    }

    private func endInlineTextEditing() {
        if inlineEditingBox != nil || inlineBoxFocus != nil {
            inlineEditingBox = nil
            inlineBoxFocus = nil
        }
        if editingEditorial != nil || editorialFocus != nil {
            editingEditorial = nil
            editorialFocus = nil
        }
    }

    private func selectEditorial(_ object: EditorialObject, on leaf: BookPage? = nil) {
        finishCrop()
        if editingEditorial != object { endInlineTextEditing() }
        if let leaf { select(leaf) }
        selectedEditorial = object
        if case .cover = object { coverTypographyExpanded = true }
        selectedBox = nil
        selectedPhoto = nil
        canvasPhotoSelection = nil
        searchingPhotos = false
        writing = false
        writingBox = false
        inspector = .page
    }

    private func pageEditorialText(_ role: PageComposition.TextRole, on pageID: UUID) -> Binding<String> {
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

    private func coverEditorialValue(_ side: CoverSide) -> Binding<String> {
        Binding(
            get: { side == .front ? book.cover?.title ?? book.title : book.cover?.backText ?? "" },
            set: { value in
                changeCover {
                    if side == .front { $0.title = value }
                    else { $0.backText = value.isEmpty ? nil : value }
                }
            }
        )
    }

    private func movePageText(_ role: PageComposition.TextRole, on pageID: UUID, to frame: PageRect) {
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

    private func moveStoryGroup(on pageID: UUID, by translation: CGSize) {
        guard let index = book.pages.firstIndex(where: { $0.id == pageID }) else { return }
        let leaf = book.pages[index]
        let composition = pageComposition(leaf)
        let blocks = composition.storyBlocks(page: leaf, book: book)
        let backings = composition.storyBackgroundFrames(page: leaf, blocks: blocks)
        editPages(tr("Sposta blocco di testo", "Move Story Group")) { pages in
            pages[index].moveStoryGroup(by: translation, blocks: blocks, backdrops: backings, in: composition.bounds)
        }
    }

    private func moveCoverText(_ side: CoverSide, to frame: PageRect?) {
        let key: WritableKeyPath<BookCover, PageRect?> = side == .front ? \.frontTitleFrame : \.backTextFrame
        let previous = book.cover?[keyPath: key]
        let next = frame?.clamped
        guard previous != next else { return }
        changeCover { $0[keyPath: key] = next }
        if let undoManager {
        undoTarget.registerCoverValue(undoManager, binding: $book, bookID: book.id, key: key, previous: previous,
                                          name: tr("Sposta o ridimensiona testo", "Move or Resize Text"))
        }
    }

    private func setLayout(_ layout: PageLayout) {
        finishCrop()
        guard let index, book.pages[index].layout != layout || book.pages[index].arrangement != nil else { return }
        editPages(tr("Cambia composizione", "Change Layout")) { pages in
            pages[index].layout = layout
            pages[index].arrangement = nil
        }
    }

    private func applyPageArrangement(_ arrangement: PageArrangement?, to pageID: UUID) {
        finishCrop()
        endInlineTextEditing()
        guard let index = book.pages.firstIndex(where: { $0.id == pageID }) else { return }
        editPages(tr("Cambia modello della pagina", "Change Page Template")) { pages in
            pages[index].arrangement = arrangement
            if let arrangement {
                pages[index].layout = arrangement.layout
                pages[index].photoPlacements = Self.photoCrops(from: pages[index].photoPlacements)
            }
        }
        if let selection = canvasPhotoSelection, selection.pageID == pageID,
           !pageComposition(book.pages[index]).photos.contains(where: { $0.id == selection.photoID }) {
            canvasPhotoSelection = nil
            selectedPhoto = nil
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

    private func insertPageHeading() {
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
        endInlineTextEditing()
        editPages(tr("Elimina pagina", "Delete Page")) { $0.remove(at: index) }
        selection = book.pages.isEmpty ? nil : book.pages[min(index, book.pages.count - 1)].id
        selectedPhoto = nil
        selectedBox = nil
        selectedEditorial = nil
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
                activateCanvas { setCoverPhoto(id, side: coverSide) }
            }
        } else {
            for leaf in book.pages {
                guard let rect = dropFrames[.canvasPage(leaf.id)], rect.contains(location) else { continue }
                let local = CGPoint(x: location.x - rect.minX, y: location.y - rect.minY)
                activateCanvas {
                    dropPhoto(id, on: leaf, at: local, in: CGRect(origin: .zero, size: rect.size))
                }
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
                                        bounds: CGRect, textFrames: [CGRect]) -> IncomingPhotoPlacement? {
        guard let dragging, case let .photo(id) = dragging.item, let photo = indexedPhoto(id),
              isPhotoDropTarget(.canvasPage(leaf.id)), let screenFrame = dropFrames[.canvasPage(leaf.id)] else { return nil }
        let location = CGPoint(x: dragging.location.x - screenFrame.minX, y: dragging.location.y - screenFrame.minY)
        if let target = photoSwapTarget(id, at: location, in: bounds, composition: composition, textFrames: textFrames) {
            return .swap(target)
        }
        return .position(photoPlacement(photo, in: composition, at: location, bounds: bounds))
    }

    private func photoSwapTarget(_ id: UUID, at point: CGPoint, in bounds: CGRect,
                                 composition: PageComposition, textFrames: [CGRect]) -> CanvasPhotoSwap.Target? {
        guard !NSEvent.modifierFlags.contains(.option) else { return nil }
        return CanvasPhotoSwap.target(moving: id, at: point, in: bounds, composition: composition, storyFrames: textFrames)
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
        let blocks = composition.storyBlocks(page: current, book: book)
        let textFrames = blocks.map(\.frame) + composition.storyBackgroundFrames(page: current, blocks: blocks)
        if let target = photoSwapTarget(id, at: location, in: bounds, composition: composition, textFrames: textFrames) {
            swapPhoto(id, with: target.id, on: leaf.id)
            return
        }
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

    private func swapPhoto(_ id: UUID, with target: UUID, on pageID: UUID) {
        guard let index = book.pages.firstIndex(where: { $0.id == pageID }) else { return }
        var leaf = book.pages[index]
        guard leaf.swapPhotos(id, target, in: pageComposition(leaf)) else { return }
        editPages(tr("Scambia foto", "Swap Photos")) { $0[index] = leaf }
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
            pages[index].photoPlacements = Self.photoCrops(from: placements)
            if pages[index].arrangement == nil, pages[index].layout == .text, !pages[index].photoIDs.isEmpty {
                pages[index].layout = .mixed
            }
        }
    }

    private static func photoCrops(from placements: [UUID: PhotoPlacement]?) -> [UUID: PhotoPlacement]? {
        let crops = placements?.compactMapValues { $0.crop.map { PhotoPlacement(crop: $0) } } ?? [:]
        return crops.isEmpty ? nil : crops
    }

    private func beginCrop(_ photoID: UUID, in leaf: BookPage) {
        finishCrop()
        guard let current = book.pages.first(where: { $0.id == leaf.id }) else { return }
        let composition = pageComposition(current)
        guard let item = composition.photos.first(where: { $0.id == photoID }) else { return }
        selectCanvasPhoto(photoID, in: current)
        let frame = PageRect(item.frame, in: composition.bounds)
        cropSession = CropSession(surface: .canvasPage(leaf.id), photoID: photoID, initialFrame: frame,
                                  initialCrop: item.crop,
                                  frame: frame, crop: item.crop)
    }

    private func beginCoverCrop(_ side: CoverSide) {
        finishCrop()
        guard let id = coverPhotoID(side) else { return }
        let geometry = BookCoverGeometry(book: book, front: side == .front)
        selectCoverPhoto(id)
        let frame = PageRect(geometry.photoFrame, in: geometry.bounds)
        cropSession = CropSession(surface: .cover(front: side == .front), photoID: id, initialFrame: frame,
                                  initialCrop: geometry.photoCrop, frame: frame, crop: geometry.photoCrop)
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
        guard changedFrame || changedCrop else { return }
        if case let .cover(front) = session.surface {
            let side: CoverSide = front ? .front : .back
            guard coverPhotoID(side) == session.photoID else { return }
            changeCoverPhotoPlacement(side, name: tr("Ritaglia foto", "Crop Photo")) {
                if changedFrame { $0.frame = session.frame }
                $0.crop = session.crop
            }
            return
        }
        guard case let .canvasPage(pageID) = session.surface,
              let index = book.pages.firstIndex(where: { $0.id == pageID }),
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
        guard page.arrangement == nil, (page.layout == .gallery || page.layout == .mixed),
              placements[id]?.frame == nil else { return }
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
        if let arrangement = page.arrangement {
            if arrangement.photoCapacity == 1 { page.photoIDs.insert(id, at: 0) }
            else { page.photoIDs.append(id) }
            return
        }
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
        guard cropSession == nil, inlineBoxFocus == nil, editorialFocus == nil,
              remove(id, from: pageID) else { return false }
        if canvasPhotoSelection?.photoID == id { canvasPhotoSelection = nil }
        if selectedPhoto == id { selectedPhoto = nil }
        return true
    }

    private func deleteSelectedCanvasObject() -> Bool {
        guard canvasInput.ownsKeyboard, cropSession == nil, inlineEditingBox == nil, editingEditorial == nil
        else { return false }
        if let selectedBox, let page, page.textBoxes?.contains(where: { $0.id == selectedBox }) == true {
            changeTextBoxes(on: page.id, name: tr("Rimuovi box", "Remove Box")) { boxes in
                boxes.removeAll { $0.id == selectedBox }
            }
            self.selectedBox = nil
            return true
        }
        guard let selection = canvasPhotoSelection, selectedPhoto == selection.photoID else { return false }
        switch selection.surface {
        case let .canvasPage(id) where id == page?.id:
            return deleteCanvasPhoto(selection.photoID, from: id)
        case let .cover(front) where coverSide == (front ? .front : .back):
            let side: CoverSide = front ? .front : .back
            guard coverPhotoID(side) == selection.photoID else { return false }
            setCoverPhoto(nil, side: side)
            return true
        default: return false
        }
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

private struct NavigatorPreview<Content: View>: View, Equatable {
    let target: EditorDropTarget
    let book: Book
    let directory: URL
    let original: Bool
    let originalPhoto: UUID?
    @ViewBuilder let content: () -> Content

    var body: some View { content() }

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.target == rhs.target && lhs.book == rhs.book && lhs.directory == rhs.directory
            && lhs.original == rhs.original && lhs.originalPhoto == rhs.originalPhoto
    }
}

private struct CoverImage {
    let id: UUID?
    let placement: PhotoPlacement?
}

private final class EditorUndo {
    func registerCoverImage(_ manager: UndoManager, binding: Binding<Book>, bookID: UUID,
                            idKey: WritableKeyPath<BookCover, UUID?>,
                            placementKey: WritableKeyPath<BookCover, PhotoPlacement?>,
                            previous: CoverImage, name: String) {
        manager.registerUndo(withTarget: self) { [weak manager] target in
            guard let manager, binding.wrappedValue.id == bookID, var cover = binding.wrappedValue.cover else { return }
            let current = CoverImage(id: cover[keyPath: idKey], placement: cover[keyPath: placementKey])
            cover[keyPath: idKey] = previous.id
            cover[keyPath: placementKey] = previous.placement
            binding.wrappedValue.cover = cover
            target.registerCoverImage(manager, binding: binding, bookID: bookID, idKey: idKey,
                                      placementKey: placementKey, previous: current, name: name)
        }
        manager.setActionName(name)
    }

    func registerCoverValue<Value>(_ manager: UndoManager, binding: Binding<Book>, bookID: UUID,
                                   key: WritableKeyPath<BookCover, Value>, previous: Value, name: String) {
        manager.registerUndo(withTarget: self) { [weak manager] target in
            guard let manager, binding.wrappedValue.id == bookID, var cover = binding.wrappedValue.cover else { return }
            let current = cover[keyPath: key]
            cover[keyPath: key] = previous
            binding.wrappedValue.cover = cover
            target.registerCoverValue(manager, binding: binding, bookID: bookID, key: key, previous: current, name: name)
        }
        manager.setActionName(name)
    }

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

    func registerBookFilm(_ manager: UndoManager, binding: Binding<Book>, bookID: UUID,
                          previous: FilmSettings?, name: String) {
        manager.registerUndo(withTarget: self) { [weak manager] target in
            guard let manager, binding.wrappedValue.id == bookID else { return }
            let current = binding.wrappedValue.film
            binding.wrappedValue.film = previous
            target.registerBookFilm(manager, binding: binding, bookID: bookID, previous: current, name: name)
        }
        manager.setActionName(name)
    }

    func registerPhotoValue<Value>(_ manager: UndoManager, binding: Binding<Book>, bookID: UUID,
                                   photoID: UUID, key: WritableKeyPath<BookPhoto, Value>, previous: Value, name: String) {
        manager.registerUndo(withTarget: self) { [weak manager] target in
            guard let manager, binding.wrappedValue.id == bookID,
                  let index = binding.wrappedValue.photos.firstIndex(where: { $0.id == photoID }) else { return }
            let current = binding.wrappedValue.photos[index][keyPath: key]
            binding.wrappedValue.photos[index][keyPath: key] = previous
            target.registerPhotoValue(manager, binding: binding, bookID: bookID, photoID: photoID, key: key,
                                      previous: current, name: name)
        }
        manager.setActionName(name)
    }
}

private enum FilmTarget: Equatable {
    case book, photo(UUID)
}

@Observable private final class FilmEdit {
    private(set) var bookID: UUID?
    private(set) var target: FilmTarget?
    private(set) var initial: FilmSettings?
    var draft: FilmSettings?
    var preview: FilmSettings?

    func start(bookID: UUID, target: FilmTarget, settings: FilmSettings) {
        self.bookID = bookID
        self.target = target
        initial = settings
        draft = settings
        preview = nil
    }

    func clear() {
        target = nil
        bookID = nil
        initial = nil
        draft = nil
        preview = nil
    }
}

private struct FilmSlider: View {
    let label: String
    let value: WritableKeyPath<FilmSettings, Double>
    let target: FilmTarget?
    let committed: FilmSettings
    let edit: FilmEdit
    let change: (Double) -> Void
    let editingChanged: (Bool) -> Void

    private var amount: Double {
        (edit.target == target ? edit.draft ?? committed : committed)[keyPath: value]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.system(size: 11))
                Spacer()
                Text(amount.formatted(.percent.precision(.fractionLength(0))))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
            Slider(value: Binding(get: { amount }, set: change), in: 0...1, step: 0.02,
                   onEditingChanged: editingChanged)
                .accessibilityLabel(label)
        }
    }
}

private struct EditorPreview<Placeholder: View>: View {
    let request: EditorPreviewRequest
    let crop: PhotoCrop
    let fills: Bool
    let filmEdit: FilmEdit?
    let photoID: UUID
    let inheritsBookFilm: Bool
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: NSImage?
    @State private var displayedURL: URL?

    private var liveRequest: EditorPreviewRequest {
        guard let filmEdit, let target = filmEdit.target,
              target == .photo(photoID) || (target == .book && inheritsBookFilm),
              let look = filmEdit.preview, look != request.look else { return request }
        // Slider drafts keep the committed preset and its LUT. Smaller renders use a separate queue.
        return EditorPreviewRequest(url: request.url, limit: 640, look: look, lutURL: request.lutURL,
                                    adjustments: request.adjustments, isInteractive: true)
    }

    var body: some View {
        let request = liveRequest
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
            let pixels = await EditorPreviewLoader.image(for: request)
            guard !Task.isCancelled else { return }
            image = pixels.map {
                NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height))
            }
            displayedURL = request.url
        }
    }
}
