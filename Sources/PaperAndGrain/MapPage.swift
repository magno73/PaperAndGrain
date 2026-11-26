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
    /// Saved only: the template of the map page (`PageArrangement.map` when nil). In memory the page's
    /// arrangement says it; see `BookPage`'s coding.
    var layout: MapLayout? = nil
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

/// How a map page is laid out, as saved in the manifest.
enum MapLayout: String, Codable, Sendable {
    /// The map fills the page.
    case page
    /// The map sits above the story.
    case aboveText
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

/// A map page is saved with an arrangement 0.10 knows, `textOnly`, and is a map by its `map` field, which
/// 0.10 ignores. 0.10 can therefore decode a book with map pages, read `writerVersion` 2 and open it
/// read-only as a newer format, instead of failing on an unknown arrangement. Every other page is coded
/// exactly as the synthesized `Codable` would.
extension BookPage: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, layout, photoIDs, text, framing, textPlacement, heading, photoPlacements, textBoxes, arrangement
        case typography, layerOrder, titleFrame, storyFrame, storyBackdropFrames, map
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        id = try values.decode(UUID.self, forKey: .id)
        layout = try values.decode(PageLayout.self, forKey: .layout)
        photoIDs = try values.decode([UUID].self, forKey: .photoIDs)
        text = try values.decode(String.self, forKey: .text)
        framing = try values.decodeIfPresent(Double.self, forKey: .framing)
        textPlacement = try values.decodeIfPresent(PageTextPlacement.self, forKey: .textPlacement)
        heading = try values.decodeIfPresent(String.self, forKey: .heading)
        photoPlacements = try values.decodeIfPresent([UUID: PhotoPlacement].self, forKey: .photoPlacements)
        textBoxes = try values.decodeIfPresent([PageTextBox].self, forKey: .textBoxes)
        arrangement = try values.decodeIfPresent(PageArrangement.self, forKey: .arrangement)
        typography = try values.decodeIfPresent(EditorialTypography.self, forKey: .typography)
        layerOrder = try values.decodeIfPresent([PageLayer].self, forKey: .layerOrder)
        titleFrame = try values.decodeIfPresent(PageRect.self, forKey: .titleFrame)
        storyFrame = try values.decodeIfPresent(PageRect.self, forKey: .storyFrame)
        storyBackdropFrames = try values.decodeIfPresent([PageRect].self, forKey: .storyBackdropFrames)
        map = try values.decodeIfPresent(PageMap.self, forKey: .map)
        // A saved map page: text only with a map. The command line may also name the map templates directly.
        if var saved = map, arrangement == .textOnly || arrangement?.isMap == true {
            if arrangement == .textOnly { arrangement = saved.layout == .aboveText ? .mapAboveText : .map }
            saved.layout = nil
            // In memory a map page with default settings holds no map: the arrangement says it is one.
            map = saved == PageMap() ? nil : saved
            if let arrangement { layout = arrangement.layout }
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        var arrangement = self.arrangement
        var layout = self.layout
        var map = self.map
        if let current = arrangement, current.isMap {
            var saved = map ?? PageMap()
            saved.layout = current == .mapAboveText ? .aboveText : nil
            map = saved
            arrangement = .textOnly
            layout = PageArrangement.textOnly.layout
        }
        try values.encode(id, forKey: .id)
        try values.encode(layout, forKey: .layout)
        try values.encode(photoIDs, forKey: .photoIDs)
        try values.encode(text, forKey: .text)
        try values.encodeIfPresent(framing, forKey: .framing)
        try values.encodeIfPresent(textPlacement, forKey: .textPlacement)
        try values.encodeIfPresent(heading, forKey: .heading)
        try values.encodeIfPresent(photoPlacements, forKey: .photoPlacements)
        try values.encodeIfPresent(textBoxes, forKey: .textBoxes)
        try values.encodeIfPresent(arrangement, forKey: .arrangement)
        try values.encodeIfPresent(typography, forKey: .typography)
        try values.encodeIfPresent(layerOrder, forKey: .layerOrder)
        try values.encodeIfPresent(titleFrame, forKey: .titleFrame)
        try values.encodeIfPresent(storyFrame, forKey: .storyFrame)
        try values.encodeIfPresent(storyBackdropFrames, forKey: .storyBackdropFrames)
        try values.encodeIfPresent(map, forKey: .map)
    }
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

    /// The map of a page, reused while nothing it depends on changes: every surface composes the page,
    /// and names, labels and geography need not be worked out again for each.
    static func cached(page: BookPage, book: Book, frame: CGRect, fillsTrim: Bool,
                       language: String = L10n.interfaceLanguage, store: MapDataStore = .shared) -> MapComposition {
        let settings = page.map ?? PageMap()
        let located = locatedPhotos(book, settings: settings)
        let key = MapCompositionCache.Key(
            settings: settings, frame: [frame.minX, frame.minY, frame.width, frame.height], fillsTrim: fillsTrim,
            language: language, template: book.template, captions: book.captionStyle,
            located: located.map { MapCompositionCache.Located(id: $0.photo.id, coordinate: $0.coordinate, name: $0.photo.location?.name) },
            geography: store.loadedGeography != nil, store: ObjectIdentifier(store))
        return MapCompositionCache.shared.map(for: key) {
            MapComposition(page: page, book: book, frame: frame, fillsTrim: fillsTrim, language: language, store: store,
                           located: located)
        }
    }

    init(page: BookPage, book: Book, frame: CGRect, fillsTrim: Bool, language: String = L10n.interfaceLanguage,
         store: MapDataStore = .shared, located: [(photo: BookPhoto, coordinate: MapCoordinate)]? = nil) {
        self.frame = frame
        self.fillsTrim = fillsTrim
        let settings = page.map ?? PageMap()
        let located = located ?? Self.locatedPhotos(book, settings: settings)
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

/// Recent maps by everything they depend on.
final class MapCompositionCache: @unchecked Sendable {
    static let shared = MapCompositionCache()

    struct Located: Hashable {
        let id: UUID
        let coordinate: MapCoordinate
        let name: String?
    }

    struct Key: Hashable {
        let settings: PageMap
        let frame: [CGFloat]
        let fillsTrim: Bool
        let language: String
        let template: BookTemplate?
        let captions: EditorialTextStyle
        let located: [Located]
        let geography: Bool
        let store: ObjectIdentifier
    }

    private let lock = NSLock()
    private var entries: [Key: MapComposition] = [:]
    private var order: [Key] = []
    private let capacity = 16

    func map(for key: Key, make: () -> MapComposition) -> MapComposition {
        lock.lock()
        if let cached = entries[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let map = make()
        lock.lock()
        if entries[key] == nil { order.append(key) }
        entries[key] = map
        if order.count > capacity { entries.removeValue(forKey: order.removeFirst()) }
        lock.unlock()
        return map
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
            guard let label = place.label, let frame = place.labelFrame else { continue }
            // A halo of the land's tint keeps the name readable where the route or a border runs under it.
            let halo = NSMutableAttributedString(attributedString: label)
            let whole = NSRange(location: 0, length: halo.length)
            halo.addAttribute(NSAttributedString.Key(kCTStrokeColorAttributeName as String),
                              value: EditorialStyle.color(style.mapLand), range: whole)
            halo.addAttribute(NSAttributedString.Key(kCTStrokeWidthAttributeName as String), value: 24.0, range: whole)
            context.saveGState()
            context.setLineJoin(.round)
            EditorialTypesetter.draw(halo, in: frame, context: context)
            context.restoreGState()
            EditorialTypesetter.draw(label, in: frame, context: context)
        }
        context.restoreGState()
        if !map.fillsTrim {
            context.setStrokeColor(EditorialStyle.color(style.mapLine))
            context.setLineWidth(0.35)
            context.stroke(map.frame.insetBy(dx: 0.175, dy: 0.175))
        }
    }
}
