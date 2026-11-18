#!/usr/bin/env swift
// Draws the app icon (a character sheet with a portrait and a gold level badge, on indigo) and writes a 1024 px PNG.
// Few, bold shapes so it still reads at small sizes. Usage: swift scripts/make-icon.swift [--full-bleed] <output.png>
// --full-bleed draws the iOS icon: the indigo fills the square, opaque, and the system rounds the corners.
import AppKit
import CoreGraphics

let fullBleed = CommandLine.arguments.contains("--full-bleed")
let outputPath = CommandLine.arguments.dropFirst().filter { $0 != "--full-bleed" }
let size: CGFloat = 1024
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Maps unit coordinates (0…1, origin bottom left) into a rectangle.
struct Frame {
    let rect: CGRect

    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
    }

    func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
        CGRect(origin: point(x, y), size: CGSize(width: width * rect.width, height: height * rect.height))
    }

    func polygon(_ points: [(CGFloat, CGFloat)]) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: points.map { point($0.0, $0.1) })
        path.closeSubpath()
        return path
    }
}

func fill(_ context: CGContext, _ path: CGPath, _ hex: UInt32) {
    context.addPath(path)
    context.setFillColor(color(hex))
    context.fillPath()
}

func fillEllipse(_ context: CGContext, _ rect: CGRect, _ hex: UInt32) {
    context.setFillColor(color(hex))
    context.fillEllipse(in: rect)
}

func drawBackground(_ context: CGContext) {
    let corner: CGFloat = fullBleed ? 0 : 185
    let shape = CGPath(roundedRect: body, cornerWidth: corner, cornerHeight: corner, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0, 0.35))
    fill(context, shape, 0x1B1D4F)
    context.restoreGState()
    context.saveGState()
    context.addPath(shape)
    context.clip()
    let gradient = CGGradient(colorsSpace: sRGB, colors: [color(0x4A4FB8), color(0x1B1D4F)] as CFArray,
                              locations: nil)!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY),
                               options: [])
    context.restoreGState()
}

/// The character sheet: a parchment card with the character's bust and two lines of writing.
func drawSheet(_ context: CGContext) {
    let card = CGPath(roundedRect: CGRect(x: 250, y: 180, width: 470, height: 660), cornerWidth: 48,
                      cornerHeight: 48, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: color(0, 0.45))
    fill(context, card, 0xF6EEDB)
    context.restoreGState()
    let frame = Frame(rect: CGRect(x: 250, y: 180, width: 470, height: 660))
    // The portrait: a rounded frame with a bust inside it.
    let portrait = frame.rect(0.17, 0.42, 0.66, 0.5)
    let window = CGPath(roundedRect: portrait, cornerWidth: 36, cornerHeight: 36, transform: nil)
    fill(context, window, 0xD9CFF2)
    context.saveGState()
    context.addPath(window)
    context.clip()
    drawBust(context, in: Frame(rect: portrait))
    context.restoreGState()
    for (y, width) in [(0.29, 0.66), (0.18, 0.44)] as [(CGFloat, CGFloat)] {
        let line = frame.rect(0.17, y, width, 0.055)
        fill(context, CGPath(roundedRect: line, cornerWidth: 14, cornerHeight: 14, transform: nil), 0xB9AE95)
    }
}

/// A hooded adventurer's head and shoulders, in the indigo of the background, with the face in shadow.
func drawBust(_ context: CGContext, in frame: Frame) {
    let hood = CGMutablePath()
    hood.move(to: frame.point(0.24, 0.3))
    hood.addQuadCurve(to: frame.point(0.56, 0.96), control: frame.point(0.22, 0.86))
    hood.addQuadCurve(to: frame.point(0.76, 0.3), control: frame.point(0.8, 0.7))
    hood.closeSubpath()
    fill(context, hood, 0x2E3283)
    fillEllipse(context, frame.rect(0.38, 0.4, 0.24, 0.3), 0x1B1D4F)
    let shoulders = CGMutablePath()
    shoulders.move(to: frame.point(0.08, -0.05))
    shoulders.addQuadCurve(to: frame.point(0.5, 0.42), control: frame.point(0.12, 0.42))
    shoulders.addQuadCurve(to: frame.point(0.92, -0.05), control: frame.point(0.88, 0.42))
    shoulders.closeSubpath()
    fill(context, shoulders, 0x2E3283)
}

/// A gold rosette with two ribbon tails and an upward chevron: the level.
func drawBadge(_ context: CGContext) {
    let center = CGPoint(x: 712, y: 300)
    let frame = Frame(rect: CGRect(x: center.x - 150, y: center.y - 150, width: 300, height: 300))
    fill(context, frame.polygon([(0.22, 0.42), (0.44, 0.42), (0.36, -0.12), (0.26, -0.02), (0.14, -0.08)]), 0xB8452F)
    fill(context, frame.polygon([(0.56, 0.42), (0.78, 0.42), (0.86, -0.08), (0.74, -0.02), (0.64, -0.12)]), 0xB8452F)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -8), blur: 20, color: color(0, 0.4))
    fillEllipse(context, frame.rect(0.1, 0.2, 0.8, 0.8), 0xB07A1E)
    context.restoreGState()
    fillEllipse(context, frame.rect(0.17, 0.27, 0.66, 0.66), 0xF2C14E)
    let chevron = CGMutablePath()
    chevron.addLines(between: [frame.point(0.32, 0.5), frame.point(0.5, 0.7), frame.point(0.68, 0.5)])
    context.addPath(chevron)
    context.setStrokeColor(color(0xFFFFFF))
    context.setLineWidth(34)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.strokePath()
}

guard outputPath.count == 1 else {
    FileHandle.standardError.write("usage: make-icon.swift [--full-bleed] <output.png>\n".data(using: .utf8)!)
    exit(1)
}
// App Store Connect rejects an iOS icon with an alpha channel, so the full-bleed icon is drawn opaque.
let alpha = fullBleed ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast
let context = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                        space: sRGB, bitmapInfo: alpha.rawValue)!
if fullBleed {
    // The icon's square fills the canvas.
    context.scaleBy(x: size / body.width, y: size / body.height)
    context.translateBy(x: -body.minX, y: -body.minY)
}
drawBackground(context)
drawSheet(context)
drawBadge(context)

let output = URL(fileURLWithPath: outputPath[0])
let destination = CGImageDestinationCreateWithURL(output as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { exit(1) }
