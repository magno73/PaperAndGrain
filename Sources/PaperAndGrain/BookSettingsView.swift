import SwiftUI

struct BookSettingsView: View, Localizing {
    let book: Book
    let language: String
    let close: () -> Void
    let apply: (String, BookFormat, PrintSettings, BookCover?, EditorialTypography?) -> Void

    @State private var title: String
    @State private var format: BookFormat
    @State private var printProfile: PrintSettings
    @State private var cover: BookCover
    @State private var hasCover: Bool
    @State private var typography: EditorialTypography

    init(book: Book, language: String, close: @escaping () -> Void,
         apply: @escaping (String, BookFormat, PrintSettings, BookCover?, EditorialTypography?) -> Void) {
        self.book = book
        self.language = language
        self.close = close
        self.apply = apply
        _title = State(initialValue: book.title)
        _format = State(initialValue: book.format)
        _printProfile = State(initialValue: book.printSettings ?? PrintSettings())
        _cover = State(initialValue: book.cover ?? BookCover(title: book.title))
        _hasCover = State(initialValue: book.cover != nil)
        _typography = State(initialValue: book.typography ?? EditorialTypography())
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
                    Text(tr("Book & Print")).font(.system(.largeTitle, design: .serif))
                    Text(tr("Book size, PDF settings and cover."))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                formatCard
            }

            Form {
                Section(tr("Book")) {
                    TextField(tr("Title"), text: $title)
                    Picker(tr("Size"), selection: Binding(
                        get: { BookFormatPreset.matching(format)?.id ?? "custom" },
                        set: { id in
                            if let preset = BookFormatPreset.all.first(where: { $0.id == id }) { format = preset.format }
                        }
                    )) {
                        ForEach(BookFormatPreset.Shape.allCases, id: \.self) { shape in
                            Section(shape.title(language)) {
                                ForEach(BookFormatPreset.presets(shape)) { preset in
                                    Text(preset.name(language)).tag(preset.id)
                                }
                            }
                        }
                        Divider()
                        Text(tr("Custom")).tag("custom")
                    }
                    TextField(tr("Width (mm)"), value: $format.widthMM, format: number)
                    TextField(tr("Height (mm)"), value: $format.heightMM, format: number)
                }
                printServiceSection
                Section(tr("Book Typography")) {
                    DisclosureGroup(tr("Headings")) {
                        EditorialTypographyControls(style: $typography.title,
                                                   inherited: book.editorialStyle.defaultTitleStyle(mixed: false),
                                                   language: language, updatesSizeWhileTyping: true)
                            .frame(maxWidth: 320, alignment: .leading)
                            .padding(.top, 6)
                    }
                    DisclosureGroup(tr("Body Text")) {
                        EditorialTypographyControls(style: $typography.body,
                                                   inherited: book.editorialStyle.defaultBodyStyle,
                                                   language: language, updatesSizeWhileTyping: true)
                            .frame(maxWidth: 320, alignment: .leading)
                            .padding(.top, 6)
                    }
                }
                Section(tr("Interior")) {
                    TextField(tr("Bleed (mm)"), value: $printProfile.bleedMM, format: number)
                    TextField(tr("Safe margin (mm)"), value: $printProfile.safeMM, format: number)
                    TextField(tr("Target resolution (ppi)"),
                              value: $printProfile.targetPPI, format: number)
                    Toggle(tr("Export facing-page spreads"), isOn: $printProfile.spreads)
                    Toggle(tr("First interior page on the right"), isOn: firstPageOnRight)
                }
                Section(tr("Cover")) {
                    Toggle(tr("Export a separate cover"), isOn: $hasCover)
                    if hasCover {
                        TextField(tr("Cover title"), text: $cover.title)
                        photoPicker(tr("Front"), selection: $cover.frontPhotoID)
                        photoPicker(tr("Back"), selection: $cover.backPhotoID)
                        TextField(tr("Spine width (mm)"), value: $cover.spineMM, format: number)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                if !valid {
                    Text(tr("Check the title and dimensions."))
                        .foregroundStyle(.secondary).font(.callout)
                }
                Spacer()
                Button(tr("Cancel"), action: close).keyboardShortcut(.cancelAction)
                Button(tr("Apply")) {
                    let type = typography.title == nil && typography.body == nil ? nil : typography
                    var updatedCover = cover
                    if cover.frontPhotoID != book.cover?.frontPhotoID { updatedCover.frontPhotoPlacement = nil }
                    if cover.backPhotoID != book.cover?.backPhotoID { updatedCover.backPhotoPlacement = nil }
                    apply(title.trimmingCharacters(in: .whitespacesAndNewlines), format, printProfile,
                          hasCover ? updatedCover : nil, type)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .keyboardShortcut(.defaultAction)
                .disabled(!valid)
            }
        }
        .padding(26)
        .frame(width: 690, height: 690)
    }

    private var catalog: PrintProfileCatalog { .bundled }

    private var chosenProfile: PrintProfile? { catalog.profile(printProfile.profileID) }

    /// The product size chosen if the book has its trim, else the size with the book's trim, else the
    /// one chosen, else the product's first.
    private var chosenSize: PrintProfile.Size? {
        guard let profile = chosenProfile else { return nil }
        let stored = profile.size(printProfile.profileSizeID)
        if let stored, stored.matches(format) { return stored }
        return profile.size(matching: format) ?? stored ?? profile.sizes.first
    }

    /// Keeps the saved size in step with the book's size, so a size change never leaves a stale choice.
    private func syncSize() {
        guard let profile = chosenProfile, let size = chosenSize, size.matches(format) else { return }
        if printProfile.profileSizeID != size.id, profile.size(size.id) != nil { printProfile.profileSizeID = size.id }
    }

    /// A field for a measure the author can type: one given per order, or a computed one to replace.
    private func measureField(_ measure: PrintMeasure, plan: PrintPlan) -> some View {
        let rule = plan.rule(measure, for: previewBook)
        let pages = BookPDF.interiorPageCount(previewBook, plan: plan)
        let computed = rule?.value(pages: pages, paper: plan.paper?.id)
        let label = rule?.isTyped == true ? tr("%@ from the quote", measure.label(language)) : measure.label(language)
        let value = Binding<Double?>(get: { printProfile.profileMeasures?[measure] }, set: { newValue in
            var measures = printProfile.profileMeasures ?? PrintMeasures()
            measures[measure] = newValue
            printProfile.profileMeasures = measures == PrintMeasures() ? nil : measures
        })
        return TextField(label + " (mm)", value: value, format: number,
                         prompt: Text(computed.map { $0.formatted(number) } ?? tr("from the quote")))
            .help(rule?.isTyped == true ? tr("Copy the value from the printer’s quote.")
                                        : tr("Computed from the page count; type a value to replace it."))
    }

    /// `profile|size`, or empty for generic print.
    private var serviceSelection: Binding<String> {
        Binding(get: {
            guard let profile = chosenProfile, let size = chosenSize else { return "" }
            return profile.id + "|" + size.id
        }, set: { value in
            let parts = value.split(separator: "|", maxSplits: 1).map(String.init)
            let profile = parts.first.flatMap { catalog.profile($0) }
            let size = parts.count == 2 ? profile?.size(parts[1]) : nil
            printProfile.choose(profile, size: size,
                                paperID: profile?.id == printProfile.profileID ? printProfile.profilePaperID : nil)
        })
    }

    /// **Print service**: a printer's product sets bleed and safe margin and shows its rules. The book's
    /// size changes only when the author asks for it.
    @ViewBuilder private var printServiceSection: some View {
        Section(tr("Print service")) {
            Picker(tr("Print service"), selection: serviceSelection) {
                Text(tr("None (generic print)")).tag("")
                ForEach(catalog.services, id: \.name) { service in
                    Section(service.name) {
                        ForEach(service.profiles) { profile in
                            ForEach(profile.sizes) { size in
                                Text(profile.product(language) + " · " + size.title(language)).tag(profile.id + "|" + size.id)
                            }
                        }
                    }
                }
            }
            .help(tr("Choosing a printer’s product sets bleed and safe margin from its specification."))
            .onChange(of: format) { _, _ in syncSize() }
            if !catalog.skipped.isEmpty {
                Text(tr("Some print-service files could not be read: %@", catalog.skipped.map(\.file).joined(separator: ", ")))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(catalog.skipped.map(\.errorDescription).compactMap { $0 }.joined(separator: "\n"))
            }
            if let profile = chosenProfile, let size = chosenSize {
                if let papers = profile.papers, papers.count > 1 {
                    Picker(tr("Paper"), selection: Binding(get: { printProfile.profilePaperID ?? papers[0].id },
                                                           set: { printProfile.profilePaperID = $0 })) {
                        ForEach(papers) { paper in Text(paper.name(language)).tag(paper.id) }
                    }
                    .help(tr("The paper changes the spine width."))
                }
                if !size.matches(format) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tr("This product does not offer %1$@. Its sizes, closest first: %2$@. Changing the size re-flows the pages.",
                                BookFormatPreset.centimetres(format, language: language),
                                profile.sizes(closestTo: format).map { $0.title(language) }.joined(separator: ", ")))
                            .fixedSize(horizontal: false, vertical: true)
                        Button(tr("Use %@", size.title(language))) { format = size.format }
                            .help(tr("Sets the book’s size to the product’s trim."))
                    }
                }
                let plan = PrintPlan(profile: profile, sizeID: size.id, paperID: printProfile.profilePaperID,
                                     measures: printProfile.profileMeasures ?? PrintMeasures())
                ForEach(plan.editableMeasures(for: previewBook), id: \.self) { measure in
                    measureField(measure, plan: plan)
                }
                PrintServiceRules(plan: plan, book: previewBook, language: language)
                PrintServiceNotice(profile: profile, language: language)
            }
        }
    }

    /// The book as it would be after Apply, for the product's rules.
    private var previewBook: Book {
        var preview = book
        preview.format = format
        preview.printSettings = printProfile
        return preview
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
            Text(tr("No photo")).tag(Optional<UUID>.none)
            ForEach(book.photos) { photo in Text(photo.name).tag(Optional(photo.id)) }
        }
    }
}
