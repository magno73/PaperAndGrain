import CoreGraphics
import XCTest
@testable import PaperAndGrain

final class SimilarPhotosTests: XCTestCase {
    struct RNG: RandomNumberGenerator { var s: UInt64; mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; return s ^ (s >> 29) } }

    static func scene(seed: UInt64, shift: CGFloat = 0, crop: CGFloat = 0, bright: CGFloat = 0) -> CGImage {
        let w = 600, h = 400
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: .sRGBSpace,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        var g = RNG(s: seed &* 7919 &+ 17)
        func r() -> CGFloat { CGFloat(Double.random(in: 0...1, using: &g)) }
        ctx.saveGState()
        // crop: zoom in by crop fraction on each side; shift: translate.
        let zoom = 1 / (1 - 2 * crop)
        ctx.translateBy(x: CGFloat(w) * shift, y: 0)
        ctx.translateBy(x: CGFloat(w) / 2, y: CGFloat(h) / 2); ctx.scaleBy(x: zoom, y: zoom); ctx.translateBy(x: -CGFloat(w) / 2, y: -CGFloat(h) / 2)
        let colors = [CGColor(red: r(), green: r(), blue: r(), alpha: 1), CGColor(red: r(), green: r(), blue: r(), alpha: 1)]
        let grad = CGGradient(colorsSpace: .sRGBSpace, colors: colors as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(grad, start: CGPoint(x: r() * 600, y: 0), end: CGPoint(x: r() * 600, y: 400), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        for _ in 0..<9 {
            ctx.setFillColor(CGColor(red: r(), green: r(), blue: r(), alpha: 1))
            let rect = CGRect(x: r() * 500, y: r() * 320, width: 40 + r() * 160, height: 30 + r() * 120)
            if r() > 0.5 { ctx.fillEllipse(in: rect) } else { ctx.fill(rect) }
        }
        ctx.restoreGState()
        if bright != 0 {
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: bright))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        }
        return ctx.makeImage()!
    }

    func hashOf(_ image: CGImage) -> UInt64 { UInt64(PhotoVisualSignals.measure(image)!.perceptualHash, radix: 16)! }

    private func entry(_ hash: UInt64, time: Double? = nil) -> SimilarPhotos.Entry {
        SimilarPhotos.Entry(id: UUID(), hash: hash, time: time)
    }

    /// `hash` with the lowest `bits` bits flipped.
    private func flipped(_ hash: UInt64, _ bits: Int) -> UInt64 { hash ^ ((1 << UInt64(bits)) - 1) }

    func testGroupsAreTransitive() {
        let base: UInt64 = 0xF0F0_F0F0_F0F0_F0F0
        // a-b are 6 bits apart, b-c are 6 bits apart, a-c are 12 apart: still one group.
        let a = entry(base), b = entry(flipped(base, 6)), c = entry(base ^ 0xFFF)
        let far = entry(~base)
        XCTAssertGreaterThan((a.hash ^ c.hash).nonzeroBitCount, 8)
        XCTAssertEqual(SimilarPhotos.groups([a, far, c, b]).map(Set.init), [Set([a.id, b.id, c.id])])
        XCTAssertEqual((b.hash ^ c.hash).nonzeroBitCount <= 8, true)
    }

    func testTheTimeRuleWidensTheThresholdOnlyForCloseShots() {
        let base: UInt64 = 0x0123_4567_89AB_CDEF
        let near = flipped(base, 10)
        let a = entry(base, time: 1000), soon = entry(near, time: 1060), late = entry(near, time: 1000 + 3600)
        let undated = entry(near)
        XCTAssertEqual(SimilarPhotos.groups([a, soon]).count, 1)
        XCTAssertEqual(SimilarPhotos.groups([a, late]).count, 0)
        XCTAssertEqual(SimilarPhotos.groups([a, undated]).count, 0)
        // Nine bits apart is over the plain threshold and under the time one.
        XCTAssertEqual((base ^ flipped(base, 9)).nonzeroBitCount, 9)
        XCTAssertEqual(SimilarPhotos.groups([a, entry(flipped(base, 9), time: 1119)]).count, 1)
        XCTAssertEqual(SimilarPhotos.groups([a, entry(flipped(base, 9), time: 1121)]).count, 0)
        // Eleven bits is over both.
        XCTAssertEqual(SimilarPhotos.groups([a, entry(flipped(base, 11), time: 1001)]).count, 0)
    }

    func testPhotosWithoutAHashAreNeverGrouped() {
        func photo(_ hash: String?) -> BookPhoto {
            var p = BookPhoto(name: "p", filename: "p", pixelWidth: 4, pixelHeight: 3)
            if let hash {
                var visual = PhotoVisualSignals(orientation: "landscape", brightness: 0.5, sharpness: 0.1, contrast: 0.1,
                                                dominantColors: [], perceptualHash: hash)
                visual.sharpness = 0.1
                p.analysis = PhotoAnalysis(labels: [], concepts: [], visual: visual)
            }
            return p
        }
        let photos = [photo("0123456789abcdef"), photo("0123456789abcdef"), photo(nil), photo(nil), photo("short")]
        XCTAssertEqual(SimilarPhotos.entries(photos).count, 2)
        XCTAssertEqual(SimilarPhotos.groups(SimilarPhotos.entries(photos)).count, 1)
    }

    func testResultDoesNotDependOnInputOrder() {
        var generator = SystemRandomNumberGenerator()
        let base = UInt64.random(in: .min ... .max, using: &generator)
        var entries: [SimilarPhotos.Entry] = []
        for index in 0..<60 {
            let hash: UInt64 = index % 3 == 0 ? base ^ UInt64(1 << (index % 5)) : UInt64.random(in: .min ... .max, using: &generator)
            let time: Double? = index.isMultiple(of: 2) ? Double(index * 30) : nil
            entries.append(entry(hash, time: time))
        }
        let expected = SimilarPhotos.groups(entries)
        for _ in 0..<5 {
            XCTAssertEqual(SimilarPhotos.groups(entries.shuffled()), expected)
        }
        XCTAssertFalse(expected.isEmpty)
    }

    func testShownPhotoPrefersPlacedThenDetailThenEarliest() {
        func photo(_ sharpness: Double?) -> BookPhoto {
            var p = BookPhoto(name: "p", filename: UUID().uuidString, pixelWidth: 4, pixelHeight: 3)
            if let sharpness {
                p.analysis = PhotoAnalysis(labels: [], concepts: [], visual: PhotoVisualSignals(
                    orientation: "l", brightness: 0, sharpness: sharpness, contrast: 0, dominantColors: [], perceptualHash: "0000000000000000"))
            }
            return p
        }
        let a = photo(0.2), b = photo(0.9), c = photo(0.5)
        let byID = Dictionary(uniqueKeysWithValues: [a, b, c].map { ($0.id, $0) })
        let group = [a.id, b.id, c.id]
        XCTAssertEqual(SimilarPhotos.shownPhoto(in: group, photos: byID, placed: [c.id]), c.id)
        XCTAssertEqual(SimilarPhotos.shownPhoto(in: group, photos: byID, placed: []), b.id)
        let flat = [photo(nil), photo(nil)]
        let flatByID = Dictionary(uniqueKeysWithValues: flat.map { ($0.id, $0) })
        XCTAssertEqual(SimilarPhotos.shownPhoto(in: flat.map(\.id), photos: flatByID, placed: []), flat[0].id)
    }

    func testSubstitutionKeepsFrameCropAndLayer() {
        let old = UUID(), chosen = UUID(), other = UUID()
        let crop = PhotoCrop(x: 0.2, y: 0.7)
        var page = BookPage(photoIDs: [other, old],
                            photoPlacements: [old: PhotoPlacement(frame: PageRect(x: 0.1, y: 0.1, width: 0.4, height: 0.4), crop: crop)],
                            layerOrder: [.photo(old), .story, .photo(other)])
        XCTAssertTrue(page.substitutePhoto(old, with: chosen))
        XCTAssertEqual(page.photoIDs, [other, chosen])
        XCTAssertEqual(page.photoPlacements?[chosen]?.crop, crop)
        XCTAssertNil(page.photoPlacements?[old])
        XCTAssertEqual(page.layerOrder, [.photo(chosen), .story, .photo(other)])
        XCTAssertFalse(page.substitutePhoto(old, with: chosen), "nothing left to replace")
        // The chosen photo is already on the page: the other one is only removed.
        var both = BookPage(photoIDs: [old, chosen], layerOrder: [.photo(old), .photo(chosen)])
        XCTAssertTrue(both.substitutePhoto(old, with: chosen))
        XCTAssertEqual(both.photoIDs, [chosen])
        XCTAssertEqual(both.layerOrder, [.photo(chosen)])
    }

    /// Generated pictures: the same scene brightened, shifted and cropped must group at the chosen thresholds
    /// when they are easy, and different scenes must never group.
    func testThresholdsOnGeneratedPictures() {
        let seeds = 1...60
        let base = seeds.map { hashOf(Self.scene(seed: UInt64($0))) }
        var brightened = 0, shifted = 0
        for (index, seed) in seeds.enumerated() {
            if (base[index] ^ hashOf(Self.scene(seed: UInt64(seed), bright: 0.2))).nonzeroBitCount <= 8 { brightened += 1 }
            if (base[index] ^ hashOf(Self.scene(seed: UInt64(seed), shift: 0.02))).nonzeroBitCount <= 10 { shifted += 1 }
        }
        XCTAssertEqual(brightened, 60)
        XCTAssertGreaterThanOrEqual(shifted, 50)
        let entries = base.map { SimilarPhotos.Entry(id: UUID(), hash: $0, time: nil) }
        XCTAssertTrue(SimilarPhotos.groups(entries).isEmpty, "different pictures stay apart")
    }

    /// 1,000 photos in under 50 ms (the work runs off the main thread).
    func testGroupingOneThousandPhotosIsFast() {
        var generator = SystemRandomNumberGenerator()
        let entries = (0..<1000).map { index -> SimilarPhotos.Entry in
            let hash = UInt64.random(in: .min ... .max, using: &generator)
            return SimilarPhotos.Entry(id: UUID(), hash: hash, time: Double(index) * 20)
        }
        let clock = ContinuousClock()
        var best = Duration.seconds(10)
        for _ in 0..<5 {
            let elapsed = clock.measure { _ = SimilarPhotos.groups(entries) }
            best = min(best, elapsed)
        }
        print("SIMILAR 1000 photos grouped in \(best)")
        // About 0.3 ms in a release build; a debug build runs this loop 100 times slower.
        #if DEBUG
        XCTAssertLessThan(best, .milliseconds(150))
        #else
        XCTAssertLessThan(best, .milliseconds(50))
        #endif
    }
}
