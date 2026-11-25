import Foundation

/// Trimmed page sizes commonly offered by photobook printers. The book keeps only
/// `BookFormat` in millimetres, so presets never change the document schema.
struct BookFormatPreset: Identifiable, Hashable, Sendable {
    enum Shape: String, CaseIterable, Sendable {
        case square, landscape, portrait

        func title(_ language: String) -> String {
            switch self {
            case .square: L10n.string("format.shape.square", language: language, default: "Square")
            case .landscape: L10n.string("format.shape.landscape", language: language, default: "Landscape")
            case .portrait: L10n.string("format.shape.portrait", language: language, default: "Portrait")
            }
        }
    }

    let id: String
    let shape: Shape
    let format: BookFormat
    let inches: String?
    /// What the size is for, in English; it is the catalog key.
    let note: String

    func name(_ language: String) -> String {
        let size = Self.centimetres(format, language: language)
        let note = L10n.string(self.note, language: language)
        if let inches { return "\(inches) · \(size) · \(note)" }
        return "\(size) · \(note)"
    }

    static func centimetres(_ format: BookFormat, language: String) -> String {
        let style = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...1))
            .locale(Locale(identifier: language))
        return "\((format.widthMM / 10).formatted(style)) × \((format.heightMM / 10).formatted(style)) cm"
    }

    static func matching(_ format: BookFormat) -> Self? {
        all.first { abs($0.format.widthMM - format.widthMM) < 0.5 && abs($0.format.heightMM - format.heightMM) < 0.5 }
    }

    static func presets(_ shape: Shape) -> [Self] { all.filter { $0.shape == shape } }

    static let all: [Self] = [
        Self(id: "square-15", shape: .square, format: BookFormat(widthMM: 150, heightMM: 150), inches: nil,
             note: "small, gift size"),
        Self(id: "square-8in", shape: .square, format: BookFormat(widthMM: 203, heightMM: 203), inches: "8 × 8″",
             note: "US standard"),
        Self(id: "square-20", shape: .square, format: BookFormat(widthMM: 200, heightMM: 200), inches: nil,
             note: "medium"),
        Self(id: "square-21", shape: .square, format: .square, inches: nil,
             note: "medium, Pixartprinting profile"),
        Self(id: "square-25", shape: .square, format: BookFormat(widthMM: 250, heightMM: 250), inches: nil,
             note: "large"),
        Self(id: "square-30", shape: .square, format: BookFormat(widthMM: 300, heightMM: 300), inches: nil,
             note: "extra large, coffee table"),
        Self(id: "square-12in", shape: .square, format: BookFormat(widthMM: 305, heightMM: 305), inches: "12 × 12″",
             note: "US album"),

        Self(id: "landscape-20x15", shape: .landscape, format: BookFormat(widthMM: 200, heightMM: 150), inches: nil,
             note: "small"),
        Self(id: "landscape-10x8in", shape: .landscape, format: BookFormat(widthMM: 254, heightMM: 203), inches: "10 × 8″",
             note: "US standard"),
        Self(id: "landscape-28x21", shape: .landscape, format: BookFormat(widthMM: 280, heightMM: 210), inches: nil,
             note: "medium"),
        Self(id: "landscape-a4", shape: .landscape, format: BookFormat(widthMM: 297, heightMM: 210), inches: nil,
             note: "A4"),
        Self(id: "landscape-30x20", shape: .landscape, format: .landscape, inches: nil,
             note: "panoramic"),
        Self(id: "landscape-33x23", shape: .landscape, format: BookFormat(widthMM: 330, heightMM: 230), inches: nil,
             note: "large"),
        Self(id: "landscape-13x11in", shape: .landscape, format: BookFormat(widthMM: 330, heightMM: 279), inches: "13 × 11″",
             note: "US large"),
        Self(id: "landscape-40x30", shape: .landscape, format: BookFormat(widthMM: 400, heightMM: 300), inches: nil,
             note: "extra large"),

        Self(id: "portrait-15x20", shape: .portrait, format: BookFormat(widthMM: 150, heightMM: 200), inches: nil,
             note: "small"),
        Self(id: "portrait-8x10in", shape: .portrait, format: BookFormat(widthMM: 203, heightMM: 254), inches: "8 × 10″",
             note: "US standard"),
        Self(id: "portrait-a4", shape: .portrait, format: BookFormat(widthMM: 210, heightMM: 297), inches: nil,
             note: "A4, magazine"),
        Self(id: "portrait-21x28", shape: .portrait, format: BookFormat(widthMM: 210, heightMM: 280), inches: nil,
             note: "medium"),
        Self(id: "portrait-20x30", shape: .portrait, format: .portrait, inches: nil,
             note: "tall"),
        Self(id: "portrait-23x30", shape: .portrait, format: BookFormat(widthMM: 230, heightMM: 300), inches: nil,
             note: "large"),
    ]
}
