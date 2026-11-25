import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension EditorView {
    var photoDropZone: some View {
        Label(tr("Trascina foto qui", "Drop Photos Here"), systemImage: "photo.badge.plus")
            .font(.caption.weight(.medium))
            .foregroundStyle(pine)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 24)
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

    func acceptPhotoDrop(_ accepted: Bool) -> Bool {
        guard accepted else { return false }
        search = ""
        concept = nil
        trayFilter = .all
        showsTray = true
        return true
    }

    var photoTray: some View {
        let results = photoLibraryCache.results(photos: book.photos, language: language, search: search, concept: concept)
        let photoLocations = photoUsageIndex.locations(in: book)
        let assigned = Set(coverSide.map { [coverPhotoID($0)].compactMap { $0 } } ?? page?.photoIDs ?? [])
        let filtered: [BookPhoto] = switch trayFilter {
        case .all: results.photos
        case .unused: results.photos.filter { photoLocations[$0.id]?.isEmpty ?? true }
        case .onPage: results.photos.filter { assigned.contains($0.id) }
        }
        let sections = libraryOrdering.groups(
            for: filtered, order: photoOrder, locale: Locale(identifier: language),
            places: placesRead, used: photoOrder == .usage ? Set(photoLocations.keys) : []
        )
        let unused = book.photos.filter { photoLocations[$0.id]?.isEmpty ?? true }.count
        let pendingPlaces = placeAssetsToRead
        let needsAnalysis = book.photos.contains { ($0.analysis?.revision ?? 0) < PhotoAnalysis.currentRevision }
        let hasOlderAnalysis = book.photos.contains { $0.analysis.map { $0.revision < PhotoAnalysis.currentRevision } == true }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(tr("Fototeca", "Photo Library")).font(.headline)
                    Text(tr("\(book.photos.count) foto · \(unused) non usate",
                            "\(book.photos.count) photos · \(unused) unused"))
                        .font(.caption)
                        .foregroundStyle(muted)
                        .monospacedDigit()
                }
                .fixedSize()
                if isAnalyzing || !pendingPlaces.isEmpty {
                    ProgressView().controlSize(.small)
                        .help(analysisStatus)
                        .accessibilityLabel(analysisStatus)
                }
                Spacer(minLength: 8)
                if !book.photos.isEmpty {
                    Picker(tr("Mostra", "Show"), selection: $trayFilter) {
                        Text(tr("Tutte", "All")).tag(TrayFilter.all)
                        Text(tr("Non usate", "Unused")).tag(TrayFilter.unused)
                        Text(coverSide == nil ? tr("In pagina", "On Page") : tr("In copertina", "On Cover")).tag(TrayFilter.onPage)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    Picker(libraryLabel("sort", "Ordina per", "Sort by"), selection: $photoOrder) {
                        ForEach(PhotoLibraryOrder.allCases) { order in
                            Text(photoOrderLabel(order)).tag(order)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                    .help(libraryLabel("sort", "Ordina per", "Sort by"))
                    conceptFilter(results.concepts)
                        .fixedSize()
                    TextField(tr("Cerca foto", "Search photos"), text: $search)
                        .textFieldStyle(.roundedBorder)
                        .focused($searchingPhotos)
                        .frame(minWidth: 90, maxWidth: 180)
                }
                photoDropZone
                    .frame(width: 140)
                Menu {
                    Button(hasOlderAnalysis ? tr("Aggiorna analisi", "Update Analysis") : tr("Analizza foto", "Analyze Photos"),
                           systemImage: "viewfinder", action: onAnalyze)
                        .disabled(isAnalyzing || !needsAnalysis)
                    Button(tr("Importa file…", "Import Files…"), systemImage: "folder", action: actions.importFiles)
                    if !analysisStatus.isEmpty {
                        Divider()
                        Text(analysisStatus)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(tr("Altre azioni della fototeca", "More photo library actions"))
                .accessibilityLabel(tr("Altre azioni della fototeca", "More photo library actions"))
            }
            if book.photos.isEmpty {
                Text(tr("Trascina qui foto dal Finder o da Foto, oppure importa dei file.",
                        "Drag photos here from the Finder or Photos, or import files."))
                    .font(.callout)
                    .foregroundStyle(muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { scroll in
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 18) {
                            Color.clear.frame(width: 0, height: 0).id("photoLibraryTop").accessibilityHidden(true)
                            if sections.isEmpty {
                                intro(tr("Nessuna foto corrispondente.", "No matching photos."))
                                    .padding(.top, 20)
                            }
                            ForEach(sections) { section in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(photoSectionTitle(section.id))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(muted)
                                        .lineLimit(1)
                                        .accessibilityAddTraits(.isHeader)
                                    LazyHStack(spacing: 8) {
                                        ForEach(section.photos) { photo in
                                            photoLibraryTile(photo, used: assigned.contains(photo.id),
                                                             locations: photoLocations[photo.id] ?? [])
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 4)
                    }
                    .scrollIndicators(.automatic)
                    .onChange(of: photoOrder) { _, _ in scroll.scrollTo("photoLibraryTop", anchor: .leading) }
                    .task(id: importedPhotoToReveal) {
                        guard let id = importedPhotoToReveal else { return }
                        await Task.yield()
                        guard !Task.isCancelled else { return }
                        scroll.scrollTo(id, anchor: .center)
                        importedPhotoToReveal = nil
                    }
                }
                // Native photo hit testing reads these frames without updating the editor.
                .libraryPhotoFrame()
                .onPreferenceChange(LibraryPhotoFrames.self) { libraryHitFrames.frames = $0 }
                .onDisappear { libraryHitFrames.frames = .init() }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(height: 188)
        .frame(maxWidth: .infinity)
        .background(pine.opacity(hoveringPhotoDrop || hoveringPhotoPromise ? 0.08 : 0),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .floatingPanel(cornerRadius: 18)
        .overlay {
            if hoveringPhotoDrop || hoveringPhotoPromise {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(pine, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .padding(3)
                    .overlay {
                        Label(tr("Rilascia per aggiungere al libro", "Drop to Add to the Book"), systemImage: "photo.badge.plus")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(pine)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.regularMaterial, in: Capsule())
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .onDrop(of: [UTType.fileURL, UTType.image], isTargeted: $hoveringPhotoDrop) { providers in
            acceptPhotoDrop(onDropPhotos(providers, { importedPhotoToReveal = $0 }))
        }
        .onDisappear { hoveringPhotoPromise = false }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .task(id: pendingPlaces) { await readPhotoPlaces(pendingPlaces) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tr("Fototeca", "Photo Library"))
    }

    var placeAssetsToRead: [PlaceAsset] {
        guard photoOrder == .place else { return [] }
        return book.photos.compactMap { photo in
            guard photo.location == nil else { return nil }
            let asset = PlaceAsset(id: photo.id, filename: photo.filename, sourceID: photo.sourceID)
            return scannedPlaceAssets.contains(asset) ? nil : asset
        }
    }

    func readPhotoPlaces(_ pending: [PlaceAsset]) async {
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

    func libraryLabel(_ key: String, _ italian: String, _ english: String) -> String {
        localized("editor.photo_library." + key, fallback: tr(italian, english))
    }

    func photoOrderLabel(_ order: PhotoLibraryOrder) -> String {
        switch order {
        case .date: libraryLabel("date", "Data", "Date")
        case .place: libraryLabel("place", "Luogo", "Place")
        case .subject: libraryLabel("subject", "Argomento", "Subject")
        case .usage: libraryLabel("usage", "Non usate prima", "Unused First")
        }
    }

    func photoSectionTitle(_ section: PhotoLibraryOrdering.Section.Key) -> String {
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

    func conceptFilter(_ concepts: [InspectorPhotoLibraryCache.Concept]) -> some View {
        Picker(tr("Concetto", "Concept"), selection: $concept) {
            Text(tr("Tutti i concetti", "All concepts")).tag(nil as String?)
            ForEach(concepts) { item in
                Text(item.name + " · " + String(item.count)).tag(Optional(item.id))
            }
        }
        .labelsHidden()
        .disabled(concepts.isEmpty)
    }

    func photoLibraryTile(_ photo: BookPhoto, used: Bool, locations: [PhotoUsageIndex.Location]) -> some View {
        let active = photo.id == selectedPhoto
        let orientation = photoOrientation(photo)
        let details = ([orientation.label] + locations.map(usageDescription)).joined(separator: " · ")
        return preview(photo, small: true, fills: false)
            .frame(width: 104, height: 76)
            .background(pine.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(alignment: .topLeading) {
                Image(systemName: orientation.symbol)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 4))
                    .padding(3)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
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
            .help(photo.name + "\n" + details)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(photo.name)
            .accessibilityValue(details)
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

    func photoOrientation(_ photo: BookPhoto) -> (symbol: String, label: String) {
        if photo.pixelWidth > photo.pixelHeight {
            return ("rectangle", localized("editor.photo_orientation.landscape", fallback: tr("Orizzontale", "Landscape")))
        }
        if photo.pixelWidth < photo.pixelHeight {
            return ("rectangle.portrait", localized("editor.photo_orientation.portrait", fallback: tr("Verticale", "Portrait")))
        }
        return ("square", localized("editor.photo_orientation.square", fallback: tr("Quadrata", "Square")))
    }

    func usageBadge(_ location: PhotoUsageIndex.Location) -> String {
        switch location {
        case let .page(numbers):
            numbers.lowerBound == numbers.upperBound ? "\(numbers.lowerBound)" : "\(numbers.lowerBound)–\(numbers.upperBound)"
        case .frontCover:
            tr("C", "F")
        case .backCover:
            tr("R", "B")
        }
    }

    func usageDescription(_ location: PhotoUsageIndex.Location) -> String {
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

    func selectLibraryPhoto(_ id: UUID) {
        endInlineTextEditing()
        canvasPhotoSelection = nil
        selectedPhoto = id
        selectedBox = nil
        selectedEditorial = nil
    }

    func browsePhotos() {
        showsTray = true
        trayFilter = .all
    }
}
