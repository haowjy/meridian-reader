import SwiftUI

/// Reader chrome layout (docs/NAVIGATION.md). The text runs edge to edge; the top row and the
/// bottom controls (the browser's bottom chrome, `BottomChrome.swift`) sit over it and never hide,
/// exactly like the browser's search bar / toolbar (Nav H). The reading views inset their scroll
/// content by these amounts so the first and last lines always scroll clear of the bars.

/// Room the text leaves for the reader chrome (points; includes the safe area).
struct ReaderTextInsets: Equatable {
    var top: CGFloat = 0
    var bottom: CGFloat = 0
}
