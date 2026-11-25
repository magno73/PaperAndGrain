import AppKit
import Photos
import SwiftUI

struct AlbumPicker: View {
    let language: String
    let close: () -> Void
    let onImport: ([LibraryPhoto], String, BookFormat) -> Void

    @State private var status: PHAuthorizationStatus = .notDetermined
    @State private var albums: [Album] = []
    @State private var albumID: Album.ID?
    @State private var entries: [LibraryPhoto] = []
    @State private var selected = Set<String>()
    @State private var formatChoice = "square-21"
    @State private var width = "210"
    @State private var height = "210"
    @State private var loading = true

    private static let customChoice = "custom"

    private var album: Album? { albums.first { $0.id == albumID } }
    private var format: BookFormat? {
        if let preset = BookFormatPreset.all.first(where: { $0.id == formatChoice }) { return preset.format }
        do {
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: language)
            formatter.numberStyle = .decimal
            guard let w = formatter.number(from: width)?.doubleValue,
                  let h = formatter.number(from: height)?.doubleValue,
                  (80...600).contains(w), (80...600).contains(h) else { return nil }
            return BookFormat(widthMM: w, heightMM: h)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(s("Scegli un album", "Choose an Album"))
                    .font(.system(.largeTitle, design: .serif))
                Text(s("Seleziona gli scatti da impaginare.", "Select the photos to lay out."))
                    .foregroundStyle(.secondary)
            }

            if loading {
                ProgressView(s("Carico gli album…", "Loading albums…"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if status == .denied || status == .restricted {
                ContentUnavailableView {
                    Label(s("Accesso a Foto", "Access to Photos"), systemImage: "photo.badge.exclamationmark")
                } description: {
                    Text(s("Consenti l’accesso in Impostazioni di Sistema oppure importa i file dal Finder.",
                           "Allow access in System Settings or import files from Finder."))
                } actions: {
                    Button(s("Apri Impostazioni", "Open Settings")) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            } else {
                albumSelection
            }

            HStack {
                Button(s("Annulla", "Cancel"), action: close).keyboardShortcut(.cancelAction)
                Spacer()
                if let format {
                    let style = FloatingPointFormatStyle<Double>.number.locale(Locale(identifier: language))
                        .precision(.fractionLength(0...1))
                    let w = format.widthMM.formatted(style)
                    let h = format.heightMM.formatted(style)
                    Text("\(w) × \(h) mm").foregroundStyle(.secondary)
                }
                Button(s("Impagina", "Auto-Layout")) {
                    guard let album, let format else { return }
                    onImport(entries.filter { selected.contains($0.id) }, album.title, format)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(selected.isEmpty || format == nil)
            }
        }
        .padding(26)
        .frame(width: 850, height: 635)
        .task {
            status = await PhotoLibrary.authorize()
            if status == .authorized || status == .limited {
                albums = PhotoLibrary.albums()
                albumID = albums.first { $0.title.localizedCaseInsensitiveCompare("Namibia") == .orderedSame }?.id
                    ?? albums.first?.id
                loadAlbum()
            }
            loading = false
        }
        .onChange(of: albumID) { _, _ in loadAlbum() }
    }

    private var albumSelection: some View {
        HStack(alignment: .top, spacing: 20) {
            List(albums, selection: $albumID) { candidate in
                HStack {
                    Text(candidate.title)
                    Spacer()
                    Text(candidate.count, format: .number)
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                .tag(candidate.id)
            }
            .frame(width: 195)
            .accessibilityLabel(s("Album di Foto", "Photos Albums"))

            VStack(alignment: .leading, spacing: 10) {
                if status == .limited {
                    Text(s("Vedi soltanto le foto che hai autorizzato.", "Only the photos you allowed are shown."))
                        .font(.callout).foregroundStyle(.secondary)
                }
                HStack {
                    Button(s("Seleziona tutte", "Select All")) { selected = Set(entries.map(\.id)) }
                        .keyboardShortcut("a", modifiers: [.command])
                    Button(s("Deseleziona tutte", "Deselect All")) { selected.removeAll() }
                    Spacer()
                    Text(language == "it" ? "\(selected.count) selezionate" : "\(selected.count) selected")
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                if entries.isEmpty {
                    ContentUnavailableView(s("Nessuna foto nell’album", "No Photos in This Album"), systemImage: "photo.on.rectangle.angled")
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 95), spacing: 8)], spacing: 8) {
                            ForEach(entries) { entry in
                                let marked = selected.contains(entry.id)
                                Button {
                                    if marked { selected.remove(entry.id) } else { selected.insert(entry.id) }
                                } label: {
                                    LibraryThumbnail(photo: entry, selected: marked)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(entry.capturedAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? s("Foto", "Photo"))
                                .accessibilityAddTraits(marked ? .isSelected : [])
                            }
                        }
                        .padding(3)
                    }
                }
                Picker(s("Formato del libro", "Book Size"), selection: $formatChoice) {
                    ForEach(BookFormatPreset.Shape.allCases, id: \.self) { shape in
                        Section(shape.title(language)) {
                            ForEach(BookFormatPreset.presets(shape)) { preset in
                                Text(preset.name(language)).tag(preset.id)
                            }
                        }
                    }
                    Divider()
                    Text(s("Personalizzato…", "Custom…")).tag(Self.customChoice)
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 460, alignment: .leading)
                if formatChoice == Self.customChoice {
                    HStack {
                        TextField(s("Larghezza in mm", "Width in mm"), text: $width)
                        TextField(s("Altezza in mm", "Height in mm"), text: $height)
                        if format == nil {
                            Text("80–600 mm").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func loadAlbum() {
        entries = album.map(PhotoLibrary.photos(in:)) ?? []
        selected.removeAll()
    }

    private func s(_ italian: String, _ english: String) -> String { language == "it" ? italian : english }
}

private struct LibraryThumbnail: View {
    let photo: LibraryPhoto
    let selected: Bool
    @State private var image: NSImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 7).fill(.quaternary)
            if let image {
                // clipped() hides the overflow but SwiftUI still hit-tests it: a portrait photo
                // would steal clicks from the cells above and below.
                Image(nsImage: image).resizable().scaledToFill().frame(width: 100, height: 76).clipped()
                    .allowsHitTesting(false)
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Theme.accent)
                    .font(.system(size: 16))
                    .padding(5)
            }
        }
        .frame(width: 100, height: 76)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.accent, lineWidth: 2)
            }
        }
        .task(id: photo.id) { image = await PhotoLibrary.thumbnail(photo) }
    }
}
