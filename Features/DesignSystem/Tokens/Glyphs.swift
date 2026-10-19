import SwiftUI

/// Fixed sizes of small glyphs and indicators. They are sizes, not spacing, so changing the
/// spacing scale never resizes them.
enum Glyph {
    /// A part-way listening ring before a row's time left (rings mean listening, nothing else).
    static let ring: CGFloat = 12
    /// Playing bars beside a row's status; the empty slot beside the address field's text.
    static let indicator: CGFloat = 16
    /// A book preview's chapter row's empty leading mark (`ListRow`); the playing bars inside a
    /// play button; a Settings row's leading symbol, and its ✓ or spinner.
    static let mark: CGFloat = 20
    /// A round control: a download's `DownloadMark` in the Downloads list and a folder header, the
    /// header's ⋯.
    static let control: CGFloat = 28
    /// A voice model's download in Settings, beside its row's text.
    static let modelDownload: CGFloat = 24
    /// The leading slot of every band field (Library search and the browser's address): 🔍, or
    /// on a loaded page its 📄 / spinner, always this square so the text starts at one place.
    static let fieldLeading: CGFloat = 30
}

extension View {
    /// The shadow under things that float over the page: the Now Playing bar, Jump to Audio,
    /// a book cover.
    func floatingShadow(opacity: Double = 0.14) -> some View {
        shadow(color: Palette.scrim.opacity(opacity), radius: 12, y: 4)
    }
}
