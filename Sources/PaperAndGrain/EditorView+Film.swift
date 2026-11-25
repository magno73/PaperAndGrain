import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension EditorView {
    var filmPhoto: BookPhoto? {
        selectedPhoto.flatMap(indexedPhoto)
    }

    var currentFilm: FilmSettings {
        if filmScope == .photo, let photo = filmPhoto { return book.effectiveFilm(for: photo) }
        return book.film ?? FilmSettings()
    }

    var filmInspector: some View {
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

    var filmLUTMenu: some View {
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

    func fujifilmLooks(_ input: FujifilmFilmLook.Input, selected: FujifilmFilmLook?,
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

    func fujifilmInputDescription(_ input: FujifilmFilmLook.Input) -> String {
        switch input {
        case .linear:
            tr("Per immagini sviluppate con contrasto lineare.", "For images developed with linear contrast.")
        case .provia:
            tr("Per immagini già sviluppate con Provia.", "For images already developed with Provia.")
        }
    }

    func applyBuiltInLUT(_ look: FujifilmFilmLook, resources: URL) {
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

    var filmSwatches: some View {
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

    func filmName(_ preset: FilmPreset) -> String {
        switch preset {
        case .original: tr("Originale", "Original")
        case .documentary: tr("Documentario", "Documentary")
        case .warmNegative: tr("Negativo caldo", "Warm Negative")
        case .monochrome: tr("Monocromatico", "Monochrome")
        case .custom: tr("LUT personalizzata", "Custom LUT")
        }
    }

    var filmTarget: FilmTarget? {
        if filmScope == .book { return .book }
        return filmPhoto.map { .photo($0.id) }
    }

    func filmSlider(_ label: String, value: WritableKeyPath<FilmSettings, Double>) -> some View {
        FilmSlider(label: label, value: value, target: filmTarget, committed: currentFilm, edit: filmEdit,
                   change: { amount in updateFilmDraft(value, to: amount) },
                   editingChanged: { editing in
            finishFilmEdit()
            if editing, let target = filmTarget {
                filmEdit.start(bookID: book.id, target: target, settings: currentFilm)
            }
        })
    }

    func updateFilmDraft(_ key: WritableKeyPath<FilmSettings, Double>, to amount: Double) {
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

    func finishFilmEdit() {
        filmPreviewTask?.cancel()
        filmPreviewTask = nil
        guard let target = filmEdit.target, let draft = filmEdit.draft else { return }
        let shouldCommit = filmEdit.bookID == book.id && draft != filmEdit.initial
        filmEdit.clear()
        if shouldCommit { commitFilm(draft, to: target) }
    }

    func setFilm(_ edit: (inout FilmSettings) -> Void) {
        finishFilmEdit()
        guard let target = filmTarget else { return }
        let previous = currentFilm
        var settings = previous
        edit(&settings)
        if settings != previous { commitFilm(settings, to: target) }
    }

    func commitFilm(_ settings: FilmSettings, to target: FilmTarget) {
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

    func setPhotoFilm(_ settings: FilmSettings?, for id: UUID) {
        guard let index = photoIndex(id) else { return }
        let previous = book.photos[index].film
        guard settings != previous else { return }
        book.photos[index].film = settings
        if let undoManager {
            undoTarget.registerPhotoValue(undoManager, binding: $book, bookID: book.id, photoID: id,
                                         key: \.film, previous: previous, name: tr("Modifica pellicola", "Change Film Look"))
        }
    }

    func importFilmLUT() {
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

    func filmLUTName(_ filename: String) -> String {
        filename.replacingOccurrences(of: "-[0-9a-f]{16}(?=\\.)", with: "", options: .regularExpression)
    }
}
