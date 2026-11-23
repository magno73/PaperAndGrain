import Foundation

struct FujifilmFilmLook: Identifiable, Hashable, Sendable {
    enum Input: CaseIterable, Hashable, Sendable {
        case linear, provia
    }

    let name: String
    let filename: String
    let input: Input
    private let contentHash: String

    var id: String { filename }

    func url(in resourceDirectory: URL) -> URL {
        resourceDirectory.appendingPathComponent("FujifilmFilmLooks", isDirectory: true)
            .appendingPathComponent(filename)
    }

    /// Match the name and content fingerprint written by BookStorage.importLUT.
    /// A different LUT with the same upstream basename is still a custom look.
    static func importedLook(filename: String) -> Self? {
        all.first { look in
            let stem = (look.filename as NSString).deletingPathExtension.prefix(72)
            return filename == "\(stem)-\(look.contentHash).cube"
        }
    }

    static let all: [Self] = [
        Self(name: "Provia", filename: "provia_sRGB.cube", input: .linear, contentHash: "5aecd2df2999ee69"),
        Self(name: "Velvia", filename: "velvia_sRGB.cube", input: .linear, contentHash: "e576e9b9013d5e78"),
        Self(name: "Astia", filename: "astia_sRGB.cube", input: .linear, contentHash: "84d884693ca55668"),
        Self(name: "Classic Chrome", filename: "classic chrome_sRGB.cube", input: .linear, contentHash: "4568770fd3a89d0c"),
        Self(name: "Classic Neg", filename: "classic neg_sRGB.cube", input: .linear, contentHash: "de8b59d1017ceef2"),
        Self(name: "Pro Neg Std", filename: "pro neg std_sRGB.cube", input: .linear, contentHash: "9dbdd7208b2389c1"),
        Self(name: "Pro Neg Hi", filename: "pro neg hi_sRGB.cube", input: .linear, contentHash: "2ddec4a6a436d153"),
        Self(name: "Eterna", filename: "eterna_sRGB.cube", input: .linear, contentHash: "1847d5560f929737"),
        Self(name: "Bleach Bypass", filename: "bleach bypass_sRGB.cube", input: .linear, contentHash: "0415a60d9947392e"),
        Self(name: "Nostalgic Neg", filename: "nostalgic neg_sRGB.cube", input: .linear, contentHash: "329c903aea19b331"),
        Self(name: "Reala Ace", filename: "reala ace_sRGB.cube", input: .linear, contentHash: "8555ccd47f913064"),
        Self(name: "Classic Neg", filename: "Provia to Classic Neg sRGB.cube", input: .provia, contentHash: "c8d7b46bb781a968"),
        Self(name: "Bleach Bypass", filename: "Provia to Bleach Bypass sRGB.cube", input: .provia, contentHash: "8425966e8c1e892e"),
        Self(name: "Nostalgic Neg", filename: "Provia to Nostalgic Neg sRGB.cube", input: .provia, contentHash: "ba5f4f00eaa990d4")
    ]
}
