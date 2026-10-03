import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Draws the HuaSideload icon: a watch with a suspension bridge across its face.
//   swiftc -O -o /tmp/icon tools/make-brand-icon.swift
//   /tmp/icon 1024 HuaSideload/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png      (iOS, square)
//   /tmp/icon 114 watch-apps/sample/entry/src/main/resources/base/media/icon.png round   (watch, round)
func draw(size: Int, rounded: Bool, path: String) {
    let s = CGFloat(size)
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setShouldAntialias(true)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
        CGColor(colorSpace: space, components: [CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, a])!
    }
    // background gradient
    if rounded { ctx.addEllipse(in: CGRect(x: 0, y: 0, width: s, height: s)); ctx.clip() }
    let gradient = CGGradient(colorsSpace: space, colors: [color(0x1E2A78), color(0x0EA5E9)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])

    let c = CGPoint(x: s / 2, y: s / 2)
    let r = s * 0.30
    // straps
    ctx.setFillColor(color(0xFFFFFF, 0.22))
    let strapW = r * 0.95
    for (y, h) in [(c.y + r * 0.55, s * 0.5), (c.y - r * 0.55 - s * 0.5, s * 0.5)] {
        let rect = CGRect(x: c.x - strapW / 2, y: y, width: strapW, height: h)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: strapW * 0.25, cornerHeight: strapW * 0.25, transform: nil))
        ctx.fillPath()
    }
    // case + face
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillEllipse(in: CGRect(x: c.x - r * 1.13, y: c.y - r * 1.13, width: r * 2.26, height: r * 2.26))
    ctx.setFillColor(color(0x0F172A))
    ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    // crown
    ctx.setFillColor(color(0xFFFFFF))
    ctx.addPath(CGPath(roundedRect: CGRect(x: c.x + r * 1.08, y: c.y - r * 0.16, width: r * 0.2, height: r * 0.32),
                       cornerWidth: r * 0.06, cornerHeight: r * 0.06, transform: nil))
    ctx.fillPath()

    // bridge inside the face (clip to face)
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)); ctx.clip()
    let deckY = c.y - r * 0.18
    let left = c.x - r * 0.95, right = c.x + r * 0.95
    let towerX = [c.x - r * 0.45, c.x + r * 0.45]
    let towerTop = c.y + r * 0.42
    let accent = color(0xFBBF24)
    // water glow
    ctx.setFillColor(color(0x0EA5E9, 0.35))
    ctx.fill(CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: deckY - (c.y - r) - r * 0.02))
    // main cable: left anchor -> tower -> sag -> tower -> right anchor
    ctx.setStrokeColor(accent); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.setLineWidth(r * 0.065)
    ctx.move(to: CGPoint(x: left, y: deckY + r * 0.02))
    ctx.addQuadCurve(to: CGPoint(x: towerX[0], y: towerTop), control: CGPoint(x: (left + towerX[0]) / 2 + r * 0.05, y: deckY + r * 0.08))
    ctx.addQuadCurve(to: CGPoint(x: towerX[1], y: towerTop), control: CGPoint(x: c.x, y: deckY - r * 0.05))
    ctx.addQuadCurve(to: CGPoint(x: right, y: deckY + r * 0.02), control: CGPoint(x: (right + towerX[1]) / 2 - r * 0.05, y: deckY + r * 0.08))
    ctx.strokePath()
    // hangers
    ctx.setLineWidth(r * 0.025)
    for i in 1..<8 {
        let x = towerX[0] + (towerX[1] - towerX[0]) * CGFloat(i) / 8
        let t = (x - towerX[0]) / (towerX[1] - towerX[0])
        // point on the middle quad curve
        let p0 = CGPoint(x: towerX[0], y: towerTop), p1 = CGPoint(x: c.x, y: deckY - r * 0.05), p2 = CGPoint(x: towerX[1], y: towerTop)
        let y = (1 - t) * (1 - t) * p0.y + 2 * (1 - t) * t * p1.y + t * t * p2.y
        ctx.move(to: CGPoint(x: x, y: deckY)); ctx.addLine(to: CGPoint(x: x, y: y)); ctx.strokePath()
    }
    // towers
    ctx.setFillColor(color(0xFFFFFF))
    for x in towerX {
        ctx.addPath(CGPath(roundedRect: CGRect(x: x - r * 0.06, y: deckY - r * 0.42, width: r * 0.12, height: towerTop - deckY + r * 0.48),
                           cornerWidth: r * 0.03, cornerHeight: r * 0.03, transform: nil))
        ctx.fillPath()
    }
    // deck
    ctx.setStrokeColor(color(0xFFFFFF)); ctx.setLineWidth(r * 0.09); ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: c.x - r * 1.05, y: deckY)); ctx.addLine(to: CGPoint(x: c.x + r * 1.05, y: deckY)); ctx.strokePath()
    ctx.restoreGState()

    let image = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let args = CommandLine.arguments
draw(size: Int(args[1])!, rounded: args.count > 3 && args[3] == "round", path: args[2])
