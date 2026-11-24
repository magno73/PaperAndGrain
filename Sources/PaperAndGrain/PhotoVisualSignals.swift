import Foundation
import CoreGraphics

struct PhotoClassification: Codable, Hashable, Sendable {
    var label: String
    var confidence: Double
}

struct PhotoBox: Codable, Hashable, Sendable {
    var x, y, width, height: Double

    init(_ rect: CGRect) {
        (x, y, width, height) = (rect.minX, rect.minY, rect.width, rect.height)
    }
}

struct PhotoDetection: Codable, Hashable, Sendable {
    var kind, label: String
    var confidence: Double
    var box: PhotoBox
}

struct PhotoText: Codable, Hashable, Sendable {
    var text: String
    var confidence: Double
    var box: PhotoBox
}

struct PhotoVisualSignals: Codable, Hashable, Sendable {
    var orientation: String
    var brightness, sharpness, contrast: Double
    var dominantColors: [String]
    var perceptualHash: String

    private static func sample(_ image: CGImage, width: Int, height: Int) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let success = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
            else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return success ? bytes : nil
    }

    private static func luminance(_ bytes: [UInt8], _ pixel: Int) -> Double {
        let index = pixel * 4
        return (0.2126 * Double(bytes[index]) + 0.7152 * Double(bytes[index + 1]) + 0.0722 * Double(bytes[index + 2])) / 255
    }

    static func measure(_ image: CGImage) -> Self? {
        let size = 64
        guard let rgb = sample(image, width: size, height: size),
              let tiny = sample(image, width: 9, height: 8) else { return nil }
        var hash: UInt64 = 0
        for y in 0..<8 {
            for x in 0..<8 {
                let i = y * 9 + x
                hash = (hash << 1) | (luminance(tiny, i) > luminance(tiny, i + 1) ? 1 : 0)
            }
        }
        var sum = 0.0, squares = 0.0, gradient = 0.0
        var bins: [Int: (count: Int, r: Int, g: Int, b: Int)] = [:]
        for i in 0..<(size * size) {
            let light = luminance(rgb, i)
            sum += light
            squares += light * light
            if i % size > 0 { gradient += abs(light - luminance(rgb, i - 1)) }
            if i >= size { gradient += abs(light - luminance(rgb, i - size)) }
            let r = Int(rgb[i * 4]), g = Int(rgb[i * 4 + 1]), b = Int(rgb[i * 4 + 2])
            let key = ((r >> 5) << 6) | ((g >> 5) << 3) | (b >> 5)
            let old = bins[key] ?? (0, 0, 0, 0)
            bins[key] = (old.0 + 1, old.1 + r, old.2 + g, old.3 + b)
        }
        let colors = bins.sorted { a, b in
            a.value.count == b.value.count ? a.key < b.key : a.value.count > b.value.count
        }.prefix(5).map { entry in
            let v = entry.value
            return String(format: "#%02X%02X%02X", v.r / v.count, v.g / v.count, v.b / v.count)
        }
        let n = Double(size * size), mean = sum / n
        let orientation = image.width == image.height ? "square" : (image.width > image.height ? "landscape" : "portrait")
        return Self(orientation: orientation, brightness: mean, sharpness: gradient / Double(2 * size * (size - 1)),
                    contrast: sqrt(max(0, squares / n - mean * mean)), dominantColors: colors,
                    perceptualHash: String(format: "%016llx", hash))
    }
}
