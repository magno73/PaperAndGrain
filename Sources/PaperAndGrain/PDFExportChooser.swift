import SwiftUI

enum PDFExportRequest: Sendable {
    case proof
    case printPackage
    /// A print-service product, with the measures typed in the sheet.
    case service(PrintPlan)
}

struct PDFExportChooser: View, Localizing {
    let book: Book
    /// The open package; with it the preflight also checks photo and LUT files on disk.
    let directory: URL?
    let language: String
    let cancel: () -> Void
    let export: (PDFExportRequest) -> Void
    /// The remedy a row offers. The sheet is opened by the app scene, which cannot reach the editor
    /// that performs fixes, so the scene passes nothing today; a task that adds a fix passes the
    /// editor's provider here and the rows stay identical to the Issues popover.
    let fix: (BookPDF.PreflightIssue) -> IssueFix?
    let catalog: PrintProfileCatalog
    /// Keeps measures the author changed for the book's own product in its print settings, as one undo
    /// step, so the live Issues list sees them too.
    let saveMeasures: (PrintMeasures) -> Void

    @State private var choice: Choice = .proof
    /// The product picked under **Other print service…**.
    @State private var otherID: String?
    @State private var otherSizeID: String?
    @State private var otherPaperID: String?
    /// The measures typed in the sheet, as text in the interface language.
    @State private var typed: [PrintMeasure: String] = [:]
    /// The text the fields started with, to tell what the author changed.
    @State private var initialTyped: [PrintMeasure: String] = [:]
    @State private var report: BookPDF.Preflight?

    private enum Choice: Hashable {
        case proof, printPackage, bookProfile, other
    }

    init(book: Book, directory: URL? = nil, language: String, catalog: PrintProfileCatalog = .bundled,
         cancel: @escaping () -> Void,
         fix: @escaping (BookPDF.PreflightIssue) -> IssueFix? = { _ in nil },
         saveMeasures: @escaping (PrintMeasures) -> Void = { _ in },
         export: @escaping (PDFExportRequest) -> Void) {
        self.book = book
        self.directory = directory
        self.language = language
        self.catalog = catalog
        self.cancel = cancel
        self.export = export
        self.fix = fix
        self.saveMeasures = saveMeasures
        let bookPlan = PrintPlan(book: book, catalog: catalog)
        let text = Self.typedText(bookPlan, book: book, language: language)
        _typed = State(initialValue: text)
        _initialTyped = State(initialValue: text)
        let first = catalog.profiles.first { $0.id == PrintProfileCatalog.pixartID } ?? catalog.profiles.first
        _otherID = State(initialValue: first?.id)
        _otherSizeID = State(initialValue: first.flatMap { $0.size(matching: book.format)?.id ?? $0.sizes.first?.id })
    }

    private let pine = Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(tr("Export PDF"))
                .font(.system(size: 23, weight: .semibold, design: .serif))
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 6) {
                ForEach(choices, id: \.self, content: option)
            }
            if choice == .other { otherPicker }
            if let plan = basePlan { serviceOptions(plan) }
            preflight
            HStack {
                Spacer()
                Button(tr("Cancel"), action: cancel).keyboardShortcut(.cancelAction)
                Button(tr("Continue…")) {
                    guard let request else { return }
                    if choice == .bookProfile, let changed = changedMeasures { saveMeasures(changed) }
                    export(request)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(pine)
                .disabled(request == nil || report?.blockers.isEmpty != true)
            }
        }
        .padding(22)
        .frame(width: 490)
        .onChange(of: otherID) { _, id in
            let profile = catalog.profile(id)
            otherSizeID = profile?.size(matching: book.format)?.id ?? profile?.sizes.first?.id
            otherPaperID = nil
            if choice == .other { resetTyped() }
        }
        .onChange(of: choice) { _, _ in resetTyped() }
    }

    private func resetTyped() {
        typed = Self.typedText(basePlan, book: book, language: language)
        initialTyped = typed
    }

    /// The book's saved measures with the fields the author changed in the sheet; nil when none changed.
    private var changedMeasures: PrintMeasures? {
        guard let plan else { return nil }
        var measures = book.printSettings?.profileMeasures ?? PrintMeasures()
        var changed = false
        for measure in PrintMeasure.allCases where (typed[measure] ?? "") != (initialTyped[measure] ?? "") {
            measures[measure] = plan.measures[measure]
            changed = true
        }
        return changed ? measures : nil
    }

    private var choices: [Choice] {
        [.proof, .printPackage] + (PrintPlan(book: book, catalog: catalog) == nil ? [] : [.bookProfile])
            + (catalog.profiles.isEmpty ? [] : [.other])
    }

    /// The chosen product before the typed measures are applied.
    private var basePlan: PrintPlan? {
        switch choice {
        case .proof, .printPackage: return nil
        case .bookProfile: return PrintPlan(book: book, catalog: catalog)
        case .other:
            guard let profile = catalog.profile(otherID) else { return nil }
            return PrintPlan(profile: profile, sizeID: otherSizeID, paperID: otherPaperID)
        }
    }

    /// The chosen product with the measures typed in the sheet; nil when one is not a valid number.
    private var plan: PrintPlan? {
        guard var plan = basePlan else { return nil }
        for measure in PrintMeasure.allCases {
            let entry = (typed[measure] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !entry.isEmpty else {
                plan.measures[measure] = nil
                continue
            }
            let separator = Locale(identifier: language).decimalSeparator ?? "."
            guard let mm = Double(entry.replacingOccurrences(of: separator, with: ".")),
                  plan.rule(measure, for: book)?.accepts(mm) ?? false else { return nil }
            plan.measures[measure] = mm
        }
        return plan
    }

    private static func typedText(_ plan: PrintPlan?, book: Book, language: String) -> [PrintMeasure: String] {
        guard let plan else { return [:] }
        let number = FloatingPointFormatStyle<Double>.number.locale(Locale(identifier: language))
            .precision(.fractionLength(0...2)).grouping(.never)
        var text = [PrintMeasure: String]()
        for measure in PrintMeasure.allCases {
            if let value = plan.typed(measure, for: book) { text[measure] = value.formatted(number) }
        }
        return text
    }

    private func option(_ candidate: Choice) -> some View {
        let active = choice == candidate
        let (title, detail, icon) = labels(candidate)
        return Button { choice = candidate } label: {
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

    private var otherPicker: some View {
        VStack(alignment: .leading, spacing: 7) {
            Picker(tr("Print service"), selection: $otherID) {
                ForEach(catalog.services, id: \.name) { service in
                    Section(service.name) {
                        ForEach(service.profiles) { profile in
                            Text(profile.title(language)).tag(Optional(profile.id))
                        }
                    }
                }
            }
            .help(tr("The printer and product to export for."))
            if let profile = catalog.profile(otherID) {
                if profile.sizes.count > 1 {
                    Picker(tr("Size"), selection: $otherSizeID) {
                        ForEach(profile.sizes) { size in Text(size.title(language)).tag(Optional(size.id)) }
                    }
                    .help(tr("The product size; it must match the book’s size."))
                }
                if let papers = profile.papers, papers.count > 1 {
                    Picker(tr("Paper"), selection: $otherPaperID) {
                        ForEach(papers) { paper in Text(paper.name(language)).tag(Optional(paper.id)) }
                    }
                    .help(tr("The paper changes the spine width."))
                }
            }
        }
        .font(.callout)
    }

    private func serviceOptions(_ plan: PrintPlan) -> some View {
        let interiorPages = BookPDF.interiorPageCount(book, plan: plan)
        let flat = plan.coverKind(for: book) == .flat
        return VStack(alignment: .leading, spacing: 7) {
            if plan.size(for: book) == nil {
                Text(tr("This product does not offer the book’s size. Choose one of its sizes in Book & Print: %@",
                        plan.profile.sizes(closestTo: book.format).map { $0.title(language) }.joined(separator: ", ")))
                    .fixedSize(horizontal: false, vertical: true)
            } else if flat && book.cover == nil {
                Text(tr("Add the cover in the Page inspector."))
            } else {
                ForEach(plan.editableMeasures(for: book), id: \.self) { measure in
                    measureField(measure, plan: plan, interiorPages: interiorPages)
                }
            }
            if plan.profile.color.accepts.contains(.cmyk) {
                Text(plan.profile.color.accepts.contains(.srgb)
                     ? tr("This PDF uses sRGB. Check the color profile in the instructions for your quote.")
                     : tr("This printer asks for CMYK. This PDF uses sRGB; the printer may convert or refuse it."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            PrintServiceNotice(profile: plan.profile, language: language)
        }
        .font(.callout)
        .padding(.horizontal, 3)
    }

    private func measureField(_ measure: PrintMeasure, plan: PrintPlan, interiorPages: Int) -> some View {
        let rule = plan.rule(measure, for: book)
        let computed = rule?.value(pages: interiorPages, paper: plan.paper?.id)
        let number = FloatingPointFormatStyle<Double>.number.locale(Locale(identifier: language))
            .precision(.fractionLength(0...2)).grouping(.never)
        let label = rule?.isTyped == true ? tr("%@ from the quote", measure.label(language)) : measure.label(language)
        return HStack {
            Text(label)
            Spacer()
            TextField(label, text: Binding(get: { typed[measure] ?? "" }, set: { typed[measure] = $0 }),
                      prompt: computed.map { Text($0.formatted(number)) })
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 61)
                .help(rule?.isTyped == true ? tr("Copy the value from the printer’s quote.")
                                            : tr("Computed from the page count; type a value to replace it."))
            Text("mm").foregroundStyle(.secondary).accessibilityHidden(true)
        }
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
                    IssueList(report: report, language: language, emptyText: tr("No problems found"), fix: fix)
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
                    Text(choice == .proof ? tr("Checking text and files…")
                                           : tr("Checking resolution and pages…"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .task(id: checkedProfile) {
            report = nil
            let book = book
            let directory = directory
            let checked = checkedProfile
            let found = await Task.detached(priority: .userInitiated) {
                BookPDF.preflight(book, directory: directory, profile: checked)
            }.value
            if !Task.isCancelled { report = found }
        }
    }

    /// The check the sheet runs; a product without a valid plan falls back to the generic print check.
    private var checkedProfile: BookPDF.Profile {
        switch choice {
        case .proof: .proof
        case .printPackage: .print
        case .bookProfile, .other: (plan ?? basePlan).map { .service($0) } ?? .print
        }
    }

    private var request: PDFExportRequest? {
        switch choice {
        case .proof: return .proof
        case .printPackage: return .printPackage
        case .bookProfile, .other:
            guard let plan, plan.size(for: book) != nil else { return nil }
            if plan.coverKind(for: book) == .flat, book.cover == nil { return nil }
            guard plan.missingMeasures(for: book, interiorPages: BookPDF.interiorPageCount(book, plan: plan)).isEmpty
            else { return nil }
            return .service(plan)
        }
    }

    private func labels(_ item: Choice) -> (String, String, String) {
        switch item {
        case .proof:
            return (tr("Viewing PDF"),
                    tr("Interior pages at the book’s trim size."),
                    "book.closed")
        case .printPackage:
            return (tr("Generic Print"),
                    tr("Separate interior and cover files using your book settings."),
                    "printer")
        case .bookProfile:
            guard let plan = PrintPlan(book: book, catalog: catalog) else { return ("", "", "book.pages") }
            let size = plan.size(for: book)?.title(language)
            return ([plan.profile.title(language), size].compactMap { $0 }.joined(separator: " · "),
                    describe(plan), "book.pages")
        case .other:
            return (tr("Other print service…"),
                    tr("Export for another printer’s product from the catalog."),
                    "list.bullet.rectangle")
        }
    }

    /// The files and pages the product's export writes, in two short sentences.
    private func describe(_ plan: PrintPlan) -> String {
        let files: String = switch (plan.profile.files.arrangement, plan.coverKind(for: book)) {
        case (.single, .flat): tr("One PDF with the flat cover first.")
        case (.single, .interiorPages), (.separate, .interiorPages): tr("One PDF with the cover as first and last page.")
        case (.single, .none), (.separate, .none): tr("One PDF without the cover.")
        case (.separate, .flat): tr("Separate interior and cover files.")
        }
        let bleed = plan.interiorBleed(for: book) ?? plan.profile.interior.bleed.fixedValues
        let spread = plan.profile.interior.layout == .spread
        let width = (spread ? 2 : 1) * book.format.widthMM + bleed.outer + (spread ? bleed.outer : bleed.inner)
        let height = book.format.heightMM + bleed.top + bleed.bottom
        let style = FloatingPointFormatStyle<Double>.number.locale(Locale(identifier: language)).precision(.fractionLength(0...1))
        let size = "\(width.formatted(style)) × \(height.formatted(style)) mm"
        return files + " " + (spread ? tr("Double pages of %@.", size) : tr("Single pages of %@.", size))
    }
}
