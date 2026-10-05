import UIKit
import XCTest

/// How readable the status bar is in a screenshot: the clock's contrast against the strip under it,
/// as WCAG counts it (relative luminance, (L1 + 0.05) / (L2 + 0.05)).
///
/// The region is the leading part of the status bar's frame as SpringBoard reports it (the clock
/// side, clear of the Dynamic Island). The strip's colour is the region's median (the glyphs cover
/// a few percent of it); the text's is the far end of the region's luminance in either direction
/// (0.5% of its pixels, the glyphs' solid cores), whichever stands out more from the strip.
struct StatusBarContrast: CustomStringConvertible {
    enum Text: Equatable {
        /// Lighter than the strip.
        case light
        /// Darker than the strip.
        case dark
    }

    let text: Text
    let ratio: Double
    let stripLuminance: Double

    /// WCAG AA for text (the clock is 17 pt semibold: not "large text", so 4.5:1, not 3:1).
    static let minimum = 4.5

    var isReadable: Bool { ratio >= Self.minimum }

    var description: String {
        "\(text) text at \(String(format: "%.2f", ratio)):1 on a strip of luminance \(String(format: "%.3f", stripLuminance))"
    }

    /// The clock's region of the status bar, in points: its leading 30% (the clock ends before
    /// the Dynamic Island, which starts past a third of the width), its full height.
    static func clockRegion(statusBar frame: CGRect) -> CGRect {
        CGRect(x: frame.minX, y: frame.minY, width: frame.width * 0.3, height: frame.height)
    }

    /// Reads `region` (points) of `screenshot`; nil if it can't be drawn.
    static func read(_ screenshot: UIImage, region: CGRect) -> StatusBarContrast? {
        guard let image = screenshot.cgImage else { return nil }
        let scale = screenshot.scale
        let pixels = CGRect(x: region.minX * scale, y: region.minY * scale,
                            width: region.width * scale, height: region.height * scale).integral
        guard let crop = image.cropping(to: pixels) else { return nil }
        return read(crop)
    }

    static func read(_ crop: CGImage) -> StatusBarContrast? {
        let (w, h) = (crop.width, crop.height)
        guard w > 0, h > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        var levels: [Double] = []
        levels.reserveCapacity(w * h)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            levels.append(luminance(bytes[i], bytes[i + 1], bytes[i + 2]))
        }
        levels.sort()
        let strip = levels[levels.count / 2]
        let tail = max(1, levels.count / 200)
        let lightest = levels[levels.count - tail]
        let darkest = levels[tail - 1]
        let light = contrast(lightest, strip)
        let dark = contrast(darkest, strip)
        return light >= dark
            ? StatusBarContrast(text: .light, ratio: light, stripLuminance: strip)
            : StatusBarContrast(text: .dark, ratio: dark, stripLuminance: strip)
    }

    static func contrast(_ a: Double, _ b: Double) -> Double {
        (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// WCAG relative luminance of an sRGB pixel.
    static func luminance(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Double {
        func linear(_ c: UInt8) -> Double {
            let v = Double(c) / 255
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }
}

extension XCTestCase {
    /// The status bar's frame, from SpringBoard (the app's own tree has no status bar).
    func statusBarFrame() -> CGRect {
        let bar = XCUIApplication(bundleIdentifier: "com.apple.springboard").statusBars.firstMatch
        return bar.exists ? bar.frame : .zero
    }

    /// The status bar's contrast in `screenshot` (now, by default).
    func statusBarContrast(_ screenshot: XCUIScreenshot = XCUIScreen.main.screenshot()) -> StatusBarContrast? {
        let frame = statusBarFrame()
        guard frame.height > 0 else { return nil }
        return StatusBarContrast.read(screenshot.image, region: StatusBarContrast.clockRegion(statusBar: frame))
    }

    /// A screenshot taken `after` seconds into `gesture`, while it holds (a gesture's call returns
    /// only once the finger lifts, so the shot is taken from another thread).
    func screenshot(after delay: TimeInterval, during gesture: () -> Void) -> XCUIScreenshot? {
        let taken = expectation(description: "screenshot during the gesture")
        var shot: XCUIScreenshot?
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
            shot = XCUIScreen.main.screenshot()
            taken.fulfill()
        }
        gesture()
        wait(for: [taken], timeout: delay + 10)
        return shot
    }
}

/// The detector itself, on clocks drawn here: it passes readable ones and rejects unreadable ones,
/// whichever way round the colours are.
final class StatusBarContrastTests: XCTestCase {
    func testItRejectsAClockTheColourOfItsStrip() throws {
        // White on a mid grey (49%): what a light status bar over a half-lifted dim looked like.
        let grey = try XCTUnwrap(reading(text: .white, on: UIColor(white: 0.49, alpha: 1)))
        XCTAssertEqual(grey.text, .light)
        XCTAssertFalse(grey.isReadable, "white on 49% grey: \(grey)")
        XCTAssertEqual(grey.ratio, StatusBarContrast.contrast(1, 0.2051), accuracy: 0.25, "about 4.0:1 measured")

        let dark = try XCTUnwrap(reading(text: .black, on: UIColor(white: 0.25, alpha: 1)))
        XCTAssertFalse(dark.isReadable, "black on dark grey: \(dark)")
        let none = try XCTUnwrap(reading(text: UIColor(white: 0.5, alpha: 1), on: UIColor(white: 0.5, alpha: 1)))
        XCTAssertEqual(none.ratio, 1, accuracy: 0.05, "no clock at all: \(none)")
    }

    func testItPassesAReadableClock() throws {
        // White over the player's dim (0.7 black) on a white page: 30% white.
        let light = try XCTUnwrap(reading(text: .white, on: UIColor(white: 0.3, alpha: 1)))
        XCTAssertEqual(light.text, .light)
        XCTAssertTrue(light.isReadable, "\(light)")
        let dark = try XCTUnwrap(reading(text: .black, on: UIColor(white: 0.96, alpha: 1)))
        XCTAssertEqual(dark.text, .dark)
        XCTAssertTrue(dark.isReadable, "\(dark)")
    }

    /// "9:41" in the status bar's font (17 pt semibold) at 3×, in a 120 × 54 pt strip.
    private func reading(text: UIColor, on strip: UIColor) -> StatusBarContrast? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 54), format: format).image { context in
            strip.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 54))
            ("9:41" as NSString).draw(at: CGPoint(x: 40, y: 17), withAttributes: [
                .font: UIFont.systemFont(ofSize: 17, weight: .semibold), .foregroundColor: text,
            ])
        }
        return StatusBarContrast.read(image, region: CGRect(x: 0, y: 0, width: 120, height: 54))
    }
}
