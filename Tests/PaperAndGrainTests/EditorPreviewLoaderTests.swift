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

    func testBlockedThumbnailAllowsCanvasRenderAndCancelledWorkNeverRuns() async throws {
        let sample = try pixels()
        let starts = Starts()
        let first = request("first", size: 180)
        let obsolete = request("obsolete", size: 180)
        let current = request("current", size: 1440)
        let entered = expectation(description: "First thumbnail is rendering")
        let displayed = expectation(description: "Canvas rendered while thumbnails were busy")
        let permitFinish = DispatchSemaphore(value: 0)
        defer { permitFinish.signal() }
        let loader = EditorPreviewLoader { request in
            starts.record(request)
            if request == first {
                entered.fulfill()
                _ = permitFinish.wait(timeout: .now() + 5)
            }
            if request == current { displayed.fulfill() }
            return sample
        }
        let thumbnail = Task { await loader.load(first) }
        await fulfillment(of: [entered], timeout: 2)
        let hidden = Task { await loader.load(obsolete) }
        let canvas = Task { await loader.load(current) }
        await fulfillment(of: [displayed], timeout: 2)
        hidden.cancel()
        let discarded = await hidden.value
        XCTAssertNil(discarded)
        permitFinish.signal()
        let visibleThumbnail = await thumbnail.value
        let visibleCanvas = await canvas.value
        XCTAssertNotNil(visibleThumbnail)
        XCTAssertNotNil(visibleCanvas)
        // A new thumbnail completes after any old request that remained on its FIFO lane.
        let following = await loader.load(request("following", size: 180))
        XCTAssertNotNil(following)
        XCTAssertEqual(starts.count(obsolete), 0)
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

    private func request(_ name: String, size: Int, adjustments: PhotoAdjustments? = nil) -> EditorPreviewRequest {
        EditorPreviewRequest(url: URL(fileURLWithPath: "/" + name + ".png"), limit: size, look: FilmSettings(),
                             lutURL: nil, adjustments: adjustments)
    }

    private func pixels() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 3, height: 3, bitsPerComponent: 8,
                                              bytesPerRow: 12, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return try XCTUnwrap(context.makeImage())
    }
}
