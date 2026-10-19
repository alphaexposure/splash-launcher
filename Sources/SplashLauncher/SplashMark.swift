import AppKit
import SwiftUI

/// The Splash Launcher mark: an upright S-Wave, a circle split by an S into two halves.
/// Concept developed with ChatGPT design assistance; traced here as two smooth outlines.
/// This file is the single source for the app icon, the sidebar mark and the menu bar symbol,
/// and is compiled into `Scripts/make-icon` as well as the app.
enum SplashMark {
    /// Outline points in the concept artwork's pixel space (y down), joined by smooth curves.
    /// Changes from the concept: the left half's lower tail is shorter so the S gap never
    /// pinches shut, and the tail tips are fuller so they survive 16 px.
    static let leftHalf: [CGPoint] = [
        (790, 262), (770, 238), (700, 220), (600, 222), (480, 255), (380, 330), (316, 430), (300, 530),
        (335, 630), (410, 700), (500, 745), (556, 780), (588, 838), (582, 888), (560, 916),
        (584, 922), (640, 878), (684, 800), (692, 720), (660, 645), (596, 580), (548, 505),
        (536, 425), (565, 352), (640, 304), (730, 286), (782, 284),
    ].map { CGPoint(x: $0.0, y: $0.1) }

    static let rightHalf: [CGPoint] = [
        (700, 362), (770, 366), (858, 404), (934, 482), (976, 582), (984, 668), (958, 784), (888, 892),
        (790, 976), (680, 1012), (590, 1010), (522, 988), (508, 962),
        (540, 954), (628, 942), (712, 906), (776, 836), (802, 742), (790, 650), (748, 588),
        (690, 528), (654, 468), (650, 414), (668, 378),
    ].map { CGPoint(x: $0.0, y: $0.1) }

    /// The concept's tile, used to place the mark on the app icon tile the same way.
    static let conceptTile = CGRect(x: 95, y: 80, width: 1067, height: 1067)

    /// Both halves in concept space (y down).
    static let conceptPath: CGPath = {
        let path = CGMutablePath()
        path.addPath(smoothClosed(leftHalf))
        path.addPath(smoothClosed(rightHalf))
        return path
    }()

    /// The mark scaled to fit `rect` without distortion, centred (y down, as in SwiftUI).
    static func path(fitting rect: CGRect) -> CGPath {
        let bounds = conceptPath.boundingBoxOfPath
        let scale = min(rect.width / bounds.width, rect.height / bounds.height)
        var transform = CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -bounds.midX, y: -bounds.midY)
        return conceptPath.copy(using: &transform) ?? conceptPath
    }

    /// A closed outline through the points, as Catmull-Rom curves converted to cubic Béziers.
    static func smoothClosed(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath(), n = points.count
        path.move(to: points[0])
        for i in 0..<n {
            let p0 = points[(i - 1 + n) % n], p1 = points[i], p2 = points[(i + 1) % n], p3 = points[(i + 2) % n]
            path.addCurve(to: p2,
                          control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                          control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
        path.closeSubpath()
        return path
    }

    /// Menu bar symbol: a template image, so macOS tints it for light and dark menu bars.
    static func menuBarImage(pointSize: CGFloat = 16) -> NSImage {
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.addPath(path(fitting: rect.insetBy(dx: 0.5, dy: 0.5)))
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Splash Launcher"
        return image
    }

    /// Draws the app icon (light tile) into a y-up bitmap context of `size` pixels.
    static func drawAppIcon(in context: CGContext, size: CGFloat) {
        let unit = size / 1024
        context.saveGState()
        context.scaleBy(x: unit, y: unit)
        let tileRect = CGRect(x: 100, y: 100, width: 824, height: 824)
        let tile = CGPath(roundedRect: tileRect, cornerWidth: 186, cornerHeight: 186, transform: nil)

        context.saveGState()   // soft shadow under the tile
        context.setShadow(offset: CGSize(width: 0, height: -10), blur: 22,
                          color: CGColor(srgbRed: 0, green: 0.12, blue: 0.16, alpha: 0.18))
        context.addPath(tile)
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fillPath()
        context.restoreGState()

        context.saveGState()   // tile: white fading to a pale teal-grey
        context.addPath(tile)
        context.clip()
        drawVerticalGradient(context, top: (1, 1, 1), bottom: (0.918, 0.953, 0.961), in: tileRect)
        context.restoreGState()

        // Mark: concept space (y down) mapped onto the tile (y up), same placement as the concept.
        let scale = tileRect.width / conceptTile.width
        var transform = CGAffineTransform(translationX: tileRect.minX, y: tileRect.maxY)
            .scaledBy(x: scale, y: -scale)
            .translatedBy(x: -conceptTile.minX, y: -conceptTile.minY)
        let mark = conceptPath.copy(using: &transform) ?? conceptPath
        context.saveGState()
        context.addPath(mark)
        context.clip()
        drawVerticalGradient(context, top: (0.173, 0.643, 0.694), bottom: (0.067, 0.376, 0.424),
                             in: mark.boundingBoxOfPath)
        context.restoreGState()
        context.restoreGState()
    }

    private static func drawVerticalGradient(_ context: CGContext, top: (CGFloat, CGFloat, CGFloat),
                                             bottom: (CGFloat, CGFloat, CGFloat), in rect: CGRect) {
        let colours = [CGColor(srgbRed: top.0, green: top.1, blue: top.2, alpha: 1),
                       CGColor(srgbRed: bottom.0, green: bottom.1, blue: bottom.2, alpha: 1)] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colours,
                                        locations: [0, 1]) else { return }
        context.drawLinearGradient(gradient, start: CGPoint(x: rect.midX, y: rect.maxY),
                                   end: CGPoint(x: rect.midX, y: rect.minY), options: [])
    }
}

/// The mark as a SwiftUI shape, for the sidebar and the menu bar window.
struct SplashMarkShape: Shape {
    func path(in rect: CGRect) -> Path { Path(SplashMark.path(fitting: rect)) }
}
