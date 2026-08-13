#!/usr/bin/env swift
// Generates the menu-bar template PNGs from the xAI `grok-imagine-image-2.0`
// source (a JPEG: black bar + near-dot on a white background).
//
// Keying: pixels with luminance > 0.85 are treated as background and become
// fully transparent; everything else becomes opaque black. Template images
// are drawn from the alpha mask, so black + alpha is exactly what the menu
// bar needs. The keyed image is downscaled with high-quality interpolation
// so the glyph edges get real anti-aliasing instead of nearest-neighbor
// stairstepping.
//
// Usage: swift scripts/make-menu-bar-icons.swift <source-jpeg> <output-dir>
import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(
        Data("usage: swift make-menu-bar-icons.swift <source-jpeg> <output-dir>\n".utf8))
    exit(1)
}

let sourcePath = arguments[1]
let outputDir = arguments[2]

guard let data = FileManager.default.contents(atPath: sourcePath),
    let source = NSBitmapImageRep(data: data)
else {
    FileHandle.standardError.write(Data("error: cannot load \(sourcePath)\n".utf8))
    exit(1)
}

// Key the full-resolution image once; the two menu-bar sizes are scaled
// down from it afterwards.
guard
    let keyed = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: source.pixelsWide,
        pixelsHigh: source.pixelsHigh,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )
else {
    FileHandle.standardError.write(Data("error: cannot allocate keyed image\n".utf8))
    exit(1)
}

let inPixels = source.bitmapData!
let inRowBytes = source.bytesPerRow
let inSamples = source.samplesPerPixel
let outPixels = keyed.bitmapData!
let outRowBytes = keyed.bytesPerRow

var opaquePixels = 0
for y in 0..<source.pixelsHigh {
    for x in 0..<source.pixelsWide {
        let inOffset = y * inRowBytes + x * inSamples
        let r = Double(inPixels[inOffset]) / 255.0
        let g = Double(inPixels[inOffset + 1]) / 255.0
        let b = Double(inPixels[inOffset + 2]) / 255.0
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        let outOffset = y * outRowBytes + x * 4
        if luminance > 0.85 {
            outPixels[outOffset] = 0
            outPixels[outOffset + 1] = 0
            outPixels[outOffset + 2] = 0
            outPixels[outOffset + 3] = 0
        } else {
            outPixels[outOffset] = 0
            outPixels[outOffset + 1] = 0
            outPixels[outOffset + 2] = 0
            outPixels[outOffset + 3] = 255
            opaquePixels += 1
        }
    }
}
print(
    "keyed \(source.pixelsWide)x\(source.pixelsHigh): \(opaquePixels) opaque glyph pixels, "
        + "\(source.pixelsWide * source.pixelsHigh - opaquePixels) transparent"
)

let keyedImage = NSImage(size: NSSize(width: keyed.pixelsWide, height: keyed.pixelsHigh))
keyedImage.addRepresentation(keyed)

func writeTemplate(size: Int, name: String) throws {
    guard
        let output = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size,
            pixelsHigh: size,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ),
        let context = NSGraphicsContext(bitmapImageRep: output)
    else {
        throw NSError(
            domain: "make-menu-bar-icons",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "cannot allocate \(name)"])
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    keyedImage.draw(
        in: NSRect(x: 0, y: 0, width: size, height: size),
        from: .zero,
        operation: .copy,
        fraction: 1.0
    )
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    guard let png = output.representation(using: .png, properties: [:]) else {
        throw NSError(
            domain: "make-menu-bar-icons",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "cannot encode \(name)"])
    }
    let url = URL(fileURLWithPath: outputDir).appendingPathComponent(name)
    try png.write(to: url)
    print("wrote \(url.path) (\(size)x\(size))")
}

do {
    try writeTemplate(size: 36, name: "MenuBarTemplate@2x.png")
    try writeTemplate(size: 18, name: "MenuBarTemplate.png")
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
