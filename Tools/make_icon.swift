#!/usr/bin/env swift
// Génère l'icône Focale (squircle dégradé + réticule + point) dans l'appiconset.
// Usage : swift Focale/Tools/make_icon.swift

import AppKit
import Foundation

let fileManager = FileManager.default
let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardized
// Focale/Tools/make_icon.swift -> Focale/Focale/Resources/Assets.xcassets/AppIcon.appiconset
let projectRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let iconSet = projectRoot
    .appendingPathComponent("Focale/Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: CGSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }
    guard let ctx = NSGraphicsContext.current?.cgContext else { return image }
    let bounds = CGRect(x: 0, y: 0, width: size, height: size)

    // Fond squircle dégradé bleu -> violet.
    let radius = size * 0.225
    let body = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            NSColor(calibratedRed: 0x0A / 255, green: 0x84 / 255, blue: 1, alpha: 1).cgColor,
            NSColor(calibratedRed: 0x5E / 255, green: 0x5C / 255, blue: 0xE6 / 255, alpha: 1).cgColor,
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
    // Reflet de verre.
    let gloss = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [NSColor.white.withAlphaComponent(0.22).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        gloss,
        start: CGPoint(x: 0, y: size),
        end: CGPoint(x: 0, y: size * 0.45),
        options: []
    )
    ctx.restoreGState()

    // Réticule : 4 coins ouverts.
    let inset = size * 0.29
    let arm = size * 0.135
    let frame = bounds.insetBy(dx: inset, dy: inset)
    let brackets = NSBezierPath()
    brackets.lineWidth = size * 0.062
    brackets.lineCapStyle = .round
    let corners: [(CGPoint, CGPoint, CGPoint)] = [
        (CGPoint(x: frame.minX, y: frame.minY + arm), CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.minX + arm, y: frame.minY)),
        (CGPoint(x: frame.maxX - arm, y: frame.minY), CGPoint(x: frame.maxX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.minY + arm)),
        (CGPoint(x: frame.maxX, y: frame.maxY - arm), CGPoint(x: frame.maxX, y: frame.maxY), CGPoint(x: frame.maxX - arm, y: frame.maxY)),
        (CGPoint(x: frame.minX + arm, y: frame.maxY), CGPoint(x: frame.minX, y: frame.maxY), CGPoint(x: frame.minX, y: frame.maxY - arm)),
    ]
    for (start, corner, end) in corners {
        brackets.move(to: start)
        brackets.line(to: corner)
        brackets.line(to: end)
    }
    NSColor.white.setStroke()
    brackets.stroke()

    // Point lumineux central.
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: size * 0.03, color: NSColor.white.cgColor)
    NSColor.white.setFill()
    let dotRadius = size * 0.052
    let dot = NSBezierPath(ovalIn: CGRect(
        x: size / 2 - dotRadius, y: size / 2 - dotRadius,
        width: dotRadius * 2, height: dotRadius * 2
    ))
    dot.fill()
    ctx.restoreGState()
    return image
}

func writePNG(_ image: NSImage, name: String) throws {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "FocaleIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Encodage PNG impossible"])
    }
    try data.write(to: iconSet.appendingPathComponent(name))
}

let targets: [(pixel: CGFloat, name: String)] = [
    (16, "Icon-16.png"),
    (32, "Icon-16@2x.png"),
    (32, "Icon-32.png"),
    (64, "Icon-32@2x.png"),
    (128, "Icon-128.png"),
    (256, "Icon-128@2x.png"),
    (256, "Icon-256.png"),
    (512, "Icon-256@2x.png"),
    (512, "Icon-512.png"),
    (1024, "Icon-512@2x.png"),
]

try fileManager.createDirectory(at: iconSet, withIntermediateDirectories: true)
for target in targets {
    try writePNG(drawIcon(size: target.pixel), name: target.name)
    print("OK \(target.name) (\(Int(target.pixel))px)")
}
print("Icône générée dans \(iconSet.path)")
