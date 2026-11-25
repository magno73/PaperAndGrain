import CoreGraphics
import Foundation
import XCTest
@testable import PaperAndGrain

final class EditorPreviewLoaderTests: XCTestCase {
    /// The synchronous render closure runs on the same queues as the real image decoder.
    private final class Starts: @unchecked Sendable {
        private let lock = NSLock()
        private var requests: [EditorPreviewRequest] = []

        func record(_ request: EditorPreviewRequest) {
            lock.withLock { requests.append(request) }
        }

        func count(_ request: EditorPreviewRequest) -> Int {
            lock.withLock { requests.filter { $0 == request }.count }
        }
    }

    func testConcurrentRequestsSharePixelsAndEditedSettingsGetTheirOwnEntry() async throws {
        let sample = try pixels()
        let starts = Starts()
        let loader = EditorPreviewLoader { request in
            starts.record(request)
            return sample
        }
        let first = request("sample", size: 1440)
        let matched = await withTaskGroup(of: Bool.self, returning: Bool.self) { group in
            for _ in 0..<24 { group.addTask { await loader.load(first) === sample } }
            for await received in group where !received { return false }
            return true
        }
        XCTAssertTrue(matched)
        XCTAssertEqual(starts.count(first), 1)

        let changed = request("sample", size: 1440, adjustments: PhotoAdjustments(exposure: 0.7))
        let edited = await loader.load(changed)
        let restored = await loader.load(first)
        XCTAssertNotNil(edited)
        XCTAssertNotNil(restored)
        XCTAssertEqual(starts.count(changed), 1)
        XCTAssertEqual(starts.count(first), 1)
    }

    func testBlockedThumbnailAllowsCanvasAndFilmSwatchAndCancelledWorkNeverRuns() async throws {
        let sample = try pixels()
        let starts = Starts()
        // Every thumbnail lane is busy, so a newer thumbnail waits and can still be dropped.
        let width = EditorPreviewLoader.thumbnailLaneWidth
        let blockers = (0..<width).map { request("first-\($0)", size: 180) }
        let first = blockers[0]
        let obsolete = request("obsolete", size: 180)
        let current = request("current", size: 1440)
        let swatch = request("current", size: 180, isFilmSwatch: true)
        let entered = expectation(description: "Every thumbnail lane is rendering")
        entered.expectedFulfillmentCount = width
        let displayed = expectation(description: "Canvas rendered while thumbnails were busy")
        let filmDisplayed = expectation(description: "Film swatch rendered while thumbnails were busy")
        let permitFinish = DispatchSemaphore(value: 0)
        defer { for _ in 0..<width { permitFinish.signal() } }
        let loader = EditorPreviewLoader { request in
            starts.record(request)
            if blockers.contains(request) {
                entered.fulfill()
                _ = permitFinish.wait(timeout: .now() + 5)
            }
            if request == current { displayed.fulfill() }
            if request == swatch { filmDisplayed.fulfill() }
            return sample
        }
        let thumbnail = Task { await loader.load(first) }
        let others = blockers.dropFirst().map { blocker in Task { await loader.load(blocker) } }
        await fulfillment(of: [entered], timeout: 2)
        let hidden = Task { await loader.load(obsolete) }
        let canvas = Task { await loader.load(current) }
        let film = Task { await loader.load(swatch) }
        await fulfillment(of: [displayed, filmDisplayed], timeout: 2)
        hidden.cancel()
        let discarded = await hidden.value
        XCTAssertNil(discarded)
        for _ in 0..<width { permitFinish.signal() }
        let visibleThumbnail = await thumbnail.value
        for other in others { _ = await other.value }
        let visibleCanvas = await canvas.value
        let visibleSwatch = await film.value
        XCTAssertNotNil(visibleThumbnail)
        XCTAssertNotNil(visibleCanvas)
        XCTAssertNotNil(visibleSwatch)
        // A new thumbnail completes after any old request that remained on its FIFO lane.
        let following = await loader.load(request("following", size: 180))
        XCTAssertNotNil(following)
        XCTAssertEqual(starts.count(obsolete), 0)
    }

    func testLiveFilmPreviewCanFinishWhileFullCanvasIsRendering() async throws {
        let sample = try pixels()
        let full = request("image", size: 1440)
        let live = EditorPreviewRequest(url: full.url, limit: 640, look: FilmSettings(grain: 0.25),
                                        lutURL: nil, adjustments: nil, isInteractive: true)
        let fullStarted = expectation(description: "Full canvas render started")
        let liveStarted = expectation(description: "Live preview did not wait for the canvas")
        let permitFull = DispatchSemaphore(value: 0)
        defer { permitFull.signal() }
        let loader = EditorPreviewLoader { request in
            if request == full {
                fullStarted.fulfill()
                _ = permitFull.wait(timeout: .now() + 5)
            }
            if request == live { liveStarted.fulfill() }
            return sample
        }
        let fullRender = Task { await loader.load(full) }
        await fulfillment(of: [fullStarted], timeout: 2)
        let liveRender = Task { await loader.load(live) }
        await fulfillment(of: [liveStarted], timeout: 2)
        let livePixels = await liveRender.value
        XCTAssertTrue(livePixels === sample)
        permitFull.signal()
        let fullPixels = await fullRender.value
        XCTAssertTrue(fullPixels === sample)
    }

    func testCancellingOneSubscriberLeavesAnIdenticalInFlightRenderAvailable() async throws {
        let sample = try pixels()
        let starts = Starts()
        let entered = expectation(description: "Preview render started")
        let permitFinish = DispatchSemaphore(value: 0)
        defer { permitFinish.signal() }
        let loader = EditorPreviewLoader { request in
            starts.record(request)
            entered.fulfill()
            _ = permitFinish.wait(timeout: .now() + 5)
            return sample
        }
        let request = request("shared", size: 1440)
        let hidden = Task { await loader.load(request) }
        await fulfillment(of: [entered], timeout: 2)
        let visible = Task { await loader.load(request) }
        hidden.cancel()
        let discarded = await hidden.value
        XCTAssertNil(discarded)
        permitFinish.signal()
        let received = await visible.value
        XCTAssertTrue(received === sample)
        XCTAssertEqual(starts.count(request), 1)
    }

    private func request(_ name: String, size: Int, adjustments: PhotoAdjustments? = nil,
                         isFilmSwatch: Bool = false) -> EditorPreviewRequest {
        EditorPreviewRequest(url: URL(fileURLWithPath: "/" + name + ".png"), limit: size, look: FilmSettings(),
                             lutURL: nil, adjustments: adjustments, isFilmSwatch: isFilmSwatch)
    }

    private func pixels() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 3, height: 3, bitsPerComponent: 8,
                                              bytesPerRow: 12, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return try XCTUnwrap(context.makeImage())
    }
}
