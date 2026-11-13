// Regenerate the icon set with:
//   xcrun swiftc -O -o /tmp/suitcase Design/SuitcaseIcon.swift && /tmp/suitcase Design/AppIcon-suitcase-source.png Trippin/Assets.xcassets/AppIcon.appiconset
import AppKit
// Makes iOS app icons from a black-on-white line drawing: centers the drawing,
// and writes a light icon plus dark and tinted variants (white lines on black).
let src = NSImage(contentsOfFile: CommandLine.arguments[1])!
let out = CommandLine.arguments[2]
let srcCG = src.cgImage(forProposedRect: nil, context: nil, hints: nil)!
let w = srcCG.width, h = srcCG.height

// Flatten onto white and read pixels to find the drawing's bounds.
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let flat = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs,
                     bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
flat.setFillColor(CGColor(gray: 1, alpha: 1)); flat.fill(CGRect(x: 0, y: 0, width: w, height: h))
flat.draw(srcCG, in: CGRect(x: 0, y: 0, width: w, height: h))
let px = flat.data!.assumingMemoryBound(to: UInt8.self)
var minX = w, minY = h, maxX = 0, maxY = 0
for y in 0..<h { for x in 0..<w {
    let i = (y * w + x) * 4
    if Int(px[i]) + Int(px[i+1]) + Int(px[i+2]) < 3 * 160 {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
    }
}}
let box = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
print("drawing bounds (top-left origin):", box)
let flatImage = flat.makeImage()!.cropping(to: box)!

func render(_ name: String, dark: Bool) {
    let N = 1024, fill: CGFloat = 0.78
    let ctx = CGContext(data: nil, width: N, height: N, bitsPerComponent: 8, bytesPerRow: N * 4, space: cs,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: N, height: N))
    let scale = fill * CGFloat(N) / max(box.width, box.height)
    let dw = box.width * scale, dh = box.height * scale
    ctx.interpolationQuality = .high
    ctx.draw(flatImage, in: CGRect(x: (CGFloat(N) - dw) / 2, y: (CGFloat(N) - dh) / 2, width: dw, height: dh))
    var img = ctx.makeImage()!
    if dark {
        // Invert: white lines on near-black.
        let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
        for i in stride(from: 0, to: N * N * 4, by: 4) { for c in 0..<3 { p[i+c] = 255 - p[i+c] } }
        img = ctx.makeImage()!
    }
    let rep = NSBitmapImageRep(cgImage: img)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
}
render("AppIcon", dark: false)
render("AppIcon-Dark", dark: true)
render("AppIcon-Tinted", dark: true)
