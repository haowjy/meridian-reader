import SwiftUI

/// Recently visited pages (the bounded `RecentVisit` list), newest first, in the Library's rows:
/// the site's icon (or its letter tile), the title, then the site (not for an untitled visit,
/// whose title line is already its site) and how long ago. Tap to open; ⋯ and the long press are
/// the page's menu (`ArticleMenu`, on the Library's page for the address when it has one), then
/// *Remove from History*.
///
/// ```
/// History                                           ( Done )
/// ▣  Speech synthesis                                   ⋯
///    en.wikipedia.org   2 hr ago
/// ```
struct BrowseHistoryView: View {
    let visits: [RecentVisit]
    var onOpen: (RecentVisit) -> Void
    var onDone: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if visits.isEmpty {
                    EmptyState(String(localized: "No History Yet"), symbol: Icons.history,
                               description: String(localized: "Pages you open show up here."))
                        .background(Palette.paper)
                } else {
                    List {
                        Section {
                            ForEach(visits, id: \.id) { visit in
                                HistoryRow(visit: visit, onOpen: onOpen)
                            }
                            .listRowInsets(EdgeInsets())
                            .listCard()
                        }
                    }
                    .cardListStyle()
                }
            }
            .navigationTitle(Verbs.history)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                SheetBarButton(Verbs.done, placement: .confirmationAction, identifier: "historyDone", action: onDone)
            }
        }
        .accessibilityIdentifier("browseHistory")
    }
}

/// A visit's row, with its page's menu: the Library's page for its address when there is one
/// (`ArticleLookup`), so its rows read as that page's do everywhere.
private struct HistoryRow: View {
    let visit: RecentVisit
    let onOpen: (RecentVisit) -> Void

    @Environment(LibraryStore.self) private var library
    @Environment(ShellState.self) private var shell
    @Environment(\.speechController) private var speech
    @Environment(PrepareCenter.self) private var preparedAudio
    @Environment(FollowCenter.self) private var follow

    var body: some View {
        ArticleLookup(key: ArticleIdentity.articleKey(canonicalURL: visit.urlString), canonicalURL: visit.urlString) { page in
            let menu = AnyView(VisitMenu(visit: visit,
                                         actions: ArticleActions(article: page, url: visit.url, library: library, shell: shell,
                                                              speech: speech, preparedAudio: preparedAudio, follow: follow),
                                         library: library))
            ListRow(kind: .article(artwork: visit.faviconData.flatMap(UIImage.init(data:)).map(Image.init(uiImage:)),
                                letter: ArticleRowTitle.artworkLetter(title: visit.title, source: visit.host,
                                                              address: visit.urlString)),
                    title: visit.lineOne, subtitle: visit.title.isEmpty ? nil : visit.host,
                    note: visit.visitedAt.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated)),
                    menu: menu, showsListening: false)
                .opensOnTap { onOpen(visit) }
                .contextMenu { menu }
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("historyRow")
        }
    }
}

/// The page's menu, then History's own *Remove from History*.
private struct VisitMenu: View {
    let visit: RecentVisit
    let actions: ArticleActions
    let library: LibraryStore

    var body: some View {
        ArticleMenu(actions: actions, place: .history(onRemove: { library.removeVisit(visit) }))
    }
}
