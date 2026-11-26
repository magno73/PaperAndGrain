import AppKit
import Observation
import UniformTypeIdentifiers
import SwiftUI

struct EditorView: View, Localizing {
    @Binding var book: Book

    let directory: URL

    let language: String

    let analysisStatus: String

    let isAnalyzing: Bool

    let onAnalyze: () -> Void

    let onDropPhotos: ([NSItemProvider], @escaping (UUID) -> Void) -> Bool

    let onDropPhotoPromises: ([NSFilePromiseReceiver], @escaping (UUID) -> Void) -> Bool

    let onExport: () -> Void

    let actions: EditorAppActions

    @Environment(\.undoManager) var undoManager

    @FocusState var writing: Bool

    @FocusState var writingBox: Bool

    @FocusState var inlineBoxFocus: UUID?

    @FocusState var editorialFocus: EditorialObject?

    @FocusState var searchingPhotos: Bool

    @FocusState var headingFocused: Bool

    @State var selection: UUID?

    @State var selectedPhoto: UUID?

    @State var canvasPhotoSelection: CanvasPhotoSelection?

    @State var photoIndices: [UUID: Int] = [:]

    @State var selectedBox: UUID?

    @State var inlineEditingBox: UUID?

    @State var selectedEditorial: EditorialObject?

    @State var editingEditorial: EditorialObject?

    @State var coverSide: CoverSide?


    @State var zoom: CanvasZoom = .fitPage

    @State var dropFrames = [EditorDropTarget: CGRect]()

    @State var canvasHits = CanvasHitStorage()

    @State var editorInput = EditorInput()

    @AppStorage("editorShowsPages") var showsNavigator = true

    @AppStorage("editorShowsInspector") var showsInspector = true

    @AppStorage("editorShowsTray") var showsTray = true

    @AppStorage("editorNavigatorWidth") var navigatorWidth = 212.0

    @State var showLayoutPopover = false

    @State var browsingSpread: Int?

    @State var hoveredGap: NavigatorPageGap?

    @State var trayFilter: TrayFilter = .all

    @State var libraryHitFrames = LibraryHitFrames()

    @State var hoveringPhotoDrop = false

    @State var hoveringPhotoPromise = false

    @State var importedPhotoToReveal: UUID?

    @GestureState var dragging: EditorDragPreview?

    @State var showSpread = true

    @State var gutterGuide = false

    /// Print guides on the canvas; kept between launches.
    @AppStorage("editorShowsPrintGuides") var printGuides = false

    @State var showDelete = false

    @State var inspectorNavigation = InspectorNavigation()

    @State var filmScope: FilmScope = .book

    @State var showsAdjustSection = false

    @State var showsPhotoFilmSection = false

    @State var canvasNotice: String?

    /// Off by default: with a photo selected, the film look changes only that photo.
    @State var filmAppliesToBook = false

    @AppStorage("inspectorShowsAnalysis") var showsAnalysisSection = false

    @State var filmEdit = FilmEdit()

    @State var filmPreviewTask: Task<Void, Never>?

    @State var compareOriginal = false

    @State var comparePhotoOriginal: UUID?

    @State var enhancingPhotos: [UUID: UUID] = [:]

    @State var adjustmentErrors: [UUID: String] = [:]

    @State var adjustmentEdit: AdjustmentEdit?

    @State var adjustmentPreviewTask: Task<Void, Never>?

    @State var lutImportError: String?

    @State var concept: String?

    @State var search = ""

    @State var photoLibraryCache = InspectorPhotoLibraryCache()

    @State var photoUsageIndex = PhotoUsageIndex()

    @AppStorage("libraryPhotoOrder") var photoOrder: PhotoLibraryOrder = .date

    @State var libraryOrdering = PhotoLibraryOrdering()

    @State var placesRead: [UUID: PhotoLocation] = [:]

    @State var scannedPlaceAssets: Set<PlaceAsset> = []

    @State var suggestedPhotos: [PhotoSuggestion] = []

    @State var undoTarget = EditorUndo()

    @State var cropSession: CropSession?

    @State var issues = IssueMonitor()

    @State var showsIssues = false

    /// The popover opened from the menu, anchored to the canvas so it shows even when the toolbar
    /// has no Issues item (removed with Customize Toolbar, or a layout saved by 0.10).
    @State var showsIssuesFromMenu = false

    enum Inspector: String, CaseIterable {
        case page, text, photo, film
    }

    enum TrayFilter: Hashable {
        case all, unused, onPage
    }

    @Observable final class InspectorNavigation {
        var tab: Inspector = .page
    }

    final class EditorInput {
        var target: EditorKeyboardTarget = .none
    }

    final class LibraryHitFrames {
        var frames = LibraryPhotoFrames()
    }

    var inspector: Inspector {
        get { inspectorNavigation.tab }
        nonmutating set { inspectorNavigation.tab = newValue }
    }

    struct InspectorHost<Content: View>: View {
        @Bindable var navigation: InspectorNavigation
        let title: String
        let tabs: [InspectorTab]
        let finishAdjustment: () -> Void
        let finishFilm: () -> Void
        @ViewBuilder let content: (Inspector) -> Content

        var body: some View {
            VStack(spacing: 0) {
                Picker(title, selection: $navigation.tab) {
                    ForEach(tabs) { tab in
                        Text(tab.title).tag(tab.id)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 8)
                content(navigation.tab)
            }
            .onChange(of: navigation.tab) { _, tab in
                if tab != .photo { finishAdjustment() }
                finishFilm()
            }
        }
    }

    struct InspectorTab: Identifiable {
        let id: Inspector
        let title: String
    }

    struct CanvasPhotoSelection {
        let surface: EditorDropTarget
        let photoID: UUID

        var pageID: UUID? {
            if case let .canvasPage(id) = surface { return id }
            return nil
        }
    }

    struct AdjustmentEdit {
        let photoID: UUID
        var draft: PhotoAdjustments
        var preview: PhotoAdjustments
    }

    struct PlaceAsset: Hashable, Sendable {
        let id: UUID
        let filename: String
        let sourceID: String?
    }

    struct PhotoSuggestion: Identifiable, Sendable {
        let id: UUID
        let score: Double
        let evidence: PhotoMatchEvidence
    }

    struct PhotoSuggestionQuery: Equatable, Sendable {
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

    struct NavigatorSpread: Identifiable {
        let id: UUID
        let pages: [BookPage]
        let blankLeft: Bool

        var paired: Bool { blankLeft || pages.count == 2 }
    }

    enum FilmScope: Hashable {
        case book, photo
    }

    enum CoverSide: Hashable {
        case front, back
    }

    enum EditorialObject: Hashable {
        case page(UUID, PageComposition.TextRole)
        case storyGroup(UUID)
        case cover(CoverSide)

        var pageID: UUID? {
            switch self {
            case let .page(id, _), let .storyGroup(id): id
            case .cover: nil
            }
        }
    }

    enum AlignmentElement: Equatable {
        case photo(UUID), textBox(UUID), editorial(PageComposition.TextRole)
    }

    enum IncomingPhotoPlacement {
        case position(CanvasAlignment.Result)
        case swap(CanvasPhotoSwap.Target)
        case replace(CanvasPhotoSwap.Target)
    }

    /// What dropping a dragged photo at a point of a page will do.
    enum PhotoDropAction {
        /// Two photos of the page trade places.
        case swap(CanvasPhotoSwap.Target)
        /// A photo from the library takes the place and frame of the one under the pointer.
        case replace(CanvasPhotoSwap.Target)
        /// The photo fills an empty slot of the page layout; the frame is in page view coordinates.
        case fillSlot(index: Int, frame: CGRect)
        /// The first photo of an automatic page joins its layout.
        case join
        /// A free frame where the pointer is.
        case free
    }

    struct CropSession {
        let surface: EditorDropTarget
        let photoID: UUID
        let initialFrame: PageRect
        let initialCrop: PhotoCrop
        var frame: PageRect
        var crop: PhotoCrop
    }

    enum CanvasZoom: Hashable {
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

    let ink = Theme.ink

    let pine = Theme.accent

    let muted = Theme.muted

    let paper = Theme.field

    let panel = Theme.panel

    let edge = Theme.edge

    var page: BookPage? {
        guard coverSide == nil else { return nil }
        return book.pages.first { $0.id == selection } ?? book.pages.first
    }

    var index: Int? {
        guard let page else { return nil }
        return book.pages.firstIndex { $0.id == page.id }
    }

    var text: Binding<String> {
        Binding(
            get: { page?.text ?? "" },
            set: { value in
                guard let index else { return }
                book.pages[index].text = value
            }
        )
    }

    var groups: [[BookPage]] {
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

    var navigatorSpreads: [NavigatorSpread] {
        groups.compactMap { row in
            guard let first = row.first else { return nil }
            let blankLeft = row.count == 1 && first.effectiveLayout != .fullSpread
                && first.id == book.pages.first?.id && book.printSettings?.firstPageOnRight == true
            return NavigatorSpread(id: first.id, pages: row, blankLeft: blankLeft)
        }
    }

    var body: some View {
        editorContent
            .inspector(isPresented: $showsInspector) {
                sidePanel
                    .inspectorColumnWidth(min: 270, ideal: 300, max: 420)
            }
            // The window can't shrink below the panes it shows, so the inspector never gets clipped.
            .frame(minWidth: (showsNavigator ? navigatorWidth : 0) + 640 + (showsInspector ? 280 : 0))
            .toolbar(id: "editor") { editorToolbar }
            .navigationTitle(book.title.isEmpty ? tr("Untitled") : book.title)
            .navigationSubtitle(toolbarSubtitle)
            .toolbarTitleMenu { bookTitleMenu }
            .focusedSceneValue(\.editorCommands, editorCommands)
            .onChange(of: showsInspector) { _, visible in
                if !visible {
                    finishPhotoAdjustmentEdit()
                    finishFilmEdit()
                }
            }
            .alert(tr("Delete the page?"), isPresented: $showDelete) {
                Button(tr("Cancel"), role: .cancel) {}
                Button(tr("Delete"), role: .destructive, action: deletePage)
            } message: {
                Text(tr("The page’s photos will remain available in the book."))
            }
            .overlay {
                if let browsing = browsingSpread {
                    bookBrowser(start: browsing)
                }
            }
    }

    var editorContent: some View {
        HStack(spacing: 0) {
            if showsNavigator {
                // Selecting a photo or text must not rebuild every thumbnail of a long book.
                Memoized(key: navigatorKey) { navigatorPane }
                    .equatable()
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            VStack(spacing: 0) {
                canvas.frame(maxWidth: .infinity, maxHeight: .infinity)
                if showsTray {
                    photoTray
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .background { Theme.table.ignoresSafeArea() }
        .background(alignment: .topLeading) {
            CanvasDeleteShortcut(onDelete: deleteEditorSelection, onDeselect: deselectCanvas,
                                 onNudge: handleArrowKey, onClick: selectObject(at:),
                                 onPointerDown: { point in
                if dropFrames[.canvasViewport]?.contains(point) == true {
                    editorInput.target = .canvas
                } else if !isNavigatorPoint(point) {
                    editorInput.target = .none
                }
            }, onKeyboardTraversal: { editorInput.target = .none },
                                 onContextMenu: canvasMenu(at:), canTurnPages: canTurnPages(at:),
                                 onTurnPage: turnCanvasPage)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .overlay(alignment: .topTrailing) {
            Color.clear.frame(width: 1, height: 1)
                .popover(isPresented: $showsIssuesFromMenu, arrowEdge: .bottom) { issuesPopover }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .foregroundStyle(ink)
        .tint(pine)
        .coordinateSpace(name: EditorDropTarget.coordinateSpace)
        .onPreferenceChange(EditorDropFrames.self) { dropFrames = $0 }
        .onPreferenceChange(CanvasHitMaps.self) { canvasHits.maps = $0 }
        .task { recheckIssues(immediately: true) }
        .onChange(of: book) { recheckIssues() }
        // A package renamed or moved in Finder changes where the photo files are looked up.
        .onChange(of: directory) { recheckIssues(immediately: true) }
        .onChange(of: book.photos.map(\.id), initial: true) { _, ids in
            photoIndices = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($0.element, $0.offset) })
        }
        .onChange(of: inlineBoxFocus) { previous, current in
            if previous != nil && current == nil && inlineEditingBox == previous { inlineEditingBox = nil }
        }
        .onChange(of: editorialFocus) { previous, current in
            if let previous, current == nil, editingEditorial == previous { editingEditorial = nil }
        }
        .onChange(of: selectedText) { previous, current in
            if current != nil, previous == nil, inspector == .page { inspector = .text }
            if current == nil, inspector == .text { inspector = .page }
        }
        .onChange(of: selectedPhoto) { previous, id in
            if canvasPhotoSelection?.photoID != id { canvasPhotoSelection = nil }
            if comparePhotoOriginal != id { comparePhotoOriginal = nil }
            if previous != id { filmAppliesToBook = false }
            if let adjustmentEdit, adjustmentEdit.photoID != id { finishPhotoAdjustmentEdit() }
            if case let .photo(target)? = filmEdit.target, target != id { finishFilmEdit() }
            followSelectionInInspector(previous: previous, current: id)
        }
        .onChange(of: filmScope) { _, _ in finishFilmEdit() }
        .onDisappear {
            issues.stop()
            adjustmentPreviewTask?.cancel()
            filmPreviewTask?.cancel()
            undoManager?.removeAllActions(withTarget: undoTarget)
        }
        .overlay(alignment: .topLeading) {
            dragPreview.allowsHitTesting(false).accessibilityHidden(true)
        }
        .animation(.snappy(duration: 0.22), value: showsNavigator)
        .animation(.snappy(duration: 0.22), value: showsTray)
    }

    func preview(_ photo: BookPhoto, small: Bool = false, crop: PhotoCrop = PhotoCrop(),
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

    var dimensions: String {
        let style = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...2))
            .locale(Locale(identifier: language))
        return "\((book.format.widthMM / 10).formatted(style)) × \((book.format.heightMM / 10).formatted(style)) cm"
    }

    var aspect: CGFloat {
        CGFloat(max(0.1, min(10, book.format.widthMM / max(1, book.format.heightMM))))
    }

    var physicalPageCount: Int {
        book.pages.reduce(0) { $0 + ($1.effectiveLayout == .fullSpread ? 2 : 1) }
    }

    func number(of leaf: BookPage) -> Int {
        book.pageNumber(of: leaf)
    }

    func spreadNumber(_ spread: [BookPage]) -> String {
        guard let first = spread.first, let last = spread.last else { return "" }
        let start = number(of: first)
        let end = number(of: last) + (last.effectiveLayout == .fullSpread ? 1 : 0)
        return start == end ? String(start) : "\(start)–\(end)"
    }

    func caption(_ value: String) -> some View {
        Text(value)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ink)
            .accessibilityAddTraits(.isHeader)
    }

    func intro(_ value: String) -> some View {
        Text(value).font(.caption).foregroundStyle(muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    func action(_ symbol: String, _ label: String, perform: @escaping () -> Void) -> some View {
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

    func conceptName(_ value: String) -> String {
        PhotoAnalyzer.displayName(for: value, language: language)
    }

    func photos(on page: BookPage) -> [BookPhoto] {
        page.photoIDs.compactMap(indexedPhoto)
    }

    func photoIndex(_ id: UUID) -> Int? {
        if let index = photoIndices[id], book.photos.indices.contains(index), book.photos[index].id == id {
            return index
        }
        return book.photos.firstIndex { $0.id == id }
    }

    func indexedPhoto(_ id: UUID) -> BookPhoto? {
        photoIndex(id).map { book.photos[$0] }
    }

    func pageComposition(_ page: BookPage) -> PageComposition {
        PageComposition(page: page, book: book, photoForID: indexedPhoto)
    }

    func coverName(_ side: CoverSide) -> String {
        side == .front ? tr("Front Cover") : tr("Back Cover")
    }

    func coverPhotoID(_ side: CoverSide) -> UUID? {
        side == .front ? book.cover?.frontPhotoID : book.cover?.backPhotoID
    }

    func editPages(_ name: String, change: (inout [BookPage]) -> Void) {
        let previous = book.pages
        change(&book.pages)
        registerUndo(previous, name: name)
    }

    func registerUndo(_ previous: [BookPage], name: String) {
        guard previous != book.pages, let undoManager else { return }
        undoTarget.register(undoManager, binding: $book, bookID: book.id, pages: previous, name: name)
    }
}

struct NavigatorPreview<Content: View>: View, Equatable {
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

struct CoverImage {
    let id: UUID?
    let placement: PhotoPlacement?
}

@MainActor
final class EditorUndo {
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

    /// Makes undo and redo of a page insertion also move the page selection.
    func registerSelection(_ manager: UndoManager, binding: Binding<UUID?>, book: Binding<Book>, bookID: UUID, restoring: UUID, then next: UUID) {
        manager.registerUndo(withTarget: self) { [weak manager] target in
            guard let manager, book.wrappedValue.id == bookID else { return }
            binding.wrappedValue = restoring
            target.registerSelection(manager, binding: binding, book: book, bookID: bookID, restoring: next, then: restoring)
        }
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

enum FilmTarget: Equatable {
    case book, photo(UUID)
}

@Observable final class FilmEdit {
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

struct FilmSlider: View {
    let label: String
    let value: WritableKeyPath<FilmSettings, Double>
    let target: FilmTarget?
    let committed: FilmSettings
    let edit: FilmEdit
    let change: (Double) -> Void
    let editingChanged: (Bool) -> Void

    var amount: Double {
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
            // Quantized in the setter: a stepped Slider draws a tick mark per step on macOS.
            Slider(value: Binding(get: { amount }, set: { change(PhotoAdjustmentsPanel.quantized($0, step: 0.02, in: 0...1)) }),
                   in: 0...1, onEditingChanged: editingChanged)
                .accessibilityLabel(label)
        }
    }
}

struct EditorPreview<Placeholder: View>: View {
    let request: EditorPreviewRequest
    let crop: PhotoCrop
    let fills: Bool
    let filmEdit: FilmEdit?
    let photoID: UUID
    let inheritsBookFilm: Bool
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: NSImage?
    @State private var displayedURL: URL?

    var liveRequest: EditorPreviewRequest {
        guard let filmEdit, let target = filmEdit.target,
              target == .photo(photoID) || (target == .book && inheritsBookFilm),
              let look = filmEdit.preview, look != request.look else { return request }
        // Slider drafts keep the committed preset and its LUT. Smaller renders use a separate queue.
        return EditorPreviewRequest(url: request.url, limit: 640, look: look, lutURL: request.lutURL,
                                    adjustments: request.adjustments, isInteractive: true)
    }

    @Environment(\.displayScale) private var displayScale

    /// Renders no larger than the frame needs, in steps so small resizes reuse the cache.
    static func sized(_ request: EditorPreviewRequest, frame: CGSize, zoom: Double, scale: CGFloat) -> EditorPreviewRequest {
        guard request.limit > 180, !request.isInteractive, frame.width > 0, frame.height > 0 else { return request }
        let needed = Double(max(frame.width, frame.height) * max(1, scale)) * max(1, zoom)
        let step = [480, 720, 1080, 1440, 2048].first { Double($0) >= needed * 1.1 } ?? 2048
        guard step < request.limit else { return request }
        var sized = EditorPreviewRequest(url: request.url, limit: step, look: request.look, lutURL: request.lutURL,
                                         adjustments: request.adjustments)
        sized.isFilmSwatch = request.isFilmSwatch
        return sized
    }

    var body: some View {
        let live = liveRequest
        GeometryReader { geometry in
            let request = Self.sized(live, frame: geometry.size, zoom: crop.zoom, scale: displayScale)
            Group {
                if let image, displayedURL == request.url {
                    let frame = crop.imageRect(for: image.size, in: CGRect(origin: .zero, size: geometry.size), fills: fills)
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                } else {
                    placeholder()
                }
            }
            .task(id: request) {
                // Show the navigator's thumbnail at once while the sharp render is on its way.
                if displayedURL != request.url, request.limit > 180 {
                    let thumbnail = EditorPreviewRequest(url: request.url, limit: 180, look: request.look,
                                                         lutURL: request.lutURL, adjustments: request.adjustments)
                    if let quick = await EditorPreviewLoader.cachedImage(for: thumbnail), !Task.isCancelled {
                        image = NSImage(cgImage: quick, size: NSSize(width: quick.width, height: quick.height))
                        displayedURL = request.url
                    }
                }
                let pixels = await EditorPreviewLoader.image(for: request)
                guard !Task.isCancelled, let pixels else { return }
                image = NSImage(cgImage: pixels, size: NSSize(width: pixels.width, height: pixels.height))
                displayedURL = request.url
            }
        }
        .clipped()
    }
}
