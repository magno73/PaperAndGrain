import Foundation

/// PSO Coated v3 (FOGRA51) from the European Color Initiative. Its licence does not allow shipping the
/// file, but each author may download it from ECI (decision D7). The app fetches ECI's official archive
/// only when the author clicks **Download PSO Coated v3 from ECI…**: this is the only network request the
/// app makes. The archive is streamed to disk with a size limit, nothing from it is run, and the profile
/// is checked against the SHA-256 fixed here before it is kept in Application Support.
enum ECIProfile {
    static let id = "eci:PSOcoated_v3"
    static let archiveURL = URL(string: "https://www.eci.org/lib/exe/pso-coated_v3.zip")!
    static let pageURL = URL(string: "https://www.eci.org/doku.php?id=en:downloads")!
    static let profileFilename = "PSOcoated_v3.icc"
    /// The description the profile carries, compared for equality.
    static let expectedName = "PSO Coated v3"
    /// The SHA-256 of `PSOcoated_v3.icc` in ECI's archive, read from a download on 26 November 2026
    /// (archive 1,783,124 bytes, profile 2,195,228 bytes).
    static let expectedSHA256: String? = "c30ad2c01e8f93135ec7682c535e0a81bc2d177c301e196376c5f5838b5c8e86"
    /// The archive is 1.7 MB and the profile 2.2 MB; anything much larger is not ECI's file.
    static let maximumArchiveBytes = 8_000_000
    static let maximumProfileBytes = 6_000_000

    enum Failure: LocalizedError, Equatable {
        case download
        case tooLarge
        case notInArchive
        case wrongProfile

        var errorDescription: String? {
            let language = L10n.interfaceLanguage
            return switch self {
            case .download:
                L10n.string("PSO Coated v3 could not be downloaded from eci.org.", language: language)
            case .tooLarge, .notInArchive, .wrongProfile:
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
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= maximumProfileBytes,
              let data = try? Data(contentsOf: url), (try? check(data)) != nil else { return nil }
        return data
    }

    /// A valid PSO Coated v3: a CMYK output profile whose description is exactly `expectedName` and whose
    /// SHA-256 is `expectedSHA256`. Without a pinned hash, an intact non-zero MD5 profile ID is required.
    static func check(_ data: Data, expectedName: String = expectedName, expectedSHA256: String? = expectedSHA256) throws {
        guard data.count <= maximumProfileBytes, let info = ICCProfileInfo(data), info.isCMYKOutput,
              info.name == expectedName else { throw Failure.wrongProfile }
        if let expectedSHA256 {
            guard info.sha256 == expectedSHA256 else { throw Failure.wrongProfile }
        } else {
            guard info.hasProfileID, info.idMatches else { throw Failure.wrongProfile }
        }
    }

    /// Streams `url` to `file`, stopping past `limit` bytes.
    static func download(_ url: URL, to file: URL, limit: Int) async throws {
        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.download }
        if response.expectedContentLength > Int64(limit) { throw Failure.tooLarge }
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        var buffer = Data()
        buffer.reserveCapacity(65_536)
        var total = 0
        for try await byte in bytes {
            buffer.append(byte)
            total += 1
            if total > limit { throw Failure.tooLarge }
            if buffer.count == 65_536 {
                try handle.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
            }
        }
        try handle.write(contentsOf: buffer)
    }

    /// Downloads the archive with `fetch` (which writes it to the file it is given), extracts it with the
    /// system's `ditto` into a temporary folder, takes the profile only if it is a regular file (no links),
    /// checks it and writes it to `destination`. A failure leaves nothing behind.
    static func install(to destination: URL = installedURL, expectedName: String = expectedName,
                        expectedSHA256: String? = expectedSHA256,
                        fetch: @Sendable (URL, URL) async throws -> Void = { url, file in
                            try await download(url, to: file, limit: maximumArchiveBytes)
                        }) async throws -> Data {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("pso-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: scratch) }
        let zip = scratch.appendingPathComponent("archive.zip")
        do {
            try await fetch(archiveURL, zip)
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.download
        }
        guard let size = try? zip.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= maximumArchiveBytes else {
            throw Failure.tooLarge
        }
        let extracted = scratch.appendingPathComponent("extracted", isDirectory: true)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, extracted.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else { throw Failure.notInArchive }
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        let entries = fm.enumerator(at: extracted, includingPropertiesForKeys: keys, options: [])?
            .compactMap { $0 as? URL } ?? []
        // Links of any kind in the archive are refused, not followed.
        guard !entries.contains(where: { (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true })
        else { throw Failure.notInArchive }
        guard let found = entries.first(where: {
                  $0.lastPathComponent == profileFilename && !$0.path.contains("__MACOSX")
              }),
              let values = try? found.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
              values.isSymbolicLink != true, (values.fileSize ?? .max) <= maximumProfileBytes,
              let data = try? Data(contentsOf: found) else { throw Failure.notInArchive }
        try check(data, expectedName: expectedName, expectedSHA256: expectedSHA256)
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: [.atomic])
        return data
    }
}
