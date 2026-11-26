import SwiftUI

/// Map pages in the editor (T14): drawing the map with the shared renderer, the Page tab's map
/// settings and the list of places.
extension EditorView {
    /// The map under everything else on the page, drawn by the same code as the PDF.
    func mapLayer(_ map: MapComposition, bounds: CGRect, scale: CGFloat) -> some View {
        let style = book.editorialStyle
        return Canvas { graphics, _ in
            graphics.withCGContext { context in
                context.scaleBy(x: scale, y: scale)
                MapRenderer.draw(map, style: style, in: context)
            }
        }
        .frame(width: bounds.width * scale, height: bounds.height * scale)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("Map"))
        .accessibilityValue(map.places.compactMap(\.name).joined(separator: ", "))
    }

    /// The editor's note on a map with nothing to show. The PDF draws nothing there.
    @ViewBuilder func mapNotice(_ map: MapComposition, scale: CGFloat) -> some View {
        let message: String? = map.isEmpty ? tr("No photo in this book has a location")
            : (map.missingGeography && MapDataStore.shared.isUnavailable ? tr("The map data is missing from this copy of the app.") : nil)
        if let message {
            positioned(
                Label(message, systemImage: "map")
                    .font(.callout)
                    .foregroundStyle(muted)
                    .multilineTextAlignment(.center)
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(pine.opacity(0.05))
                    .overlay { Rectangle().strokeBorder(pine.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3])) },
                in: scaled(map.frame, by: scale))
            .allowsHitTesting(false)
        }
    }

    func insertMapPage() {
        insert(arrangement: .map)
    }

    /// Photos whose coordinates are not in the book yet. Books made before locations were saved on
    /// import keep them only in the files or in Photos; a map page reads them once, like the Photo
    /// Library's sorting by place.
    var mapLocationsToRead: [PlaceAsset] {
        guard book.pages.contains(where: \.isMapPage) else { return [] }
        return book.photos.compactMap { photo in
            guard photo.location?.latitude == nil else { return nil }
            let asset = PlaceAsset(id: photo.id, filename: photo.filename, sourceID: photo.sourceID)
            return scannedPlaceAssets.contains(asset) ? nil : asset
        }
    }

    /// Reads the missing coordinates and keeps them in the book, so the map, Issues, the PDF and the
    /// command line all see them. Not an undo step: it records facts about the photos, not an edit.
    func readMapLocations() async {
        adoptReadLocations()
        let pending = mapLocationsToRead
        guard !pending.isEmpty else { return }
        await readPhotoPlaces(pending)
        adoptReadLocations()
    }

    func adoptReadLocations() {
        guard book.pages.contains(where: \.isMapPage), !actions.isReadOnly,
              let photos = Book.photosAdopting(placesRead, in: book.photos) else { return }
        book.photos = photos
    }

    /// Changes the map of a page as one undo step.
    func changeMap(on pageID: UUID, name: String, _ change: (inout PageMap) -> Void) {
        guard let index = book.pages.firstIndex(where: { $0.id == pageID }) else { return }
        var map = book.pages[index].map ?? PageMap()
        change(&map)
        let next: PageMap? = map == PageMap() ? nil : map
        guard next != book.pages[index].map else { return }
        editPages(name) { $0[index].map = next }
    }

    func mapBinding<Value: Equatable>(_ pageID: UUID, _ read: @escaping (PageMap) -> Value, name: String,
                                      write: @escaping (inout PageMap, Value) -> Void) -> Binding<Value> {
        Binding(
            get: { read(book.pages.first { $0.id == pageID }?.map ?? PageMap()) },
            set: { value in changeMap(on: pageID, name: name) { write(&$0, value) } }
        )
    }

    /// Renames a place (an empty name goes back to the suggested one) or hides it.
    func changeMapLabel(_ key: String, on pageID: UUID, name: String? = nil, hidden: Bool? = nil) {
        changeMap(on: pageID, name: tr("Edit Place Name")) { map in
            var labels = map.labels ?? []
            var label = labels.first { $0.key == key } ?? MapLabel(key: key)
            if let name { label.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : name }
            if let hidden { label.hidden = hidden ? true : nil }
            labels.removeAll { $0.key == key }
            if label.name != nil || label.hidden != nil { labels.append(label) }
            map.labels = labels.isEmpty ? nil : labels.sorted { $0.key < $1.key }
        }
    }

    /// The Page tab of a map page: which photos, route, names, borders, zoom, and the places.
    @ViewBuilder func mapInspector(_ leaf: BookPage) -> some View {
        let map = pageComposition(leaf).map
        VStack(alignment: .leading, spacing: 8) {
            caption(tr("Map"))
            Picker(tr("Photos"), selection: mapBinding(leaf.id, \.resolvedPhotos, name: tr("Map Photos")) { $0.photos = $1 == .placed ? nil : $1 }) {
                Text(tr("Placed in the book")).tag(PageMap.Photos.placed)
                Text(tr("All in the library")).tag(PageMap.Photos.all)
            }
            .help(tr("Which photos the map shows"))
            Toggle(tr("Route"), isOn: mapBinding(leaf.id, \.route, name: tr("Map Route")) { $0.showsRoute = $1 ? nil : false })
                .help(tr("A line through the places in the order the photos were taken"))
            Toggle(tr("Place names"), isOn: mapBinding(leaf.id, \.placeNames, name: tr("Map Place Names")) { $0.showsLabels = $1 ? nil : false })
                .help(tr("Names next to the places, in the book's caption style"))
            Toggle(tr("Country borders"), isOn: mapBinding(leaf.id, \.countryBorders, name: tr("Country Borders")) { $0.showsBorders = $1 ? nil : false })
                .help(tr("Borders as Natural Earth draws them; disputed ones are dashed"))
            HStack(spacing: 6) {
                Button(tr("Adjust Map")) { beginMapAdjust(on: leaf.id) }
                    .help(tr("Drag the map to move it and pinch or scroll to zoom; Done or Esc to finish"))
                Button(tr("Fit to Places")) { fitMapToPlaces(on: leaf.id) }
                    .help(tr("Show every place again, centered"))
                    .disabled(leaf.map?.zoom == nil && leaf.map?.centerOffset == nil)
            }
            MapZoomSlider(zoom: leaf.map?.resolvedZoom ?? 1, language: language) { value in
                // While the map is framed on the canvas the slider is part of that session's one undo step.
                if let session = mapAdjust, session.pageID == leaf.id {
                    zoomMap(by: value / session.baseZoom, ended: true)
                } else {
                    changeMap(on: leaf.id, name: tr("Map Zoom")) { $0.zoom = abs(value - 1) < 0.001 ? nil : value }
                }
            }
            if let map, !map.isEmpty {
                caption(tr("Places"))
                ForEach(map.places) { place in
                    MapPlaceRow(name: leaf.map?.label(place.key)?.name ?? "", suggested: place.suggestedName,
                                shownName: place.name ?? place.suggestedName, shown: true, language: language,
                                rename: { changeMapLabel(place.key, on: leaf.id, name: $0) },
                                show: { changeMapLabel(place.key, on: leaf.id, hidden: !$0) })
                }
                // Hidden places stay listed, switched off, so they can come back.
                ForEach(map.hiddenPlaces) { place in
                    let edited = leaf.map?.label(place.key)?.name
                    MapPlaceRow(name: edited ?? "", suggested: place.suggestedName,
                                shownName: edited ?? place.suggestedName, shown: false, language: language,
                                rename: { changeMapLabel(place.key, on: leaf.id, name: $0) },
                                show: { changeMapLabel(place.key, on: leaf.id, hidden: !$0) })
                }
            } else {
                intro(tr("No photo in this book has a location"))
            }
            intro(tr("The map is drawn from Natural Earth's public-domain data: it shows countries and regions, not streets."))
        }
        .controlSize(.small)
    }
}

/// One place of a map in the Page tab: its name, committed when the field is left or Return is pressed
/// (one undo step), and a switch to hide it.
struct MapPlaceRow: View, Localizing {
    let name: String
    let suggested: String?
    /// What VoiceOver calls the place: its name on the map, or the suggested one.
    var shownName: String? = nil
    let shown: Bool
    let language: String
    let rename: (String) -> Void
    let show: (Bool) -> Void

    @State private var draft: String?
    @FocusState private var editing: Bool

    var body: some View {
        HStack(spacing: 6) {
            TextField(suggested ?? tr("No name"), text: Binding(get: { draft ?? name }, set: { draft = $0 }))
                .textFieldStyle(.roundedBorder)
                .focused($editing)
                .onSubmit(commit)
                .onChange(of: editing) { _, now in if !now { commit() } }
                .accessibilityLabel(tr("Place name") + ": " + (shownName ?? tr("No name")))
                .help(tr("A name for this place; empty uses the suggested one"))
            Toggle(tr("Show"), isOn: Binding(get: { shown }, set: { show($0) }))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .accessibilityLabel(tr("Show this place") + ": " + (shownName ?? tr("No name")))
                .help(tr("Show or hide this place: a hidden place has no dot, no name, is left off the route and the map no longer fits it"))
        }
    }

    private func commit() {
        guard let draft else { return }
        self.draft = nil
        if draft != name { rename(draft) }
    }
}

/// The map's zoom from 25 % to 800 %, on a doubling scale so 100 % sits in the useful middle. Dragging shows
/// the value; releasing makes one undo step.
struct MapZoomSlider: View, Localizing {
    let zoom: Double
    let language: String
    let commit: (Double) -> Void

    @State private var draft: Double?

    private var shown: Double { draft ?? zoom }
    private var percent: String { (shown).formatted(.percent.precision(.fractionLength(0)).locale(Locale(identifier: language))) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(tr("Zoom")).font(.system(size: 11))
                Spacer()
                Text(percent).font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
            // Quantized in the setter: a stepped Slider draws a tick per step on macOS.
            Slider(value: Binding(get: { log2(shown) }, set: { draft = Self.zoom(atStep: $0) }),
                   in: log2(PageMap.zoomRange.lowerBound)...log2(PageMap.zoomRange.upperBound)) { editing in
                if !editing, let value = draft {
                    draft = nil
                    if value != zoom { commit(value) }
                }
            }
            .accessibilityLabel(tr("Zoom"))
            .accessibilityValue(percent)
            // VoiceOver adjusts in steps that commit at once.
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: commit(Self.zoom(atStep: log2(zoom) + 0.25))
                case .decrement: commit(Self.zoom(atStep: log2(zoom) - 0.25))
                @unknown default: break
                }
            }
            .help(tr("100% fits every place on the map"))
        }
    }

    /// The zoom for a slider position, rounded to 5 % so 100 % is easy to hit.
    static func zoom(atStep step: Double) -> Double {
        let value = pow(2, step)
        return min(PageMap.zoomRange.upperBound, max(PageMap.zoomRange.lowerBound, (value * 20).rounded() / 20))
    }
}

/// A map being framed on the canvas: the pages before it started (for its one undo step), and the zoom
/// and offset a drag or a pinch started from.
struct MapAdjustSession: Equatable {
    let pageID: UUID
    let before: [BookPage]
    var baseZoom: Double
    var baseOffset: MapOffset
}

/// Framing a map on the canvas, as cropping frames a photo: double-click the map (or **Adjust Map**), drag
/// to move it, pinch, scroll or use the slider to zoom, **Done** or Esc to finish. The whole session is one
/// undo step. Zoom and offset stay in `PageMap` as the region's own fractions, so every surface draws the
/// same framing at any size.
extension EditorView {
    static let mapOffsetLimit = 2.0

    func mapFrame(on leaf: BookPage) -> CGRect? {
        pageComposition(leaf).map?.frame
    }

    func beginMapAdjust(on pageID: UUID) {
        guard let leaf = book.pages.first(where: { $0.id == pageID }), leaf.isMapPage else { return }
        if mapAdjust?.pageID == pageID { return }
        endMapAdjust()
        finishCrop()
        endInlineTextEditing()
        select(leaf)
        clearCanvasSelection()
        editorInput.target = .canvas
        let map = leaf.map ?? PageMap()
        mapAdjust = MapAdjustSession(pageID: pageID, before: book.pages, baseZoom: map.resolvedZoom,
                                     baseOffset: map.centerOffset ?? MapOffset(x: 0, y: 0))
    }

    /// Ends the session and records it as one undo step when it changed anything.
    func endMapAdjust() {
        guard let session = mapAdjust else { return }
        mapAdjust = nil
        registerUndo(session.before, name: tr("Adjust Map"))
    }

    /// Writes the framing live, without an undo step of its own.
    func setMapFraming(on pageID: UUID, zoom: Double?, offset: MapOffset?) {
        guard let index = book.pages.firstIndex(where: { $0.id == pageID }) else { return }
        var map = book.pages[index].map ?? PageMap()
        map.zoom = zoom.map { min(PageMap.zoomRange.upperBound, max(PageMap.zoomRange.lowerBound, $0)) }
            .flatMap { abs($0 - 1) < 0.001 ? nil : $0 }
        map.centerOffset = offset.flatMap { abs($0.x) < 0.0005 && abs($0.y) < 0.0005 ? nil : $0 }
        let next: PageMap? = map == PageMap() ? nil : map
        if book.pages[index].map != next { book.pages[index].map = next }
    }

    /// A drag of `translation` displayed points on a map shown `size` points large moves the map with the
    /// pointer: the offset is a share of the fitted region, divided by the zoom.
    func panMap(by translation: CGSize, shownSize size: CGSize, ended: Bool) {
        guard var session = mapAdjust, size.width > 0, size.height > 0 else { return }
        let offset = MapGeometry.panned(session.baseOffset, by: translation, shownSize: size, zoom: session.baseZoom,
                                        limit: Self.mapOffsetLimit)
        setMapFraming(on: session.pageID, zoom: session.baseZoom, offset: offset)
        if ended {
            session.baseOffset = offset
            mapAdjust = session
        }
    }

    /// Zooms by `factor` from the zoom the gesture started at.
    func zoomMap(by factor: Double, ended: Bool) {
        guard var session = mapAdjust, factor.isFinite, factor > 0 else { return }
        let zoom = min(PageMap.zoomRange.upperBound, max(PageMap.zoomRange.lowerBound, session.baseZoom * factor))
        setMapFraming(on: session.pageID, zoom: zoom, offset: session.baseOffset)
        if ended {
            session.baseZoom = zoom
            mapAdjust = session
        }
    }

    /// Back to the fit of all shown places: in a session it is part of the session's step, otherwise its own.
    func fitMapToPlaces(on pageID: UUID) {
        if var session = mapAdjust, session.pageID == pageID {
            setMapFraming(on: pageID, zoom: nil, offset: nil)
            session.baseZoom = 1
            session.baseOffset = MapOffset(x: 0, y: 0)
            mapAdjust = session
            return
        }
        changeMap(on: pageID, name: tr("Fit to Places")) {
            $0.zoom = nil
            $0.centerOffset = nil
        }
    }

    /// A double-click on blank paper over a map starts framing it.
    func doubleClickCanvas(at point: CGPoint) {
        guard coverSide == nil, cropSession == nil, inlineEditingBox == nil, editingEditorial == nil,
              let leaf = pageUnder(point), leaf.isMapPage, canvasTarget(at: point, on: .canvasPage(leaf.id)) == .paper,
              let local = pagePoint(point, on: leaf.id), mapFrame(on: leaf)?.contains(local) == true else { return }
        beginMapAdjust(on: leaf.id)
    }

    /// While a map is framed, scrolling over it zooms instead of turning the page.
    func scrollCanvas(at point: CGPoint, delta: CGFloat) -> Bool {
        guard let session = mapAdjust, let leaf = pageUnder(point), leaf.id == session.pageID else { return false }
        guard delta != 0 else { return true }
        zoomMap(by: exp(Double(delta) * 0.006), ended: true)
        return true
    }

    /// Whether a point of the editor lies on the map being framed.
    func isOnAdjustedMap(_ point: CGPoint) -> Bool {
        guard let session = mapAdjust, let leaf = book.pages.first(where: { $0.id == session.pageID }),
              dropFrames[.canvasPage(leaf.id)]?.contains(point) == true,
              let local = pagePoint(point, on: leaf.id) else { return false }
        return mapFrame(on: leaf)?.contains(local) == true
    }

    /// The surface over the map while it is framed: drag to move, pinch to zoom.
    @ViewBuilder func mapAdjustSurface(_ leaf: BookPage, map: MapComposition, scale: CGFloat) -> some View {
        if mapAdjust?.pageID == leaf.id {
            let frame = scaled(map.frame, by: scale)
            positioned(
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .overlay { Rectangle().strokeBorder(pine, style: StrokeStyle(lineWidth: 2, dash: [6, 3])) }
                    .gesture(DragGesture(minimumDistance: 1)
                        .onChanged { panMap(by: $0.translation, shownSize: frame.size, ended: false) }
                        .onEnded { panMap(by: $0.translation, shownSize: frame.size, ended: true) })
                    .simultaneousGesture(MagnifyGesture()
                        .onChanged { zoomMap(by: $0.magnification, ended: false) }
                        .onEnded { zoomMap(by: $0.magnification, ended: true) })
                    .onHover { inside in if inside { NSCursor.openHand.push() } else { NSCursor.pop() } }
                    .accessibilityElement()
                    .accessibilityLabel(tr("Map framing"))
                    .accessibilityHint(tr("Drag to move the map; pinch or scroll to zoom"))
                    .accessibilityAction(named: Text(tr("Zoom In"))) { zoomMap(by: 1.25, ended: true) }
                    .accessibilityAction(named: Text(tr("Zoom Out"))) { zoomMap(by: 0.8, ended: true) }
                    .accessibilityAction(named: Text(tr("Fit to Places"))) { fitMapToPlaces(on: leaf.id) },
                in: frame)
        }
    }

    /// The floating bar while a map is framed, like the crop bar.
    func mapAdjustToolbar(_ session: MapAdjustSession) -> some View {
        let zoom = book.pages.first { $0.id == session.pageID }?.map?.resolvedZoom ?? 1
        return HStack(spacing: 8) {
            Label(tr("Adjust Map"), systemImage: "map")
                .font(.system(size: 11, weight: .semibold))
            Divider().frame(height: 17)
            action("minus", tr("Zoom Out")) { zoomMap(by: 1 / 1.25, ended: true) }
                .disabled(zoom <= PageMap.zoomRange.lowerBound)
            Text(zoom.formatted(.percent.precision(.fractionLength(0))))
                .font(.system(size: 11).monospacedDigit())
                .frame(minWidth: 43)
            action("plus", tr("Zoom In")) { zoomMap(by: 1.25, ended: true) }
                .disabled(zoom >= PageMap.zoomRange.upperBound)
            Divider().frame(height: 17)
            Button(tr("Fit to Places")) { fitMapToPlaces(on: session.pageID) }
                .help(tr("Show every place again, centered"))
            Button(tr("Done")) { endMapAdjust() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .floatingCapsule()
    }
}
