import AppKit
import Foundation

// Renders the app icon at every iconset size from the shared mark in
// Sources/SplashLauncher/SplashMark.swift (compiled together with this file by build-app.zsh).
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent(".build/Splash.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(size: Int, name: String) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    context.imageInterpolation = .high
    SplashMark.drawAppIcon(in: context.cgContext, size: CGFloat(size))
    context.flushGraphics()
    try bitmap.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
}
for size in [16, 32, 128, 256, 512] {
    try render(size: size, name: "icon_\(size)x\(size).png")
    try render(size: size * 2, name: "icon_\(size)x\(size)@2x.png")
}
