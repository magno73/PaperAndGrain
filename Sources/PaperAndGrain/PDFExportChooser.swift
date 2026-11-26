import SwiftUI

enum PDFExportRequest: Sendable {
    case proof
    case printPackage
    case pixart(spineMM: Double)
}

struct PDFExportChooser: View, Localizing {
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
            Text(tr("Export PDF"))
                .font(.system(size: 23, weight: .semibold, design: .serif))
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 6) {
                ForEach(Profile.allCases, id: \.self, content: option)
            }
            if profile == .pixart { pixartOptions }
            preflight
            HStack {
                Spacer()
                Button(tr("Cancel"), action: cancel).keyboardShortcut(.cancelAction)
                Button(tr("Continue…")) {
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
                Text(tr("Set the book size to 21 × 21 cm in Book & Print."))
            } else if book.cover == nil {
                Text(tr("Add the cover in the Page inspector."))
            } else {
                HStack {
                    Text(tr("Spine width from the quote"))
                    Spacer()
                    TextField(tr("Spine Width"), text: $spine)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 61)
                    Text("mm").foregroundStyle(.secondary).accessibilityHidden(true)
                }
                Text(tr("This PDF uses sRGB. Check the color profile in the instructions for your quote."))
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
            Text(tr("Preflight"))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            if let report {
                IssueScroll(maxHeight: 210) {
                    IssueList(report: report, language: language, emptyText: tr("No problems found"))
                }
                if !report.blockers.isEmpty {
                    Text(tr("Fix these problems to export the PDF."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !report.warnings.isEmpty {
                    Text(tr("You can still export: the same warnings appear when the export finishes."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(profile == .proof ? tr("Checking text and files…")
                                           : tr("Checking resolution and pages…"))
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
            return (tr("Viewing PDF"),
                    tr("Interior pages at the book’s trim size."),
                    "book.closed")
        case .printPackage:
            return (tr("Generic Print"),
                    tr("Separate interior and cover files using your book settings."),
                    "printer")
        case .pixart:
            return ("Pixartprinting · 21 × 21 cm",
                    tr("One PDF with a wraparound hardcover and 216 × 216 mm single pages."),
                    "book.pages")
        }
    }
}
