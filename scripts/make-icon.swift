// Renders the Paper & Grain app icon with Core Graphics.
//
//   swift scripts/make-icon.swift <variant> <output.png> [size]
//   swift scripts/make-icon.swift sheet <output.png>          (all variants, light and dark, several sizes)
//   swift scripts/make-icon.swift iconset AppIcon.iconset prints && iconutil -c icns AppIcon.iconset -o Resources/AppIcon.icns
//
// The app uses the "prints" variant.
// Variants: "book" (an open photobook on pine green) and "prints" (two stacked prints on paper).
// The drawing follows the macOS icon grid: an 824 px rounded square centred on a 1024 px canvas.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let pine = color(0x23503B)
let pineLight = color(0x3B7A5A)
let pineDark = color(0x173826)
let paper = color(0xF6F3EC)
let paperShade = color(0xE8E0D0)
let ink = color(0x2A2622)

/// Core Graphics draws shadows in device pixels, ignoring the transform: scale them by hand.
var shadowScale: CGFloat = 1

func shadow(_ ctx: CGContext, y: CGFloat, blur: CGFloat, _ shade: CGColor) {
    ctx.setShadow(offset: CGSize(width: 0, height: -y * shadowScale), blur: blur * shadowScale, color: shade)
}

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// A superellipse close to the macOS icon shape.
func iconShape(in rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2, n: CGFloat = 5
    for step in 0...720 {
        let t = CGFloat(step) / 720 * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = rect.midX + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = rect.midY + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        if step == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

func linear(_ ctx: CGContext, _ colors: [CGColor], from: CGPoint, to: CGPoint) {
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

/// Deterministic film grain: many tiny dots with low alpha.
func grain(_ ctx: CGContext, in rect: CGRect, light: Bool, amount: Int) {
    var seed: UInt64 = 0x9E3779B97F4A7C15
    func next() -> CGFloat {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(seed >> 33) / CGFloat(1 << 31)
    }
    for _ in 0..<amount {
        let x = rect.minX + next() * rect.width, y = rect.minY + next() * rect.height
        let r = 0.7 + next() * 1.6
        ctx.setFillColor(light ? color(0xFFFFFF, 0.05 + next() * 0.07) : color(0x000000, 0.03 + next() * 0.06))
        ctx.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
    }
}

/// A small landscape: warm sky, low sun and dunes. Drawn inside `rect` (top-left origin).
func landscape(_ ctx: CGContext, in rect: CGRect) {
    ctx.saveGState()
    ctx.clip(to: rect)
    linear(ctx, [color(0xF4D9A6), color(0xEFA866), color(0xE07B45)],
           from: CGPoint(x: rect.midX, y: rect.minY), to: CGPoint(x: rect.midX, y: rect.maxY))
    let sun = rect.width * 0.17
    ctx.setFillColor(color(0xFFF3D6, 0.95))
    ctx.fillEllipse(in: CGRect(x: rect.minX + rect.width * 0.60, y: rect.minY + rect.height * 0.30, width: sun, height: sun))
    func dune(_ base: CGFloat, _ peak: CGFloat, _ shift: CGFloat, _ fill: CGColor) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * base))
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * (base - 0.04)),
                      control1: CGPoint(x: rect.minX + rect.width * shift, y: rect.minY + rect.height * peak),
                      control2: CGPoint(x: rect.minX + rect.width * (shift + 0.35), y: rect.minY + rect.height * (base + 0.08)))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        ctx.addPath(path)
        ctx.setFillColor(fill)
        ctx.fillPath()
    }
    dune(0.66, 0.40, 0.18, color(0xC9733A))
    dune(0.82, 0.58, 0.45, color(0x9A4E25))
    ctx.restoreGState()
}

/// Variant "book": an open photobook on a pine green tile.
func drawBook(_ ctx: CGContext) {
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = iconShape(in: tile)
    ctx.saveGState()
    shadow(ctx, y: 10, blur: 24, color(0x000000, 0.28))
    ctx.addPath(shape); ctx.setFillColor(pine); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    linear(ctx, [pineLight, pine, pineDark], from: CGPoint(x: 512, y: 100), to: CGPoint(x: 512, y: 924))
    grain(ctx, in: tile, light: true, amount: 26000)

    // Book: two pages that rise slightly towards the outer edges.
    let spine = CGPoint(x: 512, y: 338)
    let pageWidth: CGFloat = 300, pageHeight: CGFloat = 390, lift: CGFloat = 26
    func page(left: Bool) -> CGPath {
        let d: CGFloat = left ? -1 : 1
        let p = CGMutablePath()
        p.move(to: spine)
        p.addQuadCurve(to: CGPoint(x: spine.x + d * pageWidth, y: spine.y - lift),
                       control: CGPoint(x: spine.x + d * pageWidth * 0.5, y: spine.y + 6))
        p.addLine(to: CGPoint(x: spine.x + d * pageWidth, y: spine.y - lift + pageHeight))
        p.addQuadCurve(to: CGPoint(x: spine.x, y: spine.y + pageHeight),
                       control: CGPoint(x: spine.x + d * pageWidth * 0.5, y: spine.y + pageHeight + 6))
        p.closeSubpath()
        return p
    }
    // Block of pages under the cover edge.
    ctx.saveGState()
    shadow(ctx, y: 18, blur: 30, color(0x000000, 0.35))
    for left in [true, false] {
        ctx.saveGState()
        ctx.translateBy(x: 0, y: 14)
        ctx.addPath(page(left: left)); ctx.setFillColor(paperShade); ctx.fillPath()
        ctx.restoreGState()
    }
    ctx.restoreGState()
    for left in [true, false] {
        ctx.addPath(page(left: left)); ctx.setFillColor(paper); ctx.fillPath()
    }
    // Gutter shadow.
    ctx.saveGState()
    ctx.addPath(page(left: true)); ctx.addPath(page(left: false)); ctx.clip()
    linear(ctx, [color(0x000000, 0), color(0x000000, 0.16), color(0x000000, 0)],
           from: CGPoint(x: 470, y: 0), to: CGPoint(x: 554, y: 0))
    ctx.restoreGState()

    // Left page: heading and lines of text.
    ctx.setFillColor(color(0x2A2622, 0.85))
    ctx.fill(CGRect(x: 268, y: 406, width: 150, height: 20))
    ctx.setFillColor(color(0x2A2622, 0.32))
    for (i, w) in [196, 210, 188, 205, 150, 198, 176].enumerated() {
        ctx.fill(CGRect(x: 268, y: 456 + CGFloat(i) * 34, width: CGFloat(w), height: 11))
    }
    // Right page: a photo with a thin border.
    let photo = CGRect(x: 560, y: 390, width: 214, height: 286)
    landscape(ctx, in: photo)
    ctx.restoreGState()
}

/// Variant "prints": two stacked prints with a pine bookmark on a paper tile.
func drawPrints(_ ctx: CGContext) {
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = iconShape(in: tile)
    ctx.saveGState()
    shadow(ctx, y: 10, blur: 24, color(0x000000, 0.25))
    ctx.addPath(shape); ctx.setFillColor(paper); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    linear(ctx, [color(0xFBF8F2), paper, color(0xEAE2D2)], from: CGPoint(x: 512, y: 100), to: CGPoint(x: 512, y: 924))
    grain(ctx, in: tile, light: false, amount: 26000)

    func print(center: CGPoint, angle: CGFloat, withPhoto: Bool) {
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: angle)
        let card = CGRect(x: -230, y: -280, width: 460, height: 560)
        shadow(ctx, y: 14, blur: 26, color(0x3A2A18, 0.30))
        ctx.setFillColor(color(0xFFFDF8)); ctx.fill(card)
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        if withPhoto {
            landscape(ctx, in: CGRect(x: card.minX + 34, y: card.minY + 34, width: card.width - 68, height: 350))
            ctx.setFillColor(color(0x2A2622, 0.78))
            ctx.fill(CGRect(x: card.minX + 34, y: card.minY + 420, width: 190, height: 22))
            ctx.setFillColor(color(0x2A2622, 0.30))
            ctx.fill(CGRect(x: card.minX + 34, y: card.minY + 462, width: 300, height: 12))
            ctx.fill(CGRect(x: card.minX + 34, y: card.minY + 490, width: 250, height: 12))
        } else {
            ctx.setFillColor(color(0xE6DDCB)); ctx.fill(card.insetBy(dx: 34, dy: 34))
        }
        ctx.restoreGState()
    }
    print(center: CGPoint(x: 540, y: 500), angle: 0.13, withPhoto: false)
    print(center: CGPoint(x: 492, y: 522), angle: -0.05, withPhoto: true)

    // Pine bookmark ribbon hanging from the top edge of the front print.
    ctx.saveGState()
    ctx.translateBy(x: 492, y: 522); ctx.rotate(by: -0.05)
    let ribbon = CGMutablePath()
    ribbon.move(to: CGPoint(x: 120, y: -300))
    ribbon.addLine(to: CGPoint(x: 178, y: -300))
    ribbon.addLine(to: CGPoint(x: 178, y: -136))
    ribbon.addLine(to: CGPoint(x: 149, y: -164))
    ribbon.addLine(to: CGPoint(x: 120, y: -136))
    ribbon.closeSubpath()
    shadow(ctx, y: 4, blur: 8, color(0x000000, 0.25))
    ctx.addPath(ribbon); ctx.setFillColor(pine); ctx.fillPath()
    ctx.restoreGState()
    ctx.restoreGState()
}

func render(_ variant: String, size: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    shadowScale = CGFloat(size) / 1024
    // Draw in 1024 units with a top-left origin.
    ctx.translateBy(x: 0, y: CGFloat(size))
    ctx.scaleBy(x: CGFloat(size) / 1024, y: -CGFloat(size) / 1024)
    switch variant {
    case "book": drawBook(ctx)
    case "prints": drawPrints(ctx)
    default: fatalError("Unknown variant \(variant); use book or prints")
    }
    return ctx.makeImage()!
}

func write(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("Cannot write \(path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Cannot write \(path)") }
}

/// Each variant on a light and a dark background at 384, 128, 64, 32 and 16 px, as in Finder and the Dock.
func sheet() -> CGImage {
    let width = 1600, rowHeight = 470, height = rowHeight * 2
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    for (row, variant) in ["book", "prints"].enumerated() {
        let y = height - (row + 1) * rowHeight
        for (column, background) in [color(0xECEAE4), color(0x1E1E1E)].enumerated() {
            let x = column * width / 2
            ctx.setFillColor(background)
            ctx.fill(CGRect(x: x, y: y, width: width / 2, height: rowHeight))
            ctx.draw(render(variant, size: 384), in: CGRect(x: x + 30, y: y + 43, width: 384, height: 384))
            ctx.draw(render(variant, size: 128), in: CGRect(x: x + 450, y: y + 171, width: 128, height: 128))
            ctx.draw(render(variant, size: 64), in: CGRect(x: x + 610, y: y + 203, width: 64, height: 64))
            ctx.draw(render(variant, size: 32), in: CGRect(x: x + 700, y: y + 219, width: 32, height: 32))
            ctx.draw(render(variant, size: 16), in: CGRect(x: x + 755, y: y + 227, width: 16, height: 16))
        }
    }
    return ctx.makeImage()!
}

let arguments = CommandLine.arguments.dropFirst()
guard arguments.count >= 2 else {
    fputs("usage: make-icon.swift <book|prints|sheet> <output.png> [size]\n       make-icon.swift iconset <output.iconset> [book|prints]\n", stderr)
    exit(2)
}
let variant = arguments[arguments.startIndex], output = arguments[arguments.startIndex + 1]
if variant == "iconset" {
    // Every size drawn natively, so small icons stay sharp; then `iconutil -c icns` builds the .icns.
    let chosen = arguments.count > 2 ? arguments[arguments.startIndex + 2] : "prints"
    try? FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
    for base in [16, 32, 128, 256, 512] {
        write(render(chosen, size: base), to: "\(output)/icon_\(base)x\(base).png")
        write(render(chosen, size: base * 2), to: "\(output)/icon_\(base)x\(base)@2x.png")
    }
} else if variant == "sheet" {
    write(sheet(), to: output)
} else {
    let size = arguments.count > 2 ? Int(arguments[arguments.startIndex + 2]) ?? 1024 : 1024
    write(render(variant, size: size), to: output)
}
