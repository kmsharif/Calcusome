// Renders every AppIcon PNG into the asset catalog. Run from apple/App:
//   swift Icon/make_icon.swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let out = URL(fileURLWithPath: "Resources/Assets.xcassets/AppIcon.appiconset")
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: srgb, components: [r, g, b, a])!
}

// Graphite theme colors (see Sources/Theme.swift).
let orange = rgb(1.0, 0.55, 0.1)
let pink = rgb(1.0, 0.35, 0.6)
let graphiteTop = rgb(0.19, 0.19, 0.21)
let graphiteBottom = rgb(0.06, 0.06, 0.07)

enum Style { case light, dark, tinted }

/// Draws the 1024-unit design into `rect` (top-left origin): an equals sign with an orange→pink sweep.
func drawArt(_ ctx: CGContext, in rect: CGRect, style: Style, background: Bool) {
    let s = rect.width / 1024
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }

    if background {
        let bg: [CGColor] = style == .light ? [graphiteTop, graphiteBottom] : [rgb(0, 0, 0), rgb(0, 0, 0)]
        let g = CGGradient(colorsSpace: srgb, colors: bg as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: p(0, 0), end: p(0, 1024), options: [])
    }

    let barW: CGFloat = 600, barH: CGFloat = 140, gap: CGFloat = 104
    let x = (1024 - barW) / 2, y0 = (1024 - barH * 2 - gap) / 2
    let path = CGMutablePath()
    for y in [y0, y0 + barH + gap] {
        path.addRoundedRect(in: CGRect(origin: p(x, y), size: CGSize(width: barW * s, height: barH * s)),
                            cornerWidth: barH / 2 * s, cornerHeight: barH / 2 * s)
    }
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let ink: [CGColor] = style == .tinted ? [rgb(1, 1, 1), rgb(0.72, 0.72, 0.72)] : [orange, pink]
    let g = CGGradient(colorsSpace: srgb, colors: ink as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: p(x, y0), end: p(x + barW, 1024 - y0), options: [])
    ctx.restoreGState()
}

func render(_ px: Int, _ name: String, mac: Bool = false, style: Style = .light) {
    // App Store rejects an alpha channel on the opaque iOS icons.
    let alpha: CGImageAlphaInfo = mac || style == .dark ? .premultipliedLast : .noneSkipLast
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                        bitmapInfo: alpha.rawValue)!
    let size = CGFloat(px)
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: 1, y: -1)

    if mac {
        // macOS grid: 824pt rounded rect centered on a 1024pt canvas, with a soft drop shadow.
        let s = size / 1024
        let tile = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
        let shape = CGPath(roundedRect: tile, cornerWidth: 185 * s, cornerHeight: 185 * s, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 10 * s), blur: 24 * s, color: rgb(0, 0, 0, 0.35))
        ctx.addPath(shape)
        ctx.setFillColor(graphiteBottom)
        ctx.fillPath()
        ctx.restoreGState()
        ctx.addPath(shape)
        ctx.clip()
        drawArt(ctx, in: tile, style: style, background: true)
    } else {
        // iOS: full-bleed and opaque; the system applies the mask. Dark keeps a clear background.
        drawArt(ctx, in: CGRect(x: 0, y: 0, width: size, height: size), style: style, background: style != .dark)
    }

    let dest = CGImageDestinationCreateWithURL(out.appendingPathComponent(name) as CFURL,
                                               UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(dest), "failed to write \(name)")
}

render(1024, "ios.png")
render(1024, "ios-dark.png", style: .dark)
render(1024, "ios-tinted.png", style: .tinted)
for pt in [16, 32, 128, 256, 512] {
    render(pt, "mac-\(pt).png", mac: true)
    render(pt * 2, "mac-\(pt)@2x.png", mac: true)
}
