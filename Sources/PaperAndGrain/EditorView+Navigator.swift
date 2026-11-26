import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Re-renders its content only when the key changes. The key must list everything the content shows.
struct Memoized<Key: Equatable & Sendable, Content: View>: View, Equatable {
    let key: Key
    @ViewBuilder let content: () -> Content

    var body: some View { content() }

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.key == rhs.key }
}

extension EditorView {
    /// What the navigator draws. Actions read live state when they run, so they are not part of it.
    struct NavigatorKey: Equatable, Sendable {
        let book: Book
        let page: UUID?
        let coverSide: CoverSide?
        let width: Double
        let hoveredGap: NavigatorPageGap?
        let insertionID: UUID?
        let insertionAfter: Bool?
        let draggingPage: Bool
        let scrollDirection: Int?
        let compareOriginal: Bool
        let comparePhotoOriginal: UUID?
        let language: String
    }

    var navigatorKey: NavigatorKey {
        let insertion = previewPageInsertion
        let draggingPage: Bool = if case .page? = dragging?.item { true } else { false }
        return NavigatorKey(book: book, page: page?.id, coverSide: coverSide, width: navigatorWidth,
                            hoveredGap: hoveredGap, insertionID: insertion?.id, insertionAfter: insertion?.after,
                            draggingPage: draggingPage, scrollDirection: navigatorScrollDirection,
                            compareOriginal: compareOriginal, comparePhotoOriginal: comparePhotoOriginal,
                            language: language)
    }

    /// The navigator floats as a glass pane on macOS 26 and sits in a classic sidebar column before.
    @ViewBuilder var navigatorPane: some View {
        if #available(macOS 26.0, *) {
            HStack(spacing: 0) {
                navigator
                    .frame(width: navigatorWidth)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .floatingPanel(cornerRadius: 18)
                    .padding(.leading, 8)
                    .padding(.vertical, 8)
                PaneResizeHandle(width: $navigatorWidth, range: 150...340, label: tr("Pages Width"))
            }
        } else {
            HStack(spacing: 0) {
                navigator
                    .frame(width: navigatorWidth)
                    .background(Theme.sidebar)
                PaneResizeHandle(width: $navigatorWidth, range: 150...340, label: tr("Pages Width"))
                    .overlay { Rectangle().fill(edge).frame(width: 1) }
            }
        }
    }

    var navigator: some View {
        let insertion = previewPageInsertion
        return VStack(spacing: 0) {
            HStack {
                caption(tr("Pages"))
                Spacer()
                Text(String(physicalPageCount))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(muted)
                    .accessibilityLabel(tr("%lld pages", physicalPageCount))
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(spacing: 3) {
                        coverItem(.front).id(CoverSide.front)
                        ForEach(navigatorSpreads) { spread in
                            navigatorInsertButton(.before(spread.id), betweenColumns: false)
                            HStack(spacing: 2) {
                                if spread.blankLeft {
                                    navigatorBlankPage
                                }
                                ForEach(spread.pages) { leaf in
                                    if leaf.id != spread.id {
                                        navigatorInsertButton(.before(leaf.id), betweenColumns: true)
                                    }
                                    navigatorItem(leaf, paired: spread.paired,
                                                  insertionAfter: insertion?.id == leaf.id ? insertion?.after : nil)
                                        .id(leaf.id)
                                }
                            }
                        }
                        navigatorInsertButton(.end, betweenColumns: false)
                        coverItem(.back).id(CoverSide.back)
                    }
                    .padding(.horizontal, 10).padding(.bottom, 8)
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
            Divider()
            HStack(spacing: 6) {
                Button { insert(.gallery) } label: {
                    Label(tr("Page"), systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .help(tr("Add page"))
                Spacer()
                action("chevron.up", tr("Move earlier")) { move(-1) }
                    .disabled(index.map { $0 < 1 } ?? true)
                action("chevron.down", tr("Move later")) { move(1) }
                    .disabled(index.map { $0 >= book.pages.count - 1 } ?? true)
                action("book", tr("Browse the Book")) { openBrowser() }
                    .disabled(book.pages.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    /// Thumbnail edge for one page, following the navigator's width.
    var thumbBase: CGFloat {
        max(47, min(118, (CGFloat(navigatorWidth) - 50) / 2))
    }

    func navigatorInsertButton(_ gap: NavigatorPageGap, betweenColumns: Bool) -> some View {
        let label = tr("Insert Page Here")
        let visible = hoveredGap == gap
        return Button {
            guard let index = gap.index(in: book.pages) else { return }
            insert(.gallery, at: index)
        } label: {
            ZStack {
                Capsule().fill(visible ? pine.opacity(0.5) : .clear)
                    .frame(width: betweenColumns ? 1.5 : nil, height: betweenColumns ? thumbBase * 0.7 : 1.5)
                    .padding(.horizontal, betweenColumns ? 0 : 8)
                Image(systemName: "plus")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(pine)
                    .frame(width: 15, height: 15)
                    .background(panel, in: Circle())
                    .overlay { Circle().strokeBorder(pine.opacity(0.30)) }
                    .opacity(visible ? 1 : 0)
            }
            .frame(width: betweenColumns ? 14 : nil, height: betweenColumns ? thumbBase : 12)
            .frame(maxWidth: betweenColumns ? nil : .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { hoveredGap = gap } else if hoveredGap == gap { hoveredGap = nil }
        }
        .animation(.easeOut(duration: 0.12), value: visible)
        .accessibilityLabel(label)
        .help(label)
        .editorDropFrame(.navigatorGap(gap))
    }

    func navigatorItem(_ leaf: BookPage, paired: Bool, insertionAfter: Bool?) -> some View {
        let active = leaf.id == page?.id
        let first = leaf.id == book.pages.first?.id
        let ratio = aspect * (leaf.effectiveLayout == .fullSpread ? 2 : 1)
        let width = min(paired ? thumbBase * 1.2 : thumbBase * 2.45, thumbBase * ratio)
        let number = spreadNumber([leaf])
        let label = first && !paired ? tr("First Page") : number
        return navigatorCard(label, active: active) {
            select(leaf)
            clearCanvasSelection()
            editorInput.target = .navigatorPage(leaf.id)
        } preview: {
            navigatorPreview(for: .navigatorPage(leaf.id)) {
                mini(leaf)
            }
            .frame(width: width, height: width / ratio)
        }
        .accessibilityLabel(first ? tr("First Page") : tr("Page") + " " + number)
        .help(tr("Drag to reorder the page"))
        .onKeyPress(keys: [.delete, .deleteForward], phases: .down) { press in
            guard press.modifiers.intersection([.command, .shift, .control, .option]).isEmpty else { return .ignored }
            return deleteNavigatorPage(leaf.id) ? .handled : .ignored
        }
        .editorDropFrame(.navigatorPage(leaf.id))
        .simultaneousGesture(editorDrag(.page(leaf.id)))
        .contextMenu { navigatorContextMenu(leaf) }
        .overlay(alignment: navigatorInsertionAlignment(paired: paired, after: insertionAfter == true)) {
            if insertionAfter != nil {
                Capsule().fill(pine).frame(width: paired ? 3 : nil, height: paired ? nil : 3)
                    .padding(paired ? .vertical : .horizontal, 4)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder func navigatorContextMenu(_ leaf: BookPage) -> some View {
        let position = book.pages.firstIndex { $0.id == leaf.id }
        Button(tr("Insert Page Before")) {
            if let position { insert(.gallery, at: position) }
        }
        Button(tr("Insert Page After")) {
            if let position { insert(.gallery, at: position + 1) }
        }
        Button(tr("Duplicate Page")) { duplicatePage(leaf.id) }
            .disabled(!canDuplicatePage(leaf.id))
        Divider()
        Button(tr("Move Earlier")) {
            select(leaf)
            move(-1)
        }
        .disabled(position.map { $0 < 1 } ?? true)
        Button(tr("Move Later")) {
            select(leaf)
            move(1)
        }
        .disabled(position.map { $0 >= book.pages.count - 1 } ?? true)
        Divider()
        Button(tr("Delete Page…"), role: .destructive) {
            select(leaf)
            showDelete = true
        }
    }

    func navigatorInsertionAlignment(paired: Bool, after: Bool) -> Alignment {
        if paired { return after ? .trailing : .leading }
        return after ? .bottom : .top
    }

    var navigatorBlankPage: some View {
        let width = min(thumbBase * 1.2, thumbBase * aspect)
        return Color(cgColor: EditorialStyle.color(book.editorialStyle.paper))
            .frame(width: width, height: width / aspect)
            .overlay { Rectangle().strokeBorder(.black.opacity(0.09)) }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 18)
            .accessibilityHidden(true)
    }

    func coverItem(_ side: CoverSide) -> some View {
        let width = min(thumbBase * 1.9, thumbBase * aspect)
        return navigatorCard(coverName(side), active: coverSide == side) {
            selectCover(side)
            editorInput.target = .navigatorCover
        } preview: {
            navigatorPreview(for: .cover(front: side == .front)) {
                coverCanvas(side, scale: width / book.format.pageSize.width, thumbnail: true)
            }
                .shadow(color: .black.opacity(0.11), radius: 2, y: 1)
        }
    }

    func navigatorCard<Thumbnail: View>(_ label: String, active: Bool,
                                                  action: @escaping () -> Void,
                                                  @ViewBuilder preview: () -> Thumbnail) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                preview().frame(height: thumbBase + 1)
                Text(label)
                    .font(.caption.weight(active ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(active ? pine : muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: thumbBase + 30)
            .contentShape(Rectangle())
            .background(active ? pine.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(active ? pine.opacity(0.55) : .clear, lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    func navigatorPreview<Content: View>(for target: EditorDropTarget,
                                                  @ViewBuilder content: @escaping () -> Content) -> some View {
        NavigatorPreview(target: target, book: book, directory: directory, original: compareOriginal,
                         originalPhoto: comparePhotoOriginal, content: content)
            .equatable()
    }

    func mini(_ leaf: BookPage, small: Bool = true) -> some View {
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
                    positioned(preview(item.photo, small: small, crop: item.crop, fills: item.fills),
                               in: scaled(item.frame, by: scale))
                        .zIndex(Double(composition.rank(.photo(item.id))))
                }
                ZStack(alignment: .topLeading) {
                    storyBacking(backings, scale: scale)
                    ForEach(blocks) { block in
                        positioned(editorialText(block.text, scale: scale), in: scaled(block.frame, by: scale))
                    }
                }
                .zIndex(Double(composition.rank(.story)))
                ForEach(composition.textBoxes.filter { $0.prints(paper: style.paper, ink: style.ink) }) { box in
                    let frame = box.frame.rect(in: composition.bounds)
                    let text = PageComposition.boxText(box: box, book: book)
                    let inset = box.textInsetPoints
                    ZStack(alignment: .topLeading) {
                        if let fill = box.printedFill(paper: style.paper) {
                            positioned(Color(cgColor: EditorialStyle.color(fill)), in: scaled(frame, by: scale))
                        }
                        if let border = box.border(ink: style.ink) {
                            positioned(Rectangle().strokeBorder(Color(cgColor: EditorialStyle.color(border.color)),
                                                                lineWidth: max(0.3, border.width * scale)),
                                       in: scaled(frame, by: scale))
                        }
                        positioned(editorialText(text, scale: scale), in: scaled(frame.insetBy(dx: inset, dy: inset), by: scale))
                    }
                    .zIndex(Double(composition.rank(.textBox(box.id))))
                }
                if let folio = composition.folio {
                    let number = style.typography(String(number(of: leaf)), heading: nil, mixed: true)
                    positioned(editorialText(number, scale: scale), in: scaled(folio, by: scale))
                        .zIndex(20_000)
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

    /// Clicks inside the navigator keep its keyboard focus; the row's own action sets the page.
    func isNavigatorPoint(_ point: CGPoint) -> Bool {
        showsNavigator && point.x <= navigatorWidth
    }

    func select(_ leaf: BookPage) {
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

    func deletePage() {
        guard let index else { return }
        endInlineTextEditing()
        editPages(tr("Delete Page")) { $0.remove(at: index) }
        selection = book.pages.isEmpty ? nil : book.pages[min(index, book.pages.count - 1)].id
        editorInput.target = .none
        canvasPhotoSelection = nil
        selectedPhoto = nil
        selectedBox = nil
        selectedEditorial = nil
        filmScope = .book
    }

    /// Duplicate Page works on a book page, not on a cover, and never while text is being typed.
    var canDuplicatePage: Bool { page.map { canDuplicatePage($0.id) } ?? false }

    func canDuplicatePage(_ id: UUID) -> Bool {
        coverSide == nil && cropSession == nil && !showDelete && !writing && !writingBox
            && inlineBoxFocus == nil && editorialFocus == nil && !searchingPhotos
            && book.pages.contains { $0.id == id }
    }

    /// Puts a copy right after the page and selects it, as one undo step.
    func duplicatePage(_ id: UUID? = nil) {
        guard let id = id ?? page?.id, canDuplicatePage(id),
              let position = book.pages.firstIndex(where: { $0.id == id }) else { return }
        let copy = book.pages[position].duplicated()
        editPages(tr("Duplicate Page")) { $0.insert(copy, at: position + 1) }
        if let undoManager {
            undoTarget.registerSelection(undoManager, binding: $selection, restoring: id, then: copy.id)
        }
        select(copy)
        clearCanvasSelection()
    }

    func move(_ offset: Int) {
        guard let index, book.pages.indices.contains(index + offset) else { return }
        if let page { selection = page.id }
        editPages(tr("Move Page")) { $0.swapAt(index, index + offset) }
    }

    func pageInsertion(at location: CGPoint) -> (id: UUID, after: Bool)? {
        guard dropFrames[.navigatorViewport]?.contains(location) == true else { return nil }
        for (target, frame) in dropFrames where frame.contains(location) {
            if case let .navigatorGap(gap) = target { return gap.dropTarget(in: book.pages) }
        }
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

    var previewPageInsertion: (id: UUID, after: Bool)? {
        guard let dragging, case let .page(sourceID) = dragging.item,
              let insertion = pageInsertion(at: dragging.location), insertion.id != sourceID else { return nil }
        return insertion
    }

    var navigatorScrollDirection: Int? {
        guard let dragging, case .page = dragging.item,
              let viewport = dropFrames[.navigatorViewport], viewport.contains(dragging.location) else { return nil }
        if dragging.location.y - viewport.minY < 28 { return -1 }
        if viewport.maxY - dragging.location.y < 28 { return 1 }
        return nil
    }

    @MainActor func scrollWhileDragging(_ scroll: ScrollViewProxy) async {
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

    func reorderPage(_ sourceID: UUID, relativeTo targetID: UUID, after: Bool) {
        guard sourceID != targetID,
              let source = book.pages.firstIndex(where: { $0.id == sourceID }),
              book.pages.contains(where: { $0.id == targetID }) else { return }
        let leaf = book.pages[source]
        editPages(tr("Reorder Page")) { pages in
            pages.remove(at: source)
            guard let target = pages.firstIndex(where: { $0.id == targetID }) else { return }
            pages.insert(leaf, at: target + (after ? 1 : 0))
        }
        select(leaf)
    }

    func deleteNavigatorPage(_ id: UUID) -> Bool {
        guard showsNavigator, !showDelete, cropSession == nil, selection == id, page?.id == id,
              !writing, !writingBox, inlineBoxFocus == nil, editorialFocus == nil, !searchingPhotos else { return false }
        deletePage()
        return true
    }
}
