import CoreGraphics
import Foundation

/// The pure geometry of a map page: projection, region, merging, clipping and label placement.
enum MapGeometry {
    /// Mercator stops here, so polar land does not grow without end.
    static let maximumLatitude = 80.0
    /// The narrowest span shown, in degrees of longitude, so one place still shows its surroundings.
    static let minimumSpan = 3.0
    /// Each side of the places' box gets this share of its span.
    static let padding = 0.15
    /// Places closer than this share of the map's diagonal are one place.
    static let mergeFraction = 0.02

    /// Mercator's y for a latitude, in degree units (equal to longitude degrees at the equator).
    static func mercatorY(_ latitude: Double) -> Double {
        let limited = min(maximumLatitude, max(-maximumLatitude, latitude)) * .pi / 180
        return log(tan(.pi / 4 + limited / 2)) * 180 / .pi
    }

    /// The part of the world a map shows, in projected units: x in degrees of longitude (it can pass 180
    /// for a trip across the 180° meridian), y in Mercator degrees, north up.
    struct Region: Equatable, Hashable, Sendable {
        var minX: Double, maxX: Double, minY: Double, maxY: Double
        /// Longitudes below this are shifted by +360, so the window is continuous across 180°.
        var wrapStart: Double?

        var width: Double { maxX - minX }
        var height: Double { maxY - minY }

        func x(_ longitude: Double) -> Double {
            if let wrapStart, longitude < wrapStart { return longitude + 360 }
            return longitude
        }

        /// A coordinate in `frame`, from its top left.
        func point(_ coordinate: MapCoordinate, in frame: CGRect) -> CGPoint {
            point(x: x(coordinate.longitude), y: mercatorY(coordinate.latitude), in: frame)
        }

        func point(x: Double, y: Double, in frame: CGRect) -> CGPoint {
            CGPoint(x: frame.minX + (x - minX) / width * frame.width,
                    y: frame.minY + (maxY - y) / height * frame.height)
        }
    }

    /// The smallest box around the places, padded, given a minimum span and the frame's proportions, then
    /// zoomed and moved by the author. A trip across the 180° meridian takes the narrower window.
    static func region(for coordinates: [MapCoordinate], aspect: Double, zoom: Double = 1,
                       offset: CGSize = .zero) -> Region? {
        guard !coordinates.isEmpty, aspect.isFinite, aspect > 0 else { return nil }
        let longitudes = Array(Set(coordinates.map(\.longitude))).sorted()
        // The largest gap between neighbouring longitudes, around the globe, is left out of the window.
        var start = longitudes[0], largest = longitudes[0] + 360 - longitudes[longitudes.count - 1]
        for index in longitudes.indices.dropLast() where longitudes[index + 1] - longitudes[index] > largest {
            largest = longitudes[index + 1] - longitudes[index]
            start = longitudes[index + 1]
        }
        let wrap: Double? = start == longitudes[0] ? nil : start
        func x(_ longitude: Double) -> Double { wrap.map { longitude < $0 ? longitude + 360 : longitude } ?? longitude }
        let xs = coordinates.map { x($0.longitude) }, ys = coordinates.map { mercatorY($0.latitude) }
        var minX = xs.min()!, maxX = xs.max()!, minY = ys.min()!, maxY = ys.max()!
        let padX = (maxX - minX) * padding, padY = (maxY - minY) * padding
        minX -= padX; maxX += padX; minY -= padY; maxY += padY
        func widen(_ low: inout Double, _ high: inout Double, to span: Double) {
            guard high - low < span else { return }
            let middle = (low + high) / 2
            low = middle - span / 2
            high = middle + span / 2
        }
        widen(&minX, &maxX, to: minimumSpan)
        widen(&minY, &maxY, to: minimumSpan)
        // The frame's proportions: widen the narrower side.
        if (maxX - minX) / (maxY - minY) < aspect {
            widen(&minX, &maxX, to: (maxY - minY) * aspect)
        } else {
            widen(&minY, &maxY, to: (maxX - minX) / aspect)
        }
        let scale = 1 / min(8, max(0.25, zoom.isFinite ? zoom : 1))
        let centerX = (minX + maxX) / 2 + Double(offset.width) * (maxX - minX)
        let centerY = (minY + maxY) / 2 - Double(offset.height) * (maxY - minY)
        let halfX = (maxX - minX) * scale / 2, halfY = (maxY - minY) * scale / 2
        return Region(minX: centerX - halfX, maxX: centerX + halfX, minY: centerY - halfY, maxY: centerY + halfY,
                      wrapStart: wrap)
    }

    /// Merges points closer than `threshold`, in order: each point joins the first place within reach of it,
    /// whose position stays where it was first seen. Returns, for each place, its point and its members.
    static func merge(_ points: [CGPoint], threshold: CGFloat) -> [(point: CGPoint, members: [Int])] {
        var places: [(point: CGPoint, members: [Int])] = []
        for (index, point) in points.enumerated() {
            if let near = places.firstIndex(where: { hypot($0.point.x - point.x, $0.point.y - point.y) < threshold }) {
                places[near].members.append(index)
            } else {
                places.append((point, [index]))
            }
        }
        return places
    }

    /// Sutherland–Hodgman: the part of a closed polygon inside `rect`.
    static func clip(polygon: [CGPoint], to rect: CGRect) -> [CGPoint] {
        var output = polygon
        let edges: [(CGPoint) -> Bool] = [{ $0.x >= rect.minX }, { $0.x <= rect.maxX }, { $0.y >= rect.minY }, { $0.y <= rect.maxY }]
        let crossings: [(CGPoint, CGPoint) -> CGPoint] = [
            { a, b in CGPoint(x: rect.minX, y: a.y + (b.y - a.y) * (rect.minX - a.x) / (b.x - a.x)) },
            { a, b in CGPoint(x: rect.maxX, y: a.y + (b.y - a.y) * (rect.maxX - a.x) / (b.x - a.x)) },
            { a, b in CGPoint(x: a.x + (b.x - a.x) * (rect.minY - a.y) / (b.y - a.y), y: rect.minY) },
            { a, b in CGPoint(x: a.x + (b.x - a.x) * (rect.maxY - a.y) / (b.y - a.y), y: rect.maxY) },
        ]
        for (inside, crossing) in zip(edges, crossings) {
            guard let last = output.last else { return [] }
            let input = output
            output = []
            var previous = last
            for point in input {
                if inside(point) {
                    if !inside(previous) { output.append(crossing(previous, point)) }
                    output.append(point)
                } else if inside(previous) {
                    output.append(crossing(previous, point))
                }
                previous = point
            }
        }
        return output
    }

    /// Liang–Barsky on each segment: the pieces of a line inside `rect`.
    static func clip(polyline: [CGPoint], to rect: CGRect) -> [[CGPoint]] {
        var pieces: [[CGPoint]] = []
        var current: [CGPoint] = []
        for (a, b) in zip(polyline, polyline.dropFirst()) {
            guard let (start, end) = clipSegment(a, b, to: rect) else {
                if current.count > 1 { pieces.append(current) }
                current = []
                continue
            }
            if current.last != start {
                if current.count > 1 { pieces.append(current) }
                current = [start]
            }
            current.append(end)
            if end != b {
                pieces.append(current)
                current = []
            }
        }
        if current.count > 1 { pieces.append(current) }
        return pieces
    }

    static func clipSegment(_ a: CGPoint, _ b: CGPoint, to rect: CGRect) -> (CGPoint, CGPoint)? {
        var low: CGFloat = 0, high: CGFloat = 1
        let dx = b.x - a.x, dy = b.y - a.y
        for (p, q) in [(-dx, a.x - rect.minX), (dx, rect.maxX - a.x), (-dy, a.y - rect.minY), (dy, rect.maxY - a.y)] {
            if p == 0 {
                if q < 0 { return nil }
            } else {
                let t = q / p
                if p < 0 { if t > high { return nil }; low = max(low, t) } else { if t < low { return nil }; high = min(high, t) }
            }
        }
        return (CGPoint(x: a.x + low * dx, y: a.y + low * dy), CGPoint(x: a.x + high * dx, y: a.y + high * dy))
    }

    /// Places labels beside their dots without overlapping each other or a dot: right, left, above, below,
    /// most important place first; a label that fits nowhere is dropped. Deterministic for equal input.
    static func placeLabels(dots: [CGPoint], sizes: [CGSize?], importance: [Int], frame: CGRect,
                            dotRadius: CGFloat, gap: CGFloat) -> [CGRect?] {
        let order = dots.indices.sorted { importance[$0] == importance[$1] ? $0 < $1 : importance[$0] > importance[$1] }
        let dotBoxes = dots.map { CGRect(x: $0.x - dotRadius, y: $0.y - dotRadius, width: 2 * dotRadius, height: 2 * dotRadius) }
        var placed = [CGRect?](repeating: nil, count: dots.count)
        var taken: [CGRect] = []
        for index in order {
            guard let size = sizes[index], size.width > 0 else { continue }
            let dot = dots[index]
            let candidates = [
                CGRect(x: dot.x + dotRadius + gap, y: dot.y - size.height / 2, width: size.width, height: size.height),
                CGRect(x: dot.x - dotRadius - gap - size.width, y: dot.y - size.height / 2, width: size.width, height: size.height),
                CGRect(x: dot.x - size.width / 2, y: dot.y - dotRadius - gap - size.height, width: size.width, height: size.height),
                CGRect(x: dot.x - size.width / 2, y: dot.y + dotRadius + gap, width: size.width, height: size.height),
            ]
            for candidate in candidates where frame.contains(candidate)
                && !taken.contains(where: { $0.intersects(candidate) })
                && !dotBoxes.contains(where: { $0.intersects(candidate) }) {
                placed[index] = candidate
                taken.append(candidate)
                break
            }
        }
        return placed
    }

    /// Great-circle distance in kilometres.
    static func distance(_ a: MapCoordinate, _ b: MapCoordinate) -> Double {
        let radians = Double.pi / 180
        let dLat = (b.latitude - a.latitude) * radians, dLon = (b.longitude - a.longitude) * radians
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(a.latitude * radians) * cos(b.latitude * radians) * sin(dLon / 2) * sin(dLon / 2)
        return 6371 * 2 * atan2(sqrt(h), sqrt(max(0, 1 - h)))
    }
}
