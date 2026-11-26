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

    /// The converter already built for a profile's SHA-256, for the editor's soft proof.
    static func cachedConverter(sha256: String) -> CMYKConverter? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cache[sha256]
    }

    /// One converter per profile, kept for the session: building its table takes a few milliseconds.
    static func converter(for data: Data, sha256: String? = nil) throws -> CMYKConverter {
        let key = sha256 ?? SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
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

    /// Checks an ICC file and names its copy in the package after the file and its hash, like an imported
    /// LUT, without writing anything. The profile itself is never renamed inside or altered.
    static func iccProfileReference(_ data: Data, named name: String, id: String) throws -> ICCProfileReference {
        guard data.count <= 20_000_000, let info = ICCProfileInfo(data), info.isCMYKOutput else {
            throw ProfileError.notCMYKOutput(name)
        }
        let stem = (name as NSString).deletingPathExtension.replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "/", with: "_")
        return ICCProfileReference(id: id, name: info.name, filename: "\(stem.prefix(72))-\(info.sha256.prefix(16)).icc",
                                   sha256: info.sha256)
    }

    /// Writes the profile's copy into the package's `profiles/` folder, if it is not there yet.
    static func installICCProfile(_ data: Data, as reference: ICCProfileReference, in directory: URL) throws {
        let destination = profileURL(filename: reference.filename, in: directory)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: destination.path) {
            try data.write(to: destination, options: [.atomic])
        }
    }

    /// Checks an ICC file and copies it into the package (the command line and tests; **Book & Print**
    /// copies only on Apply).
    static func importICCProfile(_ data: Data, named name: String, id: String, in directory: URL) throws -> ICCProfileReference {
        let reference = try iccProfileReference(data, named: name, id: id)
        try installICCProfile(data, as: reference, in: directory)
        return reference
    }

    private struct CheckedFile: Hashable {
        let path: String
        let size: Int
        let modified: Date
        let sha256: String
    }

    private static let checkedLock = NSLock()
    nonisolated(unsafe) private static var checked = Set<CheckedFile>()

    /// The converter for the book's CMYK profile, after checking that the copy is there and unchanged. A file
    /// already checked with the same size and date is not hashed again.
    static func converter(for reference: ICCProfileReference, in directory: URL) throws -> CMYKConverter {
        let url = profileURL(filename: reference.filename, in: directory)
        if let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
           let size = values.fileSize, let modified = values.contentModificationDate,
           let converter = PrintColor.cachedConverter(sha256: reference.sha256) {
            let file = CheckedFile(path: url.path, size: size, modified: modified, sha256: reference.sha256)
            checkedLock.lock()
            let known = checked.contains(file)
            checkedLock.unlock()
            if known { return converter }
        }
        let converter = try loadConverter(for: reference, at: url)
        if let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
           let size = values.fileSize, let modified = values.contentModificationDate {
            checkedLock.lock()
            checked.insert(CheckedFile(path: url.path, size: size, modified: modified, sha256: reference.sha256))
            checkedLock.unlock()
        }
        return converter
    }

    private static func loadConverter(for reference: ICCProfileReference, at url: URL) throws -> CMYKConverter {
        guard let data = try? Data(contentsOf: url) else { throw ProfileError.missing(reference.name) }
        guard let info = ICCProfileInfo(data), info.sha256 == reference.sha256 else { throw ProfileError.changed(reference.name) }
        guard info.isCMYKOutput else { throw ProfileError.notCMYKOutput(reference.name) }
        return try PrintColor.converter(for: data, sha256: info.sha256)
    }
}

/// A profile chosen in **Book & Print** that is copied into the package only when the author applies.
struct PendingICCProfile: Hashable, Sendable {
    let data: Data
    let reference: ICCProfileReference
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

    /// The bundled profiles, from the ICC registry (terms and sources in `Resources/ICCProfiles/CREDITS.md`).
    static let bundled: [Bundled] = [
        Bundled(filename: "GRACoL2006_Coated1v2.icc",
                sha256: "7f822b354f3f4081e3b1dadd381c9f16d583257d1574e583be7d0e3433a6b45b"),
        Bundled(filename: "Coated_Fogra39L_VIGC_300.icc",
                sha256: "6df43849a84d2632e7900a125f657bd09364ed56775bc4740c1e39a5492d47e3"),
    ]

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

    /// Where the profile a printer names can be had: bundled, installed on the Mac, or downloadable.
    enum Candidate: Hashable, Sendable {
        case bundled(Bundled)
        case installed(Installed)
        /// PSO Coated v3, installed or downloadable from ECI.
        case eci
    }

    /// The press condition a profile name refers to, so "FOGRA39", "Coated FOGRA39 (ISO 12647-2:2004)" and
    /// "Coated_Fogra39L_VIGC_300.icc" are one family.
    static func family(_ name: String) -> String? {
        let text = name.lowercased().filter { $0.isLetter || $0.isNumber }
        for (key, family) in [("gracol2006", "gracol2006"), ("gracol", "gracol2006"), ("fogra39", "fogra39"),
                              ("isocoatedv2", "fogra39"), ("fogra51", "fogra51"), ("psocoatedv3", "fogra51"),
                              ("swop2006", "swop2006")] where text.contains(key) {
            return family
        }
        return nil
    }

    /// The best available profile for the one a printer names: a bundled one first, then PSO Coated v3,
    /// then one installed on the Mac. Nil when the name is unknown or nothing matches.
    static func candidate(for printerProfile: String, installed: [Installed]) -> Candidate? {
        guard let wanted = family(printerProfile) else { return nil }
        if let profile = bundled.first(where: { bundled in
            bundledData(bundled).flatMap(ICCProfileInfo.init).map { family($0.name) == wanted } ?? false
        }) {
            return .bundled(profile)
        }
        if wanted == "fogra51" { return .eci }
        return installed.first { family($0.name) == wanted }.map { .installed($0) }
    }

    static func installed() -> [Installed] {
        final class Found: @unchecked Sendable { var items = [Installed]() }
        let found = Found()
        _ = withUnsafeMutablePointer(to: &found.items) { pointer -> Bool in
            ColorSyncIterateInstalledProfilesWithOptions({ info, context in
                guard let info = info as? [String: Any], let context else { return true }
                let items = context.assumingMemoryBound(to: [Installed].self)
                guard let url = info[kColorSyncProfileURL.takeUnretainedValue() as String] as? URL,
                      let data = try? Data(contentsOf: url), let profile = ICCProfileInfo(data), profile.isCMYKOutput
                else { return true }
                items.pointee.append(Installed(name: profile.name, url: url))
                return true
            }, nil, pointer, [kColorSyncWaitForCacheReply.takeUnretainedValue() as String: true] as CFDictionary, nil)
            return true
        }
        var seen = Set<String>()
        return found.items.filter { seen.insert($0.name).inserted }.sorted { $0.name < $1.name }
    }
}
