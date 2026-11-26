import Foundation

/// One printer's product, described as data: the trims it offers, how the interior and the cover are
/// laid out in the PDF, the measures that depend on the page count, the files and the color it takes.
/// Entries live in `Resources/PrintProfiles`, one JSON file per service, so adding a printer is adding
/// a file. All lengths are millimetres; a length can keep the printer's own value and unit in `source`.
struct PrintProfile: Codable, Hashable, Sendable, Identifiable {
    enum Binding: String, Codable, Hashable, Sendable, CaseIterable {
        case hardcover, layflat, softcover
    }

    enum Side: String, Codable, Hashable, Sendable {
        case left, right
    }

    enum ColorMode: String, Codable, Hashable, Sendable {
        case srgb, cmyk
    }

    /// A name or note in the interface languages: `{"en": …, "it": …}`, or one string for every language.
    struct Text: Codable, Hashable, Sendable {
        var values: [String: String]

        init(_ english: String) { values = ["en": english] }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let plain = try? container.decode(String.self) {
                values = ["en": plain]
            } else {
                values = try container.decode([String: String].self)
            }
            guard values["en"]?.isEmpty == false else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected an English text")
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            if values.count == 1, let english = values["en"] { try container.encode(english) } else { try container.encode(values) }
        }

        func callAsFunction(_ language: String) -> String {
            values[L10n.code(language)] ?? values["en"] ?? ""
        }
    }

    /// Millimetres, with the value as the printer gives it (`"9 pt"`, `"106 px at 300 dpi"`) so an entry
    /// can be checked against its page. Written as a number, or as `{"mm": 3.175, "source": "0.125 in"}`.
    struct Length: Codable, Hashable, Sendable {
        var mm: Double
        var source: String?

        init(_ mm: Double, source: String? = nil) {
            self.mm = mm
            self.source = source
        }

        private enum CodingKeys: String, CodingKey { case mm, source }

        init(from decoder: Decoder) throws {
            if let value = try? decoder.singleValueContainer().decode(Double.self) {
                mm = value
                return
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            mm = try container.decode(Double.self, forKey: .mm)
            source = try container.decodeIfPresent(String.self, forKey: .source)
        }

        func encode(to encoder: Encoder) throws {
            if let source {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(mm, forKey: .mm)
                try container.encode(source, forKey: .source)
            } else {
                var container = encoder.singleValueContainer()
                try container.encode(mm)
            }
        }
    }

    /// A value per edge of a page. `inner` is the binding edge; on a flat cover `outer` is the left and
    /// right edge and `inner` is not used. Each edge is a fixed length or a value from the printer's quote
    /// (`{"quote": …}`); one value sets every edge, or all four are named.
    struct Edges: Codable, Hashable, Sendable {
        var top: Measure
        var bottom: Measure
        var outer: Measure
        var inner: Measure

        init(_ all: Double) { self.init(top: all, bottom: all, outer: all, inner: all) }

        init(top: Double, bottom: Double, outer: Double, inner: Double) {
            self.top = .fixed(Length(top))
            self.bottom = .fixed(Length(bottom))
            self.outer = .fixed(Length(outer))
            self.inner = .fixed(Length(inner))
        }

        private enum CodingKeys: String, CodingKey, CaseIterable { case top, bottom, outer, inner }

        init(from decoder: Decoder) throws {
            if let keyed = try? decoder.container(keyedBy: CodingKeys.self),
               CodingKeys.allCases.contains(where: keyed.contains) {
                let missing = CodingKeys.allCases.filter { !keyed.contains($0) }.map(\.rawValue)
                guard missing.isEmpty else {
                    throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription:
                        "Edges need top, bottom, outer and inner, or one value for all (missing: "
                        + missing.joined(separator: ", ") + ")"))
                }
                top = try keyed.decode(Measure.self, forKey: .top)
                bottom = try keyed.decode(Measure.self, forKey: .bottom)
                outer = try keyed.decode(Measure.self, forKey: .outer)
                inner = try keyed.decode(Measure.self, forKey: .inner)
            } else {
                let all = try Measure(from: decoder)
                (top, bottom, outer, inner) = (all, all, all, all)
            }
        }

        func encode(to encoder: Encoder) throws {
            if Set(all).count == 1 {
                try top.encode(to: encoder)
            } else {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(top, forKey: .top)
                try container.encode(bottom, forKey: .bottom)
                try container.encode(outer, forKey: .outer)
                try container.encode(inner, forKey: .inner)
            }
        }

        var all: [Measure] { [top, bottom, outer, inner] }

        /// True when an edge is given per order and the author types it.
        var isTyped: Bool { all.contains(where: \.isTyped) }

        /// The millimetres per edge, with `typed` for the edges given per order; nil when one is missing.
        func values(typed: Double?) -> EdgeValues? {
            func value(_ measure: Measure) -> Double? {
                if case let .fixed(length) = measure { return length.mm }
                guard let typed, measure.accepts(typed) else { return nil }
                return typed
            }
            guard let top = value(top), let bottom = value(bottom), let outer = value(outer), let inner = value(inner)
            else { return nil }
            return EdgeValues(top: top, bottom: bottom, outer: outer, inner: inner)
        }

        /// The fixed edges, with 0 for an edge given per order: for display and the safe margins.
        var fixedValues: EdgeValues {
            func value(_ measure: Measure) -> Double { if case let .fixed(length) = measure { length.mm } else { 0 } }
            return EdgeValues(top: value(top), bottom: value(bottom), outer: value(outer), inner: value(inner))
        }
    }

    /// Millimetres per edge, resolved.
    struct EdgeValues: Hashable, Sendable {
        var top: Double, bottom: Double, outer: Double, inner: Double

        static let zero = EdgeValues(top: 0, bottom: 0, outer: 0, inner: 0)

        var all: [Double] { [top, bottom, outer, inner] }
        var largest: Double { all.max() ?? 0 }
        /// The largest margin of the edges that are cut: top, bottom and outer.
        var largestOuter: Double { max(top, bottom, outer) }
    }

    /// A measure that can depend on the order or the page count. The author can always type another value.
    enum Measure: Codable, Hashable, Sendable {
        /// The same for every book.
        case fixed(Length)
        /// Given only in the printer's quote or configurator: the author types it, within the range.
        case quote(Quote)
        /// `baseMM + mmPerPage × pages`, for example a paperback spine from the paper thickness.
        case formula(baseMM: Double, mmPerPage: Double, source: String?)
        /// Stepped by page count, optionally per paper: the first row whose `upToPages` reaches the count.
        case table(rows: [Row], source: String?)

        /// The range a typed value must fall in. `typicalMM` is the value to propose (for a trim, the size
        /// the menus show).
        struct Quote: Codable, Hashable, Sendable {
            var minMM: Double
            var maxMM: Double
            /// True when `minMM` itself is not accepted (a spine of 0 mm, for example).
            var minExclusive: Bool?
            var typicalMM: Double?

            init(minMM: Double = 0, maxMM: Double = 100, minExclusive: Bool? = nil, typicalMM: Double? = nil) {
                self.minMM = minMM
                self.maxMM = maxMM
                self.minExclusive = minExclusive
                self.typicalMM = typicalMM
            }

            private enum CodingKeys: String, CodingKey { case minMM, maxMM, minExclusive, typicalMM }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                minMM = try container.decodeIfPresent(Double.self, forKey: .minMM) ?? 0
                maxMM = try container.decodeIfPresent(Double.self, forKey: .maxMM) ?? 100
                minExclusive = try container.decodeIfPresent(Bool.self, forKey: .minExclusive)
                typicalMM = try container.decodeIfPresent(Double.self, forKey: .typicalMM)
            }

            func accepts(_ mm: Double) -> Bool {
                mm.isFinite && (minExclusive == true ? mm > minMM : mm >= minMM) && mm <= maxMM
            }
        }

        struct Row: Codable, Hashable, Sendable {
            var paper: String?
            var upToPages: Int
            /// A number, or a `Length` object that keeps the printer's value (`{"mm": 9, "source": "106 px"}`).
            var mm: Length
        }

        private enum CodingKeys: String, CodingKey { case quote, formula, table }
        private struct Formula: Codable { var baseMM: Double; var mmPerPage: Double; var source: String? }
        private struct Table: Codable { var rows: [Row]; var source: String? }

        init(from decoder: Decoder) throws {
            if let keyed = try? decoder.container(keyedBy: CodingKeys.self) {
                if let quote = try keyed.decodeIfPresent(Quote.self, forKey: .quote) {
                    self = .quote(quote)
                    return
                }
                if let formula = try keyed.decodeIfPresent(Formula.self, forKey: .formula) {
                    self = .formula(baseMM: formula.baseMM, mmPerPage: formula.mmPerPage, source: formula.source)
                    return
                }
                if let table = try keyed.decodeIfPresent(Table.self, forKey: .table) {
                    self = .table(rows: table.rows.sorted { $0.upToPages < $1.upToPages }, source: table.source)
                    return
                }
            }
            self = .fixed(try Length(from: decoder))
        }

        func encode(to encoder: Encoder) throws {
            switch self {
            case let .fixed(length): try length.encode(to: encoder)
            case let .quote(quote):
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(quote, forKey: .quote)
            case let .formula(baseMM, mmPerPage, source):
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(Formula(baseMM: baseMM, mmPerPage: mmPerPage, source: source), forKey: .formula)
            case let .table(rows, source):
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(Table(rows: rows, source: source), forKey: .table)
            }
        }

        /// The profile's value for a book of `pages` interior pages, or nil when the author must type it
        /// or the count is outside the table.
        func value(pages: Int, paper: String?) -> Double? {
            switch self {
            case let .fixed(length): length.mm
            case .quote: nil
            case let .formula(base, perPage, _): base + perPage * Double(pages)
            case let .table(rows, _):
                rows.first { ($0.paper == nil || $0.paper == paper) && pages <= $0.upToPages }?.mm.mm
            }
        }

        /// The largest page count the table covers for `paper`; nil for a measure that is not a table.
        func tableLimit(paper: String?) -> Int? {
            guard case let .table(rows, _) = self else { return nil }
            return rows.filter { $0.paper == nil || $0.paper == paper }.map(\.upToPages).max()
        }

        var isTyped: Bool {
            if case .quote = self { return true }
            return false
        }

        var isFixedOrTyped: Bool {
            switch self {
            case .fixed, .quote: true
            case .formula, .table: false
            }
        }

        /// The value a menu shows for a fixed length or a length from the quote.
        var nominal: Double? {
            switch self {
            case let .fixed(length): length.mm
            case let .quote(quote): quote.typicalMM ?? (quote.minMM + quote.maxMM) / 2
            case .formula, .table: nil
            }
        }

        /// Whether a typed value is one the printer could accept.
        func accepts(_ mm: Double) -> Bool {
            guard mm.isFinite, mm >= 0 else { return false }
            if case let .quote(quote) = self { return quote.accepts(mm) }
            return mm <= 1000
        }

        /// Whether `mm` is this length: equal to a fixed one, inside the range of one from the quote.
        func matches(_ mm: Double) -> Bool {
            switch self {
            case let .fixed(length): abs(mm - length.mm) < 0.01
            case let .quote(quote): quote.accepts(mm)
            case .formula, .table: false
            }
        }
    }

    /// The page-count rules of the product. `coverPagesCounted` is how many cover pages the printer adds
    /// to the count (Pixartprinting counts the four sides of the cover; most printers count none).
    struct PageRules: Codable, Hashable, Sendable {
        var minimum: Int?
        var maximum: Int?
        var multiple: Int?
        var coverPagesCounted: Int?

        /// Fields set here replace the product's.
        func over(_ base: PageRules) -> PageRules {
            PageRules(minimum: minimum ?? base.minimum, maximum: maximum ?? base.maximum,
                      multiple: multiple ?? base.multiple, coverPagesCounted: coverPagesCounted ?? base.coverPagesCounted)
        }
    }

    struct Interior: Codable, Hashable, Sendable {
        enum Layout: String, Codable, Hashable, Sendable {
            /// One page per PDF page.
            case single
            /// One double page per PDF page, the first spread starting on the left.
            case spread
        }

        /// What the first and last interior pages are.
        enum Ends: String, Codable, Hashable, Sendable {
            /// Ordinary pages.
            case pages
            /// Printed on the inside of the front and back cover (Saal Digital): they belong to the
            /// first and last spread.
            case insideCovers
            /// Glued to the boards: they stay blank.
            case endpapers
        }

        var layout: Layout
        /// Per edge; zero means the printer wants that edge cut at the trim.
        var bleed: Edges
        var safe: Edges
        /// The side of the first interior page in the PDF.
        var firstPage: Side
        var ends: Ends?
        /// The resolution the printer asks for; the book's own target when absent.
        var targetPPI: Double?
        var pages: PageRules
    }

    struct Cover: Codable, Hashable, Sendable {
        enum Kind: String, Codable, Hashable, Sendable {
            /// The printer makes the cover; the PDF holds the interior only.
            case none
            /// Front cover as the first page and back cover as the last page of the interior PDF, at trim size.
            case interiorPages
            /// One flat sheet: back, spine, front, with hinges, wrap and bleed.
            case flat
        }

        /// Fixed, or `{"quote": …}` when the printer gives the board per order.
        struct Panel: Codable, Hashable, Sendable {
            var widthMM: Measure
            var heightMM: Measure
        }

        var kind: Kind?
        /// The board of each face when it differs from the page (a board overhang, or a narrower board
        /// where the hinge takes the rest); the page trim when absent.
        var panel: Panel?
        /// Between each face and the spine.
        var hinge: Measure?
        var spine: Measure?
        /// The material folded around the board, outside the trim line.
        var wrap: Measure?
        /// True when the hinge (Saal's fold-over) lies inside the board width, so the cover keeps the same
        /// outer width at every page count and only the hinge zone grows.
        var hingeWithinPanel: Bool?
        /// Beyond the wrap, per edge (`outer` is left and right).
        var bleed: Edges?
        /// From the trim line of each face.
        var safe: Length?

        /// Fields set here replace the product's.
        func over(_ base: Cover) -> Cover {
            Cover(kind: kind ?? base.kind, panel: panel ?? base.panel, hinge: hinge ?? base.hinge,
                  spine: spine ?? base.spine, wrap: wrap ?? base.wrap,
                  hingeWithinPanel: hingeWithinPanel ?? base.hingeWithinPanel, bleed: bleed ?? base.bleed,
                  safe: safe ?? base.safe)
        }
    }

    struct Files: Codable, Hashable, Sendable {
        enum Arrangement: String, Codable, Hashable, Sendable {
            /// One PDF; a flat cover is its first page.
            case single
            /// An interior PDF and a cover PDF, in a folder.
            case separate
        }

        var arrangement: Arrangement
        var interior: String?
        var cover: String?

        var interiorName: String { interior ?? "Interior.pdf" }
        var coverName: String { cover ?? "Cover.pdf" }
    }

    struct ColorRules: Codable, Hashable, Sendable {
        var accepts: [ColorMode]
        /// The ICC output profile the printer names, by its description.
        var iccProfile: String?
        /// The PDF standard the printer asks for. The app does not certify it.
        var standard: String?
        var flattenTransparency: Bool?
    }

    struct Paper: Codable, Hashable, Sendable, Identifiable {
        var id: String
        var name: Text
        /// Page limits of this paper, over the size's and the product's.
        var pages: PageRules?
    }

    /// A trim the product offers. Width and height are fixed, or `{"quote": …}` when the printer gives
    /// the exact page size per order: then any book size in the range is this size.
    struct Size: Codable, Hashable, Sendable, Identifiable {
        var id: String
        var name: Text?
        var widthMM: Measure
        var heightMM: Measure
        var pages: PageRules?
        var cover: Cover?

        /// The trim a menu proposes: the fixed size, or the typical one of a size given per order.
        var format: BookFormat { BookFormat(widthMM: widthMM.nominal ?? 0, heightMM: heightMM.nominal ?? 0) }

        func matches(_ format: BookFormat) -> Bool {
            widthMM.matches(format.widthMM) && heightMM.matches(format.heightMM)
        }

        /// The printer's name for the size when it has one, else the trim in centimetres.
        func title(_ language: String) -> String {
            name?(language) ?? BookFormatPreset.centimetres(format, language: language)
        }
    }

    var id: String
    var service: String
    var product: Text
    var binding: Binding
    /// Where the service delivers, as ISO 3166 codes or `EU`.
    var regions: [String]
    var sourceURL: URL
    /// The day the specification was checked on `sourceURL`, as `yyyy-MM-dd`.
    var verifiedOn: String
    var notes: Text?
    var papers: [Paper]?
    var interior: Interior
    var cover: Cover
    var files: Files
    var color: ColorRules
    var sizes: [Size]

    var separateFiles: Bool { files.arrangement == .separate }

    func size(_ id: String?) -> Size? { sizes.first { $0.id == id } }

    func size(matching format: BookFormat) -> Size? { sizes.first { $0.matches(format) } }

    /// The product's sizes, the one nearest to `format` first.
    func sizes(closestTo format: BookFormat) -> [Size] {
        sizes.enumerated().sorted { a, b in
            func distance(_ size: Size) -> Double {
                hypot(size.format.widthMM - format.widthMM, size.format.heightMM - format.heightMM)
            }
            return (distance(a.element), a.offset) < (distance(b.element), b.offset)
        }.map(\.element)
    }

    func coverRules(for size: Size) -> Cover { size.cover?.over(cover) ?? cover }

    /// The page limits: the paper's over the size's over the product's.
    func pageRules(for size: Size?, paper: Paper? = nil) -> PageRules {
        let sized = size?.pages?.over(interior.pages) ?? interior.pages
        return paper?.pages?.over(sized) ?? sized
    }

    var verifiedDate: Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: verifiedOn), formatter.string(from: date) == verifiedOn else { return nil }
        return date
    }

    /// "Service · Product", for menus and the export sheet.
    func title(_ language: String) -> String { service + " · " + product(language) }
}

/// The measures the author typed for the chosen print service, which replace the profile's values or
/// give the ones the printer states per order.
struct PrintMeasures: Codable, Hashable, Sendable {
    var spineMM: Double?
    var hingeMM: Double?
    var wrapMM: Double?
    var panelWidthMM: Double?
    var panelHeightMM: Double?
    var coverBleedMM: Double?
    var interiorBleedMM: Double?

    subscript(_ measure: PrintMeasure) -> Double? {
        get {
            switch measure {
            case .spine: spineMM
            case .hinge: hingeMM
            case .wrap: wrapMM
            case .panelWidth: panelWidthMM
            case .panelHeight: panelHeightMM
            case .coverBleed: coverBleedMM
            case .interiorBleed: interiorBleedMM
            }
        }
        set {
            switch measure {
            case .spine: spineMM = newValue
            case .hinge: hingeMM = newValue
            case .wrap: wrapMM = newValue
            case .panelWidth: panelWidthMM = newValue
            case .panelHeight: panelHeightMM = newValue
            case .coverBleed: coverBleedMM = newValue
            case .interiorBleed: interiorBleedMM = newValue
            }
        }
    }
}

/// The measures a profile can leave to the order or compute, named for messages and the author's values.
enum PrintMeasure: String, CaseIterable, Hashable, Sendable {
    case spine, hinge, wrap, panelWidth, panelHeight, coverBleed, interiorBleed

    /// The command-line option that types it, such as `--panel-width-mm`.
    var option: String {
        "--" + rawValue.reduce(into: "") { text, character in
            text += character.isUppercase ? "-" + character.lowercased() : String(character)
        } + "-mm"
    }
}
