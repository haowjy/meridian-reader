import UIKit
import Vision
import XCTest

/// A line of text read off a screenshot: what it says, where it is (points, top-left origin) and
/// its ink (the brightest pixel inside it, relative luminance).
struct ScreenLine: CustomStringConvertible {
    let text: String
    let frame: CGRect
    let ink: Double

    var description: String { "\"\(text)\" ink \(String(format: "%.2f", ink)) at y \(Int(frame.minY))" }
}

enum ScreenText {
    /// Every line of text Vision reads in `shot`.
    static func lines(in shot: XCUIScreenshot) throws -> [ScreenLine] {
        let image = shot.image
        guard let cg = image.cgImage else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: cg).perform([request])
        let size = CGSize(width: CGFloat(cg.width) / image.scale, height: CGFloat(cg.height) / image.scale)
        let pixels = Pixels(cg)
        return (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            // Vision's boxes are normalized with a bottom-left origin.
            let box = observation.boundingBox
            let frame = CGRect(x: box.minX * size.width, y: (1 - box.maxY) * size.height,
                               width: box.width * size.width, height: box.height * size.height)
            return ScreenLine(text: text, frame: frame, ink: pixels.brightest(in: frame, scale: image.scale))
        }
    }
}

/// An sRGB copy of a screenshot's pixels.
private struct Pixels {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init(_ image: CGImage) {
        let (w, h) = (image.width, image.height)
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        bytes.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                      bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?
                .draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        (width, height, self.bytes) = (w, h, bytes)
    }

    /// The highest relative luminance inside `rect` (points).
    func brightest(in rect: CGRect, scale: CGFloat) -> Double {
        let r = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale,
                       height: rect.height * scale).integral
            .intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !r.isNull, !r.isEmpty else { return 0 }
        var peak = 0.0
        for y in Int(r.minY)..<Int(r.maxY) {
            for x in Int(r.minX)..<Int(r.maxX) {
                let i = (y * width + x) * 4
                peak = max(peak, StatusBarContrast.luminance(bytes[i], bytes[i + 1], bytes[i + 2]))
            }
        }
        return peak
    }
}

extension XCTestCase {
    /// Screenshots taken `delays` seconds into `gesture`, while it holds (a gesture's call returns
    /// only once the finger lifts, so the shots are taken from another thread). A shot can land
    /// before the finger is down or after it lifts: callers check each one shows the held state.
    func screenshots(at delays: [TimeInterval], during gesture: () -> Void) -> [XCUIScreenshot] {
        let lock = NSLock()
        var shots: [(TimeInterval, XCUIScreenshot)] = []
        let taken = delays.map { delay -> XCTestExpectation in
            let done = expectation(description: "screenshot \(delay) s into the gesture")
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                let shot = XCUIScreen.main.screenshot()
                lock.lock()
                shots.append((delay, shot))
                lock.unlock()
                done.fulfill()
            }
            return done
        }
        gesture()
        wait(for: taken, timeout: (delays.max() ?? 0) + 10)
        return shots.sorted { $0.0 < $1.0 }.map(\.1)
    }
}
