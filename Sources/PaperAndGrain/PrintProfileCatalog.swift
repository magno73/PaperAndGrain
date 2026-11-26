import CoreGraphics
import Foundation
import os

/// The print-service profiles bundled in `Resources/PrintProfiles`. Each JSON file holds one profile or
/// an array of profiles of one service; files are read in name order.
struct PrintProfileCatalog: Hashable, Sendable {
    struct LoadError: LocalizedError, Hashable, Sendable {
        let file: String
        let reason: String
        var errorDescription: String? { file + ": " + reason }
    }

    let profiles: [PrintProfile]
    /// Files or entries that were skipped, with the reason.
    let skipped: [LoadError]

    init(profiles: [PrintProfile], skipped: [LoadError] = []) {
        self.profiles = profiles
        self.skipped = skipped
    }

    func profile(_ id: String?) -> PrintProfile? {
        guard let id else { return nil }
        return profiles.first { $0.id == id }
    }

    /// Services in catalog order, each with its products, for menus.
    var services: [(name: String, profiles: [PrintProfile])] {
        var order = [String]()
        var grouped = [String: [PrintProfile]]()
        for profile in profiles {
            if grouped[profile.service] == nil { order.append(profile.service) }
            grouped[profile.service, default: []].append(profile)
        }
        return order.map { ($0, grouped[$0] ?? []) }
    }

    /// Reads every `.json` file in `directory` and checks each entry. The first file that does not decode,
    /// or entry that breaks a rule, stops the load with the file's name and the reason: the catalog tests
    /// use this strict form.
    static func load(from directory: URL) throws -> PrintProfileCatalog {
        let catalog = try read(directory)
        if let first = catalog.skipped.first { throw first }
        return catalog
    }

    /// Reads every `.json` file in `directory`, skipping a file that does not decode, an entry that breaks
    /// a rule and a repeated id, and recording why. One bad file never removes the others.
    static func read(_ directory: URL) throws -> PrintProfileCatalog {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var profiles = [PrintProfile]()
        var skipped = [LoadError]()
        var seen = Set<String>()
        for file in files {
            let name = file.lastPathComponent
            let entries: [PrintProfile]
            do {
                entries = try decodeEntries(Data(contentsOf: file))
            } catch {
                skipped.append(LoadError(file: name, reason: describe(error)))
                continue
            }
            for entry in entries {
                if let problem = entry.problems.first {
                    skipped.append(LoadError(file: name, reason: problem))
                } else if !seen.insert(entry.id).inserted {
                    skipped.append(LoadError(file: name, reason: "Duplicate profile id " + entry.id))
                } else {
                    profiles.append(entry)
                }
            }
        }
        return PrintProfileCatalog(profiles: profiles, skipped: skipped)
    }

    /// One profile, or an array of them; an error in an array names the entry's index.
    private static func decodeEntries(_ data: Data) throws -> [PrintProfile] {
        let decoder = JSONDecoder()
        let top = try JSONSerialization.jsonObject(with: data)
        if top is [Any] { return try decoder.decode([PrintProfile].self, from: data) }
        guard top is [String: Any] else {
            throw LoadError(file: "", reason: "Expected one profile object or an array of profiles")
        }
        return [try decoder.decode(PrintProfile.self, from: data)]
    }

    /// A decoding error as "path: what is wrong", short enough for a log line and a settings note.
    static func describe(_ error: Error) -> String {
        func path(_ keys: [CodingKey]) -> String {
            let text = keys.map { $0.intValue.map { "[\($0)]" } ?? "." + $0.stringValue }.joined()
            return text.hasPrefix(".") ? String(text.dropFirst()) : (text.isEmpty ? "root" : text)
        }
        switch error {
        case let error as LoadError: return error.reason
        case let DecodingError.keyNotFound(key, context):
            return path(context.codingPath + [key]) + ": missing"
        case let DecodingError.typeMismatch(type, context):
            return path(context.codingPath) + ": expected \(type)"
        case let DecodingError.valueNotFound(type, context):
            return path(context.codingPath) + ": expected \(type), found null"
        case let DecodingError.dataCorrupted(context):
            return path(context.codingPath) + ": " + context.debugDescription
        default:
            return error.localizedDescription
        }
    }

    /// The catalog inside the app. A build run without an app bundle (`swift run`, `swift test`) reads
    /// the repository's `Resources/PrintProfiles`; an app bundle reads only its own resources. Skipped
    /// files are logged and listed in **Book & Print**.
    static let bundled: PrintProfileCatalog = {
        let bundle = Bundle.main.bundleURL.pathExtension == "app"
        let directory: URL? = bundle
            ? Bundle.main.resourceURL?.appendingPathComponent("PrintProfiles", isDirectory: true)
            : URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().appendingPathComponent("Resources/PrintProfiles", isDirectory: true)
        let logger = Logger(subsystem: "me.magno.paperandgrain", category: "print-profiles")
        guard let directory else { return PrintProfileCatalog(profiles: []) }
        do {
            let catalog = try read(directory)
            for problem in catalog.skipped {
                logger.error("Skipped print profile \(problem.file, privacy: .public): \(problem.reason, privacy: .public)")
            }
            return catalog
        } catch {
            logger.error("No print profiles in \(directory.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return PrintProfileCatalog(profiles: [], skipped: [LoadError(file: "PrintProfiles", reason: error.localizedDescription)])
        }
    }()

    /// The id the command line's `pixart` alias stands for.
    static let pixartID = "pixartprinting-photobook-hardcover"
}

extension PrintProfile {
    /// Every rule an entry breaks, in English, for the catalog tests and the loader.
    var problems: [String] {
        var found = [String]()
        func check(_ condition: Bool, _ message: @autoclosure () -> String) {
            if !condition { found.append(id + ": " + message()) }
        }
        func length(_ value: Length, _ name: String, positive: Bool) {
            check(value.mm.isFinite && (positive ? value.mm > 0 : value.mm >= 0),
                  "\(name) must be \(positive ? "positive" : "0 or more") and finite")
        }
        func measure(_ value: Measure?, _ name: String, positive: Bool = false, fixedOrQuote: Bool = false) {
            switch value {
            case nil: break
            case let .fixed(part)?: length(part, name, positive: positive)
            case let .quote(quote)?:
                check(quote.minMM.isFinite && quote.maxMM.isFinite && quote.minMM >= 0 && quote.maxMM > quote.minMM,
                      "\(name).quote needs 0 ≤ minMM < maxMM")
                if let typical = quote.typicalMM { check(quote.accepts(typical), "\(name).quote.typicalMM is out of range") }
                if positive { check(quote.minMM > 0 || quote.minExclusive == true, "\(name).quote must exclude 0") }
            case let .formula(base, perPage, _)?:
                check(!fixedOrQuote, "\(name) must be a length or a quote")
                check(base.isFinite && perPage.isFinite && base >= 0 && perPage >= 0, "\(name).formula must be finite")
            case let .table(rows, _)?:
                check(!fixedOrQuote, "\(name) must be a length or a quote")
                check(!rows.isEmpty, "\(name).table has no rows")
                for row in rows {
                    check(row.mm.mm.isFinite && row.mm.mm >= 0 && row.upToPages > 0, "\(name).table rows must be positive")
                    if let paper = row.paper { check(papers?.contains { $0.id == paper } == true, "\(name) names unknown paper \(paper)") }
                }
            }
        }
        func edges(_ value: Edges?, _ name: String) {
            guard let value else { return }
            for (edge, part) in zip(["top", "bottom", "outer", "inner"], value.all) {
                measure(part, "\(name).\(edge)", fixedOrQuote: true)
            }
            let quotes = Set(value.all.filter(\.isTyped))
            check(quotes.count <= 1, "\(name): the edges given per order share one quote")
        }
        func pages(_ rules: PageRules, _ name: String) {
            for (field, value) in [("minimum", rules.minimum), ("maximum", rules.maximum), ("multiple", rules.multiple)] {
                if let value { check(value > 0, "\(name).\(field) must be positive") }
            }
            if let count = rules.coverPagesCounted { check(count >= 0, "\(name).coverPagesCounted must be 0 or more") }
            if let minimum = rules.minimum, let maximum = rules.maximum { check(minimum <= maximum, "\(name) minimum > maximum") }
        }
        func coverRules(_ rules: Cover, _ name: String) {
            if let panel = rules.panel {
                measure(panel.widthMM, "\(name).panel.widthMM", positive: true, fixedOrQuote: true)
                measure(panel.heightMM, "\(name).panel.heightMM", positive: true, fixedOrQuote: true)
            }
            measure(rules.hinge, "\(name).hinge")
            measure(rules.spine, "\(name).spine")
            measure(rules.wrap, "\(name).wrap")
            edges(rules.bleed, "\(name).bleed")
            if let safe = rules.safe { length(safe, "\(name).safe", positive: false) }
        }
        check(!id.isEmpty && id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }, "id must be letters, digits and hyphens")
        check(!service.isEmpty, "service is empty")
        check(sourceURL.scheme == "https" && sourceURL.host != nil, "sourceURL must be https")
        check(verifiedDate != nil, "verifiedOn must be a yyyy-MM-dd date")
        check(!sizes.isEmpty, "no sizes")
        check(Set(sizes.map(\.id)).count == sizes.count, "size ids must be unique")
        if let papers {
            check(Set(papers.map(\.id)).count == papers.count, "paper ids must be unique")
            for paper in papers { if let rules = paper.pages { pages(rules.over(interior.pages), "papers.\(paper.id).pages") } }
        }
        check(!color.accepts.isEmpty, "color.accepts is empty")
        edges(interior.bleed, "interior.bleed")
        edges(interior.safe, "interior.safe")
        check(!interior.safe.isTyped, "interior.safe must be fixed")
        if let ppi = interior.targetPPI { check(ppi.isFinite && ppi >= 72 && ppi <= 1200, "interior.targetPPI out of range") }
        check(interior.layout == .single || interior.firstPage == .left, "a spread layout starts on the left")
        pages(interior.pages, "interior.pages")
        coverRules(cover, "cover")
        for size in sizes {
            measure(size.widthMM, "sizes.\(size.id).widthMM", positive: true, fixedOrQuote: true)
            measure(size.heightMM, "sizes.\(size.id).heightMM", positive: true, fixedOrQuote: true)
            if let rules = size.pages { pages(rules.over(interior.pages), "sizes.\(size.id).pages") }
            let merged = self.coverRules(for: size)
            if let override = size.cover { coverRules(override, "sizes.\(size.id).cover") }
            if merged.kind == .flat { check(merged.spine != nil, "sizes.\(size.id): a flat cover needs a spine measure") }
        }
        return found
    }
}

/// A book's choice of print service, resolved against the catalog: the product, the size, the paper and
/// the measures the author typed. The PDF writer, the preflight and the export sheet all read it.
struct PrintPlan: Hashable, Sendable {
    var profile: PrintProfile
    var sizeID: String?
    var paperID: String?
    var measures = PrintMeasures()

    init(profile: PrintProfile, sizeID: String? = nil, paperID: String? = nil, measures: PrintMeasures = PrintMeasures()) {
        self.profile = profile
        self.sizeID = sizeID
        self.paperID = paperID
        self.measures = measures
    }

    /// The plan the book chose in **Book & Print**; nil without a profile or when the catalog lacks it.
    init?(book: Book, catalog: PrintProfileCatalog = .bundled) {
        guard let settings = book.printSettings, let profile = catalog.profile(settings.profileID) else { return nil }
        self.init(profile: profile, sizeID: settings.profileSizeID, paperID: settings.profilePaperID,
                  measures: settings.profileMeasures ?? PrintMeasures())
    }

    /// The size the book is printed at: the chosen one if the book has its trim, otherwise any size of
    /// the product with the book's trim (a saved size that no longer matches is not an error when another
    /// size does). Nil when the product does not offer the book's size.
    func size(for book: Book) -> PrintProfile.Size? {
        if let sizeID, let chosen = profile.size(sizeID), chosen.matches(book.format) { return chosen }
        return profile.size(matching: book.format)
    }

    var paper: PrintProfile.Paper? {
        profile.papers?.first { $0.id == paperID } ?? profile.papers?.first
    }

    var firstPageRight: Bool { profile.interior.firstPage == .right }

    /// The cover rules of the size (the product's when the size is not offered).
    func coverRules(for book: Book) -> PrintProfile.Cover {
        size(for: book).map(profile.coverRules) ?? profile.cover
    }

    func coverKind(for book: Book) -> PrintProfile.Cover.Kind { coverRules(for: book).kind ?? .none }

    func pageRules(for book: Book) -> PrintProfile.PageRules {
        profile.pageRules(for: size(for: book), paper: paper)
    }

    /// How the interior is laid out in the PDF: side of the first page, glued endpapers, and the
    /// trailing blanks that bring the page count to the product's step.
    func imposition(for book: Book) -> BookPDF.Imposition {
        let rules = pageRules(for: book)
        return BookPDF.Imposition(firstPageRight: firstPageRight, endpapers: profile.interior.ends == .endpapers,
                                  multiple: rules.multiple, coverPagesCounted: rules.coverPagesCounted ?? 0)
    }

    /// The interior bleed per edge, with the author's value for edges given per order; nil while one is
    /// missing.
    func interiorBleed(for book: Book) -> PrintProfile.EdgeValues? {
        profile.interior.bleed.values(typed: typed(.interiorBleed, for: book))
    }

    /// The flat cover's bleed beyond the wrap; nil while an edge given per order is missing.
    func coverBleed(for book: Book) -> PrintProfile.EdgeValues? {
        (coverRules(for: book).bleed ?? PrintProfile.Edges(0)).values(typed: typed(.coverBleed, for: book))
    }

    var safe: PrintProfile.EdgeValues { profile.interior.safe.fixedValues }

    /// The interior settings the export uses: the book's own with the product's bleed, layout and resolution.
    func interiorSettings(for book: Book) -> PrintSettings {
        var settings = book.printSettings ?? PrintSettings()
        settings.spreads = profile.interior.layout == .spread
        settings.bleedMM = (interiorBleed(for: book) ?? profile.interior.bleed.fixedValues).largest
        if let ppi = profile.interior.targetPPI { settings.targetPPI = ppi }
        return settings
    }

    /// The pages the printer counts: interior pages, plus the cover pages it includes.
    func countedPages(interiorPages: Int, book: Book) -> Int {
        interiorPages + (pageRules(for: book).coverPagesCounted ?? 0)
    }

    /// The profile's rule for a measure; nil when the product does not use it.
    func rule(_ measure: PrintMeasure, for book: Book) -> PrintProfile.Measure? {
        let rules = coverRules(for: book)
        let flat = rules.kind == .flat
        switch measure {
        case .spine: return flat ? rules.spine : nil
        case .hinge: return flat ? rules.hinge : nil
        case .wrap: return flat ? rules.wrap : nil
        case .panelWidth: return flat ? rules.panel?.widthMM : nil
        case .panelHeight: return flat ? rules.panel?.heightMM : nil
        case .coverBleed: return flat ? rules.bleed?.all.first(where: \.isTyped) : nil
        case .interiorBleed: return profile.interior.bleed.all.first(where: \.isTyped)
        }
    }

    /// The measures the author can type for this product: those given per order, and computed ones that
    /// the author may replace.
    func editableMeasures(for book: Book) -> [PrintMeasure] {
        PrintMeasure.allCases.filter { measure in
            guard let rule = rule(measure, for: book) else { return false }
            switch rule {
            case .quote, .formula, .table: return true
            case .fixed: return false
            }
        }
    }

    /// The author's value for a measure, if one was typed and the product accepts it. A spine from the
    /// quote falls back to the spine width saved with the book's cover.
    func typed(_ measure: PrintMeasure, for book: Book) -> Double? {
        let rule = rule(measure, for: book)
        func valid(_ value: Double?) -> Double? {
            guard let value, rule?.accepts(value) ?? (value.isFinite && value >= 0) else { return nil }
            return value
        }
        if measure == .spine {
            let saved = rule?.isTyped == true ? book.cover.flatMap { $0.spineMM > 0 ? $0.spineMM : nil } : nil
            return valid(measures.spineMM) ?? valid(saved)
        }
        return valid(measures[measure])
    }

    /// The measure the cover is drawn with: the author's value, else the profile's. A cover measure the
    /// product does not use is 0 (the board is the page); nil means it is missing (given per order, or
    /// outside the table).
    func value(_ measure: PrintMeasure, for book: Book, interiorPages: Int) -> Double? {
        if let typed = typed(measure, for: book) { return typed }
        guard let rule = rule(measure, for: book) else {
            switch measure {
            case .spine: return coverKind(for: book) == .flat ? nil : 0
            case .panelWidth: return book.format.widthMM
            case .panelHeight: return book.format.heightMM
            case .hinge, .wrap, .coverBleed, .interiorBleed: return 0
            }
        }
        return rule.value(pages: interiorPages, paper: paper?.id)
    }

    /// The measures the export cannot do without, each with the table's last page count when the book
    /// runs past it.
    func missingMeasures(for book: Book, interiorPages: Int) -> [(measure: PrintMeasure, tableLimit: Int?)] {
        let measures: [PrintMeasure] = coverKind(for: book) == .flat ? PrintMeasure.allCases : [.interiorBleed]
        return measures.compactMap { measure in
            guard value(measure, for: book, interiorPages: interiorPages) == nil else { return nil }
            return (measure, rule(measure, for: book)?.tableLimit(paper: paper?.id))
        }
    }

    /// The problems that come from the product, for the preflight: size, page count and measures.
    /// `bookPages` is the book's own page count, without the blanks and cover pages the printer counts.
    func issues(for book: Book, interiorPages: Int, bookPages: Int)
        -> (blockers: [BookPDF.PreflightIssue], warnings: [BookPDF.PreflightIssue]) {
        typealias Issue = BookPDF.PreflightIssue
        var blockers = [Issue]()
        var warnings = [Issue]()
        if size(for: book) == nil {
            blockers.append(Issue(problem: .sizeNotOffered(book.format, offered: profile.sizes(closestTo: book.format).map(\.format))))
        }
        let rules = pageRules(for: book)
        let count = countedPages(interiorPages: interiorPages, book: book)
        if let minimum = rules.minimum, count < minimum {
            warnings.append(Issue(problem: .pageCount(.minimum(minimum), counted: count, bookPages: bookPages)))
        }
        if let maximum = rules.maximum, count > maximum {
            warnings.append(Issue(problem: .pageCount(.maximum(maximum), counted: count, bookPages: bookPages)))
        }
        for missing in missingMeasures(for: book, interiorPages: interiorPages) {
            let issue = Issue(location: missing.measure == .interiorBleed ? nil : .cover,
                              problem: .missingMeasure(missing.measure, tableLimit: missing.tableLimit))
            blockers.append(issue)
        }
        return (blockers, warnings)
    }

    /// The print zones of the product in millimetres: bleed and safe margin per edge of an interior
    /// page, and the cover's hinge and safe margin.
    func zones(for book: Book, interiorPages: Int) -> PrintZones {
        let cover = coverRules(for: book)
        return PrintZones(bleed: interiorBleed(for: book) ?? profile.interior.bleed.fixedValues, safe: safe,
                          coverHingeMM: cover.kind == .flat ? value(.hinge, for: book, interiorPages: interiorPages) : nil,
                          coverSafeMM: cover.safe?.mm)
    }

    /// The product's zones on one interior page for `PrintGuides.frames(pageSize:settings:zones:)`: the
    /// strip along the binding that its inner safe margin keeps clear of text, when it is wider than the
    /// book's safe margin. `pageSize` is the trim in points; a full spread has no binding strip.
    func guideZones(pageSize: CGSize, onRight: Bool, spread: Bool, safeMM: Double) -> [PrintGuides.Zone] {
        let inner = safe.inner
        guard !spread, inner > safeMM else { return [] }
        let width = inner * PrintGuides.pointsPerMM
        let x = onRight ? 0 : pageSize.width - width
        return [PrintGuides.Zone(kind: .innerMargin, rect: CGRect(x: x, y: 0, width: width, height: pageSize.height))]
    }
}

extension PrintSettings {
    /// Chooses a print-service product, or none for generic print. A product records its id, size and
    /// paper and sets the bleed and the safe margin from the product: the safe margin is the largest of
    /// the cut edges, because the layout keeps one margin on every side; the binding margin is checked
    /// and drawn separately (`PrintPlan.guideZones`). The book's format is not changed here.
    mutating func choose(_ profile: PrintProfile?, size: PrintProfile.Size?, paperID: String? = nil) {
        guard let profile else {
            profileID = nil
            profileSizeID = nil
            profilePaperID = nil
            profileMeasures = nil
            return
        }
        if profileID != profile.id { profileMeasures = nil }
        profileID = profile.id
        profileSizeID = size?.id
        profilePaperID = paperID
        let interior = profile.interior
        bleedMM = (interior.bleed.values(typed: profileMeasures?.interiorBleedMM) ?? interior.bleed.fixedValues).largest
        safeMM = interior.safe.fixedValues.largestOuter
    }
}

/// What a print-service profile adds to the guides on the canvas.
struct PrintZones: Hashable, Sendable {
    var bleed: PrintProfile.EdgeValues
    var safe: PrintProfile.EdgeValues
    var coverHingeMM: Double?
    var coverSafeMM: Double?
}
