import CoreGraphics
import Foundation

struct EditorPreviewRequest: Hashable, Sendable {
    let url: URL
    let limit: Int
    let look: FilmSettings
    let lutURL: URL?
    let adjustments: PhotoAdjustments?
    var isFilmSwatch = false
    var isInteractive = false
}

actor EditorPreviewLoader {
    private typealias Waiter = CheckedContinuation<CGImage?, Never>
    private let render: @Sendable (EditorPreviewRequest) -> CGImage?

    private final class Key: NSObject {
        let request: EditorPreviewRequest
        init(_ request: EditorPreviewRequest) { self.request = request }
        override var hash: Int { request.hashValue }
        override func isEqual(_ object: Any?) -> Bool { (object as? Key)?.request == request }
    }

    /// All mutable lane state belongs to the actor. Only the running render
    /// occupies the dispatch queue, so cancelled requests can leave the waiting list immediately.
    private final class Lane {
        let queue: DispatchQueue
        let cache = NSCache<Key, CGImage>()
        /// How many renders may run at once; the canvas renders a spread's photos side by side.
        let width: Int
        var running: Set<EditorPreviewRequest> = []
        var pending: [EditorPreviewRequest] = []
        var waiters: [EditorPreviewRequest: [UUID: Waiter]] = [:]

        init(name: String, qos: DispatchQoS, megabytes: Int, width: Int = 1) {
            self.width = max(1, width)
            queue = DispatchQueue(label: name, qos: qos, attributes: width > 1 ? .concurrent : [],
                                  autoreleaseFrequency: .workItem)
            cache.totalCostLimit = megabytes * 1024 * 1024
        }
    }

    private let canvas = Lane(name: "PaperAndGrain.preview.canvas", qos: .userInitiated, megabytes: 160,
                              width: min(4, max(2, ProcessInfo.processInfo.activeProcessorCount / 3)))
    private let interactive = Lane(name: "PaperAndGrain.preview.interactive", qos: .userInitiated, megabytes: 24)
    // A 180 px thumbnail of a 12 MP photo takes about 15 ms; several lanes fill a 150-photo tray in well under a second.
    static let thumbnailLaneWidth = min(4, max(2, ProcessInfo.processInfo.activeProcessorCount / 3))
    private let thumbnails = Lane(name: "PaperAndGrain.preview.thumbnails", qos: .utility, megabytes: 20,
                                  width: EditorPreviewLoader.thumbnailLaneWidth)
    private let filmSwatches = Lane(name: "PaperAndGrain.preview.filmSwatches", qos: .userInitiated, megabytes: 4)
    private static let shared = EditorPreviewLoader { request in
        FilmRenderer.image(from: request.url, maxPixelSize: request.limit, settings: request.look,
                           lutURL: request.lutURL, adjustments: request.adjustments)
    }

    init(render: @escaping @Sendable (EditorPreviewRequest) -> CGImage?) {
        self.render = render
    }

    static func image(for request: EditorPreviewRequest) async -> CGImage? {
        await shared.load(request)
    }

    static func cachedImage(for request: EditorPreviewRequest) async -> CGImage? {
        await shared.cached(request)
    }

    func cached(_ request: EditorPreviewRequest) -> CGImage? {
        lane(for: request).cache.object(forKey: Key(request))
    }

    func load(_ request: EditorPreviewRequest) async -> CGImage? {
        let ticket = UUID()
        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: Waiter) in
                guard !Task.isCancelled, request.limit > 0 else {
                    continuation.resume(returning: nil)
                    return
                }
                let lane = lane(for: request)
                if let image = lane.cache.object(forKey: Key(request)) {
                    continuation.resume(returning: image)
                    return
                }
                if lane.waiters[request] == nil { lane.pending.append(request) }
                lane.waiters[request, default: [:]][ticket] = continuation
                startNext(in: lane)
            }
        } onCancel: {
            Task { await self.cancel(ticket, request: request) }
        }
        return Task.isCancelled ? nil : result
    }

    private func lane(for request: EditorPreviewRequest) -> Lane {
        if request.isInteractive { return interactive }
        if request.isFilmSwatch { return filmSwatches }
        return request.limit <= 180 ? thumbnails : canvas
    }

    private func startNext(in lane: Lane) {
        while lane.running.count < lane.width, !lane.pending.isEmpty {
            // The newest request is the page the author is looking at now.
            let request = lane.pending.removeLast()
            lane.running.insert(request)
            lane.queue.async { [render] in
                let image = render(request)
                Task { await self.finish(request, image: image) }
            }
        }
    }

    private func cancel(_ ticket: UUID, request: EditorPreviewRequest) {
        let lane = lane(for: request)
        guard let waiter = lane.waiters[request]?.removeValue(forKey: ticket) else { return }
        if lane.waiters[request]?.isEmpty == true, !lane.running.contains(request) {
            lane.pending.removeAll { $0 == request }
            lane.waiters.removeValue(forKey: request)
        }
        waiter.resume(returning: nil)
    }

    private func finish(_ request: EditorPreviewRequest, image: CGImage?) {
        let lane = lane(for: request)
        let waiters = lane.waiters.removeValue(forKey: request) ?? [:]
        if let image, !waiters.isEmpty {
            lane.cache.setObject(image, forKey: Key(request), cost: image.bytesPerRow * image.height)
        }
        lane.running.remove(request)
        for waiter in waiters.values { waiter.resume(returning: image) }
        startNext(in: lane)
    }
}
