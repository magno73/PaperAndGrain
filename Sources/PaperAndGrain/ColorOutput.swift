@preconcurrency import ColorSync
import CryptoKit
import Foundation

/// The color the print PDFs are written in. `nil` or `srgb` is the 0.10 behavior; `cmyk` names an
/// ICC output profile copied into the book package, so the book carries what it prints with.
struct ColorOutput: Codable, Hashable, Sendable {
    enum Mode: String, Codable, Hashable, Sendable { case srgb, cmyk }

    var mode: Mode
    var profile: ICCProfileReference?

    static let srgb = ColorOutput(mode: .srgb, profile: nil)

    static func cmyk(_ profile: ICCProfileReference) -> ColorOutput { ColorOutput(mode: .cmyk, profile: profile) }
}

/// A CMYK output profile the book uses: a stable id of where it came from, the profile's own name, the
/// copy in the package's `profiles/` folder and the SHA-256 of that file.
struct ICCProfileReference: Codable, Hashable, Sendable {
    /// `bundled:<file>`, `eci:PSOcoated_v3`, `installed:<file>` or `file:<file>`.
    var id: String
    var name: String
    var filename: String
    var sha256: String
}

/// The output profile the PDF being written converts to. The exporter sets it for one export; every
/// color drawn on a page (`EditorialStyle.color`, `EditorialStyle.fillColor` and the photographs) reads it,
/// so text, captions, rules, fills and images all go through the same profile.
enum PrintColor {
    @TaskLocal static var converter: CMYKConverter?
    /// The printer asks for no live transparency: translucent panels are flattened into the photo beneath.
    @TaskLocal static var flattensTransparency = false

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cache = [String: CMYKConverter]()

    /// One converter per profile, kept for the session: building its table takes a few milliseconds.
    static func converter(for data: Data) throws -> CMYKConverter {
        let key = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let known = cache[key] { return known }
        let made = try CMYKConverter(profile: data)
        cache[key] = made
        return made
    }
}

extension PrintSettings {
    /// True when the print PDFs are written in CMYK.
    var writesCMYK: Bool { colorOutput?.mode == .cmyk }
}

extension BookStorage {
    enum ProfileError: LocalizedError, Equatable {
        case notCMYKOutput(String)
        case missing(String)
        case changed(String)

        var errorDescription: String? {
            let language = L10n.interfaceLanguage
            return switch self {
            case let .notCMYKOutput(name):
                L10n.format("%@ is not a CMYK output profile", language: language, [name])
            case let .missing(name):
                L10n.format("The color profile %@ is missing from the book", language: language, [name])
            case let .changed(name):
                L10n.format("The color profile %@ in the book has changed", language: language, [name])
            }
        }
    }

    static func profileURL(filename: String, in directory: URL) -> URL {
        directory.appendingPathComponent("profiles", isDirectory: true)
            .appendingPathComponent(validFilename(filename) ? filename : "_invalid_profile")
    }

    /// Checks an ICC file and copies it into the package, named after the file and its hash, like an
    /// imported LUT. The profile itself is never renamed inside or altered.
    static func importICCProfile(_ data: Data, named name: String, id: String, in directory: URL) throws -> ICCProfileReference {
        guard data.count <= 20_000_000, let info = ICCProfileInfo(data), info.isCMYKOutput else {
            throw ProfileError.notCMYKOutput(name)
        }
        let stem = (name as NSString).deletingPathExtension.replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "/", with: "_")
        let filename = "\(stem.prefix(72))-\(info.sha256.prefix(16)).icc"
        let destination = profileURL(filename: filename, in: directory)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: destination.path) {
            try data.write(to: destination, options: [.atomic])
        }
        return ICCProfileReference(id: id, name: info.name, filename: filename, sha256: info.sha256)
    }

    /// The converter for the book's CMYK profile, after checking that the copy is there and unchanged.
    static func converter(for reference: ICCProfileReference, in directory: URL) throws -> CMYKConverter {
        let url = profileURL(filename: reference.filename, in: directory)
        guard let data = try? Data(contentsOf: url) else { throw ProfileError.missing(reference.name) }
        guard let info = ICCProfileInfo(data), info.sha256 == reference.sha256 else { throw ProfileError.changed(reference.name) }
        guard info.isCMYKOutput else { throw ProfileError.notCMYKOutput(reference.name) }
        return try PrintColor.converter(for: data)
    }
}

/// Where CMYK profiles come from: the ones bundled with the app, PSO Coated v3 downloaded from ECI on
/// the author's request, and the CMYK output profiles installed on the Mac.
enum ICCProfileSources {
    /// A profile shipped in `Resources/ICCProfiles` with the SHA-256 it must have (decision D7).
    struct Bundled: Hashable, Sendable {
        let filename: String
        let sha256: String
        var id: String { "bundled:" + filename }
    }

    /// The bundled profiles. GRACoL2006_Coated1v2 and Coated_Fogra39L_VIGC_300 are to be added from the ICC
    /// registry with their hashes; until the files are in `Resources/ICCProfiles`, the list is empty.
    static let bundled: [Bundled] = []

    static func bundledURL(_ profile: Bundled) -> URL? {
        let candidates: [URL?] = [
            Bundle.main.bundleURL.pathExtension == "app"
                ? Bundle.main.resourceURL?.appendingPathComponent("ICCProfiles/" + profile.filename) : nil,
            Bundle.main.bundleURL.pathExtension == "app" ? nil
                : URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                    .deletingLastPathComponent().appendingPathComponent("Resources/ICCProfiles/" + profile.filename),
        ]
        return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// The bundled profile's bytes, only when they still have the hash fixed in the source.
    static func bundledData(_ profile: Bundled) -> Data? {
        guard let url = bundledURL(profile), let data = try? Data(contentsOf: url),
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == profile.sha256 else { return nil }
        return data
    }

    /// A CMYK output profile installed on the Mac (Library/ColorSync/Profiles and the like).
    struct Installed: Hashable, Sendable {
        let name: String
        let url: URL
    }

    static func installed() -> [Installed] {
        final class Found: @unchecked Sendable { var items = [Installed]() }
        let found = Found()
        _ = withUnsafeMutablePointer(to: &found.items) { pointer -> Bool in
            ColorSyncIterateInstalledProfiles({ info, context in
                guard let info = info as? [String: Any], let context else { return true }
                let items = context.assumingMemoryBound(to: [Installed].self)
                guard let url = info[kColorSyncProfileURL.takeUnretainedValue() as String] as? URL,
                      let data = try? Data(contentsOf: url), let profile = ICCProfileInfo(data), profile.isCMYKOutput
                else { return true }
                items.pointee.append(Installed(name: profile.name, url: url))
                return true
            }, nil, pointer, nil)
            return true
        }
        var seen = Set<String>()
        return found.items.filter { seen.insert($0.name).inserted }.sorted { $0.name < $1.name }
    }
}
