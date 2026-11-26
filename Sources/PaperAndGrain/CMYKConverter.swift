import Accelerate
@preconcurrency import ColorSync
import CoreGraphics
import CryptoKit
import Foundation

/// What an ICC file says about itself: the header fields the app checks and the profile's own name.
struct ICCProfileInfo: Hashable, Sendable {
    /// The four-character device class: `prtr` for an output (printer) profile.
    let deviceClass: String
    /// The four-character data color space: `CMYK` for a press profile.
    let colorSpace: String
    /// The profile's description, the name the app shows and never changes.
    let name: String
    /// True when the header's profile ID is zero or matches the MD5 of the profile, as ICC.1 defines it.
    let idMatches: Bool
    /// True when the header carries a profile ID at all; a zero ID checks nothing.
    let hasProfileID: Bool
    let sha256: String

    var isCMYKOutput: Bool { deviceClass == "prtr" && colorSpace == "CMYK" }

    init?(_ data: Data) {
        guard data.count >= 132 else { return nil }
        let bytes = [UInt8](data)
        let declared = Int(bytes[0]) << 24 | Int(bytes[1]) << 16 | Int(bytes[2]) << 8 | Int(bytes[3])
        guard declared == data.count, String(bytes: bytes[36..<40], encoding: .ascii) == "acsp" else { return nil }
        deviceClass = String(bytes: bytes[12..<16], encoding: .ascii) ?? ""
        colorSpace = (String(bytes: bytes[16..<20], encoding: .ascii) ?? "").trimmingCharacters(in: .whitespaces)
        let id = Array(bytes[84..<100])
        hasProfileID = !id.allSatisfy { $0 == 0 }
        if !hasProfileID {
            idMatches = true
        } else {
            var copy = bytes
            for range in [44..<48, 64..<68, 84..<100] { for index in range { copy[index] = 0 } }
            idMatches = Array(Insecure.MD5.hash(data: copy)) == id
        }
        sha256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard let profile = ColorSyncProfileCreate(data as CFData, nil)?.takeRetainedValue() else { return nil }
        name = (ColorSyncProfileCopyDescriptionString(profile)?.takeRetainedValue() as String?) ?? ""
    }
}

/// Converts the finished sRGB print render to a CMYK output profile: relative colorimetric intent with
/// black point compensation, computed once into a 33-step table and applied with vImage. Near-grays
/// (Lab C* ≤ 7) used for text, rules and borders print with black ink only, matched to their lightness.
///
/// ColorSync converts with the relative intent, but its own black point compensation option moves paper
/// white and the hue of neutrals (observed on macOS 27 with FOGRA39 and GRACoL profiles), so the
/// compensation is applied here between two ColorSync transforms, as Adobe and Little CMS define it:
/// in XYZ, `X' = X · (W − B) / W + B` from the sRGB black (zero) to the output profile's black.
final class CMYKConverter: @unchecked Sendable {
    enum Failure: Error { case notCMYKOutput, transform }

    let profileData: Data
    let info: ICCProfileInfo
    let space: CGColorSpace
    private let toLab: ColorSyncTransform
    private let fromLab: ColorSyncTransform
    private let blackXYZ: (Double, Double, Double)
    private let table: vImage_MultidimensionalTable
    /// L* of black ink alone at 1024 steps, for neutral grays.
    private let blackInkL: [Double]
    private let lock = NSLock()
    private var cache = [UInt32: [Double]]()
    private var inkCache = [UInt32: [CGFloat]]()

    static let gridSize = 33
    private static let whiteD50 = (0.9642, 1.0, 0.8249)

    init(profile data: Data) throws {
        guard let info = ICCProfileInfo(data), info.isCMYKOutput, let space = CGColorSpace(iccData: data as CFData)
        else { throw Failure.notCMYKOutput }
        profileData = data
        self.info = info
        self.space = space
        guard let cmyk = ColorSyncProfileCreate(data as CFData, nil)?.takeRetainedValue(),
              let srgb = ColorSyncProfileCreateWithName(kColorSyncSRGBProfile.takeUnretainedValue())?.takeRetainedValue(),
              let lab = ColorSyncProfileCreateWithName(kColorSyncGenericLabProfile.takeUnretainedValue())?.takeRetainedValue(),
              let toLab = Self.transform(srgb, lab), let fromLab = Self.transform(lab, cmyk),
              let inkToLab = Self.transform(cmyk, lab) else { throw Failure.transform }
        self.toLab = toLab
        self.fromLab = fromLab
        // The output black point: Lab 0 through the profile and back, keeping only its lightness.
        let darkest = Self.run(fromLab, [0, 128.0 / 255, 128.0 / 255], inChannels: 3, outChannels: 4)
        let black = Self.run(inkToLab, darkest, inChannels: 4, outChannels: 3)
        blackXYZ = Self.xyz(fromLab: (Double(black[0]) * 100, 0, 0))
        var ink = [Float]()
        for step in 0...1023 { ink += [0, 0, 0, Float(step) / 1023] }
        let inkLab = Self.run(inkToLab, ink, inChannels: 4, outChannels: 3)
        blackInkL = stride(from: 0, to: inkLab.count, by: 3).map { Double(inkLab[$0]) * 100 }
        // The table: vImage reads the entries as 16-bit fractions (65535 = 1) and writes 16Q12 planes.
        let n = Self.gridSize
        var grid = [Float]()
        grid.reserveCapacity(n * n * n * 3)
        for r in 0..<n { for g in 0..<n { for b in 0..<n {
            grid += [Float(r) / Float(n - 1), Float(g) / Float(n - 1), Float(b) / Float(n - 1)]
        } } }
        let converted = Self.pipeline(grid, toLab: toLab, fromLab: fromLab, black: blackXYZ)
        let fixed = converted.map { UInt16(max(0, min(65535, ($0 * 65535).rounded()))) }
        var error = vImage_Error(kvImageNoError)
        guard let table = fixed.withUnsafeBufferPointer({ buffer in
            [UInt8](repeating: UInt8(n), count: 3).withUnsafeBufferPointer { entries in
                vImageMultidimensionalTable_Create(buffer.baseAddress!, 3, 4, entries.baseAddress!,
                                                   kvImageMDTableHint_16Q12, vImage_Flags(kvImageNoFlags), &error)
            }
        }), error == kvImageNoError else { throw Failure.transform }
        self.table = table
    }

    deinit { vImageMultidimensionalTable_Release(table) }

    /// The profile's description, as shown in menus and written in the output intent.
    var name: String { info.name }

    // MARK: Solid colors

    /// CMYK from 0 to 1 for an sRGB color, through the profile (with black point compensation).
    func cmyk(red: Double, green: Double, blue: Double) -> [Double] {
        let key = UInt32((red * 255).rounded()) << 16 | UInt32((green * 255).rounded()) << 8 | UInt32((blue * 255).rounded())
        lock.lock()
        defer { lock.unlock() }
        if let known = cache[key] { return known }
        let value = Self.pipeline([Float(red), Float(green), Float(blue)], toLab: toLab, fromLab: fromLab, black: blackXYZ)
            .map { Double(max(0, min(1, $0))) }
        cache[key] = value
        return value
    }

    /// The largest Lab chroma (C*) a text, rule or border color may have to print with black ink only.
    /// Template inks are warm or cool dark grays up to C* 6.8 (Road Log's caption ink); a color with
    /// C* above 7 is visibly tinted and keeps its four inks.
    static let neutralChroma = 7.0

    /// CIELAB (D50) of an sRGB color, through ColorSync.
    func lab(red: Double, green: Double, blue: Double) -> (L: Double, a: Double, b: Double) {
        let lab = Self.run(toLab, [Float(red), Float(green), Float(blue)], inChannels: 3, outChannels: 3)
        return (Double(lab[0]) * 100, Double(lab[1]) * 255 - 128, Double(lab[2]) * 255 - 128)
    }

    /// True for the near-grays text, rules and borders use: Lab chroma at most `neutralChroma`.
    func isNeutral(red: Double, green: Double, blue: Double) -> Bool {
        let value = lab(red: red, green: green, blue: blue)
        return hypot(value.a, value.b) <= Self.neutralChroma
    }

    /// Black ink alone matching a lightness L* (0 to 100), after black point compensation.
    func blackInk(lightness: Double) -> Double {
        let target = Self.lab(fromXYZ: Self.compensate(Self.xyz(fromLab: (lightness, 0, 0)), black: blackXYZ)).0
        // Black ink gets darker as it grows: the first step at least as dark as the target.
        let index = blackInkL.firstIndex { $0 <= target + 0.0001 } ?? blackInkL.count - 1
        return Double(index) / Double(blackInkL.count - 1)
    }

    /// Black ink alone for a gray value of sRGB (0 to 1).
    func blackInk(gray: Double) -> Double { blackInk(lightness: lab(red: gray, green: gray, blue: gray).L) }

    func color(red: Double, green: Double, blue: Double, alpha: Double = 1, blackOnly: Bool) -> CGColor {
        let key = UInt32((red * 255).rounded()) << 16 | UInt32((green * 255).rounded()) << 8 | UInt32((blue * 255).rounded())
        lock.lock()
        let known = blackOnly ? inkCache[key] : nil
        lock.unlock()
        let components: [CGFloat]
        if let known {
            components = known
        } else if blackOnly && isNeutral(red: red, green: green, blue: blue) {
            components = [0, 0, 0, CGFloat(blackInk(lightness: lab(red: red, green: green, blue: blue).L))]
        } else {
            components = cmyk(red: red, green: green, blue: blue).map { CGFloat($0) }
        }
        if blackOnly && known == nil {
            lock.lock()
            inkCache[key] = components
            lock.unlock()
        }
        return CGColor(colorSpace: space, components: components + [CGFloat(alpha)])
            ?? CGColor(colorSpace: space, components: [0, 0, 0, 1, CGFloat(alpha)])!
    }

    // MARK: Images

    /// The image in the output profile: the same pixels converted through the table, in strips so memory
    /// stays small. The result is an 8-bit CMYK bitmap tagged with the profile.
    func convert(_ image: CGImage) -> CGImage? {
        let width = image.width, height = image.height
        guard width > 0, height > 0,
              let source = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                     space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                     bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let output = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                     space: space, bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let rgba = source.data, let cmyk = output.data else { return nil }
        source.interpolationQuality = .none
        source.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let strip = 128
        let count = width * strip
        // Seven planes in one allocation: R, G, B in, C, M, Y, K out.
        var planes = [UInt16](repeating: 0, count: count * 7)
        var row = 0
        while row < height {
            let rows = min(strip, height - row)
            let pixels = width * rows
            let input = rgba.advanced(by: row * width * 4).assumingMemoryBound(to: UInt8.self)
            let out = cmyk.advanced(by: row * width * 4).assumingMemoryBound(to: UInt8.self)
            let ok = planes.withUnsafeMutableBufferPointer { all -> Bool in
                guard let base = all.baseAddress else { return false }
                for index in 0..<pixels {
                    // 8-bit to 16Q12: v · 4096 / 255.
                    base[index] = UInt16((UInt32(input[index * 4]) * 4096 + 127) / 255)
                    base[count + index] = UInt16((UInt32(input[index * 4 + 1]) * 4096 + 127) / 255)
                    base[2 * count + index] = UInt16((UInt32(input[index * 4 + 2]) * 4096 + 127) / 255)
                }
                func buffer(_ plane: Int) -> vImage_Buffer {
                    vImage_Buffer(data: base + plane * count, height: vImagePixelCount(rows), width: vImagePixelCount(width),
                                  rowBytes: width * 2)
                }
                var sources = [buffer(0), buffer(1), buffer(2)]
                var destinations = [buffer(3), buffer(4), buffer(5), buffer(6)]
                guard vImageMultiDimensionalInterpolatedLookupTable_Planar16Q12(
                    &sources, &destinations, nil, table, kvImageFullInterpolation, vImage_Flags(kvImageNoFlags)) == kvImageNoError
                else { return false }
                for index in 0..<pixels {
                    for channel in 0..<4 {
                        out[index * 4 + channel] = UInt8((UInt32(min(4096, base[(3 + channel) * count + index])) * 255 + 2048) / 4096)
                    }
                }
                return true
            }
            guard ok else { return nil }
            row += rows
        }
        return output.makeImage()
    }

    // MARK: Pipeline

    private static func transform(_ source: ColorSyncProfile, _ destination: ColorSyncProfile) -> ColorSyncTransform? {
        let intent = kColorSyncRenderingIntentRelative.takeUnretainedValue()
        let profileKey = kColorSyncProfile.takeUnretainedValue() as String
        let intentKey = kColorSyncRenderingIntent.takeUnretainedValue() as String
        let tagKey = kColorSyncTransformTag.takeUnretainedValue() as String
        let sequence: [[String: Any]] = [
            [profileKey: source, intentKey: intent, tagKey: kColorSyncTransformDeviceToPCS.takeUnretainedValue()],
            [profileKey: destination, intentKey: intent, tagKey: kColorSyncTransformPCSToDevice.takeUnretainedValue()],
        ]
        return ColorSyncTransformCreate(sequence as CFArray, nil)?.takeRetainedValue()
    }

    private static func run(_ transform: ColorSyncTransform, _ values: [Float], inChannels: Int, outChannels: Int) -> [Float] {
        let pixels = values.count / inChannels
        var input = values
        var output = [Float](repeating: 0, count: pixels * outChannels)
        let layout = ColorSyncDataLayout(UInt32(kColorSyncByteOrderDefault) | kColorSyncAlphaNone.rawValue)
        _ = ColorSyncTransformConvert(transform, pixels, 1, &output, kColorSync32BitFloat, layout, pixels * outChannels * 4,
                                      &input, kColorSync32BitFloat, layout, pixels * inChannels * 4, nil)
        return output
    }

    /// sRGB to Lab, black point compensation in XYZ, Lab to CMYK.
    private static func pipeline(_ rgb: [Float], toLab: ColorSyncTransform, fromLab: ColorSyncTransform,
                                 black: (Double, Double, Double)) -> [Float] {
        // ColorSync's float Lab is encoded: L / 100, (a + 128) / 255, (b + 128) / 255.
        var lab = run(toLab, rgb, inChannels: 3, outChannels: 3)
        for index in stride(from: 0, to: lab.count, by: 3) {
            let decoded = (Double(lab[index]) * 100, Double(lab[index + 1]) * 255 - 128, Double(lab[index + 2]) * 255 - 128)
            let compensated = Self.lab(fromXYZ: compensate(xyz(fromLab: decoded), black: black))
            lab[index] = Float(compensated.0 / 100)
            lab[index + 1] = Float((compensated.1 + 128) / 255)
            lab[index + 2] = Float((compensated.2 + 128) / 255)
        }
        return run(fromLab, lab, inChannels: 3, outChannels: 4)
    }

    private static func compensate(_ xyz: (Double, Double, Double), black: (Double, Double, Double)) -> (Double, Double, Double) {
        let w = whiteD50
        return (xyz.0 * (w.0 - black.0) / w.0 + black.0,
                xyz.1 * (w.1 - black.1) / w.1 + black.1,
                xyz.2 * (w.2 - black.2) / w.2 + black.2)
    }

    private static func xyz(fromLab lab: (Double, Double, Double)) -> (Double, Double, Double) {
        let fy = (lab.0 + 16) / 116, fx = fy + lab.1 / 500, fz = fy - lab.2 / 200
        func f(_ t: Double) -> Double { t > 6.0 / 29 ? t * t * t : 3 * pow(6.0 / 29, 2) * (t - 4.0 / 29) }
        return (whiteD50.0 * f(fx), whiteD50.1 * f(fy), whiteD50.2 * f(fz))
    }

    private static func lab(fromXYZ xyz: (Double, Double, Double)) -> (Double, Double, Double) {
        func f(_ t: Double) -> Double { t > pow(6.0 / 29, 3) ? cbrt(t) : t / (3 * pow(6.0 / 29, 2)) + 4.0 / 29 }
        let fx = f(xyz.0 / whiteD50.0), fy = f(xyz.1 / whiteD50.1), fz = f(xyz.2 / whiteD50.2)
        return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }
}
