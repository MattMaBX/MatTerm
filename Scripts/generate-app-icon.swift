import AppKit
import CoreGraphics
import Foundation

let outputPath = CommandLine.arguments.dropFirst().first ?? "Resources/AppIcon.iconset"
let outputURL = URL(fileURLWithPath: outputPath, isDirectory: true)
let fileManager = FileManager.default
try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)

let iconFiles: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for iconFile in iconFiles {
    let size = CGFloat(iconFile.pixels)
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let context = CGContext(
        data: nil,
        width: iconFile.pixels,
        height: iconFile.pixels,
        bitsPerComponent: 8,
        bytesPerRow: iconFile.pixels * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(domain: "MatTermIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to create drawing context"])
    }

    let black = CGColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1)
    let white = CGColor(gray: 1, alpha: 1)
    let softWhite = CGColor(gray: 1, alpha: 0.82)

    context.setFillColor(black)
    context.addPath(CGPath(
        roundedRect: CGRect(x: size * 0.047, y: size * 0.047, width: size * 0.906, height: size * 0.906),
        cornerWidth: size * 0.223,
        cornerHeight: size * 0.223,
        transform: nil
    ))
    context.fillPath()

    context.setStrokeColor(white)
    context.setLineWidth(size * 0.047)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.addPath(CGPath(
        roundedRect: CGRect(x: size * 0.186, y: size * 0.215, width: size * 0.629, height: size * 0.570),
        cornerWidth: size * 0.094,
        cornerHeight: size * 0.094,
        transform: nil
    ))
    context.strokePath()

    let prompt = CGMutablePath()
    prompt.move(to: CGPoint(x: size * 0.311, y: size * 0.607))
    prompt.addLine(to: CGPoint(x: size * 0.420, y: size * 0.500))
    prompt.addLine(to: CGPoint(x: size * 0.311, y: size * 0.393))
    context.addPath(prompt)
    context.strokePath()

    context.setFillColor(white)
    context.addPath(CGPath(
        roundedRect: CGRect(x: size * 0.480, y: size * 0.438, width: size * 0.043, height: size * 0.125),
        cornerWidth: size * 0.0215,
        cornerHeight: size * 0.0215,
        transform: nil
    ))
    context.fillPath()

    context.setStrokeColor(softWhite)
    context.setLineWidth(size * 0.023)
    let baseline = CGMutablePath()
    baseline.move(to: CGPoint(x: size * 0.264, y: size * 0.312))
    baseline.addLine(to: CGPoint(x: size * 0.736, y: size * 0.312))
    context.addPath(baseline)
    context.strokePath()

    guard let image = context.makeImage() else {
        throw NSError(domain: "MatTermIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to encode \(iconFile.name)"])
    }
    let bitmap = NSBitmapImageRep(cgImage: image)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "MatTermIcon", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unable to encode \(iconFile.name)"])
    }
    try png.write(to: outputURL.appendingPathComponent(iconFile.name), options: .atomic)
}

print("Generated MatTerm iconset at \(outputURL.path)")
