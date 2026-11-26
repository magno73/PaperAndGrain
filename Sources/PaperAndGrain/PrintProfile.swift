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

    /// A length per edge of a page. `inner` is the binding edge; on a flat cover `outer` is the left and
    /// right edge and `inner` is not used. One length (a number or a `Length` object) sets every edge.
    struct Edges: Codable, Hashable, Sendable {
        var top: Length
        var bottom: Length
        var outer: Length
        var inner: Length

        init(_ all: Double) { self.init(top: all, bottom: all, outer: all, inner: all) }

        init(top: Double, bottom: Double, outer: Double, inner: Double) {
            self.top = Length(top)
            self.bottom = Length(bottom)
            self.outer = Length(outer)
            self.inner = Length(inner)
        }

        private enum CodingKeys: String, CodingKey { case top, bottom, outer, inner }

        init(from decoder: Decoder) throws {
            if let keyed = try? decoder.container(keyedBy: CodingKeys.self), keyed.contains(.top) {
                top = try keyed.decode(Length.self, forKey: .top)
                bottom = try keyed.decode(Length.self, forKey: .bottom)
                outer = try keyed.decode(Length.self, forKey: .outer)
                inner = try keyed.decode(Length.self, forKey: .inner)
            } else {
                let all = try Length(from: decoder)
                (top, bottom, outer, inner) = (all, all, all, all)
            }
        }

        func encode(to encoder: Encoder) throws {
            if Set([top, bottom, outer, inner]).count == 1 {
                try top.encode(to: encoder)
            } else {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(top, forKey: .top)
                try container.encode(bottom, forKey: .bottom)
                try container.encode(outer, forKey: .outer)
                try container.encode(inner, forKey: .inner)
            }
        }

        var all: [Length] { [top, bottom, outer, inner] }
        var largest: Double { all.map(\.mm).max() ?? 0 }
    }

    /// A cover measure that can depend on the page count. The author can always type another value.
    enum Measure: Codable, Hashable, Sendable {
        /// The same for every book.
        case fixed(Length)
        /// Given only in the printer's quote or configurator: the author types it, within the range.
        case quote(minMM: Double, maxMM: Double)
        /// `baseMM + mmPerPage × pages`, for example a paperback spine from the paper thickness.
        case formula(baseMM: Double, mmPerPage: Double, source: String?)
        /// Stepped by page count, optionally per paper: the first row whose `upToPages` reaches the count.
        case table(rows: [Row], source: String?)

        struct Row: Codable, Hashable, Sendable {
            var paper: String?
            var upToPages: Int
            /// A number, or a `Length` object that keeps the printer's value (`{"mm": 9, "source": "106 px"}`).
            var mm: Length
        }

        private enum CodingKeys: String, CodingKey { case quote, formula, table }
        private struct Quote: Codable { var minMM: Double?; var maxMM: Double? }
        private struct Formula: Codable { var baseMM: Double; var mmPerPage: Double; var source: String? }
        private struct Table: Codable { var rows: [Row]; var source: String? }

        init(from decoder: Decoder) throws {
            if let keyed = try? decoder.container(keyedBy: CodingKeys.self) {
                if let quote = try keyed.decodeIfPresent(Quote.self, forKey: .quote) {
                    self = .quote(minMM: quote.minMM ?? 0, maxMM: quote.maxMM ?? 100)
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
            case let .quote(minMM, maxMM):
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(Quote(minMM: minMM, maxMM: maxMM), forKey: .quote)
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

        var isTyped: Bool {
            if case .quote = self { return true }
            return false
        }

        /// Whether a typed value is one the printer could accept.
        func accepts(_ mm: Double) -> Bool {
            guard mm.isFinite, mm >= 0 else { return false }
            if case let .quote(minimum, maximum) = self { return mm > minimum && mm <= maximum }
            return mm <= 1000
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

        struct Panel: Codable, Hashable, Sendable {
            var widthMM: Length
            var heightMM: Length
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
        /// Beyond the wrap, per edge (`outer` is left and right).
        var bleed: Edges?
        /// From the trim line of each face.
        var safe: Length?

        /// Fields set here replace the product's.
        func over(_ base: Cover) -> Cover {
            Cover(kind: kind ?? base.kind, panel: panel ?? base.panel, hinge: hinge ?? base.hinge,
                  spine: spine ?? base.spine, wrap: wrap ?? base.wrap, bleed: bleed ?? base.bleed,
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
    }

    struct Size: Codable, Hashable, Sendable, Identifiable {
        var id: String
        var name: Text?
        var widthMM: Length
        var heightMM: Length
        var pages: PageRules?
        var cover: Cover?

        var format: BookFormat { BookFormat(widthMM: widthMM.mm, heightMM: heightMM.mm) }

        func matches(_ format: BookFormat) -> Bool {
            abs(format.widthMM - widthMM.mm) < 0.01 && abs(format.heightMM - heightMM.mm) < 0.01
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

    func size(_ id: String?) -> Size? { sizes.first { $0.id == id } }

    func size(matching format: BookFormat) -> Size? { sizes.first { $0.matches(format) } }

    /// The product's sizes, the one nearest to `format` first.
    func sizes(closestTo format: BookFormat) -> [Size] {
        sizes.enumerated().sorted { a, b in
            func distance(_ size: Size) -> Double {
                hypot(size.widthMM.mm - format.widthMM, size.heightMM.mm - format.heightMM)
            }
            return (distance(a.element), a.offset) < (distance(b.element), b.offset)
        }.map(\.element)
    }

    func coverRules(for size: Size) -> Cover { size.cover?.over(cover) ?? cover }

    func pageRules(for size: Size) -> PageRules { size.pages?.over(interior.pages) ?? interior.pages }

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

/// The measures the author typed for the chosen print service, which replace the profile's values.
struct PrintMeasures: Codable, Hashable, Sendable {
    var spineMM: Double?
    var hingeMM: Double?
    var wrapMM: Double?
}

/// The cover measures the profile depends on, named for messages and for the author's values.
enum PrintMeasure: String, CaseIterable, Hashable, Sendable {
    case spine, hinge, wrap
}
