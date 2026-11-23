import Foundation
import CoreGraphics

struct BookPhoto: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var sourceID: String? = nil
    var capturedAt: Date? = nil
    var filename: String
    var pixelWidth: Int
    var pixelHeight: Int
    var analysis: PhotoAnalysis? = nil
}

enum PageLayout: String, Codable, CaseIterable, Identifiable, Sendable {
    case gallery, text, mixed, fullPage, fullSpread
    var id: Self { self }
}

struct BookPage: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var layout: PageLayout = .gallery
    var photoIDs: [UUID] = []
    var text = ""
    /// Normalized alignment along the axis cropped by a full-bleed photo.
    var framing: Double? = nil
}

struct BookFormat: Codable, Hashable, Sendable {
    var widthMM: Double
    var heightMM: Double
    static let square = Self(widthMM: 210, heightMM: 210)
    static let landscape = Self(widthMM: 300, heightMM: 200)
    static let portrait = Self(widthMM: 200, heightMM: 300)
}

struct Book: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var title: String
    var format: BookFormat = .square
    var photos: [BookPhoto] = []
    var pages: [BookPage] = []
    var schemaVersion = 1

    func photo(_ id: UUID) -> BookPhoto? { photos.first { $0.id == id } }

    mutating func autoLayout() {
        let ordered = photos.enumerated().sorted { lhs, rhs in
            let left = lhs.element.capturedAt ?? .distantFuture
            let right = rhs.element.capturedAt ?? .distantFuture
            return left == right ? lhs.offset < rhs.offset : left < right
        }
        var result: [BookPage] = []
        var batch: [UUID] = []
        var previousDay: Date?
        let calendar = Calendar.current
        for entry in ordered {
            let day = entry.element.capturedAt.map { calendar.startOfDay(for: $0) }
            if !batch.isEmpty && (batch.count == 4 || day != previousDay) {
                result.append(BookPage(photoIDs: batch))
                batch.removeAll(keepingCapacity: true)
            }
            batch.append(entry.element.id)
            previousDay = day
        }
        if !batch.isEmpty { result.append(BookPage(photoIDs: batch)) }
        pages = result
    }
}

enum BookLayoutGeometry {
    static func rectangles(for ratios: [Double], in rect: CGRect, gap: Double) -> [CGRect] {
        guard !ratios.isEmpty, rect.width > 0, rect.height > 0 else { return [] }
        let aspects = ratios.map { $0.isFinite && $0 > 0 ? min(100, max(0.01, $0)) : 1 }
        let count = aspects.count
        let spacing = min(max(0, gap), min(rect.width, rect.height) / Double(count))
        let meanAspect = aspects.reduce(0, +) / Double(count)
        let idealRows = sqrt(Double(count) * meanAspect * rect.height / rect.width)
        let rows = Int(min(Double(count), max(1, idealRows.rounded())))
        var rowSizes: [(Range<Int>, Double)] = []
        var start = 0
        for row in 0..<rows {
            let length = count / rows + (row < count % rows ? 1 : 0)
            let range = start..<(start + length)
            let width = rect.width - spacing * Double(length - 1)
            rowSizes.append((range, width / aspects[range].reduce(0, +)))
            start += length
        }
        let height = rowSizes.reduce(0) { $0 + $1.1 }
        let gutters = spacing * Double(rows - 1)
        let scale = min(1, (rect.height - gutters) / height)
        var y = rect.midY - (height * scale + gutters) / 2
        var frames: [CGRect] = []
        for (range, naturalHeight) in rowSizes {
            let h = naturalHeight * scale
            let rowWidth = aspects[range].reduce(0, +) * h + Double(range.count - 1) * spacing
            var x = rect.midX - rowWidth / 2
            for aspect in aspects[range] {
                let width = aspect * h
                frames.append(CGRect(x: x, y: y, width: width, height: h))
                x += width + spacing
            }
            y += h + spacing
        }
        return frames
    }
}
