import SwiftUI

struct BookSettingsView: View {
    let book: Book
    let language: String
    let close: () -> Void
    let apply: (String, BookFormat, PrintSettings, BookCover?) -> Void

    @State private var title: String
    @State private var format: BookFormat
    @State private var printProfile: PrintSettings
    @State private var cover: BookCover
    @State private var hasCover: Bool

    init(book: Book, language: String, close: @escaping () -> Void,
         apply: @escaping (String, BookFormat, PrintSettings, BookCover?) -> Void) {
        self.book = book
        self.language = language
        self.close = close
        self.apply = apply
        _title = State(initialValue: book.title)
        _format = State(initialValue: book.format)
        _printProfile = State(initialValue: book.printSettings ?? PrintSettings())
        _cover = State(initialValue: book.cover ?? BookCover(title: book.title))
        _hasCover = State(initialValue: book.cover != nil)
    }

    private var number: FloatingPointFormatStyle<Double> {
        .number.locale(Locale(identifier: language)).precision(.fractionLength(0...2))
    }

    private var valid: Bool {
        let shorterSide = min(format.widthMM, format.heightMM)
        return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (80...600).contains(format.widthMM) && (80...600).contains(format.heightMM)
            && (0...25).contains(printProfile.bleedMM)
            && (0...(min(60, max(0, (shorterSide - 10) / 2)))).contains(printProfile.safeMM)
            && (72...600).contains(printProfile.targetPPI)
            && (!hasCover || (0...100).contains(cover.spineMM))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(s("Libro e stampa", "Book & Print")).font(.system(.largeTitle, design: .serif))
                    Text(s("Formato, impostazioni del PDF e copertina.", "Book size, PDF settings and cover."))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                formatCard
            }

            Form {
                Section(s("Libro", "Book")) {
                    TextField(s("Titolo", "Title"), text: $title)
                    HStack {
                        Button(s("Quadrato", "Square")) { format = .square }
                        Button(s("Orizzontale", "Landscape")) { format = .landscape }
                        Button(s("Verticale", "Portrait")) { format = .portrait }
                    }
                    TextField(s("Larghezza (mm)", "Width (mm)"), value: $format.widthMM, format: number)
                    TextField(s("Altezza (mm)", "Height (mm)"), value: $format.heightMM, format: number)
                }
                Section(s("Interni", "Interior")) {
                    TextField(s("Abbondanza (mm)", "Bleed (mm)"), value: $printProfile.bleedMM, format: number)
                    TextField(s("Margine sicuro (mm)", "Safe margin (mm)"), value: $printProfile.safeMM, format: number)
                    TextField(s("Risoluzione desiderata (ppi)", "Target resolution (ppi)"),
                              value: $printProfile.targetPPI, format: number)
                    Toggle(s("PDF a doppie pagine", "Export facing-page spreads"), isOn: $printProfile.spreads)
                    Toggle(s("Prima pagina interna a destra", "First interior page on the right"), isOn: firstPageOnRight)
                }
                Section(s("Copertina", "Cover")) {
                    Toggle(s("Esporta una copertina separata", "Export a separate cover"), isOn: $hasCover)
                    if hasCover {
                        TextField(s("Titolo in copertina", "Cover title"), text: $cover.title)
                        photoPicker(s("Fronte", "Front"), selection: $cover.frontPhotoID)
                        photoPicker(s("Retro", "Back"), selection: $cover.backPhotoID)
                        TextField(s("Larghezza del dorso (mm)", "Spine width (mm)"), value: $cover.spineMM, format: number)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                if !valid {
                    Text(s("Controlla titolo e misure.", "Check the title and dimensions."))
                        .foregroundStyle(.secondary).font(.callout)
                }
                Spacer()
                Button(s("Annulla", "Cancel"), action: close).keyboardShortcut(.cancelAction)
                Button(s("Applica", "Apply")) {
                    apply(title.trimmingCharacters(in: .whitespacesAndNewlines), format, printProfile, hasCover ? cover : nil)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.19, green: 0.34, blue: 0.27))
                .keyboardShortcut(.defaultAction)
                .disabled(!valid)
            }
        }
        .padding(26)
        .frame(width: 690, height: 690)
    }

    private var firstPageOnRight: Binding<Bool> {
        Binding(get: { printProfile.firstPageOnRight ?? false }, set: { printProfile.firstPageOnRight = $0 })
    }

    private var formatCard: some View {
        let smallerWidth = min(max(80, format.widthMM), 600)
        let smallerHeight = min(max(80, format.heightMM), 600)
        let scale = 45 / max(smallerWidth, smallerHeight)
        return HStack(spacing: 12) {
            HStack(spacing: 1) {
                ForEach(0..<2) { _ in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color(red: 0.97, green: 0.95, blue: 0.90))
                        .overlay { RoundedRectangle(cornerRadius: 1).strokeBorder(Color.secondary.opacity(0.38)) }
                        .frame(width: smallerWidth * scale, height: smallerHeight * scale)
                }
            }
            .accessibilityHidden(true)
            Text("\(format.widthMM.formatted(number)) × \(format.heightMM.formatted(number)) mm")
                .font(.caption.monospacedDigit())
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    private func photoPicker(_ label: String, selection: Binding<UUID?>) -> some View {
        Picker(label, selection: selection) {
            Text(s("Nessuna foto", "No photo")).tag(Optional<UUID>.none)
            ForEach(book.photos) { photo in Text(photo.name).tag(Optional(photo.id)) }
        }
    }

    private func s(_ it: String, _ en: String) -> String { language == "it" ? it : en }
}
