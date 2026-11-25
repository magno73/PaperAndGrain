import SwiftUI

enum PDFExportRequest: Sendable {
    case proof
    case printPackage
    case pixart(spineMM: Double)
}

struct PDFExportChooser: View {
    let book: Book
    /// The open package; with it the preflight also checks photo and LUT files on disk.
    let directory: URL?
    let language: String
    let cancel: () -> Void
    let export: (PDFExportRequest) -> Void

    @State private var profile: Profile = .proof
    @State private var spine: String
    @State private var report: BookPDF.Preflight?

    private enum Profile: CaseIterable {
        case proof, printPackage, pixart
    }

    init(book: Book, directory: URL? = nil, language: String, cancel: @escaping () -> Void,
         export: @escaping (PDFExportRequest) -> Void) {
        self.book = book
        self.directory = directory
        self.language = language
        self.cancel = cancel
        self.export = export
        let number = FloatingPointFormatStyle<Double>.number.locale(Locale(identifier: language))
            .precision(.fractionLength(0...2)).grouping(.never)
        _spine = State(initialValue: book.cover.flatMap { $0.spineMM > 0 ? $0.spineMM.formatted(number) : nil } ?? "")
    }

    private let pine = Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(tr("Esporta PDF", "Export PDF"))
                .font(.system(size: 23, weight: .semibold, design: .serif))
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 6) {
                ForEach(Profile.allCases, id: \.self, content: option)
            }
            if profile == .pixart { pixartOptions }
            preflight
            HStack {
                Spacer()
                Button(tr("Annulla", "Cancel"), action: cancel).keyboardShortcut(.cancelAction)
                Button(tr("Continua…", "Continue…")) {
                    if let request { export(request) }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(pine)
                .disabled(request == nil || report?.blockers.isEmpty != true)
            }
        }
        .padding(22)
        .frame(width: 470)
    }

    private func option(_ candidate: Profile) -> some View {
        let active = profile == candidate
        let (title, detail, icon) = labels(candidate)
        return Button { profile = candidate } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(pine)
                    .frame(width: 25)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: active ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(active ? pine : .secondary)
                    .accessibilityHidden(true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(active ? pine.opacity(0.07) : .secondary.opacity(0.035),
                        in: RoundedRectangle(cornerRadius: 7))
            .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(active ? pine.opacity(0.48) : .secondary.opacity(0.14)) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private var pixartOptions: some View {
        VStack(alignment: .leading, spacing: 7) {
            if !PixartPrintProfile.supports(book.format) {
                Text(tr("Imposta il formato del libro a 21 × 21 cm in Libro e stampa.",
                        "Set the book size to 21 × 21 cm in Book & Print."))
            } else if book.cover == nil {
                Text(tr("Aggiungi la copertina dal pannello Pagina.", "Add the cover in the Page inspector."))
            } else {
                HStack {
                    Text(tr("Dorso dal preventivo", "Spine width from the quote"))
                    Spacer()
                    TextField(tr("Dorso", "Spine Width"), text: $spine)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 61)
                    Text("mm").foregroundStyle(.secondary).accessibilityHidden(true)
                }
                Text(tr("Il PDF usa sRGB. Verifica il profilo colore richiesto nelle istruzioni del preventivo.",
                        "This PDF uses sRGB. Check the color profile in the instructions for your quote."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.callout)
        .padding(.horizontal, 3)
    }

    /// Checks shown before choosing where to save, so problems can be fixed first. Blockers would
    /// stop the export and disable Continue; warnings only describe a weaker print.
    private var preflight: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(tr("Verifica prima dell’esportazione", "Preflight"))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            if let report {
                if report.blockers.isEmpty && report.warnings.isEmpty {
                    Label(tr("Nessun problema trovato", "No problems found"), systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .symbolRenderingMode(.multicolor)
                }
                if !report.blockers.isEmpty {
                    problems(report.blockers, icon: "xmark.octagon.fill", tint: .red,
                             more: { tr("e altri \($0) problemi da correggere", "and \($0) more problems to fix") })
                    Text(tr("Correggi questi problemi per esportare il PDF.", "Fix these problems to export the PDF."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !report.warnings.isEmpty {
                    problems(report.warnings, icon: "exclamationmark.triangle.fill", tint: .orange,
                             more: { tr("e altri \($0) avvisi", "and \($0) more warnings") })
                    if report.blockers.isEmpty {
                        Text(tr("Puoi esportare comunque: gli stessi avvisi compaiono alla fine dell’esportazione.",
                                "You can still export: the same warnings appear when the export finishes."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(profile == .proof ? tr("Controllo testi e file…", "Checking text and files…")
                                           : tr("Controllo risoluzione e pagine…", "Checking resolution and pages…"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .task(id: profile) {
            report = nil
            let book = book
            let directory = directory
            let checked: BookPDF.Profile = switch profile {
            case .proof: .proof
            case .printPackage: .print
            case .pixart: .pixart
            }
            let found = await Task.detached(priority: .userInitiated) {
                BookPDF.preflight(book, directory: directory, profile: checked)
            }.value
            if !Task.isCancelled { report = found }
        }
    }

    private func problems(_ lines: [String], icon: String, tint: Color, more: @escaping (Int) -> String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(lines.prefix(6).enumerated()), id: \.offset) { _, line in
                Label {
                    Text(localizedWarning(line)).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: icon).foregroundStyle(tint)
                }
                .font(.callout)
            }
            if lines.count > 6 {
                Text(more(lines.count - 6))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Print warnings carry both languages ("Italiano / English"); show only the interface language.
    private func localizedWarning(_ warning: String) -> String {
        let italian = language.hasPrefix("it")
        let parts = warning.components(separatedBy: " · ")
        if parts.count == 2, parts[0] == "Dimensioni non valide" { return italian ? parts[0] : parts[1] }
        return parts.map { part in
            let sides = part.components(separatedBy: " / ")
            guard sides.count == 2 else { return part }
            return italian ? sides[0] : sides[1]
        }.joined(separator: " · ")
    }

    private var request: PDFExportRequest? {
        switch profile {
        case .proof: return .proof
        case .printPackage: return .printPackage
        case .pixart:
            guard PixartPrintProfile.supports(book.format), book.cover != nil else { return nil }
            let separator = Locale(identifier: language).decimalSeparator ?? "."
            let entry = spine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let mm = Double(entry.replacingOccurrences(of: separator, with: ".")),
                  PixartPrintProfile.isValidSpine(mm) else { return nil }
            return .pixart(spineMM: mm)
        }
    }

    private func labels(_ item: Profile) -> (String, String, String) {
        switch item {
        case .proof:
            return (tr("PDF da sfogliare", "Viewing PDF"),
                    tr("Interni al formato del libro, una facciata per pagina.", "Interior pages at the book’s trim size."),
                    "book.closed")
        case .printPackage:
            return (tr("Stampa generica", "Generic Print"),
                    tr("Interni e copertina separati con le impostazioni del libro.", "Separate interior and cover files using your book settings."),
                    "printer")
        case .pixart:
            return ("Pixartprinting · 21 × 21 cm",
                    tr("PDF unico con copertina rigida stesa e facciate da 216 × 216 mm.",
                       "One PDF with a wraparound hardcover and 216 × 216 mm single pages."),
                    "book.pages")
        }
    }

    private func tr(_ it: String, _ en: String) -> String { language == "it" ? it : en }
}
