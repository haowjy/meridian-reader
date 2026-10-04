import SwiftUI

/// Fixed sizes of small glyphs and indicators. They are sizes, not spacing, so changing the
/// spacing scale never resizes them.
enum Glyph {
    /// A part-way progress ring in a chapter row.
    static let ring: CGFloat = 12
    /// Playing bars beside a row's status; the empty slot beside the address field's text.
    static let indicator: CGFloat = 16
    /// A chapter row's leading status mark; the playing bars inside a play button.
    static let mark: CGFloat = 20
}

extension View {
    /// The shadow under things that float over the page: the Now Playing bar, Back to audio,
    /// a book cover.
    func floatingShadow(opacity: Double = 0.14) -> some View {
        shadow(color: .black.opacity(opacity), radius: 12, y: 4)
    }
}
