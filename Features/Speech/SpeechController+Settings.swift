import Foundation

/// The listen speed: one of `options`. The stored setting and its launch argument, the setter,
/// the players, the lock screen's speed command and the pickers all go through it, so a speed
/// outside the list (an older build's stored value) loads as the nearest one in it.
enum ListenRate {
    static let options: [Double] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    /// The option nearest `value`.
    static func nearest(to value: Double) -> Double {
        options.min { abs($0 - value) < abs($1 - value) } ?? 1
    }

    /// "1×", "1.25×".
    static func label(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        return abs(rounded - 1) < 0.01 ? "1×" : String(format: "%g×", rounded)
    }
}

extension SpeechController {
    /// Settings → Speed lists these (`ListenRate.options`).
    static var rateOptions: [Double] { ListenRate.options }
}
