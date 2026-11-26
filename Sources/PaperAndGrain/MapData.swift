import Foundation
import os

/// A longitude and latitude in degrees.
struct MapCoordinate: Hashable, Sendable {
    var longitude: Double
    var latitude: Double
}

/// The bundled geography (decision D4): land, large lakes, country borders and populated places from
/// Natural Earth, written by `scripts/make-map-data.py`. Read once, off the main thread.
struct MapGeography: Sendable {
    struct Shape: Sendable {
        var points: [MapCoordinate]
        var minLongitude: Double, maxLongitude: Double, minLatitude: Double, maxLatitude: Double

        init(points: [MapCoordinate]) {
            self.points = points
            minLongitude = points.map(\.longitude).min() ?? 0
            maxLongitude = points.map(\.longitude).max() ?? 0
            minLatitude = points.map(\.latitude).min() ?? 0
            maxLatitude = points.map(\.latitude).max() ?? 0
        }
    }

    struct Border: Sendable {
        var shape: Shape
        /// Not an agreed international boundary in the data: drawn dashed.
        var disputed: Bool
    }

    struct Place: Sendable {
        var coordinate: MapCoordinate
        var population: Int
        var name: String
        var italianName: String
        var englishName: String

        func name(language: String) -> String {
            let localized = L10n.isItalian(language) ? italianName : englishName
            return localized.isEmpty ? name : localized
        }
    }

    var land: [Shape] = []
    var lakes: [Shape] = []
    var borders: [Border] = []
    var places: [Place] = []

    enum FormatError: Error { case notMapData, truncated, unsupportedVersion(Int) }

    /// Reads the compressed file described in `scripts/make-map-data.py`.
    static func decode(compressed: Data) throws -> MapGeography {
        let data: Data
        do { data = try (compressed as NSData).decompressed(using: .zlib) as Data } catch { throw FormatError.notMapData }
        var reader = Reader(bytes: [UInt8](data))
        guard try reader.bytes(5) == Array("PGMAP".utf8) else { throw FormatError.notMapData }
        let version = Int(try reader.byte())
        guard version == 1 else { throw FormatError.unsupportedVersion(version) }
        var geography = MapGeography()
        geography.land = try (0..<reader.count()).map { _ in Shape(points: try reader.line()) }
        geography.lakes = try (0..<reader.count()).map { _ in Shape(points: try reader.line()) }
        geography.borders = try (0..<reader.count()).map { _ in
            let flags = try reader.byte()
            return Border(shape: Shape(points: try reader.line()), disputed: flags & 1 != 0)
        }
        geography.places = try (0..<reader.count()).map { _ in
            let longitude = Double(try reader.int32()) / 10_000, latitude = Double(try reader.int32()) / 10_000
            let population = Int(try reader.uint32())
            return Place(coordinate: MapCoordinate(longitude: longitude, latitude: latitude), population: population,
                         name: try reader.string(), italianName: try reader.string(), englishName: try reader.string())
        }
        return geography
    }

    private struct Reader {
        let bytes: [UInt8]
        var offset = 0

        mutating func bytes(_ count: Int) throws -> [UInt8] {
            guard offset + count <= bytes.count else { throw FormatError.truncated }
            defer { offset += count }
            return Array(bytes[offset..<(offset + count)])
        }

        mutating func byte() throws -> UInt8 { try bytes(1)[0] }

        mutating func uint32() throws -> UInt32 {
            try bytes(4).enumerated().reduce(0) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) }
        }

        mutating func int32() throws -> Int32 { Int32(bitPattern: try uint32()) }

        mutating func count() throws -> Int {
            let value = Int(try uint32())
            guard value <= bytes.count else { throw FormatError.truncated }
            return value
        }

        mutating func varint() throws -> Int64 {
            var result: UInt64 = 0, shift: UInt64 = 0
            while true {
                let next = try byte()
                result |= UInt64(next & 0x7F) << shift
                if next & 0x80 == 0 { break }
                shift += 7
                guard shift < 64 else { throw FormatError.truncated }
            }
            return Int64(bitPattern: (result >> 1) ^ (0 &- (result & 1)))
        }

        mutating func line() throws -> [MapCoordinate] {
            let count = try self.count()
            guard count > 0 else { return [] }
            var x = Int64(try int32()), y = Int64(try int32())
            var points = [MapCoordinate(longitude: Double(x) / 10_000, latitude: Double(y) / 10_000)]
            points.reserveCapacity(count)
            for _ in 1..<count {
                x += try varint()
                y += try varint()
                points.append(MapCoordinate(longitude: Double(x) / 10_000, latitude: Double(y) / 10_000))
            }
            return points
        }

        mutating func string() throws -> String {
            let length = Int(try bytes(2).enumerated().reduce(0) { $0 | UInt16($1.element) << (8 * UInt16($1.offset)) })
            return String(decoding: try bytes(length), as: UTF8.self)
        }
    }
}

/// Loads the bundled map data once. The editor asks with `prepare()` and redraws when it returns; the
/// exporter, already off the main thread, uses `geography()`, which waits for the load.
final class MapDataStore: @unchecked Sendable {
    static let shared = MapDataStore(url: MapDataStore.bundledURL)

    /// `Resources/MapData/world.mapdata` in the app, or in the repository for `swift run` and `swift test`.
    static var bundledURL: URL? {
        let inApp = Bundle.main.bundleURL.pathExtension == "app"
        let folder = inApp
            ? Bundle.main.resourceURL?.appendingPathComponent("MapData", isDirectory: true)
            : URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().appendingPathComponent("Resources/MapData", isDirectory: true)
        return folder?.appendingPathComponent("world.mapdata")
    }

    private let url: URL?
    private let lock = NSLock()
    private var loaded: MapGeography?
    private var attempted = false

    init(url: URL?) { self.url = url }

    /// The geography if it is already in memory; never reads the file.
    var loadedGeography: MapGeography? {
        lock.lock()
        defer { lock.unlock() }
        return loaded
    }

    /// The geography, reading the file the first time. Nil when the data is missing or damaged.
    func geography() -> MapGeography? {
        lock.lock()
        defer { lock.unlock() }
        if attempted { return loaded }
        attempted = true
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        do {
            loaded = try MapGeography.decode(compressed: data)
        } catch {
            Logger(subsystem: "me.magno.paperandgrain", category: "map")
                .error("Map data unreadable: \(String(describing: error), privacy: .public)")
        }
        return loaded
    }

    /// True once a read was tried and found no usable data.
    var isUnavailable: Bool {
        lock.lock()
        defer { lock.unlock() }
        return attempted && loaded == nil
    }

    /// Reads the data off the main thread; true when geography is available.
    func prepare() async -> Bool {
        await Task.detached(priority: .utility) { self.geography() != nil }.value
    }
}
