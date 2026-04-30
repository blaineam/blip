#!/usr/bin/env swift

import AppKit
import Foundation

// MARK: - Blip Asset Generator
// Generates app icon (.icns) and DMG background from code.
// Usage: swift generate-assets.swift <output-directory>

let outputDir: String
if CommandLine.arguments.count > 1 {
    outputDir = CommandLine.arguments[1]
} else {
    outputDir = "build/assets"
}

try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

// MARK: - Brand Colors

let brandDarkNavy = NSColor(red: 0.05, green: 0.08, blue: 0.18, alpha: 1.0)
let brandDeepBlue = NSColor(red: 0.10, green: 0.15, blue: 0.30, alpha: 1.0)
let brandCyan = NSColor(red: 0.3, green: 0.9, blue: 1.0, alpha: 1.0)
let brandCyanGlow = NSColor(red: 0.2, green: 0.8, blue: 1.0, alpha: 0.4)
let brandGreen = NSColor(red: 0.19, green: 0.82, blue: 0.35, alpha: 1.0)

// MARK: - App Icon

func generateAppIcon() throws {
    let sizes: [(CGFloat, String)] = [
        (16, "icon_16x16"),
        (32, "icon_16x16@2x"),
        (32, "icon_32x32"),
        (64, "icon_32x32@2x"),
        (128, "icon_128x128"),
        (256, "icon_128x128@2x"),
        (256, "icon_256x256"),
        (512, "icon_256x256@2x"),
        (512, "icon_512x512"),
        (1024, "icon_512x512@2x"),
    ]

    let iconsetPath = "\(outputDir)/Blip.iconset"
    try FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

    for (size, name) in sizes {
        let image = drawIcon(size: size)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size),
            pixelsHigh: Int(size),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        rep.size = NSSize(width: size, height: size)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()

        let data = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:])!
        try data.write(to: URL(fileURLWithPath: "\(iconsetPath)/\(name).png"))
    }

    // Convert iconset to icns
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", "-o", "\(outputDir)/Blip.icns", iconsetPath]
    try process.run()
    process.waitUntilExit()

    print("✓ Generated Blip.icns")
}

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let cornerRadius = size * 0.22

    // Background gradient: deep navy to dark blue
    let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    let gradient = NSGradient(
        colors: [brandDarkNavy, brandDeepBlue],
        atLocations: [0.0, 1.0],
        colorSpace: .deviceRGB
    )!
    gradient.draw(in: path, angle: -45)

    // Draw 3 horizontal monitor bars (CPU/MEM/HD style)
    let barWidth = size * 0.72
    let barHeight = size * 0.075
    let barX = size * 0.14
    let barSpacing = size * 0.135
    let barStartY = size * 0.42

    let barColors: [(NSColor, CGFloat)] = [
        (NSColor(red: 0.04, green: 0.52, blue: 1.0, alpha: 1.0), 0.65),  // Blue - CPU
        (brandGreen, 0.45),                                                 // Green - MEM
        (NSColor(red: 1.0, green: 0.62, blue: 0.04, alpha: 1.0), 0.30),  // Orange - HD
    ]

    for (i, (color, fillPercent)) in barColors.enumerated() {
        let y = barStartY - CGFloat(i) * barSpacing
        let bgRect = NSRect(x: barX, y: y, width: barWidth, height: barHeight)
        let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: barHeight / 2, yRadius: barHeight / 2)
        color.withAlphaComponent(0.2).setFill()
        bgPath.fill()

        let fillRect = NSRect(x: barX, y: y, width: barWidth * fillPercent, height: barHeight)
        let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: barHeight / 2, yRadius: barHeight / 2)
        color.setFill()
        fillPath.fill()
    }

    // Draw a radar "blip" dot above bars
    let dotSize = size * 0.15
    let dotCenter = NSPoint(x: size * 0.5, y: size * 0.74)

    // Outer glow
    let glowSize = dotSize * 3
    let glowRect = NSRect(
        x: dotCenter.x - glowSize / 2,
        y: dotCenter.y - glowSize / 2,
        width: glowSize,
        height: glowSize
    )
    let glowGradient = NSGradient(
        colors: [brandCyanGlow, brandCyanGlow.withAlphaComponent(0.0)]
    )!
    glowGradient.draw(in: NSBezierPath(ovalIn: glowRect), relativeCenterPosition: .zero)

    // Inner dot
    let dotRect = NSRect(
        x: dotCenter.x - dotSize / 2,
        y: dotCenter.y - dotSize / 2,
        width: dotSize,
        height: dotSize
    )
    brandCyan.setFill()
    NSBezierPath(ovalIn: dotRect).fill()

    // Subtle radar rings
    brandCyan.withAlphaComponent(0.1).setStroke()
    for i in 1...2 {
        let ringSize = dotSize * CGFloat(i) * 2.0
        let ringRect = NSRect(
            x: dotCenter.x - ringSize / 2,
            y: dotCenter.y - ringSize / 2,
            width: ringSize,
            height: ringSize
        )
        let ring = NSBezierPath(ovalIn: ringRect)
        ring.lineWidth = size * 0.008
        ring.stroke()
    }

    image.unlockFocus()
    return image
}

// MARK: - Helper App Icon

func generateHelperIcon() throws {
    let sizes: [(CGFloat, String)] = [
        (16, "icon_16x16"),
        (32, "icon_16x16@2x"),
        (32, "icon_32x32"),
        (64, "icon_32x32@2x"),
        (128, "icon_128x128"),
        (256, "icon_128x128@2x"),
        (256, "icon_256x256"),
        (512, "icon_256x256@2x"),
        (512, "icon_512x512"),
        (1024, "icon_512x512@2x"),
    ]

    let iconsetPath = "\(outputDir)/BlipHelper.iconset"
    try FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

    for (size, name) in sizes {
        let image = drawHelperIcon(size: size)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size),
            pixelsHigh: Int(size),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        rep.size = NSSize(width: size, height: size)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()

        let data = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:])!
        try data.write(to: URL(fileURLWithPath: "\(iconsetPath)/\(name).png"))
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", "-o", "\(outputDir)/BlipHelper.icns", iconsetPath]
    try process.run()
    process.waitUntilExit()

    print("✓ Generated BlipHelper.icns")
}

func drawHelperIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let cornerRadius = size * 0.22

    // Background gradient: slightly warmer deep navy
    let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    let gradient = NSGradient(
        colors: [
            NSColor(red: 0.06, green: 0.06, blue: 0.16, alpha: 1.0),
            NSColor(red: 0.12, green: 0.10, blue: 0.28, alpha: 1.0),
        ],
        atLocations: [0.0, 1.0],
        colorSpace: .deviceRGB
    )!
    gradient.draw(in: path, angle: -45)

    // Lightning bolt in the center
    let boltColor = NSColor(red: 1.0, green: 0.8, blue: 0.2, alpha: 1.0)
    let boltGlow = NSColor(red: 1.0, green: 0.8, blue: 0.2, alpha: 0.3)

    // Outer glow
    let glowSize = size * 0.75
    let glowRect = NSRect(
        x: (size - glowSize) / 2,
        y: (size - glowSize) / 2,
        width: glowSize,
        height: glowSize
    )
    let glowGradient = NSGradient(
        colors: [boltGlow, boltGlow.withAlphaComponent(0.0)]
    )!
    glowGradient.draw(in: NSBezierPath(ovalIn: glowRect), relativeCenterPosition: .zero)

    // Draw lightning bolt shape
    let bolt = NSBezierPath()
    let cx = size * 0.5
    let topY = size * 0.92
    let botY = size * 0.22
    let midY = size * 0.55

    bolt.move(to: NSPoint(x: cx - size * 0.03, y: topY))          // top
    bolt.line(to: NSPoint(x: cx - size * 0.18, y: midY))          // left notch
    bolt.line(to: NSPoint(x: cx + size * 0.03, y: midY + size * 0.06)) // right notch
    bolt.line(to: NSPoint(x: cx + size * 0.03, y: botY))          // bottom
    bolt.line(to: NSPoint(x: cx + size * 0.18, y: size * 0.50))   // right upper
    bolt.line(to: NSPoint(x: cx - size * 0.03, y: size * 0.44))   // left upper
    bolt.close()

    boltColor.setFill()
    bolt.fill()

    // Small "helper" bars at bottom
    let barWidth = size * 0.6
    let barHeight = size * 0.045
    let barX = size * 0.2
    let barY = size * 0.10

    let barBg = NSColor(red: 1.0, green: 0.8, blue: 0.2, alpha: 0.15)
    let bgRect = NSRect(x: barX, y: barY, width: barWidth, height: barHeight)
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: barHeight / 2, yRadius: barHeight / 2)
    barBg.setFill()
    bgPath.fill()

    let fillRect = NSRect(x: barX, y: barY, width: barWidth * 0.7, height: barHeight)
    let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: barHeight / 2, yRadius: barHeight / 2)
    boltColor.withAlphaComponent(0.6).setFill()
    fillPath.fill()

    image.unlockFocus()
    return image
}

// MARK: - DMG Background

func generateDMGBackground() throws {
    let width: CGFloat = 660
    let height: CGFloat = 400

    let image = NSImage(size: NSSize(width: width, height: height))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: width, height: height)

    // Dark gradient background
    let bgGradient = NSGradient(
        colors: [
            NSColor(red: 0.04, green: 0.06, blue: 0.14, alpha: 1.0),
            NSColor(red: 0.08, green: 0.12, blue: 0.24, alpha: 1.0),
        ],
        atLocations: [0.0, 1.0],
        colorSpace: .deviceRGB
    )!
    bgGradient.draw(in: NSBezierPath(rect: rect), angle: -45)

    // Cyan radial glow in center
    let glowRect = NSRect(x: width * 0.2, y: height * 0.1, width: width * 0.6, height: height * 0.8)
    let glowGradient = NSGradient(
        colors: [
            NSColor(red: 0.2, green: 0.8, blue: 1.0, alpha: 0.06),
            NSColor(red: 0.2, green: 0.8, blue: 1.0, alpha: 0.0),
        ]
    )!
    glowGradient.draw(in: NSBezierPath(ovalIn: glowRect), relativeCenterPosition: .zero)

    // Title text
    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 24, weight: .bold),
        .foregroundColor: NSColor(red: 0.9, green: 0.9, blue: 0.95, alpha: 1.0),
    ]
    let title = "Blip" as NSString
    let titleSize = title.size(withAttributes: titleAttrs)
    title.draw(at: NSPoint(x: (width - titleSize.width) / 2, y: height - 60), withAttributes: titleAttrs)

    // Subtitle
    let subtitleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13, weight: .medium),
        .foregroundColor: NSColor(red: 0.6, green: 0.6, blue: 0.65, alpha: 1.0),
    ]
    let subtitle = "Drag to Applications to install" as NSString
    let subtitleSize = subtitle.size(withAttributes: subtitleAttrs)
    subtitle.draw(at: NSPoint(x: (width - subtitleSize.width) / 2, y: height - 85), withAttributes: subtitleAttrs)

    // Arrow between app and Applications
    let arrowY = height / 2 - 15
    let arrowPath = NSBezierPath()
    arrowPath.move(to: NSPoint(x: 230, y: arrowY))
    arrowPath.line(to: NSPoint(x: 420, y: arrowY))
    // Arrowhead
    arrowPath.move(to: NSPoint(x: 410, y: arrowY + 8))
    arrowPath.line(to: NSPoint(x: 420, y: arrowY))
    arrowPath.line(to: NSPoint(x: 410, y: arrowY - 8))
    NSColor(red: 0.3, green: 0.9, blue: 1.0, alpha: 0.4).setStroke()
    arrowPath.lineWidth = 1.5
    arrowPath.stroke()

    image.unlockFocus()

    // Save as JPEG
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let jpegData = rep.representation(using: NSBitmapImageRep.FileType.jpeg, properties: [NSBitmapImageRep.PropertyKey.compressionFactor: 0.5]) else {
        print("⚠ Failed to generate DMG background")
        return
    }

    try jpegData.write(to: URL(fileURLWithPath: "\(outputDir)/dmg-background.jpg"))
    print("✓ Generated dmg-background.jpg")
}

// MARK: - Run

do {
    try generateAppIcon()
    try generateHelperIcon()
    try generateDMGBackground()
    print("✓ All assets generated in \(outputDir)")
} catch {
    fputs("Error: \(error)\n", stderr)
    exit(1)
}
