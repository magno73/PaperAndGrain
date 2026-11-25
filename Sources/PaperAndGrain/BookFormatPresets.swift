import Foundation

/// Trimmed page sizes commonly offered by photobook printers. The book keeps only
/// `BookFormat` in millimetres, so presets never change the document schema.
struct BookFormatPreset: Identifiable, Hashable, Sendable {
    enum Shape: String, CaseIterable, Sendable {
        case square, landscape, portrait

        func title(_ language: String) -> String {
            let italian = language.hasPrefix("it")
            switch self {
            case .square: return italian ? "Quadrati" : "Square"
            case .landscape: return italian ? "Orizzontali" : "Landscape"
            case .portrait: return italian ? "Verticali" : "Portrait"
            }
        }
    }

    let id: String
    let shape: Shape
    let format: BookFormat
    let inches: String?
    let italian: String
    let english: String

    func name(_ language: String) -> String {
        let italian = language.hasPrefix("it")
        let size = Self.centimetres(format, language: language)
        let note = italian ? self.italian : english
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
             italian: "piccolo, da regalo", english: "small, gift size"),
        Self(id: "square-8in", shape: .square, format: BookFormat(widthMM: 203, heightMM: 203), inches: "8 × 8″",
             italian: "standard americano", english: "US standard"),
        Self(id: "square-20", shape: .square, format: BookFormat(widthMM: 200, heightMM: 200), inches: nil,
             italian: "medio", english: "medium"),
        Self(id: "square-21", shape: .square, format: .square, inches: nil,
             italian: "medio, profilo Pixartprinting", english: "medium, Pixartprinting profile"),
        Self(id: "square-25", shape: .square, format: BookFormat(widthMM: 250, heightMM: 250), inches: nil,
             italian: "grande", english: "large"),
        Self(id: "square-30", shape: .square, format: BookFormat(widthMM: 300, heightMM: 300), inches: nil,
             italian: "molto grande, da tavolo", english: "extra large, coffee table"),
        Self(id: "square-12in", shape: .square, format: BookFormat(widthMM: 305, heightMM: 305), inches: "12 × 12″",
             italian: "album americano", english: "US album"),

        Self(id: "landscape-20x15", shape: .landscape, format: BookFormat(widthMM: 200, heightMM: 150), inches: nil,
             italian: "piccolo", english: "small"),
        Self(id: "landscape-10x8in", shape: .landscape, format: BookFormat(widthMM: 254, heightMM: 203), inches: "10 × 8″",
             italian: "standard americano", english: "US standard"),
        Self(id: "landscape-28x21", shape: .landscape, format: BookFormat(widthMM: 280, heightMM: 210), inches: nil,
             italian: "medio", english: "medium"),
        Self(id: "landscape-a4", shape: .landscape, format: BookFormat(widthMM: 297, heightMM: 210), inches: nil,
             italian: "A4", english: "A4"),
        Self(id: "landscape-30x20", shape: .landscape, format: .landscape, inches: nil,
             italian: "panoramico", english: "panoramic"),
        Self(id: "landscape-33x23", shape: .landscape, format: BookFormat(widthMM: 330, heightMM: 230), inches: nil,
             italian: "grande", english: "large"),
        Self(id: "landscape-13x11in", shape: .landscape, format: BookFormat(widthMM: 330, heightMM: 279), inches: "13 × 11″",
             italian: "grande americano", english: "US large"),
        Self(id: "landscape-40x30", shape: .landscape, format: BookFormat(widthMM: 400, heightMM: 300), inches: nil,
             italian: "molto grande", english: "extra large"),

        Self(id: "portrait-15x20", shape: .portrait, format: BookFormat(widthMM: 150, heightMM: 200), inches: nil,
             italian: "piccolo", english: "small"),
        Self(id: "portrait-8x10in", shape: .portrait, format: BookFormat(widthMM: 203, heightMM: 254), inches: "8 × 10″",
             italian: "standard americano", english: "US standard"),
        Self(id: "portrait-a4", shape: .portrait, format: BookFormat(widthMM: 210, heightMM: 297), inches: nil,
             italian: "A4, rivista", english: "A4, magazine"),
        Self(id: "portrait-21x28", shape: .portrait, format: BookFormat(widthMM: 210, heightMM: 280), inches: nil,
             italian: "medio", english: "medium"),
        Self(id: "portrait-20x30", shape: .portrait, format: .portrait, inches: nil,
             italian: "alto", english: "tall"),
        Self(id: "portrait-23x30", shape: .portrait, format: BookFormat(widthMM: 230, heightMM: 300), inches: nil,
             italian: "grande", english: "large"),
    ]
}
