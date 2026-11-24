import Foundation
import CoreGraphics

struct PhotoLocation: Codable, Hashable, Sendable {
    let name: String?
    let latitude: Double?
    let longitude: Double?

    init(name: String? = nil, latitude: Double? = nil, longitude: Double? = nil) {
        let label = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = label?.isEmpty == false ? label : nil
        if let latitude, let longitude, (-90...90).contains(latitude), (-180...180).contains(longitude) {
            self.latitude = latitude
            self.longitude = longitude
        } else {
            self.latitude = nil
            self.longitude = nil
        }
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(name: values.decodeIfPresent(String.self, forKey: .name),
                      latitude: values.decodeIfPresent(Double.self, forKey: .latitude),
                      longitude: values.decodeIfPresent(Double.self, forKey: .longitude))
    }

    var hasMetadata: Bool { name != nil || latitude != nil }
}

struct BookPhoto: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var sourceID: String? = nil
    var capturedAt: Date? = nil
    var filename: String
    var pixelWidth: Int
    var pixelHeight: Int
    var analysis: PhotoAnalysis? = nil
    var film: FilmSettings? = nil
    var adjustments: PhotoAdjustments? = nil
    var location: PhotoLocation? = nil
}

enum PageLayout: String, Codable, CaseIterable, Identifiable, Sendable {
    case gallery, text, mixed, fullPage, fullSpread
    var id: Self { self }
}

enum PageTextPlacement: String, Codable, Hashable, Sendable {
    case below, beside
}

struct BookPage: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var layout: PageLayout = .gallery
    var photoIDs: [UUID] = []
    var text = ""
    /// Normalized alignment along the axis cropped by a full-bleed photo.
    var framing: Double? = nil
    var textPlacement: PageTextPlacement? = nil
    var heading: String? = nil
    var photoPlacements: [UUID: PhotoPlacement]? = nil
    var textBoxes: [PageTextBox]? = nil
    var arrangement: PageArrangement? = nil
    var typography: EditorialTypography? = nil

    var titleFrame: PageRect? = nil
    var storyFrame: PageRect? = nil
    var storyBackdropFrames: [PageRect]? = nil

    mutating func freezeStoryBackdrop(_ backdrops: [CGRect], in bounds: CGRect) {
        guard storyBackdropFrames == nil, !bounds.isEmpty else { return }
        let visible = backdrops.filter { !$0.isEmpty }
        if !visible.isEmpty { storyBackdropFrames = visible.map { PageRect($0, in: bounds) } }
    }

    mutating func moveStoryGroup(by translation: CGSize, blocks: [PageComposition.TextBlock],
                                 backdrops: [CGRect], in bounds: CGRect) {
        guard hasStoryText, !bounds.isEmpty, translation.width.isFinite, translation.height.isFinite,
              translation != .zero else { return }
        let parts = blocks.filter { $0.role != .combined && !$0.frame.isEmpty }
        guard !parts.isEmpty else { return }
        let backgrounds = backdrops.filter { !$0.isEmpty }
        let extent = (parts.map(\.frame) + backgrounds).reduce(CGRect.null) { $0.union($1) }
        func limit(_ delta: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
            guard lower <= upper else { return 0 }
            return min(upper, max(lower, delta))
        }
        let dx = limit(translation.width, lower: bounds.minX - extent.minX, upper: bounds.maxX - extent.maxX)
        let dy = limit(translation.height, lower: bounds.minY - extent.minY, upper: bounds.maxY - extent.maxY)
        guard dx != 0 || dy != 0 else { return }
        func translated(_ frame: CGRect) -> PageRect { PageRect(frame.offsetBy(dx: dx, dy: dy), in: bounds) }
        for part in parts {
            switch part.role {
            case .title: titleFrame = translated(part.frame)
            case .body: storyFrame = translated(part.frame)
            case .combined: break
            }
        }
        if !backgrounds.isEmpty { storyBackdropFrames = backgrounds.map(translated) }
    }

    var effectiveLayout: PageLayout { arrangement?.layout ?? layout }
    var hasStoryText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !(heading ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
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
    var film: FilmSettings? = nil
    var printSettings: PrintSettings? = nil
    var cover: BookCover? = nil
    var template: BookTemplate? = nil
    var typography: EditorialTypography? = nil
    var showPageNumbers: Bool? = nil

    var editorialStyle: EditorialStyle { template?.style ?? .classic }

    func photo(_ id: UUID) -> BookPhoto? { photos.first { $0.id == id } }

    func effectiveFilm(for photo: BookPhoto) -> FilmSettings {
        photo.film ?? film ?? FilmSettings()
    }

    var contentInsetPoints: Double {
        let scale = 72.0 / 25.4
        let shortestSide = min(format.widthMM, format.heightMM) * scale
        let printInset = printSettings.map { $0.safeMM * scale } ?? min(30, shortestSide * 0.11)
        return max(printInset, shortestSide * editorialStyle.insetFraction)
    }

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
    static func mixedArea(in rect: CGRect, placement: PageTextPlacement?, spacing: Double) -> (photo: CGRect, text: CGRect) {
        if placement == .beside {
            let boundary = rect.minX + rect.width * 0.60
            let gap = min(spacing, rect.width * 0.12)
            return (CGRect(x: rect.minX, y: rect.minY, width: boundary - rect.minX, height: rect.height),
                    CGRect(x: boundary + gap, y: rect.minY, width: rect.maxX - boundary - gap, height: rect.height))
        }
        let boundary = rect.minY + rect.height * 0.57
        let gap = min(spacing, rect.height * 0.12)
        return (CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: boundary - rect.minY),
                CGRect(x: rect.minX, y: boundary + gap, width: rect.width, height: rect.maxY - boundary - gap))
    }

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
