import SwiftUI

/// What the reader's ⋯ bottom row (`[Bookmarks][Saved][History][Website]`) asks of the browser,
/// which owns those sheets. Supplied by `BrowseStartView` through the environment, so the ✕ reader
/// over the browser and the ‹ reader inside the library sheet reach the same sheets.
struct ReaderMenuHost {
    var showBookmarks: () -> Void
    var showSaved: () -> Void
    var showHistory: () -> Void
    /// Leave the reader for the article's own web page in the browser (closing the library sheet
    /// first when the reader is in it). Playback keeps going; the mini player takes over.
    var openWebsite: (URL) -> Void
}

private struct ReaderMenuHostKey: EnvironmentKey {
    static let defaultValue: ReaderMenuHost? = nil
}

extension EnvironmentValues {
    var readerMenuHost: ReaderMenuHost? {
        get { self[ReaderMenuHostKey.self] }
        set { self[ReaderMenuHostKey.self] = newValue }
    }
}
