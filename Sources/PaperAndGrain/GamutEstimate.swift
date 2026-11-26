import CoreGraphics
import Foundation

/// How much of a placed photo the book's CMYK profile cannot print, for the Issues list. The estimate
/// renders the part of the photo shown in its frame, with its adjustments and film look, at about
/// `sampleSize` pixels on the long side, runs it through the soft proof and counts the pixels whose color
/// moves by more than `CMYKConverter.gamutChromaLimit` from the compensated original.
///
/// The preflight never renders: it reads `cachedShare` and lists the requests it lacks; `GamutEstimator`
/// fills them in the background and asks for a recheck, so the other issues publish at once.
enum GamutEstimate {
    /// A photo warns when at least this share of it is outside the printer's range.
    static let warningShare = 0.10
    static let sampleSize = 160

    /// One estimate: the file, its look, the part shown, and the profile. Also the cache key.
    struct Request: Hashable, Sendable {
        let directory: URL
        let filename: String
        let film: FilmSettings
        let adjustments: PhotoAdjustments?
        /// The part of the image shown in the frame, normalized to the image, rounded to 1 %.
        let visible: CGRect
        let profileSHA: String

        init(photo: BookPhoto, book: Book, directory: URL, frame: CGRect, fills: Bool, crop: PhotoCrop, profileSHA: String) {
            self.directory = directory
            filename = photo.filename
            film = book.effectiveFilm(for: photo)
            adjustments = photo.adjustments
            self.profileSHA = profileSHA
            let pixels = CGSize(width: max(1, photo.pixelWidth), height: max(1, photo.pixelHeight))
            let placed = crop.imageRect(for: pixels, in: frame, fills: fills)
            let shown = placed.intersection(frame)
            func rounded(_ value: CGFloat) -> CGFloat { (min(1, max(0, value)) * 100).rounded() / 100 }
            if placed.width > 0, placed.height > 0, !shown.isNull, !shown.isEmpty {
                let x = rounded((shown.minX - placed.minX) / placed.width)
                let y = rounded((shown.minY - placed.minY) / placed.height)
                visible = CGRect(x: x, y: y, width: max(0.01, rounded((shown.maxX - placed.minX) / placed.width) - x),
                                 height: max(0.01, rounded((shown.maxY - placed.minY) / placed.height) - y))
            } else {
                visible = CGRect(x: 0, y: 0, width: 1, height: 1)
            }
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache = [Request: Double]()

    /// The share (0 to 1) already measured for a request; nil when it has not been estimated yet.
    static func cachedShare(_ request: Request) -> Double? {
        lock.lock()
        defer { lock.unlock() }
        return cache[request]
    }

    /// Renders the shown part of the photo and measures it; stores and returns the share. Nil when the
    /// file cannot be read.
    static func estimate(_ request: Request, converter: CMYKConverter) -> Double? {
        if let known = cachedShare(request) { return known }
        let lut = request.film.lutFilename.map { BookStorage.lutURL(filename: $0, in: request.directory) }
        // Render large enough that the part shown is about `sampleSize` pixels, then keep that part.
        let fraction = max(request.visible.width, request.visible.height)
        let limit = min(1024, Int((Double(sampleSize) / Double(max(0.05, fraction))).rounded(.up)))
        guard let image = FilmRenderer.image(from: BookStorage.assetURL(filename: request.filename, in: request.directory),
                                             maxPixelSize: limit, settings: request.film, lutURL: lut,
                                             adjustments: request.adjustments) else { return nil }
        let width = CGFloat(image.width), height = CGFloat(image.height)
        let crop = CGRect(x: request.visible.minX * width, y: request.visible.minY * height,
                          width: request.visible.width * width, height: request.visible.height * height).integral
        let shown = image.cropping(to: crop) ?? image
        let share = converter.outOfGamutShare(shown)
        lock.lock()
        cache[request] = share
        lock.unlock()
        return share
    }
}

/// Fills the gamut cache in the background, a few photos at a time at utility priority. Requests already
/// waiting or in flight are not added twice. Ordinary edits add requests and never cancel the work; a
/// different profile or `cancel()` (the book closes) drops it. `progress` runs after every few photos and
/// at the end, so the Issues list can recheck at once.
actor GamutEstimator {
    private var profileSHA: String?
    private var queue = [GamutEstimate.Request]()
    private var known = Set<GamutEstimate.Request>()
    private var worker: Task<Void, Never>?
    private var progress: (@Sendable () async -> Void)?

    static let batch = 2
    static let reportEvery = 6

    func enqueue(_ requests: [GamutEstimate.Request], progress: @escaping @Sendable () async -> Void) {
        guard let profile = requests.first?.profileSHA else { return }
        if profile != profileSHA {
            cancel()
            profileSHA = profile
        }
        self.progress = progress
        for request in requests where request.profileSHA == profile && GamutEstimate.cachedShare(request) == nil {
            if known.insert(request).inserted { queue.append(request) }
        }
        guard worker == nil, !queue.isEmpty else { return }
        worker = Task(priority: .utility) { await self.run() }
    }

    func cancel() {
        worker?.cancel()
        worker = nil
        queue.removeAll()
        known.removeAll()
        profileSHA = nil
    }

    /// Waits for the work in progress; for tests.
    func settle() async { await worker?.value }

    private func next() -> [GamutEstimate.Request] {
        let taken = Array(queue.prefix(Self.batch))
        queue.removeFirst(taken.count)
        return taken
    }

    private func run() async {
        var done = 0
        while !Task.isCancelled {
            let batch = next()
            guard !batch.isEmpty, let sha = profileSHA, let converter = PrintColor.cachedConverter(sha256: sha) else { break }
            await withTaskGroup(of: Void.self) { group in
                for request in batch {
                    group.addTask(priority: .utility) { _ = GamutEstimate.estimate(request, converter: converter) }
                }
            }
            for request in batch { known.remove(request) }
            done += batch.count
            if done >= Self.reportEvery {
                done = 0
                await progress?()
            }
        }
        let finished = !Task.isCancelled
        worker = nil
        if finished, done > 0 { await progress?() }
    }
}
