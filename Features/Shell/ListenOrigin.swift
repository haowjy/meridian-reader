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
/// Library's path, tab and Read in place; the Browser's page, its scroll and, if it was reading, its
/// text. Kept across relaunches (`Stored`, in `SurfaceMemoryStore`): the live `reading` text is not
/// stored, only which article was Read (Library) or that the page was in reader mode (Browser).
struct ListenLaunch {
    enum Place {
        case library(path: [LibraryRoute], tab: LibraryHomeTab, reading: ReaderArticle?)
        case browser(url: URL, reading: ReaderArticle?)
    }

    let place: Place
    /// The Browser page's vertical scroll when Listen was pressed (nil: unknown, or the Library).
    var scrollY: Double?
    /// The Library's Read in place, by key: what a relaunch keeps of `reading`.
    var readingKey: UUID?
    /// The Browser page was in reader mode: what a relaunch keeps of `reading`.
    var wasReading = false

    init(place: Place, scrollY: Double? = nil) {
        self.place = place
        self.scrollY = scrollY
        switch place {
        case .library(_, _, let reading): readingKey = reading?.id
        case .browser(_, let reading): wasReading = reading != nil
        }
    }

    /// The same place as a `ListenOrigin`, for the title block's label.
    var origin: ListenOrigin {
        switch place {
        case .library(let path, _, _): .library(path: path)
        case .browser(let url, _): .browser(url)
        }
    }

    /// The durable form. Its keys are persisted and never change.
    struct Stored: Codable, Equatable {
        enum Kind: String, Codable { case library, browser }
        var kind: Kind
        var libraryPath: [LibraryRoute] = []
        var homeTab: String?
        var readingKey: UUID?
        var url: URL?
        var wasReading = false
        var scrollY: Double?
    }

    var stored: Stored {
        switch place {
        case .library(let path, let tab, _):
            Stored(kind: .library, libraryPath: path, homeTab: tab.rawValue, readingKey: readingKey)
        case .browser(let url, _):
            Stored(kind: .browser, url: url, wasReading: wasReading, scrollY: scrollY)
        }
    }

    /// Back from the durable form, without the live text (nil for one that no longer makes sense).
    init?(stored: Stored) {
        switch stored.kind {
        case .library:
            self.init(place: .library(path: stored.libraryPath,
                                      tab: stored.homeTab.flatMap(LibraryHomeTab.init(rawValue:)) ?? .everything, reading: nil))
            readingKey = stored.readingKey
        case .browser:
            guard let url = stored.url else { return nil }
            self.init(place: .browser(url: url, reading: nil), scrollY: stored.scrollY)
            wasReading = stored.wasReading
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
