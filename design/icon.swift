// Renders the OpenBar app icon: `swift design/icon.swift <out.png> [size]`.
// An open ring ("O") above a taskbar of app tiles.
import AppKit

let args = CommandLine.arguments
let out = args.count > 1 ? args[1] : "icon.png"
let px = args.count > 2 ? Int(args[2]) ?? 1024 : 1024
let s = CGFloat(px) / 1024

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.scaleBy(x: s, y: s)

func linear(_ colors: [CGColor], _ from: CGPoint, _ to: CGPoint) {
    let g = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

// Squircle body on Apple's 824pt grid with a soft drop shadow.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let squircle = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.35))
ctx.addPath(squircle)
ctx.setFillColor(rgb(0x1A1D4E))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()
linear([rgb(0x5B4BFF), rgb(0x2E2A8C), rgb(0x141537)], CGPoint(x: 260, y: 924), CGPoint(x: 760, y: 100))
// Top sheen.
linear([rgb(0xFFFFFF, 0.18), rgb(0xFFFFFF, 0)], CGPoint(x: 512, y: 924), CGPoint(x: 512, y: 600))

// Open ring, gap at the lower right.
let center = CGPoint(x: 512, y: 590)
let radius: CGFloat = 190
let ring = CGMutablePath()
let gapCenter: CGFloat = -.pi / 4
let gap: CGFloat = 0.42
ring.addArc(center: center, radius: radius, startAngle: gapCenter + gap, endAngle: gapCenter - gap + 2 * .pi,
            clockwise: false)
let stroked = ring.copy(strokingWithWidth: 84, lineCap: .round, lineJoin: .round, miterLimit: 10)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: rgb(0x05061A, 0.45))
ctx.addPath(stroked)
ctx.setFillColor(rgb(0xFFFFFF))
ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(stroked)
ctx.clip()
linear([rgb(0xFFFFFF), rgb(0xD9E1FF)], CGPoint(x: 512, y: 780), CGPoint(x: 512, y: 340))
ctx.restoreGState()

// Glass taskbar.
let bar = CGRect(x: 180, y: 190, width: 664, height: 132)
let barPath = CGPath(roundedRect: bar, cornerWidth: 66, cornerHeight: 66, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 24, color: rgb(0x05061A, 0.5))
ctx.addPath(barPath)
ctx.setFillColor(rgb(0xFFFFFF, 0.16))
ctx.fillPath()
ctx.restoreGState()
ctx.addPath(barPath)
ctx.setStrokeColor(rgb(0xFFFFFF, 0.35))
ctx.setLineWidth(3)
ctx.strokePath()

// App tiles; the first is active.
let tiles: [(UInt32, UInt32)] = [(0xFF7A59, 0xFF4D6D), (0xFFC94A, 0xFF9F1C), (0x4BE3B0, 0x16B39A), (0x59C3FF, 0x2F7BFF)]
let tileSize: CGFloat = 84
let spacing: CGFloat = 40
let totalWidth = tileSize * CGFloat(tiles.count) + spacing * CGFloat(tiles.count - 1)
var x = bar.midX - totalWidth / 2
for (i, colors) in tiles.enumerated() {
    let rect = CGRect(x: x, y: bar.midY - tileSize / 2 + 6, width: tileSize, height: tileSize)
    let tile = CGPath(roundedRect: rect, cornerWidth: 22, cornerHeight: 22, transform: nil)
    ctx.saveGState()
    ctx.addPath(tile)
    ctx.clip()
    linear([rgb(colors.0), rgb(colors.1)], CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.minY))
    ctx.restoreGState()
    let dotWidth: CGFloat = i == 0 ? 40 : 12
    let dot = CGRect(x: rect.midX - dotWidth / 2, y: bar.minY + 14, width: dotWidth, height: 10)
    ctx.addPath(CGPath(roundedRect: dot, cornerWidth: 5, cornerHeight: 5, transform: nil))
    ctx.setFillColor(rgb(0xFFFFFF, i == 0 ? 0.95 : 0.55))
    ctx.fillPath()
    x += tileSize + spacing
}
ctx.restoreGState()

// Inner edge highlight.
ctx.addPath(squircle)
ctx.setStrokeColor(rgb(0xFFFFFF, 0.12))
ctx.setLineWidth(4)
ctx.strokePath()

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
