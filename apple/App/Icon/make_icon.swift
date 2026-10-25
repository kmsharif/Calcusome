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
let blue = rgb(0.06, 0.24, 0.72)

enum Style { case light, dark, tinted }

func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: srgb, colors: colors as CFArray, locations: nil)!
}

/// Draws the 1024-unit design into `rect` (top-left origin): four frosted-glass keys (+ − × =)
/// on a solid blue background, with the = key in the orange→pink accent.
func drawArt(_ ctx: CGContext, in rect: CGRect, style: Style, background: Bool) {
    let s = rect.width / 1024
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }

    if background {
        ctx.setFillColor(style == .light ? blue : rgb(0, 0, 0))
        ctx.fill(rect)
    }

    let key: CGFloat = 330, gap: CGFloat = 44, margin = (1024 - key * 2 - gap) / 2
    let white = rgb(1, 1, 1)
    for i in 0..<4 {
        let origin = p(margin + CGFloat(i % 2) * (key + gap), margin + CGFloat(i / 2) * (key + gap))
        let tile = CGRect(origin: origin, size: CGSize(width: key * s, height: key * s))
        let shape = CGPath(roundedRect: tile, cornerWidth: 92 * s, cornerHeight: 92 * s, transform: nil)
        let accent = i == 3

        // Shadow only outside the key, so it doesn't muddy the translucent glass.
        ctx.saveGState()
        ctx.addRect(rect)
        ctx.addPath(shape)
        ctx.clip(using: .evenOdd)
        ctx.setShadow(offset: CGSize(width: 0, height: -18 * s), blur: 40 * s, color: rgb(0, 0, 0, 0.35))
        ctx.addPath(shape)
        ctx.setFillColor(rgb(0, 0, 0))
        ctx.fillPath()
        ctx.restoreGState()

        // Glass body plus a sheen over the top half.
        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        let body: [CGColor] = switch (accent, style) {
        case (false, _): [rgb(1, 1, 1, 0.32), rgb(1, 1, 1, 0.10)]
        case (true, .light), (true, .dark): [orange, pink]
        case (true, .tinted): [rgb(0.9, 0.9, 0.9), rgb(0.6, 0.6, 0.6)]
        }
        ctx.drawLinearGradient(gradient(body), start: tile.origin, end: CGPoint(x: tile.maxX, y: tile.maxY), options: [])
        ctx.drawLinearGradient(gradient([rgb(1, 1, 1, 0.22), rgb(1, 1, 1, 0)]), start: tile.origin,
                               end: CGPoint(x: tile.minX, y: tile.midY), options: [])
        ctx.restoreGState()

        // Light catching the rim: bright top-left, faint bottom-right.
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: tile.insetBy(dx: 2 * s, dy: 2 * s), cornerWidth: 90 * s, cornerHeight: 90 * s,
                           transform: nil))
        ctx.setLineWidth(4 * s)
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        ctx.drawLinearGradient(gradient([rgb(1, 1, 1, 0.8), rgb(1, 1, 1, 0.05), rgb(1, 1, 1, 0.3)]), start: tile.origin,
                               end: CGPoint(x: tile.maxX, y: tile.maxY), options: [])
        ctx.restoreGState()

        let c = CGPoint(x: tile.midX, y: tile.midY), arm = 66 * s, d = arm * 0.85
        func line(_ dx: CGFloat, _ dy: CGFloat, _ ex: CGFloat, _ ey: CGFloat) -> [CGPoint] {
            [CGPoint(x: c.x + dx, y: c.y + dy), CGPoint(x: c.x + ex, y: c.y + ey)]
        }
        let strokes: [[CGPoint]] = switch i {
        case 0: [line(-arm, 0, arm, 0), line(0, -arm, 0, arm)]
        case 1: [line(-arm, 0, arm, 0)]
        case 2: [line(-d, -d, d, d), line(-d, d, d, -d)]
        default: [line(-arm, -38 * s, arm, -38 * s), line(-arm, 38 * s, arm, 38 * s)]
        }
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -6 * s), blur: 14 * s, color: rgb(0, 0, 0, 0.25))
        for points in strokes { ctx.addLines(between: points) }
        ctx.setLineWidth(40 * s)
        ctx.setLineCap(.round)
        ctx.setStrokeColor(white)
        ctx.strokePath()
        ctx.restoreGState()
    }
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
        ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 24 * s, color: rgb(0, 0, 0, 0.35))
        ctx.addPath(shape)
        ctx.setFillColor(blue)
        ctx.fillPath()
        ctx.restoreGState()
        ctx.addPath(shape)
        ctx.clip()
        drawArt(ctx, in: tile, style: style, background: true)
        // Liquid Glass-style specular edge: bright along the top, fading down the sides.
        ctx.addPath(CGPath(roundedRect: tile.insetBy(dx: 3 * s, dy: 3 * s), cornerWidth: 182 * s, cornerHeight: 182 * s,
                           transform: nil))
        ctx.setLineWidth(6 * s)
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        ctx.drawLinearGradient(gradient([rgb(1, 1, 1, 0.6), rgb(1, 1, 1, 0.05), rgb(1, 1, 1, 0.25)]),
                               start: tile.origin, end: CGPoint(x: tile.minX, y: tile.maxY), options: [])
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
