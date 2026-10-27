import Foundation

/// Where the article on Listen lives, which the card's title block opens (it never seeks): the
/// Library at the place it is saved, or the Browser on its page.
enum ListenOrigin: Equatable {
    /// The Library at `path` (its folder or book; `[]` is the home).
    case library(path: [LibraryRoute])
    /// The page's own address.
    case browser(URL)

    /// The title block's accessibility label: "Open Notes on Tides in Library".
    func label(title: String) -> String {
        switch self {
        case .library: String(localized: "Open \(title) in Library")
        case .browser: String(localized: "Open \(title) in Browser")
        }
    }
}

/// The place a listening was launched from (`ShellState.listenLaunch`), with what it showed: the
/// Library's path, tab and Read in place; the Browser's page and, if it was reading, its text.
struct ListenLaunch {
    enum Place {
        case library(path: [LibraryRoute], tab: LibraryHomeTab, reading: ReaderArticle?)
        case browser(url: URL, reading: ReaderArticle?)
    }

    let place: Place

    /// The same place as a `ListenOrigin`, for the title block's label.
    var origin: ListenOrigin {
        switch place {
        case .library(let path, _, _): .library(path: path)
        case .browser(let url, _): .browser(url)
        }
    }
}

extension ShellState {
    /// The title block's tap: leaves Listen for the article's origin. The Library at its place
    /// (`showLibrary`, through the same path as *Go to*); the Browser on its page, in reader mode in place
    /// when it is the page already loaded (`article` is then its text), else the page itself loads.
    /// Playback keeps going. Nothing for an origin that is gone (the caller passes nil).
    func openOrigin(_ origin: ListenOrigin, article: ReaderArticle?) {
        switch origin {
        case .library(let path):
            showLibrary(at: path)
        case .browser(let url):
            if let current = web.currentURL, current.isSamePage(as: url) {
                endAddressSearch()
                showBrowser()
                if let article, readsInPlace { openPageReader(article, requestedAt: pageReaderEpoch) }
            } else {
                navigate(to: url)
            }
        }
    }
}
