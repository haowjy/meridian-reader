import SwiftUI
import SwiftData

/// The one reader screen. Browse Reader Mode and the library both render this, so typography,
/// renderer, top row, scrub row, listen bar, Jump and highlight are identical.
///
/// Top row: `[close] [title]`
/// - close: `xmark` (over the browser → back to the page) or `chevron.left` (library → pop)
///   Navigation rule (docs/NAVIGATION.md): ‹ is a real push, so edge swipe-back comes from
///   `SwipeBackSupport`; ✕ is modal, so pulling the top bar down does exactly what ✕ does.
/// Bottom (thumb reach), above the listen controls: `[scrubber] [select paragraph] [bookmark]`
/// - bookmark: `bookmark` = unsaved (tap saves) / `bookmark.fill` = saved (tap unsaves)
/// - select paragraph (hand.tap): while on, a slim hint banner floats over the article top.
/// Listen bar: `[1×] [⏮] [▶︎] [⏭] [⋯]`. ⋯ is the browser's menu panel in reader context (Voice
/// settings, Save, Bookmark, Share, Debug; bottom row Bookmarks / Saved / History / Website).
/// Website (reader off) opens the article's own page in the browser from anywhere — the library
/// too — and playback keeps going (Nav H).
///
/// The text runs edge to edge, under the top row and the bottom controls (Nav G: the browser's
/// bottom-chrome style), inset so its first / last lines clear them. The bars never hide — they
/// behave like the browser's search bar / toolbar (Nav H). See `ReaderChrome.swift`.
///
/// Save/Unsave only flips the bookmark: the article key is already the saved id (identity v2),
/// so the view, the `SpeechSession`, and any playing audio are untouched.
struct ArticleReaderScreen: View {
    enum CloseStyle {
        /// Browse: hide Reader Mode and return to the web page.
        case hideReader
        /// Saved: pop back to the Saved list.
        case back
    }

    let article: ReaderArticle
    let closeStyle: CloseStyle
    var onClose: () -> Void
    /// Only when Save resolved to a different id than `article.id` (legacy row saved mid-read).
    var onIdentityChange: ((UUID) -> Void)? = nil

    @Bindable var speech: SpeechController

    @Environment(\.modelContext) private var modelContext
    @Environment(\.readerMenuHost) private var menuHost
    @Query private var savedRows: [SavedArticle]
    @State private var jumpMode = false
    @State private var showMore = false
    /// The listen bar ⋯ button's global frame: the menu panel grows out of it.
    @State private var moreAnchor: CGRect = .zero
    /// Presenting actions run after the popover has closed (one presentation at a time).
    @State private var pendingMenuAction: BrowseMoreMenu.Action?
    @State private var showVoiceSettings = false
    @State private var shareTarget: ReaderShareTarget?
    @State private var noFakeFailure = false
    /// ✕ reader only: how far the top bar is being pulled down (swipe-down-to-close).
    @State private var pullDownOffset: CGFloat = 0
    /// The screen's safe area (the text runs under it; the bars and text insets respect it).
    @State private var safeInsets = EdgeInsets()
    /// ✕ top row height (the ‹ row lives in the navigation bar instead).
    @State private var topRowHeight: CGFloat = 0

    init(
        article: ReaderArticle,
        closeStyle: CloseStyle,
        speech: SpeechController,
        onClose: @escaping () -> Void,
        onIdentityChange: ((UUID) -> Void)? = nil
    ) {
        self.article = article
        self.closeStyle = closeStyle
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

    /// Saved (‹) is pushed in a `NavigationStack`: its row lives *in* the system navigation bar
    /// (bar stays visible, back button hidden) so push/pop — including the edge swipe — is the
    /// standard iOS transition. Hiding the bar here made the pop show the Saved list's bar
    /// (search field, voice button) full-width over the reader mid-swipe.
    /// Browse (✕) is an overlay without a navigation bar, so it draws the same row inline.
    private var rowInNavigationBar: Bool { closeStyle == .back }

    /// ✕ top band (below the safe area) + 6 pt of air above the text.
    private var topChromeHeight: CGFloat { rowInNavigationBar ? 0 : topRowHeight + 6 }

    @ViewBuilder
    var body: some View {
        if rowInNavigationBar {
            content
                .toolbar {
                    ToolbarItem(placement: .principal) { navigationBarRow }
                }
                // The same bar material as the browser's bottom band (Nav G). Clear while the ⋯
                // menu dims the page (the dim runs up under it).
                .toolbarBackground(.bar, for: .navigationBar)
                .toolbarBackground(showMore ? .hidden : .visible, for: .navigationBar)
        } else {
            content
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
                scrubControls: ReaderScrubControls(isSaved: isSaved, jumpEnabled: sessionReady,
                                                   toggleJump: toggleJump, toggleSaved: toggleSaved),
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
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: jumpMode)
        .background {
            Color(.systemBackground)
                .ignoresSafeArea()
                .onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: { safeInsets = $0 }
        }
        // ⋯ menu: grows out of the listen bar button and covers it (same panel as the browser).
        .overlay {
            MorphMenuOverlay(isPresented: $showMore, anchor: moreAnchor) { moreMenuPanel }
        }
        .offset(y: pullDownOffset)
        .task(id: WarmKey(id: article.id, count: article.document.count)) {
            prepareListen()
        }
        .onDisappear(perform: persistProgress)
        .onChange(of: showMore) { _, open in
            guard !open, let action = pendingMenuAction else { return }
            pendingMenuAction = nil
            runMenuAction(action)
        }
        .sheet(isPresented: $showVoiceSettings) {
            NavigationStack {
                SpeechSettingsView(speech: speech)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showVoiceSettings = false }
                        }
                    }
            }
        }
        .sheet(item: $shareTarget) { target in
            ActivityShareSheet(items: [target.url])
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
        }
    }

    // MARK: - ⋯ menu

    /// Bottom-right of the listen row: the same cell, glyph and size as the browser's ⋯
    /// (`toolbarIconFrame` in `BottomToolbarLayout`), so the menu grows from the same spot.
    private var moreButton: some View {
        Button { showMore = true } label: {
            Image(systemName: "ellipsis").toolbarIconFrame()
        }
        .foregroundStyle(.primary)
        .accessibilityLabel("More")
        .accessibilityIdentifier("readerMore")
        .morphMenuButtonHidden(showMore)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { if $0 != moreAnchor { moreAnchor = $0 } }
    }

    private var moreMenuPanel: some View {
        BrowseMoreMenu(
            context: .reader,
            hasPage: true,
            canToggleReader: true,
            isReaderOn: true,
            canOpenWebsite: websiteURL != nil,
            isSaved: isSaved,
            canSave: sessionReady,
            isBookmarked: articleURL.flatMap { BookmarkStore.shared.bookmark(for: $0) } != nil,
            canBookmark: articleURL.map(BookmarkStore.isBookmarkable) ?? false,
            canShare: shareURL != nil,
            showsDebug: speech.developerOptionsEnabled,
            fakeExtractionFailure: $noFakeFailure
        ) { action in
            switch action {
            case .toggleSave, .toggleBookmark:
                showMore = false
                runMenuAction(action)
            default:
                pendingMenuAction = action
                showMore = false
            }
        }
    }

    private var articleURL: URL? { URL(string: article.urlString) }

    /// The article's own page, for ⋯ → Website (any loadable page URL, not just http(s)).
    private var websiteURL: URL? {
        guard let url = articleURL, url.scheme != nil, url.host?.isEmpty == false else { return nil }
        return url
    }

    private var shareURL: URL? {
        guard let url = articleURL, url.scheme == "http" || url.scheme == "https" else { return nil }
        return url
    }

    private func runMenuAction(_ action: BrowseMoreMenu.Action) {
        switch action {
        case .voiceSettings: showVoiceSettings = true
        case .toggleSave: toggleSaved()
        case .toggleBookmark: toggleBookmark()
        case .share: if let shareURL { shareTarget = ReaderShareTarget(url: shareURL) }
        case .listenDebug: speech.showListenDebug = true
        case .bookmarks: menuHost?.showBookmarks()
        // Inside the library (‹) you're already in Saved: go back to the list.
        case .saved: if closeStyle == .back { close() } else { menuHost?.showSaved() }
        case .history: menuHost?.showHistory()
        // Reader off = the article's own web page in the browser, wherever the reader was opened
        // from (library, start page, Continue listening, mini player). Playback keeps going.
        case .openWebsite:
            if let websiteURL, let menuHost { persistProgress(); menuHost.openWebsite(websiteURL) } else { close() }
        case .toggleReader: close()
        case .newSearch, .reload: break
        }
    }

    /// Site bookmark for the article's page (URL, title, icon only; independent of Save).
    private func toggleBookmark() {
        guard let url = articleURL, BookmarkStore.isBookmarkable(url) else { return }
        let store = BookmarkStore.shared
        if let existing = store.bookmark(for: url) {
            store.remove(id: existing.id)
            return
        }
        let added = store.add(url: url, title: article.title, faviconData: article.faviconData)
        guard !FaviconFetcher.isTileSized(added.faviconData) else { return }
        Task { @MainActor in
            if let icon = await FaviconFetcher.fetch(forHost: added.host),
               added.faviconData == nil || FaviconFetcher.isTileSized(icon) {
                store.setFavicon(icon, for: added.id)
            }
        }
    }

    // MARK: - Top bar

    /// Inline (Browse ✕) version of the row, styled like the browser's bottom chrome mirrored to
    /// the top (Nav G): the row in the address-field capsule on the same bar material (running up
    /// under the status bar), same margins. Pull-down-to-close.
    private var topBar: some View {
        topRow
            .bottomChromeField(leading: 4, trailing: 4)
            .padding(.horizontal, BottomChrome.horizontalMargin)
            .padding(.top, 4)
            .padding(.bottom, BottomChrome.topPadding)
            .background(.bar)
            .contentShape(Rectangle())
            // Only the ✕ (modal) reader gets pull-down-to-close, and only from the top bar, so it
            // never competes with scrolling, text selection or Jump taps in the article.
            .gesture(pullDownToClose, including: closeStyle == .hideReader ? .all : .subviews)
    }

    /// Library (‹) version: the row sits in the (transparent) navigation bar so push / pop and the
    /// edge swipe stay the standard iOS transition. It fades with the chrome; while the ⋯ menu is
    /// open it dims with the page and a tap on it closes the menu.
    private var navigationBarRow: some View {
        topRow
            .bottomChromeField(leading: 4, trailing: 4)
            .opacity(showMore ? 0.45 : 1)
            .allowsHitTesting(!showMore)
            .overlay {
                if showMore {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { showMore = false }
                        .accessibilityHidden(true)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showMore)
    }

    /// `[close] [title]`. The title is centered (a clear spacer balances the close button).
    private var topRow: some View {
        HStack(spacing: 2) {
            Button(action: close) {
                Image(systemName: closeStyle == .hideReader ? "xmark" : "chevron.left")
                    .font(.body.weight(.semibold))
                    // Explicit so the row looks the same inline (Browse) and in the nav bar (Saved),
                    // where toolbar styling would otherwise make it black.
                    .foregroundStyle(Color.accentColor)
                    .frame(width: BottomChrome.fieldControlSize, height: BottomChrome.fieldControlSize)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("readerClose")
            .accessibilityLabel(closeStyle == .hideReader ? "Hide Reader" : "Back")

            Text(article.title)
                .font(.body) // the address field's text size
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)
                .layoutPriority(-1)
                .accessibilityIdentifier("readerTitle")

            Color.clear.frame(width: BottomChrome.fieldControlSize, height: BottomChrome.fieldControlSize)
        }
        .frame(maxWidth: .infinity)
    }

    /// Pull the top bar down to close the ✕ reader. Same action as tapping ✕.
    private var pullDownToClose: some Gesture {
        DragGesture(minimumDistance: SwipeGesturePolicy.verticalMinimumDistance, coordinateSpace: .global)
            .onChanged { value in
                pullDownOffset = SwipeGesturePolicy.verticalOffset(for: value.translation)
            }
            .onEnded { value in
                if SwipeGesturePolicy.shouldCommitVerticalDismiss(
                    translation: value.translation,
                    predicted: value.predictedEndTranslation
                ) {
                    close()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { pullDownOffset = 0 }
                }
            }
    }

    /// Only exists while jump mode is on; floats over the article so nothing reflows.
    private var jumpBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.tap.fill")
            Text("Tap a paragraph to play from there")
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .accessibilityIdentifier("listenJumpHint")
            Spacer(minLength: 4)
            Button("Cancel") { jumpMode = false }
                .font(.footnote.weight(.semibold))
                .accessibilityIdentifier("listenJumpCancel")
        }
        .font(.footnote)
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
        .padding(.horizontal, 10)
        .padding(.top, 6)
    }

    // MARK: - Actions

    /// ✕ / ‹ tap and ✕ pull-down all go through here (‹ swipe-back pops, `onDisappear` persists).
    private func close() {
        persistProgress()
        onClose()
    }

    private func toggleJump() {
        guard sessionReady else { return }
        speech.prepare(session, startingParagraph: resumeParagraph)
        jumpMode.toggle()
    }

    private func toggleSaved() {
        let live = isLiveSession
        if isSaved {
            ArticleLibrary.unsave(id: article.id, canonicalURL: article.canonicalURL, in: modelContext)
            // Keep audio + playhead; the cache just goes back to the ephemeral TTL.
            speech.localTTS.markListenCacheEphemeral(article.id, canonicalURL: article.canonicalURL)
            return
        }
        let playhead = live ? speech.currentParagraphIndex : nil
        let row = ArticleLibrary.save(article, playhead: playhead, in: modelContext)
        if row.id != article.id {
            // Legacy row with a different id: rekey audio + live session in place.
            speech.localTTS.migrateListenCache(from: article.id, to: row.id)
            speech.rekeyActiveSession(from: article.id, to: row.id)
            onIdentityChange?(row.id)
        } else {
            speech.localTTS.migrateListenCache(from: article.id, to: article.id)
        }
        // Background bake (keeps the live playhead plan when this article is #1).
        speech.localTTS.startBakeIfNeeded(
            articleID: row.id,
            paragraphs: article.document.paragraphs,
            rate: Float(speech.rateMultiplier),
            voiceID: speech.cacheVoiceID
        )
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
            "local_ready": speech.localTTS.localHostReady,
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
            rate: Float(speech.rateMultiplier),
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

private struct ReaderShareTarget: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
