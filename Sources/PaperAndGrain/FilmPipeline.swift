import Foundation
import CoreGraphics
import simd
import ImageIO

enum FilmPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case original, documentary, warmNegative, monochrome, custom
    var id: String { rawValue }
}

struct FilmSettings: Codable, Hashable, Sendable {
    var preset: FilmPreset = .original
    var strength: Double = 1
    var grain: Double = 0
    var grainSize: Double = 0.5
    var lutFilename: String? = nil
}

private typealias RGB = SIMD3<Float>

private struct LUTError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private final class FilmCube {
    let size: Int
    let samples: [SIMD4<Float>]
    let low: RGB
    let high: RGB

    init(size: Int, samples: [SIMD4<Float>], low: RGB = .zero, high: RGB = .one) {
        self.size = size
        self.samples = samples
        self.low = low
        self.high = high
    }
}

enum FilmRenderer {
    // ColorSync converts embedded profiles (including Display P3) to SDR sRGB.
    // Cube coordinates, interpolation, blending and grain use encoded sRGB.
    private static let space = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let cache: NSCache<NSString, FilmCube> = {
        let cache = NSCache<NSString, FilmCube>()
        cache.totalCostLimit = 80 * 1024 * 1024
        return cache
    }()

    static func validateLUT(at url: URL) throws { _ = try cube(at: url) }

    private static func cube(at url: URL) throws -> FilmCube {
        let info = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        guard let bytes = info.fileSize, bytes <= 160 * 1024 * 1024 else {
            throw LUTError(message: "LUT exceeds the 160 MB limit.")
        }
        let key = "\(url.standardizedFileURL.path)|\(bytes)|\(info.contentModificationDate?.timeIntervalSince1970 ?? 0)" as NSString
        if let stored = cache.object(forKey: key) { return stored }
        let result: FilmCube
        switch url.pathExtension.lowercased() {
        case "cube": result = try parseCube(url)
        case "png": result = try parseHald(url)
        default: throw LUTError(message: "Choose a 3D .cube file or a square Hald CLUT PNG.")
        }
        cache.setObject(result, forKey: key, cost: result.samples.count * 16)
        return result
    }

    private static func parseCube(_ url: URL) throws -> FilmCube {
        let file = try String(contentsOf: url, encoding: .utf8)
        var size = 0
        var samples: [SIMD4<Float>] = []
        var low = RGB.zero, high = RGB.one
        var seen = Set<String>()
        for (index, raw) in file.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }).enumerated() {
            let fields = raw.prefix { $0 != "#" }.split(whereSeparator: { $0.isWhitespace })
            guard let head = fields.first else { continue }
            let error = LUTError(message: "Invalid CUBE data or directive on line \(index + 1).")
            func triple(_ values: ArraySlice<Substring>) throws -> RGB {
                guard values.count == 3, let r = Float(values[values.startIndex]),
                      let g = Float(values[values.startIndex+1]), let b = Float(values[values.startIndex+2]),
                      abs(r) <= 65_504, abs(g) <= 65_504, abs(b) <= 65_504 else { throw error }
                return RGB(r,g,b)
            }
            switch head {
            case "TITLE": continue
            case "LUT_3D_SIZE":
                guard size == 0, fields.count == 2, let n = Int(fields[1]), (2...128).contains(n) else {
                    throw LUTError(message: "Expected one 3D cube dimension between 2 and 128.")
                }
                size = n
                samples.reserveCapacity(n*n*n)
            case "DOMAIN_MIN", "DOMAIN_MAX":
                guard samples.isEmpty, seen.insert(String(head)).inserted else { throw error }
                let value = try triple(fields.dropFirst())
                if head == "DOMAIN_MIN" { low = value } else { high = value }
            default:
                guard size > 0, samples.count < size*size*size else { throw error }
                samples.append(SIMD4(try triple(fields[...]), 1))
            }
        }
        guard size > 0, samples.count == size*size*size else {
            throw LUTError(message: "Incomplete CUBE table. Expected \(size*size*size) RGB rows and found \(samples.count).")
        }
        guard (0..<3).allSatisfy({ high[$0] > low[$0] && (Float(size-1) / (high[$0]-low[$0])).isFinite }) else {
            throw LUTError(message: "Each DOMAIN_MAX channel must exceed DOMAIN_MIN.")
        }
        return FilmCube(size: size, samples: samples, low: low, high: high)
    }

    private static func parseHald(_ url: URL) throws -> FilmCube {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetType(src) as String? == "public.png",
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int,
              w == h, let level = (2...11).first(where: { $0*$0*$0 == w }),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw LUTError(message: "A Hald PNG must be square with side length level³ (levels 2–11).")
        }
        // Hald values are data. Ignore PNG gamma/ICC transforms when reading them.
        guard let rgb = image.copy(colorSpace: space) else {
            throw LUTError(message: "The Hald PNG must contain RGB samples.")
        }
        let format = CGBitmapInfo.byteOrder16Little.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let bitmap = CGContext(data: nil, width: w, height: h, bitsPerComponent: 16, bytesPerRow: w*8,
                                     space: space, bitmapInfo: format), let data = bitmap.data else {
            throw LUTError(message: "Unable to decode Hald RGB samples.")
        }
        bitmap.draw(rgb, in: CGRect(x: 0, y: 0, width: w, height: h))
        let buffer = data.bindMemory(to: UInt16.self, capacity: w*h*4)
        var pixels: [SIMD4<Float>] = []
        pixels.reserveCapacity(w*h)
        for i in stride(from: 0, to: w*h*4, by: 4) {
            guard buffer[i+3] == .max else { throw LUTError(message: "The Hald PNG must be opaque.") }
            pixels.append(SIMD4(Float(buffer[i])/65535, Float(buffer[i+1])/65535, Float(buffer[i+2])/65535, 1))
        }
        return FilmCube(size: level*level, samples: pixels)
    }

    private static let looks: [FilmPreset: FilmCube] = {
        var result: [FilmPreset: FilmCube] = [:]
        for preset in [FilmPreset.documentary, .warmNegative, .monochrome] {
            var samples: [SIMD4<Float>] = []
            for b in 0...16 { for g in 0...16 { for r in 0...16 {
                let color = RGB(Float(r),Float(g),Float(b))/16
                let luma = color.x*0.2126 + color.y*0.7152 + color.z*0.0722
                let neutral = RGB(repeating: luma)
                let toe = Float(1)-luma
                let output: RGB
                switch preset {
                case .documentary:
                    let contrast = 0.11 * luma * toe * (2*luma-1)
                    output = neutral + (color-neutral)*0.82 + RGB(repeating: contrast) + RGB(-0.008,0,0.013)*toe
                case .warmNegative:
                    let muted = neutral + (color-neutral)*0.9
                    output = muted*0.93 + RGB(0.035,0.021,0.029) + RGB(0.033,0.011,-0.023)*luma
                default:
                    let gray = 0.29*color.x + 0.58*color.y + 0.13*color.z
                    output = RGB(repeating: 0.012 + gray*0.974 + 0.29*gray*(1-gray)*(2*gray-1))
                }
                samples.append(SIMD4(output,1))
            }}}
            result[preset] = FilmCube(size: 17, samples: samples)
        }
        return result
    }()

    static func image(from url: URL, maxPixelSize: Int, settings: FilmSettings, lutURL: URL?) -> CGImage? {
        guard maxPixelSize > 0, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
              ] as CFDictionary) else { return nil }
        let strength = max(0,min(1,settings.strength))
        let grain = max(0,min(1,settings.grain))
        if (settings.preset == .original || strength == 0), grain == 0,
           image.colorSpace?.name == CGColorSpace.sRGB, image.bitsPerComponent == 8 { return image }
        let table: FilmCube?
        if settings.preset == .custom, strength > 0 {
            guard let lutURL, let loaded = try? cube(at: lutURL) else { return nil }
            table = loaded
        } else { table = strength > 0 ? looksForPreset(settings.preset) : nil }

        let w = image.width, h = image.height
        let format = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let bitmap = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w*4,
                                     space: space, bitmapInfo: format), let data = bitmap.data else { return nil }
        bitmap.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard table != nil || grain > 0 else { return bitmap.makeImage() }
        let buffer = data.bindMemory(to: UInt8.self, capacity: w*h*4)
        let factor = Float(strength)
        let scale = table.map { RGB(repeating: Float($0.size-1)) / ($0.high-$0.low) } ?? .zero
        // Grain coordinates cover the entire oriented image before any page cropping.
        let pitch = Float(max(w,h))/2400 * Float(0.8 + 3.2*max(0,min(1,settings.grainSize)))
        let noiseAmplitude = Float(grain*0.18)
        for y in 0..<h {
            for x in 0..<w {
                let i = (w*y+x)*4
                let alpha = Float(buffer[i+3])
                guard alpha > 0 else { continue }
                var color = RGB(Float(buffer[i]),Float(buffer[i+1]),Float(buffer[i+2])) / alpha
                if let table {
                    let position = simd_clamp((color-table.low)*scale, .zero, RGB(repeating:Float(table.size-1)))
                    let ix = min(Int(position.x),table.size-2)
                    let iy = min(Int(position.y),table.size-2)
                    let iz = min(Int(position.z),table.size-2)
                    let fraction = position - RGB(Float(ix),Float(iy),Float(iz))
                    let n = table.size
                    let base = ix + n*(iy+n*iz)
                    func row(_ offset: Int) -> SIMD4<Float> {
                        let a = table.samples[base+offset]
                        return a + (table.samples[base+offset+1]-a)*fraction.x
                    }
                    let lower = row(0), upper = row(n*n)
                    let a = lower + (row(n)-lower)*fraction.y
                    let b = upper + (row(n*n+n)-upper)*fraction.y
                    let mix = a + (b-a)*fraction.z
                    color += (RGB(mix.x,mix.y,mix.z)-color)*factor
                }
                if grain > 0 {
                    let gx = (Float(x)+0.5)/pitch, gy = (Float(y)+0.5)/pitch
                    let ix = Int(gx), iy = Int(gy)
                    let fx = gx-Float(ix), fy = gy-Float(iy)
                    func noise(_ dx: Int, _ dy: Int) -> Float {
                        noiseTile[((ix+dx)&255) + (((iy+dy)&255)<<8)]
                    }
                    let a = noise(0,0)*(1-fx) + noise(1,0)*fx
                    let b = noise(0,1)*(1-fx) + noise(1,1)*fx
                    color += RGB(repeating: (a*(1-fy)+b*fy)*noiseAmplitude)
                }
                let output = simd_clamp(color,.zero,.one)*alpha
                buffer[i] = UInt8(output.x.rounded())
                buffer[i+1] = UInt8(output.y.rounded())
                buffer[i+2] = UInt8(output.z.rounded())
            }
        }
        return bitmap.makeImage()
    }

    private static func looksForPreset(_ preset: FilmPreset) -> FilmCube? {
        preset == .original ? nil : looks[preset]
    }

    private static let noiseTile: [Float] = {
        var random: UInt32 = 0x76ae155d
        return (0..<65536).map { _ in
            random ^= random << 13
            random ^= random >> 17
            random ^= random << 5
            return Float(UInt8(truncatingIfNeeded: random))/255 - 0.5
        }
    }()
}
