import Foundation

/// The film-emulation LUTs bundled in Resources/FilmLooks (by abpy, CC BY-NC-SA 4.0; see CREDITS.md).
/// Names describe the look; they deliberately avoid any film-stock or camera trademark.
struct BundledFilmLook: Identifiable, Hashable, Sendable {
    enum Input: CaseIterable, Hashable, Sendable {
        /// For images developed with a linear, flat contrast.
        case linear
        /// For images already rendered with a standard slide-film look, such as in-camera JPEGs.
        case slide
    }

    /// The English name, which is also the catalog key (the CLI lists it as is).
    let english: String
    let filename: String
    let input: Input
    private let contentHash: String

    var id: String { (filename as NSString).deletingPathExtension }

    func name(language: String) -> String { L10n.string(english, language: language) }

    func url(in resourceDirectory: URL) -> URL {
        resourceDirectory.appendingPathComponent("FilmLooks", isDirectory: true)
            .appendingPathComponent(filename)
    }

    /// Match the name and content fingerprint written by BookStorage.importLUT.
    /// A different LUT with the same base name is still a custom look.
    static func importedLook(filename: String) -> Self? {
        all.first { look in
            let stem = (look.filename as NSString).deletingPathExtension.prefix(72)
            return filename == "\(stem)-\(look.contentHash).cube"
        }
    }

    static let all: [Self] = [
        Self(english: "Natural Slide", filename: "natural-slide.cube",
             input: .linear, contentHash: "5aecd2df2999ee69"),
        Self(english: "Vivid Slide", filename: "vivid-slide.cube",
             input: .linear, contentHash: "e576e9b9013d5e78"),
        Self(english: "Soft Slide", filename: "soft-slide.cube",
             input: .linear, contentHash: "84d884693ca55668"),
        Self(english: "Muted Chrome", filename: "muted-chrome.cube",
             input: .linear, contentHash: "4568770fd3a89d0c"),
        Self(english: "Street Negative", filename: "street-negative.cube",
             input: .linear, contentHash: "de8b59d1017ceef2"),
        Self(english: "Portrait Standard", filename: "portrait-standard.cube",
             input: .linear, contentHash: "9dbdd7208b2389c1"),
        Self(english: "Portrait Contrast", filename: "portrait-contrast.cube",
             input: .linear, contentHash: "2ddec4a6a436d153"),
        Self(english: "Soft Cinema", filename: "soft-cinema.cube",
             input: .linear, contentHash: "1847d5560f929737"),
        Self(english: "Bleach Bypass", filename: "bleach-bypass.cube",
             input: .linear, contentHash: "0415a60d9947392e"),
        Self(english: "Vintage Negative", filename: "vintage-negative.cube",
             input: .linear, contentHash: "329c903aea19b331"),
        Self(english: "True Color", filename: "true-color.cube",
             input: .linear, contentHash: "8555ccd47f913064"),
        Self(english: "Street Negative", filename: "slide-to-street-negative.cube",
             input: .slide, contentHash: "c8d7b46bb781a968"),
        Self(english: "Bleach Bypass", filename: "slide-to-bleach-bypass.cube",
             input: .slide, contentHash: "8425966e8c1e892e"),
        Self(english: "Vintage Negative", filename: "slide-to-vintage-negative.cube",
             input: .slide, contentHash: "ba5f4f00eaa990d4"),
    ]
}
