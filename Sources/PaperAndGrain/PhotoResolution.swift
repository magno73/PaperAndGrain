import CoreGraphics
import SwiftUI

/// The print resolution of a placed photo: its pixels over the size it is printed at, crop and zoom included.
/// The same measure drives the preflight warnings, the canvas badge and the Photo tab.
enum PhotoResolution {
    enum Level: Equatable {
        /// At or above the book's target.
        case good
        /// Below the target: may look soft on close inspection.
        case low
        /// Below two thirds of the target: likely visibly soft in print.
        case poor
    }

    /// Effective pixels per inch of a photo drawn in `frame`, which is in page points (1/72 inch).
    static func ppi(of photo: BookPhoto, in frame: CGRect, fills: Bool, crop: PhotoCrop) -> Double? {
        let pixels = CGSize(width: photo.pixelWidth, height: photo.pixelHeight)
        let drawn = crop.imageRect(for: pixels, in: frame, fills: fills)
        guard drawn.width > 0, drawn.width.isFinite else { return nil }
        return Double(pixels.width * 72 / drawn.width)
    }

    static func level(_ ppi: Double, target: Double) -> Level {
        guard target > 0, ppi.isFinite else { return .good }
        // Rounded like the preflight text, so "300 ppi" is never flagged against a 300 ppi target.
        let rounded = ppi.rounded()
        if rounded >= target.rounded() { return .good }
        return rounded < (target * 2 / 3).rounded() ? .poor : .low
    }
}

/// A small warning shown in the corner of a photo on the canvas when its print resolution is low.
struct ResolutionBadge: View {
    let ppi: Double
    let target: Double
    let level: PhotoResolution.Level
    let language: String

    var body: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(level == .poor ? Color(red: 0.78, green: 0.16, blue: 0.12) : Color(red: 0.86, green: 0.52, blue: 0.06),
                        in: Circle())
            .overlay { Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5) }
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            .help(message)
            .accessibilityElement()
            .accessibilityLabel(message)
    }

    var message: String {
        let actual = Int(ppi.rounded()), goal = Int(target.rounded())
        return language.hasPrefix("it")
            ? "Risoluzione bassa per la stampa: \(actual) ppi, obiettivo \(goal) ppi. Rimpicciolisci la foto o usa un originale più grande."
            : "Low print resolution: \(actual) ppi, target \(goal) ppi. Make the photo smaller or use a larger original."
    }
}

extension EditorView {
    var targetPPI: Double { book.printSettings?.targetPPI ?? PrintSettings().targetPPI }

    /// The badge for a placed photo, at the top-right corner of the part that is visible on the page.
    /// `frame` is in page points; `shown` and `bounds` are the same frame and the page on screen.
    @ViewBuilder func resolutionBadge(_ photo: BookPhoto, frame: CGRect, fills: Bool, crop: PhotoCrop,
                                      shown: CGRect, bounds: CGRect) -> some View {
        if let ppi = PhotoResolution.ppi(of: photo, in: frame, fills: fills, crop: crop) {
            let level = PhotoResolution.level(ppi, target: targetPPI)
            let visible = shown.intersection(bounds).offsetBy(dx: -shown.minX, dy: -shown.minY)
            if level != .good, !visible.isNull, visible.width > 40, visible.height > 40 {
                ResolutionBadge(ppi: ppi, target: targetPPI, level: level, language: language)
                    .position(x: visible.maxX - 17, y: visible.minY + 17)
            }
        }
    }

    /// Print resolution of the photo selected on the canvas, where it is placed.
    var selectedPhotoResolution: Double? {
        guard let selection = canvasPhotoSelection else { return nil }
        switch selection.surface {
        case let .canvasPage(pageID):
            guard let leaf = book.pages.first(where: { $0.id == pageID }),
                  let item = pageComposition(leaf).photos.first(where: { $0.id == selection.photoID }) else { return nil }
            return PhotoResolution.ppi(of: item.photo, in: item.frame, fills: item.fills, crop: item.crop)
        case let .cover(front):
            guard let photo = indexedPhoto(selection.photoID) else { return nil }
            let face = BookCoverGeometry(book: book, front: front)
            return PhotoResolution.ppi(of: photo, in: face.photoFrame, fills: face.fills, crop: face.photoCrop)
        default:
            return nil
        }
    }

    /// A line in the Photo tab: the print resolution where the photo is placed, flagged when low.
    @ViewBuilder var photoResolutionRow: some View {
        if let ppi = selectedPhotoResolution {
            let level = PhotoResolution.level(ppi, target: targetPPI)
            let value = "\(Int(ppi.rounded())) ppi"
            Label {
                Text(level == .good
                     ? tr("Stampa: \(value)", "Print: \(value)")
                     : tr("Stampa: \(value), sotto i \(Int(targetPPI.rounded())) ppi consigliati",
                          "Print: \(value), below the recommended \(Int(targetPPI.rounded())) ppi"))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: level == .good ? "checkmark.circle" : "exclamationmark.triangle.fill")
            }
            .font(.caption)
            .foregroundStyle(level == .good ? muted : (level == .poor ? Color(red: 0.78, green: 0.16, blue: 0.12)
                                                                       : Color(red: 0.80, green: 0.47, blue: 0.04)))
            .help(tr("Pixel della foto rispetto alla dimensione stampata, con il ritaglio.",
                     "The photo's pixels over its printed size, crop included."))
        }
    }
}
