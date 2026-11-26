import Foundation
import UniformTypeIdentifiers

/// Repairs a book whose photo files are gone from the package. The pure parts live here (which photos
/// are missing, matching files by name, the photo's new values); copying and validating the new file
/// goes through the existing import path (`DroppedPhotos`, `LocalImages`).
enum PhotoRelink {
    /// What a relink did, for the message the author reads.
    struct Report: Equatable, Sendable {
        var relinked = 0
        /// Names of photos that could not be relinked: no match, or an unreadable file.
        var failed: [String] = []
        /// Names of relinked photos whose proportions changed by more than 1 %, so their crops may have shifted.
        var proportionsChanged: [String] = []
    }

    /// Photos whose file is not in the package.
    static func missing(in photos: [BookPhoto], directory: URL) -> [BookPhoto] {
        let files = FileManager.default
        return photos.filter { !files.fileExists(atPath: BookStorage.assetURL(filename: $0.filename, in: directory).path) }
    }

    /// Names a file can be matched by: the whole name, and the name without its extension when the extension
    /// is an image type (so `Namibia.2024.dune` does not become `Namibia.2024`). Lowercased.
    static func keys(_ name: String) -> Set<String> {
        let lowered = name.lowercased()
        let ext = (lowered as NSString).pathExtension
        guard !ext.isEmpty, UTType(filenameExtension: ext)?.conforms(to: .image) == true else { return [lowered] }
        return [lowered, (lowered as NSString).deletingPathExtension]
    }

    /// The outcome of matching missing photos to the files of a folder.
    struct Matching {
        var matches: [UUID: URL] = [:]
        /// Photos no file has the name of.
        var unmatched: [BookPhoto] = []
        /// Photos several files have the name of, which neither pixel size nor capture date could tell apart.
        var ambiguous: [BookPhoto] = []
    }

    /// Matches each missing photo to a file of `files` by its original name, ignoring case and extension.
    /// A full-name match beats a name-without-extension match. When several files still fit (the same name in
    /// two subfolders), the one with the photo's pixel size is taken if exactly one has it, otherwise the one
    /// with its capture date; if that does not pick exactly one the photo is reported as ambiguous.
    /// `summary` reads a file's size and date, and is only called for ambiguous names.
    static func match(missing: [BookPhoto], files: [URL],
                      summary: (URL) -> (width: Int, height: Int, date: Date?)? = { LocalImages.summary(at: $0) }) -> Matching {
        let sorted = files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        var result = Matching()
        for photo in missing {
            let wanted = keys(photo.name)
            let candidates = sorted.filter { !wanted.isDisjoint(with: keys($0.lastPathComponent)) }
            let exact = candidates.filter { $0.lastPathComponent.lowercased() == photo.name.lowercased() }
            let pool = exact.isEmpty ? candidates : exact
            switch pool.count {
            case 0: result.unmatched.append(photo)
            case 1: result.matches[photo.id] = pool[0]
            default:
                let read = pool.map { ($0, summary($0)) }
                let sameSize = read.filter { $0.1?.width == photo.pixelWidth && $0.1?.height == photo.pixelHeight }
                let sameDate = read.filter { entry in
                    guard let wantedDate = photo.capturedAt, let date = entry.1?.date else { return false }
                    return date == wantedDate
                }
                if sameSize.count == 1 { result.matches[photo.id] = sameSize[0].0 }
                else if sameDate.count == 1 { result.matches[photo.id] = sameDate[0].0 }
                else { result.ambiguous.append(photo) }
            }
        }
        return result
    }

    /// The image files in a folder and its subfolders, hidden files left out.
    static func imageFiles(in folder: URL) -> [URL] {
        guard let walker = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: [.contentTypeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var found: [URL] = []
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: [.contentTypeKey, .isRegularFileKey])
            if values?.isRegularFile == true, values?.contentType?.conforms(to: .image) == true { found.append(url) }
        }
        return found
    }

    /// True when the new image's proportions differ from the old by more than 1 %.
    static func proportionsDiffer(_ old: BookPhoto, _ new: BookPhoto) -> Bool {
        let before = Double(old.pixelWidth) / Double(max(1, old.pixelHeight))
        let after = Double(new.pixelWidth) / Double(max(1, new.pixelHeight))
        return abs(after - before) / max(before, 0.000_001) > 0.01
    }

    /// The photo after a relink: the same id, name, date, film and adjustments (so every placement, crop and
    /// look stays), pointing at the new file with its pixel size. The analysis is cleared so the photo is
    /// analysed again. A place the book does not know yet is taken from the new file.
    static func relinked(_ old: BookPhoto, with new: BookPhoto) -> BookPhoto {
        var photo = old
        photo.filename = new.filename
        photo.pixelWidth = new.pixelWidth
        photo.pixelHeight = new.pixelHeight
        photo.analysis = nil
        photo.capturedAt = old.capturedAt ?? new.capturedAt
        photo.location = old.location ?? new.location
        return photo
    }
}
