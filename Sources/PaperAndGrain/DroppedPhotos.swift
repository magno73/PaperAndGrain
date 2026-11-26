import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct DroppedPhotos {
    struct Outcome {
        let index: Int
        let photo: BookPhoto?
        /// The file name, when known, so a failure can name the image.
        var name: String? = nil
    }

    let directory: URL
    let count: Int
    let outcomes: AsyncStream<Outcome>
    private let cancelRequests: () -> Void

    /// Starts provider loading before the SwiftUI drop callback returns.
    static func start(_ providers: [NSItemProvider], fallbackName: String) throws -> Self? {
        let supported = providers.compactMap { provider in
            Representation(provider: provider).map { (provider, $0) }
        }
        guard !supported.isEmpty else { return nil }

        let directory = try stagingDirectory()
        let (outcomes, continuation) = AsyncStream<Outcome>.makeStream()
        let group = DispatchGroup()
        var requests: [Progress] = []
        for (index, item) in supported.enumerated() {
            let (provider, representation) = item
            let suggestedName = provider.suggestedName
            group.enter()
            let finish: @Sendable (BookPhoto?, String?) -> Void = { photo, name in
                continuation.yield(Outcome(index: index, photo: photo, name: name))
                group.leave()
            }
            switch representation {
            case .fileURL:
                let request = provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                    let url = data.flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                    let photo = url.flatMap { try? importFile($0, named: $0.lastPathComponent, into: directory) }
                    finish(photo, url?.lastPathComponent ?? suggestedName)
                }
                requests.append(request)
            case let .image(type):
                let name = suggestedName ?? [fallbackName, type.preferredFilenameExtension].compactMap { $0 }.joined(separator: ".")
                let request = provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
                    // The provider may remove its temporary file as soon as this closure returns.
                    let photo = url.flatMap { try? importFile($0, named: name, into: directory) }
                    finish(photo, name)
                }
                requests.append(request)
            }
        }
        group.notify(queue: .global(qos: .userInitiated)) { continuation.finish() }
        return Self(directory: directory, count: supported.count, outcomes: outcomes) {
            continuation.finish()
            for request in requests where !request.isFinished { request.cancel() }
        }
    }

    /// AppKit file promises are used by Photos and must be accepted during the native drop callback.
    static func start(_ promises: [NSFilePromiseReceiver]) throws -> Self? {
        guard !promises.isEmpty else { return nil }
        let directory = try stagingDirectory()
        let payloads = directory.appendingPathComponent("promised", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: payloads, withIntermediateDirectories: false)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }

        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 1
        queue.isSuspended = true
        let positions = PromisePositions()
        let (outcomes, continuation) = AsyncStream<Outcome>.makeStream()
        for (receiverIndex, promise) in promises.enumerated() {
            promise.receivePromisedFiles(atDestination: payloads, options: [:], operationQueue: queue) { url, error in
                guard let position = positions.next(for: receiverIndex) else { return }
                let photo = error == nil ? try? importFile(url, named: url.lastPathComponent, into: directory) : nil
                continuation.yield(Outcome(index: position.index, photo: photo, name: url.lastPathComponent))
                if position.isLast { continuation.finish() }
            }
            // AppKit populates names when it accepts the promise. Some legacy sources only publish types.
            let count = promise.fileNames.isEmpty ? max(1, promise.fileTypes.count) : promise.fileNames.count
            positions.reserve(count, for: receiverIndex)
        }
        let count = positions.count
        queue.isSuspended = false
        return Self(directory: directory, count: count, outcomes: outcomes) {
            continuation.finish()
            queue.cancelAllOperations()
        }
    }

    /// Finder files chosen in an open panel, imported into the open book's library.
    static func start(files: [URL]) throws -> Self? {
        guard !files.isEmpty else { return nil }
        let directory = try stagingDirectory()
        let (outcomes, continuation) = AsyncStream<Outcome>.makeStream()
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 2
        for (index, url) in files.enumerated() {
            queue.addOperation {
                let photo = try? importFile(url, named: url.lastPathComponent, into: directory)
                continuation.yield(Outcome(index: index, photo: photo, name: url.lastPathComponent))
            }
        }
        queue.addBarrierBlock { continuation.finish() }
        return Self(directory: directory, count: files.count, outcomes: outcomes) {
            continuation.finish()
            queue.cancelAllOperations()
        }
    }

    /// Originals fetched again from the Photos library by their local identifiers, in order; a nil
    /// identifier is reported as unavailable. Access must already be granted: this never asks for it.
    static func start(photosLibrary sourceIDs: [String?]) throws -> Self? {
        guard !sourceIDs.isEmpty else { return nil }
        let directory = try stagingDirectory()
        let (outcomes, continuation) = AsyncStream<Outcome>.makeStream()
        let task = Task {
            for (index, sourceID) in sourceIDs.enumerated() {
                if Task.isCancelled { break }
                var photo: BookPhoto?
                if let sourceID {
                    photo = try? await PhotoLibrary.importPhoto(
                        LibraryPhoto(id: sourceID, capturedAt: nil, width: 0, height: 0), into: directory)
                }
                continuation.yield(Outcome(index: index, photo: photo, name: nil))
            }
            continuation.finish()
        }
        return Self(directory: directory, count: sourceIDs.count, outcomes: outcomes) {
            continuation.finish()
            task.cancel()
        }
    }

    func cleanUp() {
        cancelRequests()
        try? FileManager.default.removeItem(at: directory)
    }

    enum Representation: Equatable {
        case fileURL
        case image(UTType)

        private static let readableFormats = Set(CGImageSourceCopyTypeIdentifiers() as? [String] ?? [])

        init?(provider: NSItemProvider) {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                self = .fileURL
            } else if let type = provider.registeredTypeIdentifiers.lazy.compactMap({ UTType($0) })
                .first(where: { $0 != .image && ($0.conforms(to: .image) || Self.readableFormats.contains($0.identifier)) }) {
                self = .image(type)
            } else {
                return nil
            }
        }
    }

    private static func stagingDirectory() throws -> URL {
        let files = FileManager.default
        let directory = files.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try files.createDirectory(at: directory.appendingPathComponent("assets", isDirectory: true),
                                  withIntermediateDirectories: true)
        return directory
    }

    private static func importFile(_ url: URL, named name: String, into directory: URL) throws -> BookPhoto {
        guard url.isFileURL else { throw AppError.imageUnavailable(name: name) }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try LocalImages.storeFile(url, name: name, in: directory)
    }

    private final class PromisePositions: @unchecked Sendable {
        private let lock = NSLock()
        private var receiverRanges: [Int: Range<Int>] = [:]
        private var total = 0
        private var remaining = 0

        var count: Int { lock.withLock { total } }

        func reserve(_ count: Int, for receiver: Int) {
            lock.withLock {
                receiverRanges[receiver] = total..<(total + count)
                total += count
                remaining += count
            }
        }

        func next(for receiver: Int) -> (index: Int, isLast: Bool)? {
            lock.withLock {
                guard let range = receiverRanges[receiver], let index = range.first else { return nil }
                receiverRanges[receiver] = (index + 1)..<range.upperBound
                remaining -= 1
                return (index, remaining == 0)
            }
        }
    }
}
