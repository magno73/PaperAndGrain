import AppKit
import CoreLocation
import Foundation
import ImageIO
import Photos
import UniformTypeIdentifiers

struct Album: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let count: Int
    /// Recents or Favorites: a new book from it starts with a generic title.
    var isSmart = false
}

struct LibraryPhoto: Identifiable, Hashable, Sendable {
    let id: String
    let capturedAt: Date?
    let width: Int
    let height: Int
}

/// Kept for the command line; the app reports `AppError.imageUnavailable` with the file name.
enum PhotoImportError: LocalizedError {
    case unreadableImage

    var errorDescription: String? { AppError.imageUnavailable(name: nil).errorDescription }
}

enum PhotoLibrary {
    static func authorize() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    static func albums() -> [Album] {
        var result: [Album] = []
        let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        collections.enumerateObjects { collection, _, _ in
            let count = PHAsset.fetchAssets(in: collection, options: imageOptions()).count
            result.append(Album(id: collection.localIdentifier, title: collection.localizedTitle ?? "Album", count: count))
        }
        return result.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Albums offered when a book starts from Photos: Recents and Favorites, then the author's albums.
    /// Runs the PhotoKit fetches off the main thread.
    static func pickerAlbums(language: String) async -> [Album] {
        await Task.detached(priority: .userInitiated) {
            let smart: [(PHAssetCollectionSubtype, String)] = [
                (.smartAlbumUserLibrary, language == "it" ? "Recenti" : "Recents"),
                (.smartAlbumFavorites, language == "it" ? "Preferiti" : "Favorites"),
            ]
            var result: [Album] = []
            for (subtype, title) in smart {
                PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: subtype, options: nil)
                    .enumerateObjects { collection, _, stop in
                        let count = PHAsset.fetchAssets(in: collection, options: imageOptions()).count
                        result.append(Album(id: collection.localIdentifier, title: title, count: count, isSmart: true))
                        stop.pointee = true
                    }
            }
            return result + albums()
        }.value
    }

    static func loadPhotos(in album: Album) async -> [LibraryPhoto] {
        await Task.detached(priority: .userInitiated) { photos(in: album) }.value
    }

    static func photos(in album: Album) -> [LibraryPhoto] {
        guard let collection = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [album.id], options: nil
        ).firstObject else { return [] }
        let options = imageOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let assets = PHAsset.fetchAssets(in: collection, options: options)
        var result: [LibraryPhoto] = []
        assets.enumerateObjects { asset, _, _ in
            result.append(LibraryPhoto(id: asset.localIdentifier, capturedAt: asset.creationDate,
                                       width: asset.pixelWidth, height: asset.pixelHeight))
        }
        return result
    }

    static func locations(for sourceIDs: [String]) -> [String: PhotoLocation] {
        guard !sourceIDs.isEmpty else { return [:] }
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return [:] }
        var locations: [String: PhotoLocation] = [:]
        PHAsset.fetchAssets(withLocalIdentifiers: sourceIDs, options: nil).enumerateObjects { asset, _, _ in
            if let coordinate = asset.location?.coordinate, CLLocationCoordinate2DIsValid(coordinate) {
                locations[asset.localIdentifier] = PhotoLocation(latitude: coordinate.latitude,
                                                                longitude: coordinate.longitude)
            }
        }
        return locations
    }

    private static func imageOptions() -> PHFetchOptions {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        return options
    }

    static func thumbnail(_ photo: LibraryPhoto) async -> NSImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [photo.id], options: nil).firstObject else {
            return nil
        }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        let request = PhotoRequest<NSImage?>()
        return try? await request.value { complete in
            PHImageManager.default().requestImage(
                for: asset, targetSize: CGSize(width: 240, height: 240),
                contentMode: .aspectFit, options: options
            ) { image, details in
                if details?[PHImageResultIsDegradedKey] as? Bool != true {
                    complete(.success(image))
                }
            }
        }
    }

    static func importPhoto(_ photo: LibraryPhoto, into directory: URL) async throws -> BookPhoto {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [photo.id], options: nil).firstObject else {
            throw AppError.imageUnavailable(name: nil)
        }
        let options = PHImageRequestOptions()
        options.version = .current
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        let request = PhotoRequest<(Data, String?)>()
        let (data, type) = try await request.value { complete in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, type, _, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    complete(.failure(error))
                } else if info?[PHImageResultIsDegradedKey] as? Bool != true {
                    complete(data.map { .success(($0, type)) } ?? .failure(AppError.imageUnavailable(name: nil)))
                }
            }
        }
        try Task.checkCancellation()
        let originalName = PHAssetResource.assetResources(for: asset).first?.originalFilename
        var imported = try LocalImages.store(
            data, preferredExtension: type.flatMap { UTType($0)?.preferredFilenameExtension },
            name: originalName ?? "Foto", sourceID: photo.id, date: photo.capturedAt, in: directory
        )
        if let coordinate = asset.location?.coordinate, CLLocationCoordinate2DIsValid(coordinate) {
            imported.location = PhotoLocation(name: imported.location?.name, latitude: coordinate.latitude,
                                              longitude: coordinate.longitude)
        }
        return imported
    }
}

private final class PhotoRequest<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var requestID: PHImageRequestID?
    private var cancelled = false

    func value(start: (@escaping (sending Result<Value, Error>) -> Void) -> PHImageRequestID) async throws -> Value {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if cancelled {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation
                lock.unlock()
                let id = start { result in self.finish(result) }
                lock.lock()
                requestID = id
                let shouldCancel = cancelled
                lock.unlock()
                if shouldCancel { PHImageManager.default().cancelImageRequest(id) }
            }
        } onCancel: {
            self.lock.lock()
            self.cancelled = true
            let id = self.requestID
            self.lock.unlock()
            if let id { PHImageManager.default().cancelImageRequest(id) }
            self.finish(.failure(CancellationError()))
        }
    }

    private func finish(_ result: sending Result<Value, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}

enum LocalImages {
    static func importFile(_ url: URL, into directory: URL) async throws -> BookPhoto {
        try await Task.detached(priority: .userInitiated) {
            try storeFile(url, name: url.lastPathComponent, in: directory)
        }.value
    }

    static func store(
        _ data: Data, preferredExtension: String?, name: String, sourceID: String?, date: Date?, in directory: URL
    ) throws -> BookPhoto {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = ImageHeader(source, preferredExtension: preferredExtension)
        else { throw AppError.imageUnavailable(name: name) }
        let filename = UUID().uuidString + "." + image.suffix
        try data.write(to: BookStorage.assetURL(filename: filename, in: directory), options: .atomic)
        return image.photo(name: name, sourceID: sourceID, date: date, filename: filename)
    }

    /// Checks the image from its header, then copies the file into the book without reading it whole.
    static func storeFile(_ url: URL, name: String, in directory: URL) throws -> BookPhoto {
        let suffix = url.pathExtension.isEmpty ? nil : url.pathExtension.lowercased()
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = ImageHeader(source, preferredExtension: suffix)
        else { throw AppError.imageUnavailable(name: name) }
        let filename = UUID().uuidString + "." + image.suffix
        let destination = BookStorage.assetURL(filename: filename, in: directory)
        try FileManager.default.copyItem(at: url, to: destination)
        // A copy keeps the source's permissions; the book must be able to manage its own files.
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: destination.path)
        return image.photo(name: name, sourceID: nil, date: nil, filename: filename)
    }

    private struct ImageHeader {
        let properties: [CFString: Any]
        let width: Int
        let height: Int
        let suffix: String

        init?(_ source: CGImageSource, preferredExtension: String?) {
            guard CGImageSourceGetType(source) != nil,
                  let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = props[kCGImagePropertyPixelWidth] as? Int,
                  let height = props[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0
            else { return nil }
            let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
            let rotated = (5...8).contains(orientation)
            let type = CGImageSourceGetType(source).flatMap { UTType($0 as String)?.preferredFilenameExtension }
            properties = props
            self.width = rotated ? height : width
            self.height = rotated ? width : height
            suffix = type ?? preferredExtension ?? "image"
        }

        func photo(name: String, sourceID: String?, date: Date?, filename: String) -> BookPhoto {
            BookPhoto(name: name, sourceID: sourceID, capturedAt: date ?? LocalImages.exifDate(from: properties),
                      filename: filename, pixelWidth: width, pixelHeight: height,
                      location: LocalImages.location(from: properties))
        }
    }

    static func location(at url: URL) -> PhotoLocation? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        return location(from: props)
    }

    fileprivate static func location(from props: [CFString: Any]) -> PhotoLocation? {
        let iptc = props[kCGImagePropertyIPTCDictionary] as? [CFString: Any]
        func placeName(_ fields: [CFString]) -> String? {
            fields.compactMap { (iptc?[$0] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
        }
        let name = placeName([kCGImagePropertyIPTCSubLocation, kCGImagePropertyIPTCCity])
        let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any]
        func degrees(_ key: CFString, reference: CFString, positive: String, negative: String) -> Double? {
            guard let value = (gps?[key] as? NSNumber)?.doubleValue else { return nil }
            switch (gps?[reference] as? String)?.uppercased() {
            case positive: return abs(value)
            case negative: return -abs(value)
            case nil: return value
            default: return nil
            }
        }
        let location = PhotoLocation(name: name,
            latitude: degrees(kCGImagePropertyGPSLatitude, reference: kCGImagePropertyGPSLatitudeRef,
                              positive: "N", negative: "S"),
            longitude: degrees(kCGImagePropertyGPSLongitude, reference: kCGImagePropertyGPSLongitudeRef,
                               positive: "E", negative: "W"))
        if location.hasMetadata { return location }
        return placeName([kCGImagePropertyIPTCProvinceState, kCGImagePropertyIPTCCountryPrimaryLocationName])
            .map { PhotoLocation(name: $0) }
    }

    static func load(_ url: URL, maxPixelSize: Int) -> CGImage? {
        let options: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }

    fileprivate static func exifDate(from props: [CFString: Any]) -> Date? {
        guard let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let value = exif[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: value)
    }
}
