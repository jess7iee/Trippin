// Draws Trippin's app icon: a map pin, a dotted takeoff route and a climbing plane.
// Regenerate the icon set with:
//   xcrun swiftc -o /tmp/appicon Design/AppIcon.swift && /tmp/appicon Trippin/Assets.xcassets/AppIcon.appiconset
import AppKit

let N: CGFloat = 1024
func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

enum Variant { case light, dark, tinted }

struct Palette {
    var bgTop: CGColor, bgBottom: CGColor, path: CGColor, accent: CGColor, pin: CGColor, pinHole: CGColor
    static func of(_ v: Variant) -> Palette {
        switch v {
        case .light: Palette(bgTop: rgb(0x23B57F), bgBottom: rgb(0x0A6646), path: rgb(0xFFFFFF), accent: rgb(0xFFB547), pin: rgb(0xFFFFFF), pinHole: rgb(0x11885F))
        case .dark: Palette(bgTop: rgb(0x123A2C), bgBottom: rgb(0x050F0B), path: rgb(0x5FE0AE), accent: rgb(0xFFB547), pin: rgb(0x5FE0AE), pinHole: rgb(0x0B2A1F))
        case .tinted: Palette(bgTop: rgb(0x000000), bgBottom: rgb(0x000000), path: rgb(0xD8D8D8), accent: rgb(0xFFFFFF), pin: rgb(0xFFFFFF), pinHole: rgb(0x000000))
        }
    }
}

func render(_ name: String, _ variant: Variant, _ draw: (CGContext, Palette) -> Void) {
    let ctx = CGContext(data: nil, width: Int(N), height: Int(N), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    // Flip to top-left origin.
    ctx.translateBy(x: 0, y: N); ctx.scaleBy(x: 1, y: -1)
    let p = Palette.of(variant)
    let grad = CGGradient(colorsSpace: nil, colors: [p.bgTop, p.bgBottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: N * 0.2, y: 0), end: CGPoint(x: N * 0.8, y: N),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    draw(ctx, p)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1] + "/" + name + ".png"))
}

/// Map pin: circle head with a hole, pointed tail. `tip` is the point it marks.
func pin(_ ctx: CGContext, tip: CGPoint, r: CGFloat, color: CGColor, hole: CGColor) {
    let c = CGPoint(x: tip.x, y: tip.y - r * 2.15)
    let path = CGMutablePath()
    let a: CGFloat = 0.62  // how far round the head the tail starts
    path.addArc(center: c, radius: r, startAngle: .pi / 2 + a, endAngle: .pi / 2 - a, clockwise: false)
    path.addLine(to: tip)
    path.closeSubpath()
    ctx.setFillColor(color); ctx.addPath(path); ctx.fillPath()
    ctx.saveGState(); ctx.setShadow(offset: .zero, blur: 0, color: nil)
    ctx.setFillColor(hole); ctx.fillEllipse(in: CGRect(x: c.x - r * 0.42, y: c.y - r * 0.42, width: r * 0.84, height: r * 0.84))
    ctx.restoreGState()
}

/// A plane silhouette drawn from scratch (SF Symbols may not be used in app icons),
/// nose pointing along `angle` (radians, 0 = right). `size` is nose-to-tail length.
func plane(_ ctx: CGContext, at p: CGPoint, size L: CGFloat, angle: CGFloat, color: CGColor) {
    func shape(_ pts: [(CGFloat, CGFloat)]) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: pts.map { CGPoint(x: $0.0 * L, y: $0.1 * L) })
        path.closeSubpath()
        return path
    }
    // Fuselage: a long capsule with a rounded nose and tail.
    var parts: [CGPath] = [CGPath(roundedRect: CGRect(x: -0.5 * L, y: -0.08 * L, width: L, height: 0.16 * L),
                                  cornerWidth: 0.08 * L, cornerHeight: 0.08 * L, transform: nil)]
    for side: CGFloat in [-1, 1] {
        // Main wing, swept back.
        parts.append(shape([(0.16, 0.05 * side), (-0.12, 0.50 * side), (-0.30, 0.50 * side), (-0.16, 0.05 * side)]))
        // Tailplane.
        parts.append(shape([(-0.30, 0.05 * side), (-0.42, 0.25 * side), (-0.53, 0.25 * side), (-0.48, 0.05 * side)]))
    }
    ctx.saveGState()
    ctx.translateBy(x: p.x, y: p.y); ctx.rotate(by: angle)
    // One layer so the shadow falls from the whole plane, not from each piece.
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.setFillColor(color)
    for part in parts { ctx.addPath(part); ctx.fillPath() }
    ctx.endTransparencyLayer()
    ctx.restoreGState()
}

func dashedCurve(_ ctx: CGContext, from a: CGPoint, control c: CGPoint, to b: CGPoint, color: CGColor, width: CGFloat, dash: [CGFloat]) {
    ctx.saveGState()
    ctx.setStrokeColor(color); ctx.setLineWidth(width); ctx.setLineCap(.round); ctx.setLineDash(phase: 0, lengths: dash)
    ctx.move(to: a); ctx.addQuadCurve(to: b, control: c); ctx.strokePath()
    ctx.restoreGState()
}

// A: pin → dotted arc → plane
func conceptRoute(_ ctx: CGContext, _ p: Palette) {
    let tip = CGPoint(x: 300, y: 840), r: CGFloat = 122
    let head = CGPoint(x: tip.x, y: tip.y - r * 2.15)
    // A takeoff swoop: out from the pin's head, dipping, then climbing into the plane.
    let a = CGPoint(x: head.x + r + 50, y: head.y + 20), c = CGPoint(x: 610, y: 640), b = CGPoint(x: 700, y: 400)
    dashedCurve(ctx, from: a, control: c, to: b, color: p.path.copy(alpha: 0.95)!, width: 40, dash: [1, 70])
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 14), blur: 30, color: rgb(0x000000, 0.28))
    pin(ctx, tip: tip, r: r, color: p.pin, hole: p.pinHole)
    // Nose up and to the right: taking off.
    plane(ctx, at: CGPoint(x: 764, y: 270), size: 330, angle: atan2(b.y - c.y, b.x - c.x), color: p.accent)
    ctx.restoreGState()
}

render("AppIcon", .light, conceptRoute)
render("AppIcon-Dark", .dark, conceptRoute)
render("AppIcon-Tinted", .tinted, conceptRoute)
