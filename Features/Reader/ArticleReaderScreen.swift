import SwiftUI
import SwiftData

/// The one reader screen. Browse Reader Mode and the library both render this, so typography,
/// renderer, top row, scrub row, listen bar, Jump and highlight are identical. `presentation`
/// decides how it closes; `origin` decides where "back" leads.
///
/// Top row: `[title]`. The overlay closes by pulling it down; the pushed reader pops with the
/// edge swipe (`edgeSwipeBack()`). Both do exactly what the back control does.
/// Bottom (thumb reach), above the listen controls: `[back] ( [scrubber] [select paragraph] [bookmark] )`
/// - back: the one close control, within thumb reach. It returns to where the reader was opened
///   from (`ReaderOrigin`: the web page, the start page, or the library) and says which.
/// - bookmark: `bookmark` = unsaved (tap saves) / `bookmark.fill` = saved (tap unsaves)
/// - select paragraph (hand.tap): while on, a slim hint banner floats over the article top.
/// Listen bar: `[1×] [⏮] [▶︎] [⏭] [⋯]`. ⋯ opens the shell's menu panel in reader context
/// (`MenuContext.reader`: Voice settings, Save, Bookmark, Share, Debug; bottom row Bookmarks /
/// Saved / History / Website). Website (reader off) opens the article's own page in the browser
/// from anywhere — the library too — and playback keeps going.
///
/// The text runs edge to edge, under the top row and the bottom controls (the browser's
/// bottom-chrome style), inset so its first / last lines clear them. The bars never hide — they
/// behave like the browser's search bar / toolbar. See `ReaderChrome.swift`.
///
/// Save/Unsave only flips the bookmark: the article key is already the saved id (identity v2),
/// so the view, the `SpeechSession`, and any playing audio are untouched.
struct ArticleReaderScreen: View {
    let article: ReaderArticle
    let presentation: ReaderPresentation
    let origin: ReaderOrigin
    var onClose: () -> Void
    /// Only when Save resolved to a different id than `article.id` (legacy row saved mid-read).
    var onIdentityChange: ((UUID) -> Void)? = nil

    @Bindable var speech: SpeechController

    @Environment(\.modelContext) private var modelContext
    @Environment(ShellState.self) private var shell
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var savedRows: [SavedArticle]
    @State private var jumpMode = false
    /// Overlay only: how far the top bar is being pulled down (swipe-down-to-close).
    @State private var pullDownOffset: CGFloat = 0
    /// Axis of the pull in progress, fixed at its first movement (nil between drags).
    @State private var pullDownAxis: Axis?
    /// Overlay only: the screen's height (a committed pull-down carries the reader off it).
    @State private var screenHeight: CGFloat = 0
    /// The screen's safe area (the text runs under it; the bars and text insets respect it).
    @State private var safeInsets = EdgeInsets()
    /// Overlay top row height (the pushed reader's row lives in the navigation bar instead).
    @State private var topRowHeight: CGFloat = 0

    init(
        article: ReaderArticle,
        presentation: ReaderPresentation,
        origin: ReaderOrigin,
        speech: SpeechController,
        onClose: @escaping () -> Void,
        onIdentityChange: ((UUID) -> Void)? = nil
    ) {
        self.article = article
        self.presentation = presentation
        self.origin = origin
        _speech = Bindable(speech)
        self.onClose = onClose
        self.onIdentityChange = onIdentityChange
        let id = article.id
        let canonical = article.canonicalURL
        _savedRows = Query(filter: #Predicate<SavedArticle> { $0.id == id || $0.canonicalURL == canonical })
    }

    private var savedRow: SavedArticle? {
        savedRows.first { $0.id == article.id } ?? savedRows.first
    }

    private var isSaved: Bool { savedRow != nil }

    private var session: SpeechSession {
        SpeechSession(id: article.id, document: article.document, detectedLanguage: article.detectedLanguage,
                      title: article.title, site: article.siteName ?? article.siteDomain, artwork: article.faviconData)
    }

    private var sessionReady: Bool { !article.document.isEmpty }

    private var isLiveSession: Bool { speech.activeSessionID == article.id }

    private var resumeParagraph: Int {
        savedRow?.playbackParagraphIndex ?? article.resumeParagraph
    }

    /// Pushed in the library's `NavigationStack`: the row lives *in* the system navigation bar
    /// (bar stays visible, back button hidden) so push/pop — including the edge swipe — is the
    /// standard iOS transition. A hidden bar would let the list's bar (title, voice button) show
    /// full-width over the reader mid-swipe. The overlay has no navigation bar, so it draws the
    /// same row inline.
    private var rowInNavigationBar: Bool { presentation == .pushed }

    /// Overlay top band (below the safe area) + 6 pt of air above the text.
    private var topChromeHeight: CGFloat { rowInNavigationBar ? 0 : topRowHeight + 6 }

    @ViewBuilder
    var body: some View {
        if rowInNavigationBar {
            content
                .toolbar {
                    ToolbarItem(placement: .principal) { navigationBarRow }
                }
                // The same bar material as the browser's bottom band. The shell's ⋯ menu dims it
                // with the rest of the screen.
                .toolbarBackground(.bar, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        } else {
            // The browser stays live underneath, so pulling the reader down reveals where it
            // goes back to: the reader shrinks a little and the dim behind it lifts as it goes.
            let pulled = PullDownLook(offset: pullDownOffset, screenHeight: screenHeight)
            content
                .scaleEffect(pulled.scale, anchor: .top)
                .offset(y: pullDownOffset)
                .background {
                    Color.black.opacity(pulled.dim)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height + $0.safeAreaInsets.top + $0.safeAreaInsets.bottom } action: {
                    screenHeight = $0
                }
        }
    }

    private var content: some View {
        ZStack(alignment: .top) {
            ArticleListenSurface(
                cleanedHTML: article.displayHTML,
                pageTitle: nil, // already stripped in `displayHTML`
                session: session,
                resumeParagraph: resumeParagraph,
                resumeUTF16Offset: savedRow?.playbackUTF16Offset,
                onProgress: { paragraph, offset in
                    guard let row = savedRow else { return }
                    row.playbackParagraphIndex = paragraph
                    row.playbackUTF16Offset = offset
                },
                jumpMode: $jumpMode,
                speech: speech,
                scrubControls: ReaderScrubControls(
                    isSaved: isSaved,
                    jumpEnabled: sessionReady,
                    toggleJump: toggleJump,
                    toggleSaved: toggleSaved,
                    back: origin,
                    onBack: close
                ),
                listenTrailing: AnyView(moreButton),
                safeInsets: safeInsets,
                topChromeHeight: topChromeHeight
            )
            .ignoresSafeArea()

            if !rowInNavigationBar {
                topBar
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                        if abs($0 - topRowHeight) > 0.5 { topRowHeight = $0 }
                    }
            }

            if jumpMode {
                jumpBanner
                    .padding(.top, topChromeHeight)
                    .transition(.slideAndFade(from: .top, reduceMotion: reduceMotion))
            }
        }
        .animation(Motion.snappy, value: jumpMode)
        .background {
            Color(.systemBackground)
                .ignoresSafeArea()
                .onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: { safeInsets = $0 }
        }
        .task(id: WarmKey(id: article.id, count: article.document.count)) {
            prepareListen()
        }
        .onDisappear(perform: persistProgress)
    }

    // MARK: - ⋯ menu

    /// Bottom-right of the listen row: the same cell, glyph and size as the browser's ⋯
    /// (`toolbarIconFrame` in `BottomToolbarLayout`), so the menu grows from the same spot.
    private var moreButton: some View {
        MoreMenuButton(id: "readerMore") { .reader(readerMenu, perform: perform) }
            .foregroundStyle(Palette.ink)
    }

    private var readerMenu: ReaderMenu {
        ReaderMenu(
            isSaved: isSaved,
            canSave: sessionReady,
            isBookmarked: articleURL.flatMap { BookmarkStore.shared.bookmark(for: $0) } != nil,
            canBookmark: articleURL.map(BookmarkStore.isBookmarkable) ?? false,
            canShare: shareURL != nil,
            canOpenWebsite: websiteURL != nil,
            showsDebug: speech.developerOptionsEnabled
        )
    }

    private var articleURL: URL? { URL(string: article.urlString) }

    /// The article's own page, for ⋯ → Website (any loadable page URL, not just http(s)).
    private var websiteURL: URL? {
        guard let url = articleURL, url.scheme != nil, url.host?.isEmpty == false else { return nil }
        return url
    }

    private var shareURL: URL? {
        guard let url = articleURL, url.isWeb else { return nil }
        return url
    }

    private func perform(_ action: ReaderMenu.Action) {
        switch action {
        case .voiceSettings: shell.present(.voiceSettings)
        case .toggleSave: toggleSaved()
        case .toggleBookmark: toggleBookmark()
        case .share: if let shareURL { shell.present(.share(shareURL)) }
        case .listenDebug: speech.showListenDebug = true
        case .bookmarks: shell.present(.bookmarks)
        // Opened from the library, you're already in Saved: go back to the list.
        case .saved: if origin == .library { close() } else { shell.openLibrary() }
        case .history: shell.present(.history)
        // Reader off = the article's own web page in the browser, wherever the reader was opened
        // from (library, start page, Continue listening, mini player). Playback keeps going.
        case .openWebsite:
            if let websiteURL { persistProgress(); shell.openWebsite(websiteURL) } else { close() }
        }
    }

    /// Site bookmark for the article's page (URL, title, icon only; independent of Save).
    private func toggleBookmark() {
        guard let url = articleURL, BookmarkStore.isBookmarkable(url) else { return }
        let title = article.title
        let icon = article.faviconData
        Task {
            await BookmarkStore.shared.toggle(url: url, title: title, faviconData: icon) {
                await FaviconFetcher.best(for: url, webView: nil)
            }
        }
    }

    // MARK: - Top bar

    /// Inline (overlay) version of the row, styled like the browser's bottom chrome mirrored to
    /// the top: the title in the address-field capsule on the same bar material (running up
    /// under the status bar), same margins. Pull-down-to-close.
    private var topBar: some View {
        topRow
            .bottomChromeField(leading: Spacing.xxs, trailing: Spacing.xxs)
            .padding(.horizontal, BottomChrome.horizontalMargin)
            .padding(.top, Spacing.xxs)
            .padding(.bottom, BottomChrome.topPadding)
            .background(.bar)
            .contentShape(Rectangle())
            // Only the overlay gets pull-down-to-close, and only from the top bar, so it never
            // competes with scrolling, text selection or Jump taps in the article.
            .gesture(pullDownToClose, including: presentation == .overlay ? .all : .subviews)
    }

    /// Pushed (library) version: the row sits in the navigation bar so push / pop and the edge
    /// swipe stay the standard iOS transition.
    private var navigationBarRow: some View {
        topRow
            .bottomChromeField(leading: Spacing.xxs, trailing: Spacing.xxs)
    }

    /// The title, centered. No close button up here: the back control sits at the bottom left,
    /// within thumb reach.
    private var topRow: some View {
        Text(article.title)
            .typeStyle(.row) // the address field's text size
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, Spacing.xs)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("readerTitle")
            .accessibilityAddTraits(.isHeader)
    }

    /// Pull the top bar down to close the overlay. Same action as the back control. The reader
    /// follows a vertical pull (down freely, up with rubber-band resistance); a pull that starts
    /// sideways leaves it in place. Released far enough or flung down, it carries on off the
    /// bottom at the release speed.
    private var pullDownToClose: some Gesture {
        DragGesture(minimumDistance: SwipeGesturePolicy.verticalMinimumDistance, coordinateSpace: .global)
            .onChanged { value in
                let axis = pullDownAxis ?? SwipeGesturePolicy.axis(ofFirstMovement: value.translation)
                pullDownAxis = axis
                guard axis == .vertical else { return }
                pullDownOffset = SwipeGesturePolicy.dismissOffset(forVerticalTranslation: value.translation.height)
            }
            .onEnded { value in
                let vertical = pullDownAxis == .vertical
                pullDownAxis = nil
                if vertical, SwipeGesturePolicy.shouldCommitDownwardDismiss(
                    translation: value.translation.height,
                    predicted: value.predictedEndTranslation.height
                ) {
                    closeByPull(velocity: value.velocity.height)
                } else {
                    withAnimation(Motion.settle) { pullDownOffset = 0 }
                }
            }
    }

    /// Only exists while jump mode is on; floats over the article so nothing reflows.
    private var jumpBanner: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "hand.tap.fill")
            Text("Tap a paragraph to play from there")
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .accessibilityIdentifier("listenJumpHint")
            Spacer(minLength: Spacing.xxs)
            Button("Cancel") { jumpMode = false }
                .typeStyle(.caption, weight: .semibold)
                .accessibilityIdentifier("listenJumpCancel")
        }
        .typeStyle(.caption)
        .foregroundStyle(Palette.accent)
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.xs)
        .background(.thinMaterial, in: Capsule())
        .padding(.horizontal, Spacing.s)
        .padding(.top, Spacing.xs)
    }

    // MARK: - Actions

    /// The back control and the overlay's pull-down go through here (the pushed reader's edge
    /// swipe pops directly; `onDisappear` persists).
    private func close() {
        persistProgress()
        onClose()
    }

    /// A committed pull-down: the reader slides the rest of the way off the screen at the
    /// finger's speed, then closes. Under Reduce Motion it just fades from where it is.
    private func closeByPull(velocity: CGFloat) {
        guard !reduceMotion, screenHeight > 0 else { return close() }
        persistProgress()
        withAnimation(Motion.dismiss(velocity: velocity, distance: screenHeight - pullDownOffset)) {
            pullDownOffset = screenHeight
        } completion: {
            onClose()
        }
    }

    private func toggleJump() {
        guard sessionReady else { return }
        speech.prepare(session, startingParagraph: resumeParagraph)
        jumpMode.toggle()
    }

    /// 🔖 / ⋯ → Save. Neither direction touches the screen or playback (see the type comment).
    private func toggleSaved() {
        let saver = ArticleSaveCoordinator(context: modelContext, speech: speech)
        if isSaved {
            saver.unsave(id: article.id, canonicalURL: article.canonicalURL)
            return
        }
        let savedID = saver.save(article)
        if savedID != article.id { onIdentityChange?(savedID) }
    }

    /// Identity alignment + queue #1 for this article. Same path for Browse and Saved.
    private func prepareListen() {
        guard sessionReady else { return }
        let live = isLiveSession
        let paragraphs = article.document.paragraphs
        ListenTimingLog.log("reader_open", [
            "key": ListenTimingLog.shortKey(article.id),
            "paragraphs": paragraphs.count,
            "chars": paragraphs.reduce(0) { $0 + $1.count },
            "resume_p": live ? speech.currentParagraphIndex : resumeParagraph,
            "local_ready": speech.localTTS.usesLocalEngine,
            "live": live,
            "saved": isSaved,
        ])
        speech.localTTS.prepareListenIdentity(
            key: article.id,
            paragraphs: article.document.paragraphs,
            trustedParagraphs: article.trustedParagraphs,
            legacyKeys: article.legacyCacheKeys,
            isLivePlayback: live
        )
        speech.localTTS.warmListenAudio(
            cacheKey: article.id,
            paragraphs: article.document.paragraphs,
            voiceID: speech.cacheVoiceID,
            resumeParagraph: live ? speech.currentParagraphIndex : resumeParagraph,
            isEphemeral: !isSaved
        )
    }

    private func persistProgress() {
        guard isLiveSession, let row = savedRow else { return }
        row.playbackParagraphIndex = speech.currentParagraphIndex
        row.playbackUTF16Offset = speech.spokenUTF16Offset
    }

    private struct WarmKey: Hashable {
        let id: UUID
        let count: Int
    }
}
