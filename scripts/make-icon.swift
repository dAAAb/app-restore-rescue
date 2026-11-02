import AppKit
import Foundation

// Original vector artwork. Built on CI; no downloaded images or brand logos.
guard CommandLine.arguments.count == 2 else {
    fputs("Usage: swift scripts/make-icon.swift OUTPUT.iconset\n", stderr)
    exit(2)
}
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

func icon(pixelSize: Int) throws -> Data {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixelSize, pixelsHigh: pixelSize,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let scale = CGFloat(pixelSize) / 1024
    context.cgContext.scaleBy(x: scale, y: scale)

    let tile = NSBezierPath(roundedRect: NSRect(x: 30, y: 30, width: 964, height: 964), xRadius: 216, yRadius: 216)
    NSGradient(starting: NSColor(calibratedRed: 0.12, green: 0.27, blue: 0.62, alpha: 1),
               ending: NSColor(calibratedRed: 0.12, green: 0.59, blue: 0.69, alpha: 1))!.draw(in: tile, angle: 55)

    NSColor(calibratedWhite: 1, alpha: 0.98).setFill()
    NSBezierPath(ovalIn: NSRect(x: 180, y: 438, width: 290, height: 290)).fill()
    NSBezierPath(ovalIn: NSRect(x: 322, y: 488, width: 390, height: 390)).fill()
    NSBezierPath(ovalIn: NSRect(x: 584, y: 438, width: 270, height: 270)).fill()
    NSBezierPath(roundedRect: NSRect(x: 240, y: 410, width: 550, height: 220), xRadius: 100, yRadius: 100).fill()

    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 512, y: 570))
    arrow.line(to: NSPoint(x: 512, y: 244))
    arrow.move(to: NSPoint(x: 358, y: 390))
    arrow.line(to: NSPoint(x: 512, y: 236))
    arrow.line(to: NSPoint(x: 666, y: 390))
    arrow.lineWidth = 90
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    NSColor(calibratedRed: 0.99, green: 0.75, blue: 0.24, alpha: 1).setStroke()
    arrow.stroke()

    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return data
}

for pointSize in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let suffix = factor == 2 ? "@2x" : ""
        let file = directory.appendingPathComponent("icon_\(pointSize)x\(pointSize)\(suffix).png")
        try icon(pixelSize: pointSize * factor).write(to: file)
    }
}
