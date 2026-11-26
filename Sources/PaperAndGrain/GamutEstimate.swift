import CoreGraphics
import Foundation

/// How much of a finished photo the book's CMYK profile cannot print, for the Issues list. The estimate
/// renders a small copy of the photo with its adjustments and film look (`sampleSize` pixels on the long
/// side), runs it through the soft proof and counts the pixels whose color moves by more than
/// `CMYKConverter.gamutChromaLimit`. Results are cached by file, look, adjustments and profile, so a
/// later check, while typing for example, costs a dictionary lookup.
enum GamutEstimate {
    /// A photo warns when at least this share of it is outside the printer's range.
    static let warningShare = 0.10
    static let sampleSize = 160

    private struct Key: Hashable {
        let filename: String
        let film: FilmSettings
        let adjustments: PhotoAdjustments?
        let profile: String
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache = [Key: Double]()

    /// The share (0 to 1) of the photo outside the profile's gamut; nil when the file cannot be read.
    static func share(of photo: BookPhoto, book: Book, directory: URL, converter: CMYKConverter) -> Double? {
        let film = book.effectiveFilm(for: photo)
        let key = Key(filename: photo.filename, film: film, adjustments: photo.adjustments, profile: converter.info.sha256)
        lock.lock()
        let known = cache[key]
        lock.unlock()
        if let known { return known }
        let lut = film.lutFilename.map { BookStorage.lutURL(filename: $0, in: directory) }
        guard let image = FilmRenderer.image(from: BookStorage.assetURL(filename: photo.filename, in: directory),
                                             maxPixelSize: sampleSize, settings: film, lutURL: lut,
                                             adjustments: photo.adjustments) else { return nil }
        let share = converter.outOfGamutShare(image)
        lock.lock()
        cache[key] = share
        lock.unlock()
        return share
    }
}
