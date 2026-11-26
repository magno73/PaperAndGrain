import AppKit
import CoreGraphics
import CoreText
import Foundation

/// The settings of a map page (`BookPage.map`). Every field is optional; nil keeps the default.
struct PageMap: Codable, Hashable, Sendable {
    /// Which photos the map shows: those placed in the book (pages and cover) or the whole library.
    enum Photos: String, Codable, CaseIterable, Sendable {
        case placed, all
    }

    var photos: Photos? = nil
    var showsRoute: Bool? = nil
    var showsLabels: Bool? = nil
    var showsBorders: Bool? = nil
    /// 1 fits the places; larger zooms in, from 0.25 to 8.
    var zoom: Double? = nil
    /// Moves the centre by a share of the map's width and height (right and down are positive).
    var centerOffset: MapOffset? = nil
    /// Names the author changed or hid, by the place's rounded position.
    var labels: [MapLabel]? = nil

    static let zoomRange = 0.25...8.0

    var resolvedPhotos: Photos { photos ?? .placed }
    var route: Bool { showsRoute ?? true }
    var placeNames: Bool { showsLabels ?? true }
    var countryBorders: Bool { showsBorders ?? true }
    var resolvedZoom: Double { min(Self.zoomRange.upperBound, max(Self.zoomRange.lowerBound, zoom ?? 1)) }

    func label(_ key: String) -> MapLabel? { labels?.first { $0.key == key } }
}

struct MapOffset: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
}

/// An author's change to one place on the map: another name, or hidden.
struct MapLabel: Codable, Hashable, Sendable {
    /// The place's position rounded to 0.01° ("latitude,longitude"), so it survives small changes.
    var key: String
    var name: String? = nil
    var hidden: Bool? = nil

    static func key(for coordinate: MapCoordinate) -> String {
        String(format: "%.2f,%.2f", locale: Locale(identifier: "en_US_POSIX"), coordinate.latitude, coordinate.longitude)
    }
}

extension BookPage {
    var isMapPage: Bool { arrangement?.isMap == true }
}

/// A map laid out on a page, in the page's points. `PageComposition.map` holds it for every surface.
struct MapComposition {
    struct Place: Identifiable {
        var id: String { key }
        let key: String
        let coordinate: MapCoordinate
        let point: CGPoint
        /// Photos taken at this place: its importance for labels.
        let photoCount: Int
        /// The name before the author's changes: the photos' place name, or the nearest town within 50 km.
        let suggestedName: String?
        /// The name shown, or nil when there is none or the author hid it.
        let name: String?
        let label: NSAttributedString?
        let labelFrame: CGRect?
    }

    let frame: CGRect
    /// True when the map reaches the trim; otherwise it gets a hairline frame.
    let fillsTrim: Bool
    let geography: MapShapes?
    let route: [CGPoint]
    let places: [Place]
    /// No photo of the book has a location: the editor says so, the PDF draws nothing, Issues blocks.
    var isEmpty: Bool { places.isEmpty }
    /// The bundled geography could not be read; places and route still show.
    let missingGeography: Bool

    static let dotRadius: CGFloat = 2.4
    static let labelReachKM = 50.0

    /// The photos a map counts, with a location, in capture order (book order for equal or missing dates).
    static func locatedPhotos(_ book: Book, settings: PageMap) -> [(photo: BookPhoto, coordinate: MapCoordinate)] {
        var used = Set<UUID>()
        if settings.resolvedPhotos == .placed {
            for page in book.pages { used.formUnion(page.photoIDs) }
            if let cover = book.cover { used.formUnion([cover.frontPhotoID, cover.backPhotoID].compactMap { $0 }) }
        }
        let photos = book.photos.enumerated().filter { settings.resolvedPhotos == .all || used.contains($0.element.id) }
        return photos.sorted { lhs, rhs in
            let left = lhs.element.capturedAt ?? .distantFuture, right = rhs.element.capturedAt ?? .distantFuture
            return left == right ? lhs.offset < rhs.offset : left < right
        }.compactMap { entry in
            guard let latitude = entry.element.location?.latitude, let longitude = entry.element.location?.longitude
            else { return nil }
            return (entry.element, MapCoordinate(longitude: longitude, latitude: latitude))
        }
    }

    init(page: BookPage, book: Book, frame: CGRect, fillsTrim: Bool, language: String = L10n.interfaceLanguage,
         store: MapDataStore = .shared) {
        self.frame = frame
        self.fillsTrim = fillsTrim
        let settings = page.map ?? PageMap()
        let located = Self.locatedPhotos(book, settings: settings)
        let world = store.loadedGeography
        missingGeography = world == nil
        guard !located.isEmpty, frame.width > 1, frame.height > 1,
              let region = MapGeometry.region(for: located.map(\.coordinate), aspect: frame.width / frame.height,
                                              zoom: settings.resolvedZoom,
                                              offset: CGSize(width: settings.centerOffset?.x ?? 0,
                                                             height: settings.centerOffset?.y ?? 0)) else {
            geography = nil
            route = []
            places = []
            return
        }
        geography = world.map { MapShapeCache.shared.shapes(world: $0, region: region, frame: frame,
                                                            borders: settings.countryBorders, reach: fillsTrim ? 30 : 2) }
        let points = located.map { region.point($0.coordinate, in: frame) }
        let threshold = hypot(frame.width, frame.height) * MapGeometry.mergeFraction
        let merged = MapGeometry.merge(points, threshold: threshold)
        var visit = [Int](repeating: 0, count: points.count)
        for (place, entry) in merged.enumerated() { for member in entry.members { visit[member] = place } }
        var sequence: [Int] = []
        for place in visit where sequence.last != place { sequence.append(place) }
        route = settings.route && merged.count > 1 ? sequence.map { merged[$0].point } : []

        let style = book.editorialStyle
        var named: [(key: String, coordinate: MapCoordinate, point: CGPoint, count: Int, suggested: String?, name: String?)] = []
        for entry in merged {
            let coordinate = located[entry.members[0]].coordinate
            let key = MapLabel.key(for: coordinate)
            let suggested = Self.photoPlaceName(entry.members.map { located[$0].photo })
                ?? world.flatMap { Self.nearestTown(to: coordinate, in: $0, language: language) }
            let override = settings.label(key)
            let edited = override?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = override?.hidden == true ? nil : (edited?.isEmpty == false ? edited : suggested)
            named.append((key, coordinate, entry.point, entry.members.count, suggested, name))
        }
        let texts: [NSAttributedString?] = named.map { item in
            guard settings.placeNames, let name = item.name else { return nil }
            return style.captionTypography(name, override: book.captionStyle, overPhoto: false)
        }
        let sizes: [CGSize?] = texts.map { text in
            guard let text else { return nil }
            // One line, measured by Core Text as it will be drawn, so the frame always holds the name.
            let width = ceil(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(text), nil, nil, nil)) + 4
            return CGSize(width: width, height: EditorialTypesetter.requiredHeight(text, width: width))
        }
        let frames = MapGeometry.placeLabels(dots: named.map(\.point), sizes: sizes, importance: named.map(\.count),
                                             frame: frame.insetBy(dx: 2, dy: 2), dotRadius: Self.dotRadius, gap: 3)
        places = named.indices.map { index in
            let item = named[index]
            return Place(key: item.key, coordinate: item.coordinate, point: item.point, photoCount: item.count,
                         suggestedName: item.suggested, name: item.name,
                         label: frames[index] == nil ? nil : texts[index], labelFrame: frames[index])
        }
    }

    /// The place name most of the photos carry; the first one on a tie.
    static func photoPlaceName(_ photos: [BookPhoto]) -> String? {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for photo in photos {
            guard let name = photo.location?.name, !name.isEmpty else { continue }
            if counts[name] == nil { order.append(name) }
            counts[name, default: 0] += 1
        }
        var best: String?
        for name in order where (counts[name] ?? 0) > (best.flatMap { counts[$0] } ?? 0) { best = name }
        return best
    }

    /// The nearest populated place within 50 km, in `language`.
    static func nearestTown(to coordinate: MapCoordinate, in world: MapGeography, language: String) -> String? {
        var best: (distance: Double, place: MapGeography.Place)?
        for place in world.places
        where abs(place.coordinate.latitude - coordinate.latitude) < 1 {
            let distance = MapGeometry.distance(coordinate, place.coordinate)
            if distance <= labelReachKM, distance < best?.distance ?? .infinity { best = (distance, place) }
        }
        return best?.place.name(language: language)
    }
}

/// Land, lakes and borders clipped to one map's region, as paths in page points.
final class MapShapes: @unchecked Sendable {
    let land: CGPath
    let lakes: CGPath
    let borders: CGPath
    let disputed: CGPath

    init(land: CGPath, lakes: CGPath, borders: CGPath, disputed: CGPath) {
        self.land = land
        self.lakes = lakes
        self.borders = borders
        self.disputed = disputed
    }
}

/// Clipped geography by region and frame, so turning pages and redrawing do not clip the world again.
final class MapShapeCache: @unchecked Sendable {
    static let shared = MapShapeCache()
    private struct Key: Hashable {
        let region: MapGeometry.Region
        let frame: CGRect
        let borders: Bool
        let reach: CGFloat

        func hash(into hasher: inout Hasher) {
            hasher.combine(region)
            hasher.combine(frame.minX); hasher.combine(frame.minY); hasher.combine(frame.width); hasher.combine(frame.height)
            hasher.combine(borders)
            hasher.combine(reach)
        }
    }
    private let lock = NSLock()
    private var entries: [Key: MapShapes] = [:]
    private var order: [Key] = []
    private let capacity = 24

    /// `reach` is how far past the frame the geography goes: into the bleed for a map that reaches the trim.
    func shapes(world: MapGeography, region: MapGeometry.Region, frame: CGRect, borders: Bool, reach: CGFloat) -> MapShapes {
        let key = Key(region: region, frame: frame, borders: borders, reach: reach)
        lock.lock()
        if let cached = entries[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let shapes = Self.make(world: world, region: region, frame: frame, borders: borders, reach: reach)
        lock.lock()
        entries[key] = shapes
        order.append(key)
        if order.count > capacity { entries.removeValue(forKey: order.removeFirst()) }
        lock.unlock()
        return shapes
    }

    static func make(world: MapGeography, region: MapGeometry.Region, frame: CGRect, borders: Bool,
                     reach: CGFloat = 2) -> MapShapes {
        // A little outside the frame, so clipped edges never show; the drawing clips to its own area.
        let limit = frame.insetBy(dx: -reach, dy: -reach)
        func offsets(_ shape: MapGeography.Shape) -> [Double] {
            [-360.0, 0, 360].filter { shape.maxLongitude + $0 >= region.minX && shape.minLongitude + $0 <= region.maxX }
                .filter { _ in MapGeometry.mercatorY(shape.maxLatitude) >= region.minY && MapGeometry.mercatorY(shape.minLatitude) <= region.maxY }
        }
        func project(_ shape: MapGeography.Shape, _ offset: Double) -> [CGPoint] {
            shape.points.map { region.point(x: $0.longitude + offset, y: MapGeometry.mercatorY($0.latitude), in: frame) }
        }
        func polygons(_ shapes: [MapGeography.Shape]) -> CGPath {
            let path = CGMutablePath()
            for shape in shapes {
                for offset in offsets(shape) {
                    let clipped = MapGeometry.clip(polygon: project(shape, offset), to: limit)
                    guard clipped.count > 2 else { continue }
                    path.addLines(between: clipped)
                    path.closeSubpath()
                }
            }
            return path
        }
        let solid = CGMutablePath(), dashed = CGMutablePath()
        if borders {
            for border in world.borders {
                for offset in offsets(border.shape) {
                    for piece in MapGeometry.clip(polyline: project(border.shape, offset), to: limit) {
                        (border.disputed ? dashed : solid).addLines(between: piece)
                    }
                }
            }
        }
        return MapShapes(land: polygons(world.land), lakes: polygons(world.lakes), borders: solid, disputed: dashed)
    }
}

extension EditorialStyle {
    /// Land: the paper with a little of the ink, so it is a tint of the paper on light and dark templates.
    var mapLand: UInt32 { Self.mix(ink, paper, inkShare: 0.10) }
    /// Coast, lake shores and borders: the ink at reduced strength.
    var mapLine: UInt32 { Self.mix(ink, paper, inkShare: 0.42) }
    /// The route: the template's accent, or its ink when the accent is too close to the paper.
    var mapRoute: UInt32 { accent }
}

enum MapRenderer {
    /// Draws a map as paths and text into a top-left context in page points. The PDF, the canvas, the
    /// thumbnails and **Browse the Book** all use it.
    /// `bleed` extends a map that reaches the trim into the print bleed.
    static func draw(_ map: MapComposition, style: EditorialStyle, in context: CGContext, bleed: CGFloat = 0) {
        guard !map.isEmpty else { return }
        let area = map.fillsTrim ? map.frame.insetBy(dx: -min(bleed, 30), dy: -min(bleed, 30)) : map.frame
        context.saveGState()
        context.clip(to: area)
        context.setFillColor(EditorialStyle.color(style.paper))
        context.fill(area)
        if let shapes = map.geography {
            context.setLineJoin(.round)
            context.addPath(shapes.land)
            context.setFillColor(EditorialStyle.color(style.mapLand))
            context.fillPath(using: .evenOdd)
            context.addPath(shapes.lakes)
            context.setFillColor(EditorialStyle.color(style.paper))
            context.fillPath(using: .evenOdd)
            context.setStrokeColor(EditorialStyle.color(style.mapLine))
            context.setLineWidth(0.35)
            context.addPath(shapes.land)
            context.addPath(shapes.lakes)
            context.strokePath()
            context.setLineWidth(0.3)
            context.addPath(shapes.borders)
            context.strokePath()
            context.setLineDash(phase: 0, lengths: [1.6, 1.4])
            context.addPath(shapes.disputed)
            context.strokePath()
            context.setLineDash(phase: 0, lengths: [])
        }
        if map.route.count > 1 {
            context.setStrokeColor(EditorialStyle.color(style.mapRoute))
            context.setLineWidth(0.9)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.addLines(between: map.route)
            context.strokePath()
        }
        context.setFillColor(EditorialStyle.color(style.ink))
        for place in map.places {
            let r = MapComposition.dotRadius
            context.fillEllipse(in: CGRect(x: place.point.x - r, y: place.point.y - r, width: 2 * r, height: 2 * r))
        }
        for place in map.places {
            if let label = place.label, let frame = place.labelFrame {
                EditorialTypesetter.draw(label, in: frame, context: context)
            }
        }
        context.restoreGState()
        if !map.fillsTrim {
            context.setStrokeColor(EditorialStyle.color(style.mapLine))
            context.setLineWidth(0.35)
            context.stroke(map.frame.insetBy(dx: 0.175, dy: 0.175))
        }
    }
}
