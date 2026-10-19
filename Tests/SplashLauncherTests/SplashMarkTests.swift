import AppKit
import XCTest
@testable import SplashLauncher

final class SplashMarkTests: XCTestCase {
    func testHalvesNeverTouchSoTheSGapStaysOpen() {
        let left = SplashMark.smoothClosed(SplashMark.leftHalf)
        let right = SplashMark.smoothClosed(SplashMark.rightHalf)
        XCTAssertFalse(left.intersects(right))
    }

    func testMarkFitsAndCentresInAnyRect() {
        for rect in [CGRect(x: 0, y: 0, width: 16, height: 16), CGRect(x: 10, y: 20, width: 300, height: 120)] {
            let bounds = SplashMark.path(fitting: rect).boundingBoxOfPath
            XCTAssertTrue(rect.insetBy(dx: -0.01, dy: -0.01).contains(bounds), "\(bounds) outside \(rect)")
            XCTAssertEqual(bounds.midX, rect.midX, accuracy: 0.01)
            XCTAssertEqual(bounds.midY, rect.midY, accuracy: 0.01)
        }
    }

    func testMenuBarImageIsATemplateSoMacOSTintsIt() {
        let image = SplashMark.menuBarImage(pointSize: 18)
        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
    }

    func testAppIconDrawsTheMarkOnALightTileWithTransparentCorners() throws {
        let size = 256
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        SplashMark.drawAppIcon(in: context.cgContext, size: CGFloat(size))
        context.flushGraphics()

        XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: 2, y: 2)).alphaComponent, 0, accuracy: 0.01)
        // Tile background near its top edge is close to white.
        let tile = try XCTUnwrap(bitmap.colorAt(x: size / 2, y: 30)?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(tile.redComponent, 0.95)
        // The mark's lower-right lobe is teal: more blue and green than red.
        let mark = try XCTUnwrap(bitmap.colorAt(x: Int(Double(size) * 0.72), y: Int(Double(size) * 0.55))?.usingColorSpace(.sRGB))
        XCTAssertLessThan(mark.redComponent, 0.3)
        XCTAssertGreaterThan(mark.greenComponent, mark.redComponent + 0.2)
    }
}
