import AppKit
import Foundation
import ImageIO
import Photos
import UniformTypeIdentifiers

struct Album: Identifiable, Hashable {
    let id: String
    let title: String
    let count: Int
}

struct LibraryPhoto: Identifiable, Hashable, Sendable {
    let id: String
    let capturedAt: Date?
    let width: Int
    let height: Int
}

enum PhotoImportError: LocalizedError {
    case unreadableImage
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unreadableImage: "Immagine non disponibile · Image unavailable"
        case .cancelled: "Operazione annullata · Operation cancelled"
        }
    }
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
            throw PhotoImportError.unreadableImage
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
                    complete(data.map { .success(($0, type)) } ?? .failure(PhotoImportError.unreadableImage))
                }
            }
        }
        try Task.checkCancellation()
        let originalName = PHAssetResource.assetResources(for: asset).first?.originalFilename
        return try LocalImages.store(
            data, preferredExtension: type.flatMap { UTType($0)?.preferredFilenameExtension },
            name: originalName ?? "Foto", sourceID: photo.id, date: photo.capturedAt, in: directory
        )
    }
}

private final class PhotoRequest<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var requestID: PHImageRequestID?
    private var cancelled = false

    func value(start: (@escaping (Result<Value, Error>) -> Void) -> PHImageRequestID) async throws -> Value {
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

    private func finish(_ result: Result<Value, Error>) {
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
            try store(Data(contentsOf: url), preferredExtension: nil, name: url.lastPathComponent,
                      sourceID: nil, date: nil, in: directory)
        }.value
    }

    static func store(
        _ data: Data, preferredExtension: String?, name: String, sourceID: String?, date: Date?, in directory: URL
    ) throws -> BookPhoto {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0
        else { throw PhotoImportError.unreadableImage }
        let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
        let rotated = (5...8).contains(orientation)
        let type = CGImageSourceGetType(source).flatMap { UTType($0 as String)?.preferredFilenameExtension }
        let suffix = type ?? preferredExtension ?? "image"
        let filename = UUID().uuidString + "." + suffix
        try data.write(to: BookStorage.assetURL(filename: filename, in: directory), options: .atomic)
        return BookPhoto(name: name, sourceID: sourceID, capturedAt: date ?? exifDate(from: props),
                         filename: filename, pixelWidth: rotated ? height : width, pixelHeight: rotated ? width : height)
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

    private static func exifDate(from props: [CFString: Any]) -> Date? {
        guard let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let value = exif[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: value)
    }
}
