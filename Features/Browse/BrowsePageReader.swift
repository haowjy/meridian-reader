import SwiftUI

/// The Browser's page as the Reader draws it, in place of the page (Safari's Reader): under the same
/// bottom chrome, whose address pill keeps the URL and whose reader icon, lit, puts the page back.
/// A slim bar on top has Aa and Listen. Listen plays the page and raises Now Playing, the primary
/// reader; this view is only a temporary one, so it ends there. Links navigate the browser.
struct BrowsePageReader: View {
    let article: ReaderArticle
    @Bindable var speech: SpeechController

    @Environment(LibraryStore.self) private var library
    @Environment(ShellState.self) private var shell
    @Environment(\.readingAppearance) private var appearance

    private var palette: ReadingPalette { appearance.palette(accent: AppAppearance.shared.accent) }

    var body: some View {
        let page = library.article(key: article.id, canonicalURL: article.origin.canonicalURL)
        let start = page?.listenStart ?? ListenSpot(paragraph: article.resumeParagraph)
        let label = article.listenLabel(from: start, finished: page?.finishedAt != nil, rate: speech.rateMultiplier)
        VStack(spacing: 0) {
            HStack(spacing: Spacing.s) {
                TextAppearanceControl()
                Spacer(minLength: 0)
                PillButton(label.title, detail: label.detail, systemImage: Icons.play, size: .compact) {
                    listen(from: start)
                }
                .disabled(article.document.isEmpty)
                .accessibilityIdentifier("pageReaderListen")
            }
            .padding(.horizontal, Spacing.pageMargin)
            .padding(.vertical, Spacing.xs)
            HTMLReadingView(html: article.readingHTML,
                            heading: ReaderHeading(title: article.title, detail: [article.sourceLabel].filter { !$0.isEmpty }),
                            activeParagraphIndex: nil, onOpenLink: shell.navigate(to:)) { _ in }
                .regularReadableMeasure(isRegular: false)
        }
        .safeAreaPadding(.bottom, ChromeMetrics.footprint)
        .background(palette.background.ignoresSafeArea())
        .readingSurface(palette)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("browsePageReader")
        .task(id: WarmKey(id: article.id, count: article.document.count)) {
            speech.warmUp(article, from: start, saved: page?.isSavedToLibrary == true)
        }
    }

    private func listen(from start: ListenSpot) {
        speech.listen(to: article, at: start)
        shell.showNowPlaying()
    }

    private struct WarmKey: Hashable {
        let id: UUID
        let count: Int
    }
}
