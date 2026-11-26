import CoreGraphics
import Foundation

/// The print-service profiles bundled in `Resources/PrintProfiles`. Each JSON file holds one profile or
/// an array of profiles of one service; files are read in name order.
struct PrintProfileCatalog: Hashable, Sendable {
    struct LoadError: LocalizedError {
        let file: String
        let reason: String
        var errorDescription: String? { file + ": " + reason }
    }

    let profiles: [PrintProfile]

    init(profiles: [PrintProfile]) { self.profiles = profiles }

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

    /// Reads every `.json` file in `directory` and checks each entry. A file that does not decode or an
    /// entry that breaks a rule stops the load with the file's name and the reason.
    static func load(from directory: URL) throws -> PrintProfileCatalog {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var profiles = [PrintProfile]()
        for file in files {
            let data = try Data(contentsOf: file)
            let decoder = JSONDecoder()
            let entries: [PrintProfile]
            do {
                if let many = try? decoder.decode([PrintProfile].self, from: data) {
                    entries = many
                } else {
                    entries = [try decoder.decode(PrintProfile.self, from: data)]
                }
            } catch {
                throw LoadError(file: file.lastPathComponent, reason: String(describing: error))
            }
            for entry in entries {
                if let problem = entry.problems.first { throw LoadError(file: file.lastPathComponent, reason: problem) }
            }
            profiles += entries
        }
        var seen = Set<String>()
        for profile in profiles where !seen.insert(profile.id).inserted {
            throw LoadError(file: directory.lastPathComponent, reason: "Duplicate profile id " + profile.id)
        }
        return PrintProfileCatalog(profiles: profiles)
    }

    /// The catalog inside the app. `swift run` and `swift test` have no app bundle, so they read the
    /// repository's `Resources/PrintProfiles`.
    static let bundled: PrintProfileCatalog = {
        var candidates = [URL]()
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("PrintProfiles", isDirectory: true))
        }
        candidates.append(URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/PrintProfiles", isDirectory: true))
        for directory in candidates where FileManager.default.fileExists(atPath: directory.path) {
            if let catalog = try? load(from: directory) { return catalog }
        }
        return PrintProfileCatalog(profiles: [])
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
        func edges(_ value: Edges?, _ name: String) {
            guard let value else { return }
            for (edge, part) in zip(["top", "bottom", "outer", "inner"], value.all) {
                length(part, "\(name).\(edge)", positive: false)
            }
        }
        func measure(_ value: Measure?, _ name: String) {
            switch value {
            case nil: break
            case let .fixed(part)?: length(part, name, positive: false)
            case let .quote(minimum, maximum)?:
                check(minimum.isFinite && maximum.isFinite && minimum >= 0 && maximum > minimum,
                      "\(name).quote needs 0 ≤ minMM < maxMM")
            case let .formula(base, perPage, _)?:
                check(base.isFinite && perPage.isFinite && base >= 0 && perPage >= 0, "\(name).formula must be finite")
            case let .table(rows, _)?:
                check(!rows.isEmpty, "\(name).table has no rows")
                for row in rows {
                    check(row.mm.mm.isFinite && row.mm.mm >= 0 && row.upToPages > 0, "\(name).table rows must be positive")
                    if let paper = row.paper { check(papers?.contains { $0.id == paper } == true, "\(name) names unknown paper \(paper)") }
                }
            }
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
                length(panel.widthMM, "\(name).panel.widthMM", positive: true)
                length(panel.heightMM, "\(name).panel.heightMM", positive: true)
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
        if let papers { check(Set(papers.map(\.id)).count == papers.count, "paper ids must be unique") }
        check(!color.accepts.isEmpty, "color.accepts is empty")
        edges(interior.bleed, "interior.bleed")
        edges(interior.safe, "interior.safe")
        if let ppi = interior.targetPPI { check(ppi.isFinite && ppi >= 72 && ppi <= 1200, "interior.targetPPI out of range") }
        check(interior.layout == .single || interior.firstPage == .left, "a spread layout starts on the left")
        pages(interior.pages, "interior.pages")
        coverRules(cover, "cover")
        for size in sizes {
            length(size.widthMM, "sizes.\(size.id).widthMM", positive: true)
            length(size.heightMM, "sizes.\(size.id).heightMM", positive: true)
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

    /// The size the book is printed at: the chosen one if the book has its trim, otherwise the product's
    /// size with the book's trim. Nil when the product does not offer the book's size.
    func size(for book: Book) -> PrintProfile.Size? {
        if let sizeID, let chosen = profile.size(sizeID) { return chosen.matches(book.format) ? chosen : nil }
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
        size(for: book).map(profile.pageRules) ?? profile.interior.pages
    }

    /// The interior settings the export uses: the book's own with the product's bleed, layout and resolution.
    func interiorSettings(for book: Book) -> PrintSettings {
        var settings = book.printSettings ?? PrintSettings()
        settings.spreads = profile.interior.layout == .spread
        settings.bleedMM = profile.interior.bleed.largest
        if let ppi = profile.interior.targetPPI { settings.targetPPI = ppi }
        return settings
    }

    /// The pages the printer counts: interior pages, plus the cover pages it includes.
    func countedPages(interiorPages: Int, book: Book) -> Int {
        interiorPages + (pageRules(for: book).coverPagesCounted ?? 0)
    }

    func rule(_ measure: PrintMeasure, for book: Book) -> PrintProfile.Measure? {
        let rules = coverRules(for: book)
        return switch measure {
        case .spine: rules.spine
        case .hinge: rules.hinge
        case .wrap: rules.wrap
        }
    }

    /// The author's value for a measure, if one was typed. A spine from the quote falls back to the
    /// spine width saved with the book's cover.
    func typed(_ measure: PrintMeasure, for book: Book) -> Double? {
        let rule = rule(measure, for: book)
        func valid(_ value: Double?) -> Double? {
            guard let value, rule?.accepts(value) ?? (value.isFinite && value >= 0) else { return nil }
            return value
        }
        switch measure {
        case .spine:
            let saved = rule?.isTyped == true ? book.cover.flatMap { $0.spineMM > 0 ? $0.spineMM : nil } : nil
            return valid(measures.spineMM) ?? valid(saved)
        case .hinge: return valid(measures.hingeMM)
        case .wrap: return valid(measures.wrapMM)
        }
    }

    /// The measure the cover is drawn with: the author's value, else the profile's. A measure the profile
    /// does not use is 0; nil means it is missing (typed from a quote, or outside the table).
    func value(_ measure: PrintMeasure, for book: Book, interiorPages: Int) -> Double? {
        if let typed = typed(measure, for: book) { return typed }
        guard let rule = rule(measure, for: book) else { return measure == .spine ? nil : 0 }
        return rule.value(pages: interiorPages, paper: paper?.id)
    }

    /// The problems that come from the product, for the preflight: size, page count and cover measures.
    func issues(for book: Book, interiorPages: Int) -> (blockers: [BookPDF.PreflightIssue], warnings: [BookPDF.PreflightIssue]) {
        typealias Issue = BookPDF.PreflightIssue
        var blockers = [Issue]()
        var warnings = [Issue]()
        if size(for: book) == nil {
            blockers.append(Issue(problem: .sizeNotOffered(book.format, offered: profile.sizes(closestTo: book.format).map(\.format))))
        }
        let rules = pageRules(for: book)
        let count = countedPages(interiorPages: interiorPages, book: book)
        if let minimum = rules.minimum, count < minimum {
            warnings.append(Issue(problem: .pageCount(.minimum(minimum), has: count)))
        }
        if let maximum = rules.maximum, count > maximum {
            warnings.append(Issue(problem: .pageCount(.maximum(maximum), has: count)))
        }
        if let multiple = rules.multiple, multiple > 1, !count.isMultiple(of: multiple) {
            warnings.append(Issue(problem: .pageCount(.multiple(multiple), has: count)))
        }
        if coverKind(for: book) == .flat {
            for measure in PrintMeasure.allCases where value(measure, for: book, interiorPages: interiorPages) == nil {
                blockers.append(Issue(location: .cover, problem: .missingMeasure(measure)))
            }
        }
        return (blockers, warnings)
    }

    /// The print zones of the product in millimetres, for the canvas guides (T2's `PrintGuides`): bleed
    /// and safe margin per edge of an interior page, and the cover's hinge and safe margin.
    func zones(for book: Book, interiorPages: Int) -> PrintZones {
        let cover = coverRules(for: book)
        return PrintZones(bleed: profile.interior.bleed, safe: profile.interior.safe,
                          coverHingeMM: cover.kind == .flat ? value(.hinge, for: book, interiorPages: interiorPages) : nil,
                          coverSafeMM: cover.safe?.mm)
    }
}

extension PrintSettings {
    /// Chooses a print-service product, or none for generic print. A product records its id, size and
    /// paper and sets the bleed and the safe margin from the product: the safe margin is the largest of
    /// the outer edges, because the layout keeps one margin on every side; the binding margin is shown
    /// with the product's rules. The book's format is not changed here.
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
        bleedMM = interior.bleed.largest
        safeMM = max(interior.safe.top.mm, interior.safe.bottom.mm, interior.safe.outer.mm)
    }
}

extension PrintPlan {
    /// The product's zones on one interior page for `PrintGuides.frames(pageSize:settings:zones:)`: the
    /// strip along the binding that its inner safe margin keeps clear of text, when it is wider than the
    /// book's safe margin. `pageSize` is the trim in points; a full spread has no binding strip.
    func guideZones(pageSize: CGSize, onRight: Bool, spread: Bool, safeMM: Double) -> [PrintGuides.Zone] {
        let inner = profile.interior.safe.inner.mm
        guard !spread, inner > safeMM else { return [] }
        let width = inner * PrintGuides.pointsPerMM
        let x = onRight ? 0 : pageSize.width - width
        return [PrintGuides.Zone(kind: .innerMargin, rect: CGRect(x: x, y: 0, width: width, height: pageSize.height))]
    }
}

/// What a print-service profile adds to the guides on the canvas.
struct PrintZones: Hashable, Sendable {
    var bleed: PrintProfile.Edges
    var safe: PrintProfile.Edges
    var coverHingeMM: Double?
    var coverSafeMM: Double?
}
