import Foundation

/// PSO Coated v3 (FOGRA51) from the European Color Initiative. Its licence does not allow shipping the
/// file, but each author may download it from ECI (decision D7). The app fetches ECI's official archive
/// only when the author clicks **Download from ECI…**: this is the only network request the app makes.
/// Nothing from the archive is run; the profile is checked and kept in Application Support.
enum ECIProfile {
    static let id = "eci:PSOcoated_v3"
    static let archiveURL = URL(string: "https://www.eci.org/lib/exe/pso-coated_v3.zip")!
    static let pageURL = URL(string: "https://www.eci.org/doku.php?id=en:downloads")!
    static let profileFilename = "PSOcoated_v3.icc"
    /// The description the profile must carry.
    static let expectedName = "PSO Coated v3"
    /// The SHA-256 of ECI's file, fixed here once it has been read from a download the author approved.
    /// Until then the check relies on the profile's own MD5 profile ID, its class and its description.
    static let expectedSHA256: String? = nil

    enum Failure: LocalizedError, Equatable {
        case download
        case notInArchive
        case wrongProfile

        var errorDescription: String? {
            let language = L10n.interfaceLanguage
            return switch self {
            case .download:
                L10n.string("PSO Coated v3 could not be downloaded from eci.org.", language: language)
            case .notInArchive, .wrongProfile:
                L10n.string("The file from eci.org is not the expected PSO Coated v3 profile.", language: language)
            }
        }
    }

    /// `~/Library/Application Support/PaperAndGrain/Profiles`.
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PaperAndGrain/Profiles", isDirectory: true)
    }

    static var installedURL: URL { directory.appendingPathComponent(profileFilename) }

    /// The installed profile's bytes, if it is there and still passes the check.
    static func installedData(at url: URL = installedURL) -> Data? {
        guard let data = try? Data(contentsOf: url), (try? check(data)) != nil else { return nil }
        return data
    }

    /// A valid PSO Coated v3: a CMYK output profile with that description, an intact profile ID and,
    /// once known, ECI's hash.
    static func check(_ data: Data, expectedName: String = expectedName, expectedSHA256: String? = expectedSHA256) throws {
        guard let info = ICCProfileInfo(data), info.isCMYKOutput, info.idMatches,
              info.name.localizedCaseInsensitiveContains(expectedName),
              expectedSHA256.map({ $0 == info.sha256 }) ?? true else { throw Failure.wrongProfile }
    }

    /// Downloads the archive with `fetch`, extracts it with the system's `ditto` into a temporary folder,
    /// checks the profile and moves it to `destination`. A failure leaves nothing behind.
    static func install(to destination: URL = installedURL, expectedName: String = expectedName,
                        expectedSHA256: String? = expectedSHA256,
                        fetch: @Sendable (URL) async throws -> Data = { url in
                            let (data, response) = try await URLSession.shared.data(from: url)
                            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.download }
                            return data
                        }) async throws -> Data {
        let archive: Data
        do { archive = try await fetch(archiveURL) } catch { throw Failure.download }
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("pso-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: scratch) }
        let zip = scratch.appendingPathComponent("archive.zip")
        try archive.write(to: zip)
        let extracted = scratch.appendingPathComponent("extracted", isDirectory: true)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, extracted.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else { throw Failure.notInArchive }
        let found = fm.enumerator(at: extracted, includingPropertiesForKeys: [.isRegularFileKey])?
            .compactMap { $0 as? URL }
            .first { $0.lastPathComponent.caseInsensitiveCompare(profileFilename) == .orderedSame && !$0.path.contains("__MACOSX") }
        guard let found, let data = try? Data(contentsOf: found) else { throw Failure.notInArchive }
        try check(data, expectedName: expectedName, expectedSHA256: expectedSHA256)
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: [.atomic])
        return data
    }
}
