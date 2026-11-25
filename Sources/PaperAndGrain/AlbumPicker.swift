import AppKit
import Photos
import SwiftUI

struct AlbumPicker: View, Localizing {
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
    @State private var loadingPhotos = false
    /// The album used last time, selected again when the picker opens.
    @AppStorage("lastPhotosAlbumID") private var lastAlbumID = ""

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
                Text(tr("Choose an Album"))
                    .font(.system(.largeTitle, design: .serif))
                Text(tr("Select the photos to lay out."))
                    .foregroundStyle(.secondary)
            }

            if loading {
                ProgressView(tr("Loading albums…"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if status == .denied || status == .restricted {
                ContentUnavailableView {
                    Label(tr("Access to Photos"), systemImage: "photo.badge.exclamationmark")
                } description: {
                    Text(tr("Allow access in System Settings or import files from Finder."))
                } actions: {
                    Button(tr("Open Settings")) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            } else if albums.isEmpty {
                ContentUnavailableView {
                    Label(tr("No Albums"), systemImage: "photo.on.rectangle.angled")
                } description: {
                    Text(tr("Your Photos library has no albums to lay out. You can start a book from Finder files instead."))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                albumSelection
            }

            HStack {
                Button(tr("Cancel"), action: close).keyboardShortcut(.cancelAction)
                Spacer()
                if let format {
                    let style = FloatingPointFormatStyle<Double>.number.locale(Locale(identifier: language))
                        .precision(.fractionLength(0...1))
                    let w = format.widthMM.formatted(style)
                    let h = format.heightMM.formatted(style)
                    Text("\(w) × \(h) mm").foregroundStyle(.secondary)
                }
                Button(tr("Auto-Layout")) {
                    guard let album, let format else { return }
                    lastAlbumID = album.id
                    let title = album.isSmart ? tr("New Book") : album.title
                    onImport(entries.filter { selected.contains($0.id) }, title, format)
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
                albums = await PhotoLibrary.pickerAlbums(language: language)
                albumID = Self.initialAlbum(in: albums, last: lastAlbumID)
            }
            loading = false
        }
        // Runs once for the first album and again for each new choice.
        .task(id: albumID) { await loadAlbum() }
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
            .accessibilityLabel(tr("Photos Albums"))

            VStack(alignment: .leading, spacing: 10) {
                if status == .limited {
                    Text(tr("Only the photos you allowed are shown."))
                        .font(.callout).foregroundStyle(.secondary)
                }
                HStack {
                    Button(tr("Select All")) { selected = Set(entries.map(\.id)) }
                        .keyboardShortcut("a", modifiers: [.command])
                    Button(tr("Deselect All")) { selected.removeAll() }
                    Spacer()
                    Text(tr("%lld selected", selected.count))
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                if loadingPhotos {
                    ProgressView(tr("Loading photos…"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if entries.isEmpty {
                    ContentUnavailableView(tr("No Photos in This Album"), systemImage: "photo.on.rectangle.angled")
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
                                .accessibilityLabel(entry.capturedAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? tr("Photo"))
                                .accessibilityAddTraits(marked ? .isSelected : [])
                            }
                        }
                        .padding(3)
                    }
                }
                Picker(tr("Book Size"), selection: $formatChoice) {
                    ForEach(BookFormatPreset.Shape.allCases, id: \.self) { shape in
                        Section(shape.title(language)) {
                            ForEach(BookFormatPreset.presets(shape)) { preset in
                                Text(preset.name(language)).tag(preset.id)
                            }
                        }
                    }
                    Divider()
                    Text(tr("Custom…")).tag(Self.customChoice)
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 460, alignment: .leading)
                if formatChoice == Self.customChoice {
                    HStack {
                        TextField(tr("Width in mm"), text: $width)
                        TextField(tr("Height in mm"), text: $height)
                        if format == nil {
                            Text("80–600 mm").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The album used last time if it still exists, otherwise the first one (Recents).
    static func initialAlbum(in albums: [Album], last: String) -> Album.ID? {
        albums.first { $0.id == last }?.id ?? albums.first?.id
    }

    private func loadAlbum() async {
        selected.removeAll()
        guard let album else {
            entries = []
            return
        }
        loadingPhotos = true
        let loaded = await PhotoLibrary.loadPhotos(in: album)
        guard !Task.isCancelled, albumID == album.id else { return }
        entries = loaded
        loadingPhotos = false
    }
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
