import AppKit
import ImageIO
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
    @State private var selection: UUID?
    @State private var selectedPhoto: UUID?
    @State private var showSpread = true
    @State private var gutterGuide = false
    @State private var showDelete = false
    @State private var inspector: Inspector = .page
    @State private var concept: String?
    @State private var search = ""
    @State private var undoTarget = EditorPageUndo()

    private enum Inspector: String, CaseIterable {
        case page, photos
    }

    private let ink = Color(red: 0.14, green: 0.17, blue: 0.14)
    private let pine = Color(red: 0.14, green: 0.31, blue: 0.23)
    private let muted = Color(red: 0.33, green: 0.37, blue: 0.33)
    private let paper = Color(red: 0.98, green: 0.97, blue: 0.93)
    private let panel = Color(red: 0.95, green: 0.95, blue: 0.91)
    private let edge = Color(red: 0.82, green: 0.83, blue: 0.78)

    private var page: BookPage? {
        book.pages.first { $0.id == selection } ?? book.pages.first
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
        for page in book.pages {
            if page.layout == .fullSpread {
                if let previous = partner { spreads.append([previous]) }
                partner = nil
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

    var body: some View {
        VStack(spacing: 0) {
            masthead
            Rectangle().fill(edge).frame(height: 1)
            HStack(spacing: 0) {
                navigator.frame(width: 128)
                Rectangle().fill(edge).frame(width: 1)
                canvas.frame(maxWidth: .infinity, maxHeight: .infinity)
                Rectangle().fill(edge).frame(width: 1)
                sidePanel.frame(width: 260)
            }
        }
        .background(panel)
        .foregroundStyle(ink)
        .tint(pine)
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
                    if writing, NSApp.sendAction(Selector(("undo:")), to: nil, from: nil) { return }
                    undoManager?.undo()
                }
                action("arrow.uturn.forward", tr("Ripristina", "Redo")) {
                    if writing, NSApp.sendAction(Selector(("redo:")), to: nil, from: nil) { return }
                    undoManager?.redo()
                }
            }
            Divider().frame(height: 23)
            Menu {
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
        }
        .padding(.horizontal, 17)
        .frame(height: 63)
    }

    private var navigator: some View {
        VStack(spacing: 0) {
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
                        ForEach(showSpread ? groups : book.pages.map { [$0] }, id: \.first!.id) { spread in
                            navigatorItem(spread)
                                .id(spread[0].id)
                        }
                    }
                    .padding(.horizontal, 9)
                }
                .onChange(of: selection) { _, selected in
                    let id = showSpread
                        ? groups.first(where: { $0.contains { $0.id == selected } })?.first?.id
                        : selected
                    if let id { withAnimation(.easeOut(duration: 0.2)) { scroll.scrollTo(id, anchor: .center) } }
                }
            }
            Rectangle().fill(edge).frame(height: 1)
            HStack(spacing: 10) {
                action("plus", tr("Aggiungi pagina", "Add page")) { insert(.gallery) }
                action("chevron.up", tr("Sposta prima", "Move earlier")) { move(-1) }
                    .disabled((index ?? 0) < 1)
                action("chevron.down", tr("Sposta dopo", "Move later")) { move(1) }
                    .disabled((index ?? 0) >= book.pages.count - 1)
            }
            .padding(.vertical, 8)
        }
        .background(Color(red: 0.93, green: 0.93, blue: 0.89))
    }

    private func navigatorItem(_ spread: [BookPage]) -> some View {
        let active = spread.contains { $0.id == page?.id }
        return VStack(spacing: 6) {
            HStack(spacing: 1) {
                ForEach(spread) { leaf in
                    let maxWidth: CGFloat = spread.count == 2 ? 43 : 86
                    let ratio = aspect * (leaf.layout == .fullSpread ? 2 : 1)
                    let width = min(maxWidth, 47 * ratio)
                    Button {
                        select(leaf)
                    } label: {
                        mini(leaf)
                            .frame(width: width, height: width / ratio)
                            .overlay {
                                if page?.id == leaf.id {
                                    Rectangle().strokeBorder(pine, lineWidth: 1)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tr("Pagina", "Page") + " " + spreadNumber([leaf]))
                    .accessibilityAddTraits(page?.id == leaf.id ? .isSelected : [])
                }
            }
            Text(spreadNumber(spread))
                .font(.system(size: 10, weight: active ? .semibold : .regular, design: .monospaced))
                .foregroundStyle(active ? pine : muted)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(active ? pine.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(active ? pine.opacity(0.65) : .clear)
                .allowsHitTesting(false)
        }
    }

    private func mini(_ leaf: BookPage) -> some View {
        ZStack {
            paper
            if leaf.layout != .text, let photo = photos(on: leaf).first {
                preview(photo, small: true)
                    .padding(leaf.layout == .gallery || leaf.layout == .mixed ? 3 : 0)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    RoundedRectangle(cornerRadius: 1).fill(pine.opacity(0.55)).frame(width: 13, height: 2)
                    RoundedRectangle(cornerRadius: 1).fill(muted.opacity(0.30)).frame(width: 18, height: 1)
                    RoundedRectangle(cornerRadius: 1).fill(muted.opacity(0.30)).frame(width: 15, height: 1)
                }
            }
        }
        .clipped()
        .overlay { Rectangle().strokeBorder(.black.opacity(0.09)) }
        .shadow(color: .black.opacity(0.11), radius: 2, y: 1)
    }

    private var canvas: some View {
        VStack(spacing: 0) {
            HStack {
                if let page {
                    caption(tr("Pagina", "Page") + " " + spreadNumber([page]))
                }
                Spacer()
                Picker(tr("Vista", "View"), selection: $showSpread) {
                    Image(systemName: "rectangle.portrait").tag(false)
                        .accessibilityLabel(tr("Pagina singola", "Single Page"))
                    Image(systemName: "book").tag(true)
                        .accessibilityLabel(tr("Doppia pagina", "Two-Page View"))
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 82)
            }
            .padding(.horizontal, 22)
            .padding(.top, 16)
            GeometryReader { geometry in
                if let page {
                    let spread = showSpread ? groups.first { $0.contains { $0.id == page.id } } ?? [page] : [page]
                    let wide = page.layout == .fullSpread
                    let count = wide ? 2 : spread.count
                    let availableWidth = max(40, geometry.size.width - 40)
                    let availableHeight = max(40, geometry.size.height - 48)
                    let height = min(availableHeight, availableWidth / (aspect * Double(count)))
                    let width = height * aspect
                    HStack(spacing: 0) {
                        if wide {
                            canvasPage(page, width: width * 2, height: height, showFolio: false)
                        } else {
                            ForEach(spread) { leaf in
                                canvasPage(leaf, width: width, height: height, showFolio: true)
                            }
                        }
                    }
                    .overlay {
                        if count == 2 {
                            LinearGradient(colors: [.clear, .black.opacity(0.18), .white.opacity(0.24), .clear],
                                           startPoint: .leading, endPoint: .trailing)
                                .frame(width: 12)
                                .allowsHitTesting(false)
                            if gutterGuide {
                                Rectangle()
                                    .fill(.white.opacity(0.23))
                                    .overlay {
                                        Rectangle().strokeBorder(pine.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                    }
                                    .frame(width: width * 0.075)
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                    .shadow(color: .black.opacity(0.16), radius: 12, x: 0, y: 7)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    layoutChoices(page)
                    if page.layout == .fullPage || page.layout == .fullSpread,
                       let photo = photos(on: page).first {
                        cropControl(for: page, photo: photo)
                    }
                    if page.layout == .fullSpread || (showSpread && groups.contains { $0.count == 2 && $0.contains { $0.id == page.id } }) {
                        Toggle(tr("Guida della piega", "Gutter Guide"), isOn: $gutterGuide)
                            .toggleStyle(.checkbox)
                            .font(.system(size: 11))
                            .foregroundStyle(muted)
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
        }
        .padding(3)
        .background(pine.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    private func cropControl(for leaf: BookPage, photo: BookPhoto) -> some View {
        let photoAspect = Double(photo.pixelWidth) / Double(max(1, photo.pixelHeight))
        let destinationAspect = Double(aspect) * (leaf.layout == .fullSpread ? 2 : 1)
        let horizontal = photoAspect > destinationAspect
        let label = horizontal
            ? tr("Inquadratura orizzontale", "Horizontal Framing")
            : tr("Inquadratura verticale", "Vertical Framing")
        return HStack(spacing: 8) {
            Text(label).font(.system(size: 11)).foregroundStyle(muted)
            Slider(value: Binding(
                get: { page?.framing ?? 0.5 },
                set: { value in
                    guard let index else { return }
                    book.pages[index].framing = value
                }
            ), in: 0...1)
            .frame(width: 110)
            .controlSize(.small)
            .accessibilityLabel(label)
        }
    }

    private func canvasPage(_ leaf: BookPage, width: CGFloat, height: CGFloat, showFolio: Bool) -> some View {
        let printHeight = max(1, book.format.heightMM * 72 / 25.4)
        let scale = height / printHeight
        let padding = min(min(width, height) * 0.2, min(30 * scale, height * 0.11))
        let innerWidth = max(1, width - padding * 2)
        let innerHeight = max(1, height - padding * 2)
        return ZStack(alignment: .bottomTrailing) {
            paper.onTapGesture {
                select(leaf)
                selectedPhoto = nil
            }
            switch leaf.layout {
            case .fullPage, .fullSpread:
                if let photo = photos(on: leaf).first {
                    canvasPhoto(photo, page: leaf, width: width, height: height)
                } else {
                    placeholder.frame(width: width, height: height)
                }
            case .gallery:
                gallery(leaf, width: innerWidth, height: innerHeight, gap: 6 * scale)
                    .frame(width: width, height: height)
            case .mixed:
                let spacing = 12 * scale
                let photoHeight = innerHeight * 0.57
                VStack(alignment: .leading, spacing: spacing) {
                    gallery(leaf, width: innerWidth, height: photoHeight, gap: 6 * scale)
                    prose(leaf, scale: scale)
                        .frame(width: innerWidth, height: max(1, innerHeight - photoHeight - spacing), alignment: .topLeading)
                        .clipped()
                }
                .frame(width: width, height: height)
            case .text:
                prose(leaf, scale: scale)
                    .frame(width: innerWidth, height: innerHeight, alignment: .topLeading)
                    .clipped()
                    .frame(width: width, height: height)
            }
            if showFolio {
                Text(String(number(of: leaf)))
                    .font(.system(size: max(7, min(11, min(width, height) * 0.030)), design: .serif))
                    .foregroundStyle(muted)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(paper.opacity(leaf.layout == .fullPage ? 0.88 : 0))
                    .padding(.trailing, padding * 0.8)
                    .padding(.bottom, max(3, padding * 0.26))
                    .allowsHitTesting(false)
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .contentShape(Rectangle())
        .overlay {
            if leaf.id == page?.id {
                Rectangle().strokeBorder(pine.opacity(0.56), lineWidth: 1.4).allowsHitTesting(false)
            }
        }
        .dropDestination(for: String.self) { items, _ in
            guard let value = items.first, let id = UUID(uuidString: value),
                  book.photos.contains(where: { $0.id == id }) else { return false }
            select(leaf)
            assign(id)
            return true
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

    private func gallery(_ leaf: BookPage, width: CGFloat, height: CGFloat, gap: CGFloat) -> some View {
        let images = photos(on: leaf)
        return ZStack(alignment: .topLeading) {
            if images.isEmpty {
                placeholder.frame(width: width, height: height)
            } else {
                let ratios = images.map { Double($0.pixelWidth) / Double(max(1, $0.pixelHeight)) }
                let rectangles = BookLayoutGeometry.rectangles(
                    for: ratios, in: CGRect(x: 0, y: 0, width: width, height: height), gap: gap
                )
                ForEach(Array(zip(images, rectangles)), id: \.0.id) { photo, frame in
                    canvasPhoto(photo, page: leaf, width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                }
            }
        }
        .frame(width: width, height: height)
        .clipped()
    }

    private func canvasPhoto(_ photo: BookPhoto, page leaf: BookPage, width: CGFloat, height: CGFloat) -> some View {
        let active = leaf.id == page?.id && photo.id == selectedPhoto
        let fills = leaf.layout == .fullPage || leaf.layout == .fullSpread
        let framing = fills ? leaf.framing ?? 0.5 : 0.5
        return Button {
            select(leaf)
            selectedPhoto = photo.id
            inspector = .photos
        } label: {
            preview(photo, framing: framing, fills: fills)
                .frame(width: width, height: height)
                .clipped()
                .overlay {
                    if active {
                        Rectangle().strokeBorder(.white, lineWidth: 3)
                        Rectangle().strokeBorder(pine, lineWidth: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(photo.name)
    }

    private func prose(_ leaf: BookPage, scale: CGFloat) -> some View {
        let empty = leaf.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return Button {
            select(leaf)
            inspector = .page
            Task { @MainActor in
                await Task.yield()
                writing = true
            }
        } label: {
            Text(empty ? tr("Scrivi qui il tuo racconto…", "Write your story here…") : leaf.text)
                .font(.custom("Baskerville", size: empty ? max(10, 14 * scale) : max(1, 14 * scale)))
                .foregroundStyle(empty ? muted : ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var sidePanel: some View {
        VStack(spacing: 0) {
            Picker(tr("Ispettore", "Inspector"), selection: $inspector) {
                Text(tr("Pagina", "Page")).tag(Inspector.page)
                Text(tr("Foto", "Photos")).tag(Inspector.photos)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(14)
            Rectangle().fill(edge).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 21) {
                    if inspector == .page {
                        pageInspector
                    } else {
                        photoInspector
                    }
                }
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(panel)
    }

    @ViewBuilder private var pageInspector: some View {
        if let page {
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
            if page.layout == .text || page.layout == .mixed {
                VStack(alignment: .leading, spacing: 8) {
                    caption(tr("Racconto", "Story"))
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
        VStack(alignment: .leading, spacing: 13) {
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
                if let selectedPhoto, let photo = book.photos.first(where: { $0.id == selectedPhoto }) {
                    selectedPhotoDetails(photo)
                }
                photoGrid
            } else {
                intro(tr("Il libro non contiene ancora foto.", "This book doesn’t have any photos yet."))
            }
        }
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
        let assigned = page?.photoIDs.contains(photo.id) == true
        return VStack(alignment: .leading, spacing: 6) {
            Text(photo.name).font(.system(size: 12, weight: .semibold)).lineLimit(2)
            if let concepts = photo.analysis?.concepts, !concepts.isEmpty {
                intro(concepts.map(conceptName).joined(separator: " · "))
            }
            Button(assigned ? tr("Rimuovi dalla pagina", "Remove from page") : tr("Aggiungi alla pagina", "Add to page")) {
                if assigned { remove(photo.id) } else { assign(photo.id) }
            }
            .disabled(page == nil)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(pine.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }

    private var photoGrid: some View {
        let filtered = book.photos.filter { photo in
            let concepts = photo.analysis?.concepts ?? []
            let matches = concept.map { concepts.contains($0) } ?? true
            let keywords = [photo.name] + concepts.map(conceptName) + (photo.analysis?.labels ?? [])
            return matches && (search.isEmpty || keywords.contains { $0.localizedStandardContains(search) })
        }
        return VStack(alignment: .leading, spacing: 7) {
            if filtered.isEmpty { intro(tr("Nessuna foto corrispondente.", "No matching photos.")) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 67), spacing: 7)], spacing: 7) {
                ForEach(filtered) { photo in
                    let active = photo.id == selectedPhoto
                    let used = page?.photoIDs.contains(photo.id) == true
                    Button {
                        selectedPhoto = photo.id
                    } label: {
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
                    }
                    .buttonStyle(.plain)
                    .draggable(photo.id.uuidString)
                    .help(photo.name)
                    .accessibilityLabel(photo.name)
                    .contextMenu {
                        Button(tr("Aggiungi alla pagina", "Add to page")) { assign(photo.id) }
                            .disabled(page == nil || used)
                    }
                }
            }
        }
    }

    private func preview(_ photo: BookPhoto, small: Bool = false, framing: Double = 0.5, fills: Bool = true) -> some View {
        let url = BookStorage.assetURL(filename: photo.filename, in: directory)
        return GeometryReader { geometry in
            if let image = EditorImageCache.image(at: url, small: small) {
                let scaleX = geometry.size.width / image.size.width
                let scaleY = geometry.size.height / image.size.height
                let scale = fills ? max(scaleX, scaleY) : min(scaleX, scaleY)
                let width = image.size.width * scale
                let height = image.size.height * scale
                let amount = min(1, max(0, framing))
                Image(nsImage: image)
                    .resizable()
                    .frame(width: width, height: height)
                    .position(
                        x: width / 2 + (geometry.size.width - width) * amount,
                        y: height / 2 + (geometry.size.height - height) * amount
                    )
                    .accessibilityHidden(true)
            } else {
                placeholder
            }
        }
        .clipped()
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
        page.photoIDs.compactMap(book.photo)
    }

    private func select(_ leaf: BookPage) {
        if leaf.id != page?.id {
            selectedPhoto = nil
            writing = false
        }
        selection = leaf.id
    }

    private func setLayout(_ layout: PageLayout) {
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

    private func deletePage() {
        guard let index else { return }
        editPages(tr("Elimina pagina", "Delete Page")) { $0.remove(at: index) }
        selection = book.pages.isEmpty ? nil : book.pages[min(index, book.pages.count - 1)].id
        selectedPhoto = nil
    }

    private func move(_ offset: Int) {
        guard let index, book.pages.indices.contains(index + offset) else { return }
        if let page { selection = page.id }
        editPages(tr("Sposta pagina", "Move Page")) { $0.swapAt(index, index + offset) }
    }

    private func assign(_ id: UUID) {
        guard let index else { return }
        let leaf = book.pages[index]
        guard !leaf.photoIDs.contains(id) else { return }
        editPages(tr("Aggiungi foto", "Add Photo")) { pages in
            switch leaf.layout {
            case .fullPage, .fullSpread:
                pages[index].photoIDs.insert(id, at: 0)
            case .text:
                pages[index].layout = .mixed
                pages[index].photoIDs.append(id)
            case .gallery, .mixed:
                pages[index].photoIDs.append(id)
            }
        }
        selectedPhoto = id
    }

    private func remove(_ id: UUID) {
        guard let index else { return }
        editPages(tr("Rimuovi foto", "Remove Photo")) { pages in
            pages[index].photoIDs.removeAll { $0 == id }
        }
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
        if let undoManager {
            let binding = $book
            undoTarget.register(undoManager, binding: binding, bookID: book.id, pages: previous, name: name)
        }
    }

}

private final class EditorPageUndo {
    func register(_ manager: UndoManager, binding: Binding<Book>, bookID: UUID, pages: [BookPage], name: String) {
        manager.registerUndo(withTarget: self) { [weak manager] target in
            guard let manager, binding.wrappedValue.id == bookID else { return }
            let current = binding.wrappedValue.pages
            let currentByID = Dictionary(current.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            binding.wrappedValue.pages = pages.map { page in
                guard let latest = currentByID[page.id] else { return page }
                var restored = page
                restored.text = latest.text
                restored.framing = latest.framing
                return restored
            }
            target.register(manager, binding: binding, bookID: bookID, pages: current, name: name)
        }
        manager.setActionName(name)
    }
}

private enum EditorImageCache {
    static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = 100 * 1024 * 1024
        return cache
    }()

    static func image(at url: URL, small: Bool) -> NSImage? {
        let key = "\(url.path):\(small)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let pixels = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: small ? 180 : 1440
              ] as CFDictionary) else { return nil }
        let image = NSImage(cgImage: pixels, size: NSSize(width: pixels.width, height: pixels.height))
        cache.setObject(image, forKey: key, cost: pixels.bytesPerRow * pixels.height)
        return image
    }
}
