import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension EditorView {
    var canvas: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Group {
                    if let coverSide {
                        Text(coverName(coverSide))
                    } else if let page {
                        Text(page.id == book.pages.first?.id
                             ? tr("First Page")
                             : tr("Page") + " " + spreadNumber([page]))
                    }
                }
                .font(.callout.weight(.medium))
                .foregroundStyle(muted)
                .monospacedDigit()
                Spacer()
                if compareOriginal {
                    Button(tr("Return to Edits")) { compareOriginal = false }
                        .controlSize(.small)
                } else if comparePhotoOriginal != nil {
                    Button(tr("Return to Edits")) { comparePhotoOriginal = nil }
                        .controlSize(.small)
                }
                canvasViewControls
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            GeometryReader { geometry in
                if let coverSide {
                    let scale = zoom.scale(viewport: geometry.size, artboard: book.format.pageSize)
                    canvasViewport(geometry.size) { coverCanvas(coverSide, scale: scale).shadow(color: .black.opacity(0.16), radius: 12, x: 0, y: 7) }
                } else if let page {
                    canvasViewport(geometry.size, outset: printGuidesOutset(viewport: geometry.size, page: page)) {
                        canvasSpread(page, viewport: geometry.size)
                    }
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: "book").font(.system(size: 33, weight: .ultraLight)).foregroundStyle(pine)
                        Text(tr("Your book starts here"))
                            .font(.system(size: 28, design: .serif))
                        Button(tr("Add a page")) { insert(.gallery) }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .overlay(alignment: .bottom) {
            Group {
                if let cropSession {
                    cropToolbar(cropSession)
                } else if let coverSide {
                    coverTools(coverSide)
                } else if let page {
                    canvasTools(page)
                }
            }
            .editorDropFrame(.canvasHUD)
            .padding(.bottom, 14)
        }
        .overlay(alignment: .top) {
            if let canvasNotice {
                Label(canvasNotice, systemImage: "info.circle")
                    .font(.callout)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .floatingCapsule()
                    .padding(.top, 44)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
    }

    /// Page view and zoom: a small floating control in the corner of the canvas.
    var canvasViewControls: some View {
        HStack(spacing: 2) {
            Picker(tr("View"), selection: $showSpread) {
                Image(systemName: "rectangle.portrait").tag(false)
                    .accessibilityLabel(tr("Single Page"))
                Image(systemName: "book").tag(true)
                    .accessibilityLabel(tr("Two-Page View"))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .disabled(coverSide != nil)
            .help(tr("Single or two-page view"))
            Menu {
                Picker(tr("Page Zoom"), selection: $zoom) {
                    ForEach(CanvasZoom.all, id: \.self) { level in
                        Text(zoomName(level)).tag(level)
                    }
                }
                .pickerStyle(.inline)
                Divider()
                Toggle(tr("Gutter Guide"), isOn: $gutterGuide)
                Toggle(tr("Print Guides"), isOn: Binding(get: { printGuides }, set: { setPrintGuides($0) }))
                    .help(tr("Show the safe margin and the bleed on the pages"))
            } label: {
                Text(zoomName(zoom)).monospacedDigit()
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(.horizontal, 8)
            .help(tr("Page Zoom"))
        }
        .controlSize(.small)
        .padding(4)
        .floatingCapsule()
        .editorDropFrame(.canvasViewControls)
    }

    /// Turns the guides on or off. The first time in a session a short legend explains the two lines.
    func setPrintGuides(_ on: Bool) {
        printGuides = on
        guard on, !PrintGuidesLegend.shown else { return }
        PrintGuidesLegend.shown = true
        showCanvasNotice(tr("Keep text inside the dashed line. Photos that reach the edge extend to the outer line."))
    }

    /// How far the bleed line reaches outside the artboard on screen, in points; 0 with the guides off.
    func printGuidesOutset(viewport: CGSize, page: BookPage) -> CGFloat {
        guard printGuides else { return 0 }
        let spread = showSpread ? groups.first { $0.contains { $0.id == page.id } } ?? [page] : [page]
        let wide = page.effectiveLayout == .fullSpread
        let blankLeft = showSpread && !wide && spread.count == 1 && page.id == book.pages.first?.id
            && book.printSettings?.firstPageOnRight == true
        let size = book.format.pageSize
        let count = wide || blankLeft ? 2 : spread.count
        let scale = zoom.scale(viewport: viewport, artboard: CGSize(width: size.width * CGFloat(count), height: size.height))
        return CGFloat((book.printSettings ?? PrintSettings()).bleedMM * PrintGuides.pointsPerMM) * scale
    }

    /// The guides of the pages in a spread, placed where the pages are drawn.
    func printGuidePages(_ spread: [BookPage], blankLeft: Bool, scale: CGFloat) -> [PrintGuidesOverlay.Page] {
        let size = book.format.pageSize
        let settings = book.printSettings ?? PrintSettings()
        // A print service adds its binding margin; the side comes from the printed imposition.
        let plan = PrintPlan(book: book)
        let right = plan == nil ? [] : BookPDF.rightPageIDs(book)
        var x = blankLeft ? size.width * scale : 0
        return spread.map { leaf in
            let wide = leaf.effectiveLayout == .fullSpread
            let width = wide ? size.width * 2 : size.width
            defer { x += width * scale }
            let pageSize = CGSize(width: width, height: size.height)
            let zones = plan?.guideZones(pageSize: pageSize, onRight: right.contains(leaf.id), spread: wide,
                                         safeMM: settings.safeMM) ?? []
            return PrintGuidesOverlay.Page(
                origin: CGPoint(x: x, y: 0),
                guides: PrintGuides.frames(pageSize: pageSize, settings: settings, zones: zones))
        }
    }

    func zoomName(_ level: CanvasZoom) -> String {
        switch level {
        case .fitPage: tr("Fit Page")
        case .fitWidth: tr("Fit Width")
        case let .percent(value): "\(value)%"
        }
    }

    /// The artboard draws its own shadow, so the print guides around it do not get one. `outset` is how
    /// far the guides reach outside the artboard; the scroll padding grows to keep the bleed line visible.
    func canvasViewport<Artboard: View>(_ viewport: CGSize, outset: CGFloat = 0,
                                        @ViewBuilder content: () -> Artboard) -> some View {
        ScrollView([.horizontal, .vertical]) {
            content()
                .padding(.horizontal, max(20, outset + 6))
                .padding(.vertical, max(24, outset + 6))
                .frame(minWidth: viewport.width, minHeight: viewport.height)
        }
        .defaultScrollAnchor(.center)
        .editorDropFrame(.canvasViewport)
    }

    func canvasSpread(_ page: BookPage, viewport: CGSize) -> some View {
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
        .shadow(color: .black.opacity(0.16), radius: 12, x: 0, y: 7)
        .overlay {
            if printGuides {
                PrintGuidesOverlay(pages: printGuidePages(spread, blankLeft: blankLeft, scale: scale), scale: scale)
            }
        }
    }

    @ViewBuilder func canvasTools(_ page: BookPage) -> some View {
        if let photo = canvasPhotoSelection, photo.pageID == page.id {
            HStack(spacing: 2) {
                hudButton(tr("Crop"), "crop") { beginCrop(photo.photoID, in: page) }
                hudButton(tr("Adjust"), "slider.horizontal.3") { showPhotoSection(film: false) }
                hudButton(tr("Film"), "camera.filters") { showPhotoSection(film: true) }
                Divider().frame(height: 16).padding(.horizontal, 3)
                hudButton(tr("Remove from Page"), "trash", role: .destructive, iconOnly: true) {
                    _ = deleteSelectedCanvasObject()
                }
            }
            .padding(4)
            .floatingCapsule()
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    func hudButton(_ title: String, _ symbol: String, role: ButtonRole? = nil, iconOnly: Bool = false,
                           action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Group {
                if iconOnly {
                    Image(systemName: symbol)
                } else {
                    Label(title, systemImage: symbol)
                }
            }
            .font(.callout)
            .padding(.horizontal, iconOnly ? 8 : 10)
            .padding(.vertical, 6)
            .contentShape(Capsule())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(role == .destructive ? Theme.destructive : ink)
        .help(title)
        .accessibilityLabel(title)
    }

    @ViewBuilder func coverTools(_ side: CoverSide) -> some View {
        let photoSelected = canvasPhotoSelection?.surface == .cover(front: side == .front)
        if photoSelected || coverEditorialValue(side).wrappedValue.isEmpty {
        HStack(spacing: 2) {
            if photoSelected {
                hudButton(tr("Crop"), "crop") { beginCoverCrop(side) }
                hudButton(tr("Adjust"), "slider.horizontal.3") { showPhotoSection(film: false) }
            }
            if coverEditorialValue(side).wrappedValue.isEmpty {
                hudButton(tr("Add Text"), "textformat") {
                    showsInspector = true
                    inspector = .page
                    Task { @MainActor in
                        await Task.yield()
                        if coverSide == side { writing = true }
                    }
                }
            }
        }
        .padding(4)
        .floatingCapsule()
        }
    }

    func cropToolbar(_ session: CropSession) -> some View {
        HStack(spacing: 8) {
            Label(tr("Crop"), systemImage: "crop")
                .font(.system(size: 11, weight: .semibold))
            Divider().frame(height: 17)
            action("minus", tr("Zoom Out Photo")) { magnifyCrop(1 / 1.15) }
                .disabled(session.crop.zoom <= 1)
            Text(session.crop.zoom.formatted(.percent.precision(.fractionLength(0))))
                .font(.system(size: 11).monospacedDigit())
                .frame(minWidth: 43)
            action("plus", tr("Zoom In Photo")) { magnifyCrop(1.15) }
                .disabled(session.crop.zoom >= 12)
            Divider().frame(height: 17)
            Button(tr("Cancel")) { cropSession = nil }
                .keyboardShortcut(.cancelAction)
            Button(tr("Done")) { finishCrop() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .floatingCapsule()
    }

    func canvasPage(_ leaf: BookPage, scale: CGFloat) -> some View {
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
                // A slot is empty when no photo covers it, also after a photo was moved out of it.
                ForEach(composition.emptySlots, id: \.index) { slot in
                    positioned(placeholder, in: scaled(slot.frame, by: scale))
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
                        .zIndex(Double(composition.rank(.photo(item.id))))
                }
            }
            ForEach(composition.captions) { caption in
                if editingEditorial != .caption(page: leaf.id, photo: caption.photoID) {
                    canvasCaptionTarget(caption, leaf: leaf, scale: scale)
                        .zIndex(Double(composition.rank(.photo(caption.photoID))) - 0.25)
                }
            }
            canvasStory(leaf, composition: composition, blocks: blocks, backings: backings, bounds: bounds, scale: scale)
                .zIndex(editsStory(on: leaf.id) ? 10_000 : Double(composition.rank(.story)))
            ForEach(composition.textBoxes) { box in
                let targets = alignmentTargets(in: composition, at: scale, excluding: .textBox(box.id), blocks: blocks)
                canvasTextBox(box, leaf: leaf, bounds: bounds, scale: scale, alignmentTargets: targets)
                    .zIndex(inlineEditingBox == box.id ? 10_000 : Double(composition.rank(.textBox(box.id))))
            }
            canvasCaptionEditor(leaf, composition: composition, scale: scale)
                .zIndex(10_000)
            if let folio = composition.folio {
                let label = style.typography(String(number(of: leaf)), heading: nil, mixed: true)
                positioned(editorialText(label, scale: scale), in: scaled(folio, by: scale))
                    .allowsHitTesting(false).accessibilityHidden(true)
                    .zIndex(20_000)
            }
            if let session = cropSession, session.surface == .canvasPage(leaf.id),
               let item = composition.photos.first(where: { $0.id == session.photoID }) {
                let targets = alignmentTargets(in: composition, at: scale, excluding: .photo(item.id), blocks: blocks)
                canvasCrop(session, photo: item.photo, bounds: bounds, scale: scale, alignmentTargets: targets)
                    .zIndex(20_001)
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
                } else if case let .replace(incoming) = incomingPhoto {
                    photoSwapIndicator(incoming, symbol: "photo.badge.arrow.down")
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

    func photoSwapIndicator(_ target: CanvasPhotoSwap.Target, symbol: String = "arrow.left.arrow.right") -> some View {
        let indicator = Rectangle()
            .strokeBorder(.white, lineWidth: 4)
            .overlay {
                Rectangle().strokeBorder(pine, style: StrokeStyle(lineWidth: 2, dash: [6, 3]))
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(pine, in: RoundedRectangle(cornerRadius: 4))
                    .padding(5)
            }
        return positioned(indicator, in: target.frame)
    }

    func alignmentTargets(in composition: PageComposition, at scale: CGFloat,
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
        // The page edges are added by each control with a longer reach (CanvasAlignment.edgeToleranceFactor).
        return photos + textBoxes + editorial
    }

    @ViewBuilder func canvasStory(_ leaf: BookPage, composition: PageComposition,
                                          blocks: [PageComposition.TextBlock], backings: [CGRect],
                                          bounds: CGRect, scale: CGFloat) -> some View {
        if let group = storyGroupFrame(blocks, backings: backings) {
            let object = EditorialObject.storyGroup(leaf.id)
            CanvasStoryGroup(frame: scaled(group, by: scale), bounds: bounds,
                             backdrops: backings.map { scaled($0, by: scale) },
                             alignmentTargets: composition.photos.map { scaled($0.frame.intersection(composition.bounds), by: scale) }
                                + composition.textBoxes.map { scaled($0.frame.rect(in: composition.bounds), by: scale) },
                             selected: selectedEditorial == object,
                             moveLabel: tr("Move Story Group"),
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

    /// True while the page's heading or story is typed in place; a caption being typed leaves the story where it is.
    func editsStory(on pageID: UUID) -> Bool {
        if case let .page(id, _)? = editingEditorial { return id == pageID }
        return false
    }

    func storyGroupFrame(_ blocks: [PageComposition.TextBlock], backings: [CGRect]) -> CGRect? {
        let visible = blocks.filter { !$0.frame.isEmpty }
        let occupied = visible.lazy.filter { $0.text.length > 0 }.count
        guard occupied > 1 || (occupied > 0 && !backings.isEmpty) else { return nil }
        return (visible.map(\.frame) + backings).reduce(CGRect.null) { $0.union($1) }
    }

    func pageHitMap(_ leaf: BookPage, composition: PageComposition, blocks: [PageComposition.TextBlock],
                            backings: [CGRect], bounds: CGRect, scale: CGFloat) -> CanvasHitMap {
        typealias Region = CanvasHitMap.Region
        var regions: [Region] = []
        let group = storyGroupFrame(blocks, backings: backings)
        for layer in composition.layers {
            switch layer {
            case let .photo(id):
                if let item = composition.photos.first(where: { $0.id == id }) {
                    regions.append(Region(frame: item.frame, target: .photo(id)))
                }
                if let caption = composition.caption(for: id) {
                    regions.append(Region(frame: caption.area, target: .caption(id)))
                }
            case .story:
                regions += backings.map { Region(frame: $0, target: group == nil ? .paper : .storyGroup) }
                regions += blocks.map { Region(frame: $0.frame, target: .story($0.role)) }
                if let group {
                    let grip = CanvasStoryGrip.frame(for: scaled(group, by: scale), in: bounds)
                    regions.append(Region(frame: scaled(grip, by: 1 / scale), target: .storyGroup))
                }
            case let .textBox(id):
                if let box = composition.textBoxes.first(where: { $0.id == id }) {
                    regions.append(Region(frame: box.frame.rect(in: composition.bounds), target: .textBox(id)))
                }
            }
        }
        // Inline editors sit above other text, while the active crop intercepts clicks within its frame.
        if let editingEditorial, case let .page(id, role) = editingEditorial, id == leaf.id,
           let block = blocks.first(where: { $0.role == role }) {
            regions.append(Region(frame: block.frame, target: .story(role)))
        }
        if case let .caption(id, photoID)? = editingEditorial, id == leaf.id,
           composition.photos.contains(where: { $0.id == photoID }) {
            let frame = captionEditingFrame(photoID, on: leaf, in: composition)
            regions.append(Region(frame: frame, target: .caption(photoID)))
        }
        if let inlineEditingBox, let box = composition.textBoxes.first(where: { $0.id == inlineEditingBox }) {
            regions.append(Region(frame: box.frame.rect(in: composition.bounds), target: .textBox(box.id)))
        }
        if let cropSession, cropSession.surface == .canvasPage(leaf.id) {
            regions.append(Region(frame: cropSession.frame.photoRect(in: composition.bounds), target: .crop))
        }
        return CanvasHitMap(bounds: composition.bounds, regions: regions)
    }

    @ViewBuilder func canvasStoryContents(_ leaf: BookPage, composition: PageComposition,
                                                  blocks: [PageComposition.TextBlock], backings: [CGRect],
                                                  bounds: CGRect, scale: CGFloat) -> some View {
        storyBacking(backings, scale: scale)
        ForEach(blocks) { block in
            let targets = alignmentTargets(in: composition, at: scale, excluding: .editorial(block.role), blocks: blocks)
            canvasEditorialText(block, in: leaf, bounds: bounds, scale: scale, targets: targets)
        }
    }

    @ViewBuilder func storyBacking(_ rects: [CGRect], scale: CGFloat) -> some View {
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

    var placeholder: some View {
        Rectangle().fill(pine.opacity(0.06))
            .overlay {
                Image(systemName: "photo")
                    .font(.system(size: 25, weight: .ultraLight))
                    .foregroundStyle(pine.opacity(0.65))
                    .accessibilityLabel(tr("No photo"))
            }
    }

    func canvasPhoto(_ item: PageComposition.Photo, leaf: BookPage, composition: PageComposition,
                             bounds: CGRect, scale: CGFloat, alignmentTargets: [CGRect], textFrames: [CGRect]) -> some View {
        let frame = scaled(item.frame, by: scale)
        let active = canvasPhotoSelection?.pageID == leaf.id && canvasPhotoSelection?.photoID == item.id
        let swapTargetAt: (CGPoint) -> CanvasPhotoSwap.Target? = { location in
            guard let pageFrame = dropFrames[.canvasPage(leaf.id)] else { return nil }
            let editorPoint = CGPoint(x: pageFrame.minX + location.x, y: pageFrame.minY + location.y)
            guard dropFrames[.canvasViewport]?.contains(editorPoint) == true else { return nil }
            return photoSwapTarget(item.id, at: location, in: bounds, composition: composition, textFrames: textFrames)
        }
        // The caption is drawn with its photo, so it shares the photo's layer and follows a drag.
        let caption = editingEditorial == .caption(page: leaf.id, photo: item.id) ? nil : composition.caption(for: item.id)
        let attachment: ((CGRect) -> AnyView)? = caption.map { caption in
            { shown in AnyView(canvasCaption(caption, photoFrame: frame, shown: shown, scale: scale)) }
        }
        return CanvasObjectControl(frame: frame, bounds: bounds, selected: active,
                                   minimumSize: CGSize(width: 40 * scale, height: 40 * scale),
                                   accessibilityName: item.photo.name, alignmentTargets: alignmentTargets,
                                   allowsPhotoOverflow: true, preservesAspectRatio: true,
                                   moveSpace: .named(leaf.id), swapTargetAt: swapTargetAt,
                                   onSwap: { swapPhoto(item.id, with: $0, on: leaf.id) },
                                   onDoubleClick: { beginCrop(item.id, in: leaf) },
                                   onDoubleClickAt: { doubleClickPhoto(item.id, at: $0, frame: frame, composition: composition,
                                                                       scale: scale, leaf: leaf) },
                                   attachment: attachment,
                                   onSelect: { activateCanvas { selectCanvasPhoto(item.id, in: leaf) } },
                                   onNudge: { nudgeFromKeyboard($0) { selectCanvasPhoto(item.id, in: leaf) } },
                                   onChange: { updatePhotoFrame(item.id, in: leaf, to: PageRect($0, in: bounds)) }) { _ in
            preview(item.photo, crop: item.crop, fills: item.fills)
                .overlay(alignment: .topLeading) {
                    resolutionBadge(item.photo, frame: item.frame, fills: item.fills, crop: item.crop,
                                    shown: frame, bounds: bounds)
                }
        }
        .accessibilityAction(named: Text(tr("Crop Photo"))) { beginCrop(item.id, in: leaf) }
        .accessibilityAction(named: Text(item.photo.printedCaption == nil ? tr("Add Caption") : tr("Edit Caption"))) {
            beginCaptionEditing(item.id, in: leaf)
        }
        .accessibilityAction(named: Text(tr("Remove from Page", key: "canvas.remove_box_from_page"))) {
            deleteCanvasPhoto(item.id, from: leaf.id)
        }
    }

    func canvasCrop(_ session: CropSession, photo: BookPhoto, bounds: CGRect, scale: CGFloat,
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

    func canvasEditorialText(_ block: PageComposition.TextBlock, in leaf: BookPage, bounds: CGRect,
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
                                       type: type, label: title ? tr("Heading") : tr("Story"),
                                       frame: scaled(block.frame, by: scale), bounds: bounds, scale: scale, targets: targets,
                                       textInk: title ? (overPhoto ? style.overlayTitleInk : style.titleInk)
                                           : (overPhoto ? style.overlayInk : style.ink),
                                       textPaper: overPhoto ? style.overlayPaper : style.paper,
                                       onSelect: { selectEditorial(object, on: leaf) },
                                       onChange: { movePageText(block.role, on: leaf.id, to: PageRect($0, in: bounds)) })
    }

    @ViewBuilder func editableEditorialObject(
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
                .foregroundStyle(Color(cgColor: EditorialStyle.color(type.color ?? textInk ?? style.ink)))
                .scrollContentBackground(.hidden)
                .background(Color(cgColor: EditorialStyle.color(textPaper ?? style.paper)))
                .overlay { Rectangle().strokeBorder(pine, lineWidth: 1.5).allowsHitTesting(false) }
                .focused($editorialFocus, equals: object)
                .checksSpelling()
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
            .accessibilityAction(named: Text(tr("Edit Text")), beginEditing)
        }
    }

    @ViewBuilder func canvasTextBox(_ box: PageTextBox, leaf: BookPage, bounds: CGRect, scale: CGFloat,
                                            alignmentTargets: [CGRect]) -> some View {
        let active = selectedBox == box.id && leaf.id == page?.id
        let style = book.editorialStyle
        let empty = box.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let label = tr("Text Box")
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
                .background(box.fill(paper: style.paper).map { Color(cgColor: EditorialStyle.color($0)) }
                    .opacity(empty ? 0.82 : 1))
                .overlay {
                    if let border = box.border(ink: style.ink) {
                        Rectangle().strokeBorder(Color(cgColor: EditorialStyle.color(border.color)),
                                                 lineWidth: max(0.5, border.width * scale))
                            .allowsHitTesting(false)
                    }
                }
                .overlay {
                    if empty && !active {
                        Rectangle().strokeBorder(pine.opacity(0.48), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
            }
            .accessibilityAction(named: Text(tr("Edit Text"))) {
                beginInlineBoxEditing(box.id, in: leaf)
            }
        }
    }

    func inlineBoxEditor(_ box: PageTextBox, leaf: BookPage, scale: CGFloat) -> some View {
        let style = book.editorialStyle
        let type = style.defaultBodyStyle.applying(book.bodyStyle(for: box))
        let font = type.fontName.flatMap { NSFont(name: $0, size: 12)?.fontName } ?? style.bodyFont
        let alignment: TextAlignment = type.alignment == .center ? .center : (type.alignment == .right ? .trailing : .leading)
        return TextEditor(text: textInBox(box.id, on: leaf.id))
            .font(.custom(font, size: max(1, (type.pointSize ?? style.bodySize) * scale)))
            .multilineTextAlignment(alignment)
            .foregroundStyle(Color(cgColor: EditorialStyle.color(type.color ?? style.ink)))
            .scrollContentBackground(.hidden)
            .focused($inlineBoxFocus, equals: box.id)
            .checksSpelling()
            .padding(max(0, box.textInsetPoints * scale - 4))
            .background(Color(cgColor: EditorialStyle.color(box.fill(paper: style.paper) ?? style.paper)).opacity(box.hidesBackground == true ? 0.7 : 1))
            .overlay { Rectangle().strokeBorder(pine, lineWidth: 1.5).allowsHitTesting(false) }
            .onExitCommand(perform: endInlineTextEditing)
            .accessibilityLabel(tr("Text Box on Page"))
            .task(id: box.id) {
                await Task.yield()
                if NSApp.isActive && inlineEditingBox == box.id { inlineBoxFocus = box.id }
            }
    }

    func editorialText(_ contents: NSAttributedString, scale: CGFloat) -> some View {
        Canvas { graphics, size in
            graphics.withCGContext { context in
                context.scaleBy(x: scale, y: scale)
                let bounds = CGRect(x: 0, y: 0, width: size.width / scale, height: size.height / scale)
                EditorialTypesetter.draw(contents, in: bounds, context: context)
            }
        }
        .clipped()
    }

    func positioned<Content: View>(_ content: Content, in rect: CGRect) -> some View {
        content.frame(width: max(0, rect.width), height: max(0, rect.height))
            .position(x: rect.midX, y: rect.midY)
    }

    func scaled(_ rect: CGRect, by scale: CGFloat) -> CGRect {
        rect.applying(CGAffineTransform(scaleX: scale, y: scale))
    }
}
