import SwiftUI

/// What a reading page (the Reader, Now Playing) hands the chrome host: its player card, drawn on
/// the host's glass above row 2, and the rows only the page can run in its ⋯. The page holds the
/// article, the playhead and the actions; the host holds the geometry, so the card goes with the
/// rest of the chrome when it folds (Listen never folds).
struct ChromeCard {
    let content: AnyView
    var menuRows: [MenuRow] = []
}

struct ChromeCardKey: PreferenceKey {
    static let defaultValue: ChromeCard? = nil

    static func reduce(value: inout ChromeCard?, nextValue: () -> ChromeCard?) {
        value = nextValue() ?? value
    }
}

extension View {
    /// Compact width: this reading page's card and ⋯ rows, for the chrome host to draw.
    func chromeCard(_ card: ChromeCard?) -> some View {
        preference(key: ChromeCardKey.self, value: card)
    }
}
