import SwiftUI

/// The statement shown next to every print-service profile (decision D5): when the specification was
/// checked, where, and that the app is not affiliated with the printer. When the printer names a PDF
/// standard, it also says that the file is not certified (decision D6).
struct PrintServiceNotice: View, Localizing {
    let profile: PrintProfile
    let language: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(tr("Specification checked on %@", checkedOn))
                Link(tr("Printer’s page"), destination: profile.sourceURL)
                    .help(profile.sourceURL.absoluteString)
                    .accessibilityHint(profile.sourceURL.absoluteString)
            }
            Text(tr("Check the printer’s current requirements before ordering. Paper & Grain is not affiliated with %@.",
                    profile.service))
                .fixedSize(horizontal: false, vertical: true)
            if let standard = profile.color.standard {
                Text(tr("The printer asks for %@. This file is not certified as such; check it with the printer’s preflight.",
                        standard))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var checkedOn: String {
        guard let date = profile.verifiedDate else { return profile.verifiedOn }
        return date.formatted(Date.FormatStyle(date: .long, time: .omitted, timeZone: TimeZone(identifier: "UTC") ?? .current)
            .locale(Locale(identifier: language)))
    }
}

/// What the product asks of the book, in a few lines: page count, margins and the cover measures.
struct PrintServiceRules: View, Localizing {
    let plan: PrintPlan
    let book: Book
    let language: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(lines, id: \.self) { Text($0).fixedSize(horizontal: false, vertical: true) }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var lines: [String] {
        var lines = [String]()
        let rules = plan.pageRules(for: book)
        switch (rules.minimum, rules.maximum) {
        case let (minimum?, maximum?): lines.append(tr("Pages: %1$lld to %2$lld", minimum, maximum))
        case let (minimum?, nil): lines.append(tr("Pages: at least %lld", minimum))
        case let (nil, maximum?): lines.append(tr("Pages: at most %lld", maximum))
        case (nil, nil): break
        }
        if let multiple = rules.multiple, multiple > 1 { lines.append(tr("Page count in steps of %lld", multiple)) }
        if let cover = rules.coverPagesCounted, cover > 0 { lines.append(tr("The count includes %lld cover pages", cover)) }
        let safe = plan.profile.interior.safe
        lines.append(tr("Keep text %1$@ mm from the edges and %2$@ mm from the binding",
                        mm(max(safe.top.mm, safe.bottom.mm, safe.outer.mm)), mm(safe.inner.mm)))
        switch plan.profile.interior.ends ?? .pages {
        case .pages: break
        case .insideCovers: lines.append(tr("The first and last pages print on the inside of the covers"))
        case .endpapers: lines.append(tr("The first and last pages are glued to the covers and stay blank"))
        }
        return lines
    }

    private func mm(_ value: Double) -> String {
        value.formatted(.number.locale(Locale(identifier: language)).precision(.fractionLength(0...2)))
    }
}

extension PrintMeasure {
    /// The field label when the value comes from the printer's quote.
    func quoteLabel(_ language: String) -> String {
        switch self {
        case .spine: L10n.string("Spine width from the quote", language: language)
        case .hinge: L10n.string("Hinge width from the quote", language: language)
        case .wrap: L10n.string("Cover wrap from the quote", language: language)
        }
    }

    /// The field label when the profile computes the value and the author may type another.
    func label(_ language: String) -> String {
        switch self {
        case .spine: L10n.string("Spine width", language: language)
        case .hinge: L10n.string("Hinge width", language: language)
        case .wrap: L10n.string("Cover wrap", language: language)
        }
    }
}
