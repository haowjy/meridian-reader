import SwiftData
import SwiftUI

/// Regular-width Now Playing dock: art + title + progress + play clustered in the main pane
/// (Spotify-parallel density). Compact keeps the full-width phone `NowPlayingBar` in `SurfaceBand`.
struct ClusteredPlayerDock: View {
    @Bindable var speech: SpeechController
    /// Hide while the Reader / Now Playing sheet shows its own player.
    var isCovered = false
    /// Optional trailing tools (Browse/Library chrome that used to sit in the five-slot toolbar).
    var trailingTools: AnyView? = nil

    @Environment(ShellState.self) private var shell
    @Environment(FollowCenter.self) private var follow
    @Environment(LibraryStore.self) private var library
    @Environment(PrepareCenter.self) private var preparedAudio
    @Query(LibraryQueries.lastPlayed) private var lastPlayed: [Article]

    private var isHidden: Bool {
        isCovered || shell.isNowPlayingPresented || shell.sheet != nil
    }

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.m) {
            Group {
                if isHidden {
                    placeholder.hidden().accessibilityHidden(true)
                } else if let now = speech.nowPlaying {
                    ClusteredLiveBar(speech: speech, now: now)
                } else if let article = lastPlayed.first(where: \.isLive) {
                    let actions = ArticleActions(article: article, library: library, shell: shell,
                                                 speech: speech, preparedAudio: preparedAudio, follow: follow)
                    ClusteredResumeBar(article: article, actions: actions)
                } else {
                    placeholder
                }
            }
            .frame(maxWidth: RegularLayout.playerClusterWidth, alignment: .leading)

            Spacer(minLength: 0)

            if let trailingTools {
                trailingTools
            }
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.xs)
        .frame(maxWidth: .infinity)
        .background(Palette.chrome.opacity(0.92))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clusteredPlayerDock")
    }

    private var placeholder: some View {
        HStack(spacing: Spacing.s) {
            ArtworkTile(letter: " ", size: PlayerCard.artworkSize)
            VStack(alignment: .leading, spacing: 0) {
                Text(String(localized: "Nothing playing"))
                    .typeStyle(.row, weight: .semibold)
                Text(String(localized: "Pick something to play"))
                    .typeStyle(.caption)
                    .foregroundStyle(Palette.secondaryInk)
            }
            Spacer(minLength: 0)
            PlayStateButton(state: .idle, action: {})
                .disabled(true)
        }
        .foregroundStyle(Palette.secondaryInk)
        .padding(Spacing.s)
        .playerCardSurface()
        .opacity(Palette.disabledOpacity)
    }
}

private struct ClusteredLiveBar: View {
    let speech: SpeechController
    let now: NowPlaying

    @Environment(ShellState.self) private var shell
    @Environment(LibraryStore.self) private var library
    @Environment(FollowCenter.self) private var follow
    @Environment(PrepareCenter.self) private var preparedAudio
    @Query private var articles: [Article]
    @State private var cover = BarCover()

    init(speech: SpeechController, now: NowPlaying) {
        self.speech = speech
        self.now = now
        _articles = Query(LibraryQueries.article(key: now.articleKey))
    }

    var body: some View {
        let doc = speech.document
        let offset = now.isFinished ? doc.utf16Length : speech.spokenUTF16Offset
        let left = ListeningTime.minutesLeft(in: doc, fromUTF16Offset: offset, rate: speech.rateMultiplier)
        let detail: [DetailPart] = now.isFinished ? [.finished]
            : [articles.first?.folder?.name ?? ArticleRowTitle.lineTwoSource(title: now.title, source: now.source),
               ListeningTime.leftLabel(minutes: left)]
                .compactMap { $0 }.map { DetailPart($0) }
        let actions = ArticleActions(article: articles.first.flatMap { $0.isLive ? $0 : nil },
                                     library: library, shell: shell, speech: speech,
                                     preparedAudio: preparedAudio, follow: follow)
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.s) {
                Button(action: shell.showNowPlaying) {
                    HStack(spacing: Spacing.s) {
                        ArtworkTile(image: cover.image(for: now.articleKey, data: now.artwork),
                                    letter: now.artworkLetter, size: PlayerCard.artworkSize)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(now.lineOne)
                                .typeStyle(.row, weight: .semibold)
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                            DetailLine(parts: detail)
                                .typeStyle(.caption)
                                .foregroundStyle(Palette.secondaryInk)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("clusteredPlayerOpen")

                PlayStateButton(state: speech.playState(of: .article(now.articleKey)),
                                action: speech.pressNowPlaying)
                    .accessibilityIdentifier("clusteredPlayerPlayPause")
            }
            ProgressLine(fraction: doc.progress(atUTF16Offset: offset),
                         height: PlayerCard.progressHeight, track: .groove)
        }
        .padding(Spacing.s)
        .playerCardSurface()
        .contextMenu {
            ArticleMenu(actions: actions, place: .bar(onStop: speech.stop))
        }
    }
}

private struct ClusteredResumeBar: View {
    let article: Article
    let actions: ArticleActions
    @State private var cover = BarCover()

    var body: some View {
        if article.isLive {
            let library = actions.libraryActions
            let progress = library.progress(of: article)
            HStack(spacing: Spacing.s) {
                Button { library.open(article) } label: {
                    HStack(spacing: Spacing.s) {
                        ArtworkTile(image: cover.image(for: article.listenKey, data: article.artworkData),
                                    letter: article.artworkLetter, size: PlayerCard.artworkSize)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(article.lineOne)
                                .typeStyle(.row, weight: .semibold)
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                            DetailLine(parts: detail(progress))
                                .typeStyle(.caption)
                                .foregroundStyle(Palette.secondaryInk)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
                PlayStateButton(state: library.playState(of: article)) { library.play(article) }
            }
            .padding(Spacing.s)
            .playerCardSurface()
            .contextMenu {
                ArticleMenu(actions: actions, place: .bar(onStop: nil))
            }
        }
    }

    private func detail(_ progress: ListRow.Progress) -> [DetailPart] {
        let source = (article.folder?.name ?? ArticleRowTitle.lineTwoSource(title: article.givenTitle,
                                                                            source: article.source))
            .map { [DetailPart($0)] } ?? []
        switch progress {
        case .partWay(_, let minutesLeft): return source + [DetailPart(ListeningTime.leftLabel(minutes: minutesLeft))]
        case .finished: return [.finished]
        default: return source
        }
    }
}
