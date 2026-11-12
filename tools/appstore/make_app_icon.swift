// Draws the 1024×1024 app icon: an open book in gold with soft rays, on the deep-purple gradient of the
// design system. No tradition's symbol is used, so none is favored.
// Usage: swift tools/appstore/make_app_icon.swift <output.png>
import AppKit
import CoreGraphics

let size = 1024.0
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let space = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                          space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError("context") }

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

// Background: deep purple, lighter at the top.
let background = CGGradient(colorsSpace: space, colors: [rgb(0x6A3FA8), rgb(0x2C1A4E)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(background, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])

let center = CGPoint(x: size / 2, y: size * 0.47)

// Soft glow above the book.
let glow = CGGradient(colorsSpace: space, colors: [rgb(0xF6DB8F, 0.55), rgb(0xF6DB8F, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: center.x, y: center.y + 150), startRadius: 0,
                       endCenter: CGPoint(x: center.x, y: center.y + 150), endRadius: 380, options: [])

// Rays.
ctx.saveGState()
ctx.setStrokeColor(rgb(0xF2D27A, 0.55))
ctx.setLineWidth(14)
ctx.setLineCap(.round)
let origin = CGPoint(x: center.x, y: center.y + 120)
for index in 0..<7 {
    let angle = Double.pi * (0.2 + 0.6 * Double(index) / 6)
    let inner = 150.0, outer = index % 2 == 0 ? 330.0 : 280.0
    ctx.move(to: CGPoint(x: origin.x + cos(angle) * inner, y: origin.y + sin(angle) * inner))
    ctx.addLine(to: CGPoint(x: origin.x + cos(angle) * outer, y: origin.y + sin(angle) * outer))
}
ctx.strokePath()
ctx.restoreGState()

// Open book: two curved pages meeting at the spine.
func page(mirrored: Bool) -> CGPath {
    let s: CGFloat = mirrored ? -1 : 1
    let path = CGMutablePath()
    let spineTop = CGPoint(x: center.x, y: center.y + 60), spineBottom = CGPoint(x: center.x, y: center.y - 170)
    path.move(to: spineBottom)
    path.addLine(to: spineTop)
    path.addCurve(to: CGPoint(x: center.x + s * 330, y: center.y + 110),
                  control1: CGPoint(x: center.x + s * 110, y: center.y + 140),
                  control2: CGPoint(x: center.x + s * 230, y: center.y + 150))
    path.addLine(to: CGPoint(x: center.x + s * 330, y: center.y - 120))
    path.addCurve(to: spineBottom,
                  control1: CGPoint(x: center.x + s * 230, y: center.y - 80),
                  control2: CGPoint(x: center.x + s * 110, y: center.y - 90))
    path.closeSubpath()
    return path
}
let gold = CGGradient(colorsSpace: space, colors: [rgb(0xF7E2A1), rgb(0xD4A640)] as CFArray, locations: [0, 1])!
for mirrored in [false, true] {
    ctx.saveGState()
    ctx.addPath(page(mirrored: mirrored))
    ctx.clip()
    ctx.drawLinearGradient(gold, start: CGPoint(x: 0, y: center.y + 160), end: CGPoint(x: 0, y: center.y - 180), options: [])
    ctx.restoreGState()
}
// Text lines on the pages (abstract, not script).
ctx.setStrokeColor(rgb(0x8C6418, 0.45))
ctx.setLineWidth(10)
ctx.setLineCap(.round)
for row in 0..<4 {
    let y = center.y + 40 - CGFloat(row) * 50
    for s in [-1.0, 1.0] {
        ctx.move(to: CGPoint(x: center.x + s * 55, y: y + 4))
        ctx.addLine(to: CGPoint(x: center.x + s * (row == 3 ? 200 : 270), y: y + 26))
    }
}
ctx.strokePath()
// Spine.
ctx.setStrokeColor(rgb(0x7A5413, 0.8))
ctx.setLineWidth(8)
ctx.move(to: CGPoint(x: center.x, y: center.y - 170))
ctx.addLine(to: CGPoint(x: center.x, y: center.y + 60))
ctx.strokePath()

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
