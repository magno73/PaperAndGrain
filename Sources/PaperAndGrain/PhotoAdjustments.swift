import CoreGraphics
import Accelerate
import Foundation
import simd

struct PhotoAdjustments: Codable, Hashable, Sendable {
    enum SelectiveColor: String, CaseIterable, Identifiable, Codable, Sendable {
        case red, orange, yellow, green, cyan, blue, magenta
        var id: Self { self }

        var hue: Double {
            switch self {
            case .red: 0
            case .orange: 30
            case .yellow: 60
            case .green: 120
            case .cyan: 180
            case .blue: 240
            case .magenta: 300
            }
        }
    }

    var brilliance = 0.0
    var exposure = 0.0
    var highlights = 0.0
    var shadows = 0.0
    var brightness = 0.0
    var contrast = 0.0
    var blackPoint = 0.0
    var saturation = 0.0
    var vibrance = 0.0
    var warmth = 0.0
    var tint = 0.0
    var monochrome = 0.0
    var monochromeNeutrals = 0.0
    var monochromeTone = 0.0
    var monochromeGrain = 0.0
    var definition = 0.0
    var sharpness = 0.0
    var noiseReduction = 0.0
    var vignette = 0.0
    var levelsBlack = 0.0
    var levelsWhite = 1.0
    var levelsGamma = 1.0
    var curveShadows = 0.0
    var curveMidtones = 0.0
    var curveHighlights = 0.0
    var selectiveColor: SelectiveColor = .red
    var selectiveHue = 0.0
    var selectiveSaturation = 0.0
    var selectiveLightness = 0.0

    var curvePoints: [CGPoint] {
        [CGPoint(x: 0, y: 0), CGPoint(x: 0.25, y: 0.25 + 0.20 * bounded(curveShadows, -1...1)),
         CGPoint(x: 0.5, y: 0.5 + 0.20 * bounded(curveMidtones, -1...1)),
         CGPoint(x: 0.75, y: 0.75 + 0.20 * bounded(curveHighlights, -1...1)), CGPoint(x: 1, y: 1)]
    }

    func applyingAutomatic(_ suggestion: Self) -> Self {
        var result = self
        result.brilliance = suggestion.brilliance
        result.exposure = suggestion.exposure
        result.highlights = suggestion.highlights
        result.shadows = suggestion.shadows
        result.vibrance = suggestion.vibrance
        return result
    }

    /// Measure a small, oriented, color-managed copy. The resulting corrections are ordinary editable values.
    static func automatic(from url: URL) -> Self? {
        guard let image = FilmRenderer.image(from: url, maxPixelSize: 220, settings: FilmSettings(), lutURL: nil)
        else { return nil }
        let width = image.width, height = image.height
        let format = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let bitmap = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                     bytesPerRow: 4 * width, space: PhotoDevelopment.space, bitmapInfo: format),
              let data = bitmap.data else { return nil }
        bitmap.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        var histogram = [Int](repeating: 0, count: 256)
        var count = 0
        var chromaSum = 0.0
        for i in stride(from: 0, to: 4 * width * height, by: 4) where pixels[i + 3] > 16 {
            let alpha = Double(pixels[i + 3])
            let rgb = SIMD3(Double(pixels[i]), Double(pixels[i+1]), Double(pixels[i+2])) / alpha
            let luma = simd_dot(rgb, PhotoDevelopment.lumaWeights)
            histogram[min(255, max(0, Int((luma * 255).rounded())))] += 1
            chromaSum += rgb.max() - rgb.min()
            count += 1
        }
        guard count > 0 else { return nil }
        func percentile(_ fraction: Double) -> Double {
            let target = max(1, Int(ceil(Double(count) * fraction)))
            var cumulative = 0
            for (index, frequency) in histogram.enumerated() {
                cumulative += frequency
                if cumulative >= target { return Double(index) / 255 }
            }
            return 1
        }
        let low = percentile(0.10), median = percentile(0.50), high = percentile(0.95)
        var result = Self()
        let exposure = 1.5 * log2(0.46 / max(0.04, median))
        result.exposure = bounded(exposure, -0.85...(high > 0.93 ? 0.20 : 1.10))
        result.shadows = bounded((0.19 - low) * 1.5, 0...0.28)
        result.highlights = -bounded((high - 0.82) * 1.5, 0...0.26)
        result.brilliance = bounded((0.78 - (high - low)) * 0.22, 0...0.17)
        let chroma = chromaSum / Double(count)
        result.vibrance = chroma < 0.025 ? 0 : bounded((0.32 - chroma) * 0.45, 0...0.14)
        return result
    }

    fileprivate var colorSettings: Self {
        var value = self
        value.definition = 0
        value.sharpness = 0
        value.noiseReduction = 0
        value.vignette = 0
        value.monochromeGrain = 0
        if value.monochrome == 0 {
            value.monochromeNeutrals = 0
            value.monochromeTone = 0
        }
        if value.selectiveHue == 0, value.selectiveSaturation == 0, value.selectiveLightness == 0 {
            value.selectiveColor = .red
        }
        return value
    }

    var changesImage: Bool {
        colorSettings != Self() || definition > 0 || sharpness > 0 || noiseReduction > 0 || vignette > 0
    }

    var normalized: Self {
        var result = self
        let signed: [WritableKeyPath<Self, Double>] = [
            \.brilliance, \.highlights, \.shadows, \.brightness, \.contrast, \.blackPoint, \.saturation,
            \.vibrance, \.warmth, \.tint, \.monochromeNeutrals, \.monochromeTone, \.curveShadows,
            \.curveMidtones, \.curveHighlights, \.selectiveHue, \.selectiveSaturation, \.selectiveLightness
        ]
        let unsigned: [WritableKeyPath<Self, Double>] = [
            \.monochrome, \.monochromeGrain, \.definition, \.sharpness, \.noiseReduction, \.vignette
        ]
        for key in signed { result[keyPath: key] = bounded(self[keyPath: key], -1...1) }
        for key in unsigned { result[keyPath: key] = bounded(self[keyPath: key], 0...1) }
        result.exposure = bounded(exposure, -2...2)
        result.levelsBlack = bounded(levelsBlack, 0...0.45)
        result.levelsWhite = bounded(levelsWhite, 0.55...1, fallback: 1)
        result.levelsGamma = bounded(levelsGamma, 0.4...2.5, fallback: 1)
        return result
    }
}

private func bounded(_ number: Double, _ range: ClosedRange<Double>, fallback: Double = 0) -> Double {
    number.isFinite ? min(range.upperBound, max(range.lowerBound, number)) : fallback
}

/// Tone and color use a small interpolated RGB cube in encoded sRGB. Spatial filters
/// run over the oriented photo before its frame, crop, film LUT and print placement.
enum PhotoDevelopment {
    fileprivate static let space = CGColorSpace(name: CGColorSpace.sRGB)!
    fileprivate static let lumaWeights = SIMD3(0.2126, 0.7152, 0.0722)
    private static let dimension = 33

    private final class Key: NSObject {
        let settings: PhotoAdjustments
        init(_ settings: PhotoAdjustments) { self.settings = settings }
        override var hash: Int { settings.hashValue }
        override func isEqual(_ object: Any?) -> Bool { (object as? Key)?.settings == settings }
    }
    private static let cubes: NSCache<Key, FilmCube> = {
        let cache = NSCache<Key, FilmCube>()
        cache.countLimit = 12
        return cache
    }()

    /// Accelerate supplies the neighborhood means. Denoising attenuates small color
    /// variations, while definition and sharpening add luminance detail at two scales.
    static func applySpatial(_ settings: PhotoAdjustments, to bitmap: CGContext) -> Bool {
        guard settings.noiseReduction > 0 || settings.definition > 0 || settings.sharpness > 0 else { return true }
        let width = bitmap.width, height = bitmap.height
        let edge = max(width, height)
        guard let data = bitmap.data, let temporary = malloc(bitmap.bytesPerRow * height) else { return false }
        defer { free(temporary) }
        var source = vImage_Buffer(data: data, height: vImagePixelCount(height), width: vImagePixelCount(width),
                                   rowBytes: bitmap.bytesPerRow)
        var local = vImage_Buffer(data: temporary, height: source.height, width: source.width, rowBytes: source.rowBytes)
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        let blurred = temporary.assumingMemoryBound(to: UInt8.self)
        let passes = [(amount: settings.noiseReduction, radius: max(1, edge / 1600), denoise: true),
                      (amount: settings.definition * 0.85, radius: max(2, edge / 145), denoise: false),
                      (amount: settings.sharpness * 1.75, radius: max(1, edge / 2100), denoise: false)]
        for pass in passes where pass.amount > 0 {
            let radius = min(pass.radius, (min(width, height) - 1) / 2)
            guard radius > 0 else { continue }
            let kernel = UInt32(2 * radius + 1)
            guard vImageTentConvolve_ARGB8888(&source, &local, nil, 0, 0, kernel, kernel,
                                               nil, vImage_Flags(kvImageEdgeExtend)) == kvImageNoError else { return false }
            let amount = Float(pass.amount)
            for i in stride(from: 0, to: width * height * 4, by: 4) where pixels[i+3] != 0 && blurred[i+3] != 0 {
                let alpha = Float(pixels[i+3])
                let rgb = FilmRGB(Float(pixels[i]), Float(pixels[i+1]), Float(pixels[i+2]))
                let mean = FilmRGB(Float(blurred[i]), Float(blurred[i+1]), Float(blurred[i+2])) * (alpha / Float(blurred[i+3]))
                let difference = rgb - mean
                let result: FilmRGB
                if pass.denoise {
                    let similarity = max(0, 1 - simd_abs(difference).max() / (alpha * (0.055 + 0.10*amount)))
                    result = rgb - difference * (amount * similarity)
                } else {
                    let luminance = simd_dot(difference, FilmRGB(0.2126, 0.7152, 0.0722))
                    result = rgb + FilmRGB(repeating: luminance * amount)
                }
                let output = simd_clamp(result, .zero, FilmRGB(repeating: alpha)).rounded(.toNearestOrAwayFromZero)
                pixels[i] = UInt8(output.x)
                pixels[i+1] = UInt8(output.y)
                pixels[i+2] = UInt8(output.z)
            }
        }
        return true
    }

    static func cube(for adjustments: PhotoAdjustments) -> FilmCube? {
        let settings = adjustments.colorSettings
        guard settings != PhotoAdjustments() else { return nil }
        let key = Key(settings)
        if let cached = cubes.object(forKey: key) { return cached }
        let transform = ColorTransform(settings: settings)
        let n = dimension
        var samples = [SIMD4<Float>]()
        samples.reserveCapacity(n * n * n)
        for blue in 0..<n {
            for green in 0..<n {
                for red in 0..<n {
                    let value = transform.color(SIMD3(Double(red), Double(green), Double(blue)) / Double(n - 1))
                    samples.append(SIMD4(Float(value.x), Float(value.y), Float(value.z), 1))
                }
            }
        }
        let cube = FilmCube(size: dimension, samples: samples)
        cubes.setObject(cube, forKey: key)
        return cube
    }

    private struct ColorTransform {
        typealias RGB = SIMD3<Double>
        let settings: PhotoAdjustments
        let channelGain: RGB
        let curves: [Double]
        let selective: Bool

        init(settings s: PhotoAdjustments) {
            settings = s
            // White-balance gains are normalized so a neutral midtone keeps its luminance.
            let balance = RGB(1 + 0.22*s.warmth + 0.10*s.tint, 1 - 0.10*s.tint, 1 - 0.22*s.warmth + 0.10*s.tint)
            channelGain = balance / simd_dot(balance, lumaWeights) * pow(2, s.exposure / 2.2)
            curves = s.curvePoints.map { Double($0.y) }
            selective = s.selectiveHue != 0 || s.selectiveSaturation != 0 || s.selectiveLightness != 0
        }

        func color(_ source: RGB) -> RGB {
            let s = settings
            var rgb = simd_clamp(source * channelGain, .zero, .one)
            let originalY = simd_dot(rgb, lumaWeights)
            var y = bounded((originalY - s.levelsBlack) / (s.levelsWhite - s.levelsBlack), 0...1)
            y = pow(y, 1 / s.levelsGamma)
            let shadows = (1-y)*(1-y), lights = y*y
            y += (s.shadows*shadows + s.highlights*lights) * 3*y*(1-y)
            y += s.brilliance * 2*y*(1-y)*(0.70-y)
            y = (y-0.5) * (1 + s.contrast*0.85) + 0.5 + s.brightness*0.19 - s.blackPoint*0.22*(1-y)*(1-y)
            let position = bounded(y, 0...1) * 4
            let segment = min(3, Int(position))
            y = curves[segment] + (curves[segment+1] - curves[segment]) * (position - Double(segment))
            let chroma = rgb.max() - rgb.min()
            rgb = RGB(repeating: y) + (rgb - RGB(repeating: originalY)) * (1 + s.saturation) * (1 + s.vibrance*(1-chroma)*0.85)
            rgb = simd_clamp(rgb, .zero, .one)
            if selective { rgb = selectedColor(rgb) }
            if s.monochrome > 0 {
                let gray = simd_dot(rgb, lumaWeights)
                let neutral = gray + s.monochromeNeutrals * (0.42*gray*(1-gray) + 0.14*(rgb.x-rgb.z))
                let toned = RGB(repeating: neutral) + RGB(0.12,0.012,-0.11) * (4*neutral*(1-neutral)*s.monochromeTone)
                rgb += (toned-rgb) * s.monochrome
            }
            return simd_clamp(rgb, .zero, .one)
        }

        private func selectedColor(_ rgb: RGB) -> RGB {
            let high = rgb.max(), spread = high - rgb.min()
            guard high > 0, spread > 0.0001 else { return rgb }
            let sector: Double
            if rgb.x == high { sector = (rgb.y-rgb.z)/spread }
            else if rgb.y == high { sector = 2 + (rgb.z-rgb.x)/spread }
            else { sector = 4 + (rgb.x-rgb.y)/spread }
            let hue = (sector*60 + 360).truncatingRemainder(dividingBy: 360)
            let distance = abs(hue - settings.selectiveColor.hue)
            let radius = settings.selectiveColor == .orange ? 31.0 : 52.0
            let proximity = max(0, 1 - min(distance, 360-distance)/radius)
            let weight = proximity*proximity*(3-2*proximity) * min(1, spread/0.12)
            guard weight > 0 else { return rgb }
            let shifted = (hue + 45*settings.selectiveHue*weight + 360).truncatingRemainder(dividingBy: 360) / 60
            let sat = bounded(spread/high * (1 + settings.selectiveSaturation*weight), 0...1)
            let light = settings.selectiveLightness*weight
            let value = light >= 0 ? high + light*(1-high)*0.85 : high*(1+light*0.72)
            let chroma = value*sat
            let x = chroma*(1-abs(shifted.truncatingRemainder(dividingBy: 2)-1))
            let base: RGB
            switch Int(shifted) {
            case 0: base = RGB(chroma,x,0)
            case 1: base = RGB(x,chroma,0)
            case 2: base = RGB(0,chroma,x)
            case 3: base = RGB(0,x,chroma)
            case 4: base = RGB(x,0,chroma)
            default: base = RGB(chroma,0,x)
            }
            return base + RGB(repeating: value-chroma)
        }
    }
}
