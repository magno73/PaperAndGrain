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
    /// Tells one loaded copy from another, for caches of shapes clipped from it.
    var identity = UUID()

    enum FormatError: Error, Equatable {
        case notMapData, damaged, truncated, unsupportedVersion(Int), outOfRange
    }

    /// The file's frame: "PGMZ", the length and CRC-32 of the compressed stream that follows, so a damaged
    /// file is refused before it is read.
    static let fileMagic = Array("PGMZ".utf8)

    /// Reads the file described in `scripts/make-map-data.py`: the frame, then a raw DEFLATE stream.
    static func decode(file: Data) throws -> MapGeography {
        let bytes = [UInt8](file)
        guard bytes.count >= 12, Array(bytes[0..<4]) == fileMagic else { throw FormatError.notMapData }
        func uint32(_ offset: Int) -> UInt32 {
            (0..<4).reduce(0) { $0 | UInt32(bytes[offset + $1]) << (8 * UInt32($1)) }
        }
        let length = Int(uint32(4)), checksum = uint32(8)
        guard bytes.count - 12 == length else { throw FormatError.truncated }
        let stream = Data(bytes[12...])
        guard CRC32.checksum(stream) == checksum else { throw FormatError.damaged }
        let payload: Data
        do { payload = try (stream as NSData).decompressed(using: .zlib) as Data } catch { throw FormatError.damaged }
        return try decode(payload: payload)
    }

    /// Reads the uncompressed data. Every count, coordinate and length is checked, so damaged input throws.
    static func decode(payload: Data) throws -> MapGeography {
        var reader = Reader(bytes: [UInt8](payload))
        guard try reader.bytes(5) == Array("PGMAP".utf8) else { throw FormatError.notMapData }
        let version = Int(try reader.byte())
        guard version == 1 else { throw FormatError.unsupportedVersion(version) }
        var geography = MapGeography()
        geography.land = try (0..<reader.count(minimumBytes: 4)).map { _ in Shape(points: try reader.line()) }
        geography.lakes = try (0..<reader.count(minimumBytes: 4)).map { _ in Shape(points: try reader.line()) }
        geography.borders = try (0..<reader.count(minimumBytes: 5)).map { _ in
            let flags = try reader.byte()
            return Border(shape: Shape(points: try reader.line()), disputed: flags & 1 != 0)
        }
        geography.places = try (0..<reader.count(minimumBytes: 18)).map { _ in
            let longitude = Int64(try reader.int32()), latitude = Int64(try reader.int32())
            try Reader.check(longitude, latitude)
            let population = Int(try reader.uint32())
            return Place(coordinate: MapCoordinate(longitude: Double(longitude) / 10_000, latitude: Double(latitude) / 10_000),
                         population: population, name: try reader.string(), italianName: try reader.string(),
                         englishName: try reader.string())
        }
        guard reader.offset == reader.bytes.count else { throw FormatError.damaged }
        return geography
    }

    private struct Reader {
        let bytes: [UInt8]
        var offset = 0

        mutating func bytes(_ count: Int) throws -> [UInt8] {
            guard count >= 0, count <= bytes.count - offset else { throw FormatError.truncated }
            defer { offset += count }
            return Array(bytes[offset..<(offset + count)])
        }

        mutating func byte() throws -> UInt8 {
            guard offset < bytes.count else { throw FormatError.truncated }
            defer { offset += 1 }
            return bytes[offset]
        }

        mutating func uint32() throws -> UInt32 {
            try bytes(4).enumerated().reduce(0) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) }
        }

        mutating func int32() throws -> Int32 { Int32(bitPattern: try uint32()) }

        /// A count of items that each take at least `minimumBytes`: more than the rest of the data could hold
        /// is impossible.
        mutating func count(minimumBytes: Int) throws -> Int {
            let value = Int(try uint32())
            guard value <= (bytes.count - offset) / max(1, minimumBytes) else { throw FormatError.damaged }
            return value
        }

        mutating func varint() throws -> Int64 {
            var result: UInt64 = 0, shift: UInt64 = 0
            while true {
                let next = try byte()
                result |= UInt64(next & 0x7F) << shift
                if next & 0x80 == 0 { break }
                shift += 7
                guard shift < 64 else { throw FormatError.damaged }
            }
            return Int64(bitPattern: (result >> 1) ^ (0 &- (result & 1)))
        }

        /// Longitude and latitude in 1e-4 degree must be on the globe.
        static func check(_ x: Int64, _ y: Int64) throws {
            guard (-1_800_000...1_800_000).contains(x), (-900_000...900_000).contains(y) else { throw FormatError.outOfRange }
        }

        mutating func line() throws -> [MapCoordinate] {
            // The first point takes 8 bytes and each further one at least 2.
            let count = Int(try uint32())
            guard count == 0 || (count - 1) <= (bytes.count - offset - min(8, bytes.count - offset)) / 2 else {
                throw FormatError.damaged
            }
            guard count > 0 else { return [] }
            var x = Int64(try int32()), y = Int64(try int32())
            try Self.check(x, y)
            var points = [MapCoordinate(longitude: Double(x) / 10_000, latitude: Double(y) / 10_000)]
            points.reserveCapacity(count)
            for _ in 1..<count {
                let (nextX, overflowX) = x.addingReportingOverflow(try varint())
                let (nextY, overflowY) = y.addingReportingOverflow(try varint())
                guard !overflowX, !overflowY else { throw FormatError.outOfRange }
                try Self.check(nextX, nextY)
                (x, y) = (nextX, nextY)
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

/// CRC-32 as zlib computes it (polynomial 0xEDB88320), for the map data's frame.
enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { index in
        (0..<8).reduce(UInt32(index)) { crc, _ in crc & 1 == 1 ? 0xEDB8_8320 ^ (crc >> 1) : crc >> 1 }
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
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
    private let condition = NSCondition()
    private var loaded: MapGeography?
    private var attempted = false
    private var loading = false

    init(url: URL?) { self.url = url }

    /// The geography if it is already in memory; never reads the file and never waits for a read.
    var loadedGeography: MapGeography? {
        condition.lock()
        defer { condition.unlock() }
        return loaded
    }

    /// The geography, reading the file the first time. Nil when the data is missing or damaged. The file is
    /// read and decoded once, outside the lock; other callers wait for that read instead of repeating it.
    func geography() -> MapGeography? {
        condition.lock()
        while loading { condition.wait() }
        if attempted {
            defer { condition.unlock() }
            return loaded
        }
        loading = true
        condition.unlock()
        var result: MapGeography?
        if let url, let data = try? Data(contentsOf: url) {
            do {
                result = try MapGeography.decode(file: data)
            } catch {
                Logger(subsystem: "me.magno.paperandgrain", category: "map")
                    .error("Map data unreadable: \(String(describing: error), privacy: .public)")
            }
        }
        condition.lock()
        loaded = result
        attempted = true
        loading = false
        condition.broadcast()
        condition.unlock()
        return result
    }

    /// True once a read was tried and found no usable data.
    var isUnavailable: Bool {
        condition.lock()
        defer { condition.unlock() }
        return attempted && loaded == nil
    }

    /// Reads the data off the main thread; true when geography is available.
    func prepare() async -> Bool {
        await Task.detached(priority: .utility) { self.geography() != nil }.value
    }
}
