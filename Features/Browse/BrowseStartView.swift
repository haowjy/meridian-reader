import SwiftUI
import SwiftData
import WebKit

/// The whole app: a browser with in-place Reader Mode (no tab bar).
/// - Start page (no page loaded): Bookmarks grid · Continue listening · Saved · Recent Searches.
/// - Bottom: [mini player] · address field (reader icon when the page is readable) · `[‹][›][⋯]`.
/// - ⋯ opens a Safari-style popover: actions, then big Bookmarks / Saved / History buttons.
struct BrowseStartView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.articleExtractor) private var extractor
    @Environment(\.speechController) private var speech
    @Query(sort: \SavedArticle.savedAt, order: .reverse) private var articles: [SavedArticle]
    @Query(sort: \RecentVisit.visitedAt, order: .reverse) private var recentVisits: [RecentVisit]

    @State private var webStore = WebViewStore()
    /// Once true, the browse WKWebView stays in the tree (history / back-forward). Starts false so
    /// cold launch on the start page never creates WebKit GPU/WebContent processes.
    @State private var browseWebViewMounted = false
    @State private var addressText = ""
    /// Search session (Safari): true from focus / Search / mic until ✕ or navigate — survives swipe-down.
    @State private var isEditingAddress = false
    @FocusState private var addressFocused: Bool
    /// The toolbar's Search button focused the field: start empty (Recent Searches), not with the
    /// page's address selected.
    @State private var startingNewSearch = false

    @State private var isBusy = false
    /// Which action `isBusy` belongs to (spinner on ⋯ for Save, on Reader for Reader).
    @State private var busyIsSave = false
    @State private var showVoiceSettings = false
    /// Address-bar dictation (created in `.task`: it needs the speech controller).
    @State private var dictation: AddressDictation?
    /// Field text when editing began: while it's untouched, show Recent Searches.
    @State private var focusStartText = ""
    @AppStorage(RecentSearches.storageKey) private var recentSearchesRaw = ""
    /// Long suggestion lists scroll; pull-down-to-cancel only when the list is at its top.
    @State private var suggestionsAtTop = true
    @State private var dragStartedAtTop: Bool?
    @State private var alertMessage: String?
    @State private var showReader = false
    /// Article shown in Reader Mode (shared `ArticleReaderScreen`). `id` is the listen/cache key.
    @State private var readerArticle: ReaderArticle?
    @State private var useFakeFailure = false
    /// Readers opened this session, by id: the mini player reopens a web article from here.
    @State private var openedArticles: [UUID: ReaderArticle] = [:]

    @State private var showMore = false
    /// The toolbar ⋯ button's global frame: the menu panel grows out of it.
    @State private var moreAnchor: CGRect = .zero
    /// ⋯ actions that present something run once the popover is gone.
    @State private var pendingMoreAction: BrowseMoreMenu.Action?
    @State private var showLibrary = false
    /// Runs once the library sheet is gone (reader-in-library ⋯ → Bookmarks / History).
    @State private var afterLibraryDismiss: (() -> Void)?
    @State private var showBookmarks = false
    /// Site bookmarks (their own JSON store; not the saved-article model).
    @State private var bookmarkStore = BookmarkStore.shared
    @State private var showHistory = false
    @State private var shareItem: ShareItem?
    @State private var listenHistory = ListenHistory(defaults: .standard)

    @State private var googleSuggestions: [String] = []
    @State private var suggestTask: Task<Void, Never>?

    /// Bottom-bar bookmark reflects "already saved" for the current page's canonical URL.
    private var currentSavedArticle: SavedArticle? {
        guard let url = webStore.currentURL, url.scheme == "http" || url.scheme == "https" else { return nil }
        let canonical = ArticleIdentity.canonicalURLString(from: url)
        return articles.first { $0.canonicalURL == canonical }
    }

    private var hasPage: Bool {
        guard let url = webStore.currentURL ?? webStore.webView?.url else { return false }
        return url.scheme != "about"
    }

    /// Create the browse WKWebView only after the first non-start navigation; keep it thereafter.
    private var showsBrowseWebView: Bool {
        browseWebViewMounted || hasPage
    }

    /// Saved articles in progress, most recently listened first.
    private var continueListeningArticles: [SavedArticle] {
        let candidates = articles.map { row in
            // Paragraph count only matters for pre-history saves (and decoding blocks isn't free).
            let needsCount = listenHistory.entry(for: row.id) == nil && row.playbackParagraphIndex > 0
            return ContinueListening.Candidate(
                id: row.id, savedAt: row.savedAt, paragraph: row.playbackParagraphIndex,
                utf16Offset: row.playbackUTF16Offset,
                paragraphCount: needsCount ? row.cachedListenParagraphs?.count : nil
            )
        }
        let byID = Dictionary(articles.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return ContinueListening.inProgress(candidates, history: listenHistory).compactMap { byID[$0.id] }
    }

    private var recentSearches: [String] { RecentSearches.decode(recentSearchesRaw) }

    /// Recent Searches replace suggestions while the field is empty or still shows the page URL.
    /// Uses `isEditingAddress` (search session), not keyboard focus — swipe-down keeps them visible.
    private var showsRecentSearches: Bool {
        guard isEditingAddress, !showReader, !recentSearches.isEmpty, dictation?.isActive != true else { return false }
        let q = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        return q.isEmpty || addressText == focusStartText
    }

    private var isDictating: Bool { dictation?.isActive == true }

    /// Local Recents/Saved matches first, then Google suggest (deduped).
    private var addressSuggestions: [AddressSuggestion] {
        let q = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isEditingAddress, q.count >= 1, !showsRecentSearches else { return [] }

        var rows: [AddressSuggestion] = []
        var seen = Set<String>()

        func take(_ key: String) -> Bool {
            seen.insert(key.lowercased()).inserted
        }

        for visit in recentVisits.prefix(RecentVisit.maxEntries) {
            let hay = "\(visit.title) \(visit.host) \(visit.urlString)".lowercased()
            guard hay.contains(q.lowercased()) else { continue }
            guard take(visit.urlString) else { continue }
            rows.append(
                AddressSuggestion(
                    id: "recent-\(visit.id.uuidString)",
                    title: visit.title,
                    subtitle: visit.host,
                    faviconData: visit.faviconData,
                    host: visit.host,
                    query: visit.urlString,
                    kind: .recent
                )
            )
            if rows.count >= 4 { break }
        }

        var savedCount = 0
        for article in articles {
            let hay = "\(article.title) \(article.siteDomain) \(article.urlString)".lowercased()
            guard hay.contains(q.lowercased()) else { continue }
            guard take(article.urlString) else { continue }
            rows.append(
                AddressSuggestion(
                    id: "saved-\(article.id.uuidString)",
                    title: article.title,
                    subtitle: article.siteDomain,
                    faviconData: article.faviconData,
                    host: article.siteDomain,
                    query: article.urlString,
                    kind: .saved
                )
            )
            savedCount += 1
            if savedCount >= 3 { break }
        }

        for text in googleSuggestions {
            guard take(text) else { continue }
            rows.append(
                AddressSuggestion(
                    id: "google-\(text)",
                    title: text,
                    subtitle: "Google Search",
                    faviconData: nil,
                    host: "",
                    query: text,
                    kind: .google
                )
            )
            if rows.count >= 10 { break }
        }

        return rows
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if showsBrowseWebView {
                    WebView(store: webStore, initialURL: nil)
                        .opacity(hasPage && !showReader ? 1 : 0)
                        .allowsHitTesting(hasPage && !showReader)
                        .onAppear { browseWebViewMounted = true }
                }

                if !hasPage && !showReader {
                    startPage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Safari-style search session: full-bleed Recent Searches / suggestions over the page.
            // Swipe down lowers the keyboard but stays in search mode (✕ exits).
            .overlay {
                if isEditingAddress && !showReader {
                    searchSessionOverlay
                }
            }
            .clipped()

            if !showReader {
                browserChrome
            }
        }
        // While editing the address, avoid the keyboard so the field sits right above it. Otherwise
        // keep ignoring it (typing into a web page must not resize the page / the web view).
        .ignoresSafeArea(.keyboard, edges: addressFocused ? [] : .bottom)
        // Reader Mode covers the whole browser, edge to edge (the text runs under its bars). Outside
        // the page ZStack, whose `.clipped()` would cut it at the safe area.
        .overlay {
            if showReader, let readerArticle {
                readerOverlay(for: readerArticle)
                    .transition(.opacity)
            }
        }
        // ⋯ menu: grows out of the toolbar button and covers it (Safari iOS 26), not a popover.
        .overlay {
            MorphMenuOverlay(isPresented: $showMore, anchor: moreAnchor) { moreMenuPanel }
        }
        .background {
            ListenHistoryRecorder(speech: speech) {
                listenHistory = ListenHistory(defaults: .standard)
            }
        }
        .onChange(of: readerArticle?.id) { _, _ in
            if let article = readerArticle { openedArticles[article.id] = article }
        }
        .alert("Couldn’t extract", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
        .task {
            if dictation == nil {
                let d = AddressDictation(recognizer: SystemDictationRecognizer(),
                                         audio: ListenDictationHandoff(speech: speech))
                dictation = d
            }
            dictation?.onTranscript = { text in
                if addressFocused || isDictating { addressText = text }
            }
            speech.onArticleFinished = { id in
                ListenHistory.record(id, finished: true)
            }
            openDemoReaderForUITestsIfRequested()
            openTestPagesIfRequested()
            openLibraryIfRequested()
            seedBookmarksIfRequested()
            await resumeAfterCrashIfNeeded()
        }
        .sheet(isPresented: $showLibrary, onDismiss: {
            guard let next = afterLibraryDismiss else { return }
            afterLibraryDismiss = nil
            next()
        }) {
            SavedListView()
                .presentationDragIndicator(.visible)
                .environment(\.readerMenuHost, readerMenuHost)
        }
        .sheet(isPresented: $showBookmarks) {
            BookmarksListView(store: bookmarkStore) { bookmark in
                showBookmarks = false
                openBookmark(bookmark)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showHistory) {
            BrowseHistoryView(visits: Array(recentVisits.prefix(RecentVisit.maxEntries))) { visit in
                showHistory = false
                openRecent(visit)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $shareItem) { item in
            ActivityShareSheet(items: [item.url])
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
        }
        .onChange(of: showMore) { _, open in
            guard !open, let action = pendingMoreAction else { return }
            pendingMoreAction = nil
            runMoreAction(action)
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
        .alert("Dictation", isPresented: Binding(
            get: { dictation?.errorMessage != nil },
            set: { if !$0 { dictation?.errorMessage = nil } }
        )) {
            Button("Open Settings") {
                dictation?.errorMessage = nil
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("OK", role: .cancel) { dictation?.errorMessage = nil }
        } message: {
            Text(dictation?.errorMessage ?? "")
        }
        .onChange(of: webStore.currentURL) { _, newURL in
            guard !addressFocused, !isEditingAddress else { return }
            syncAddressField(from: newURL)
        }
        .onChange(of: webStore.isLoading) { _, loading in
            guard !loading else { return }
            Task { await recordRecentVisitIfNeeded() }
        }
        .onChange(of: addressText) { _, text in
            // Typing (or clearing) while dictating takes over from the mic.
            if let dictation, dictation.isListening, text != dictation.transcript {
                dictation.stop()
            }
            scheduleSuggestFetch()
        }
        .onChange(of: addressFocused) { _, focused in
            if focused {
                scheduleSuggestFetch()
            } else {
                dictation?.cancel()
                // Keep suggestions while still in search session (keyboard lowered via swipe).
                if !isEditingAddress {
                    suggestTask?.cancel()
                    googleSuggestions = []
                }
            }
        }
    }

    // MARK: - Reader overlay

    @ViewBuilder
    private func readerOverlay(for article: ReaderArticle) -> some View {
        ArticleReaderScreen(
            article: article,
            closeStyle: .hideReader,
            speech: speech,
            onClose: hideReader,
            onIdentityChange: { readerArticle?.id = $0 }
        )
        .environment(\.readerMenuHost, readerMenuHost)
    }

    /// The reader's ⋯ bottom row presents the browser's own sheets. From the ‹ reader inside the
    /// library sheet, Bookmarks / History first close the library (one sheet at a time).
    private var readerMenuHost: ReaderMenuHost {
        ReaderMenuHost(
            showBookmarks: { presentFromReader { showBookmarks = true } },
            showSaved: { showLibrary = true },
            showHistory: { presentFromReader { showHistory = true } },
            openWebsite: { url in presentFromReader { openWebsite(url) } }
        )
    }

    /// Reader ⋯ → Website: close the reader and show the article's page. The ✕ reader opened from
    /// the page that's already loaded just reveals it (no reload, scroll kept); from anywhere else
    /// (library, start page, Continue listening, mini player) the page loads. Audio keeps playing.
    private func openWebsite(_ url: URL) {
        if showReader { hideReader() }
        isEditingAddress = false
        addressFocused = false
        googleSuggestions = []
        if !(hasPage && Self.samePage(webStore.currentURL, url)) {
            webStore.load(url)
        }
        syncAddressField(from: webStore.currentURL.flatMap { Self.samePage($0, url) ? $0 : nil } ?? url)
    }

    /// Same page, ignoring the fragment and a trailing slash.
    static func samePage(_ a: URL?, _ b: URL) -> Bool {
        guard let a else { return false }
        func key(_ u: URL) -> String {
            var c = URLComponents(url: u, resolvingAgainstBaseURL: false)
            c?.fragment = nil
            var s = c?.string ?? u.absoluteString
            if s.hasSuffix("/") { s.removeLast() }
            return s.lowercased()
        }
        return key(a) == key(b)
    }

    private func presentFromReader(_ present: @escaping () -> Void) {
        if showLibrary {
            afterLibraryDismiss = present
            showLibrary = false
        } else {
            present()
        }
    }

    /// UI-test hook (`-openDemoInBrowseReader`, with `-seedDemoArticle`): show the seeded article
    /// in the ✕ Reader Mode without needing the network.
    private func openDemoReaderForUITestsIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-openDemoInBrowseReader"),
              !showReader, let row = articles.first else { return }
        var article = ReaderArticle(saved: row)
        if article.document.isEmpty {
            let doc = SavedArticle.buildListenDocument(plainText: row.plainText, cleanedHTML: row.cleanedHTML, title: row.title)
            article.document = doc
            article.trustedParagraphs = doc.paragraphs
        }
        readerArticle = article
        showReader = true
    }

    /// UI-test hook (`-browseTestPages`): offline pages served by `TestPageSchemeHandler`, with a
    /// link to a second page, so ‹ / › state can be checked without the network.
    /// UI-test hook (`-openLibrary`): start with the library sheet open (article-list tests).
    private func openLibraryIfRequested() {
        if ProcessInfo.processInfo.arguments.contains("-openLibrary") { showLibrary = true }
    }

    private func openTestPagesIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-browseTestPages"), !hasPage,
              let url = URL(string: "reader-test://pages/one") else { return }
        webStore.load(url)
    }

    /// ✕ / pull-down. Playback keeps going; the mini player takes over.
    private func hideReader() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showReader = false
        }
    }

    // MARK: - Browser chrome

    /// Shared with the reader's bottom (see `BottomChrome.swift`): band, field capsule, toolbar row.
    private var browserChrome: some View {
        VStack(spacing: BottomChrome.rowSpacing) {
            if !isEditingAddress {
                MiniPlayerBar(speech: speech, onOpen: openNowPlaying)
                    .padding(.bottom, 4)
            }
            HStack(spacing: 10) {
                addressBar
                // ✕ stays while searching — even after swipe-down dismisses the keyboard.
                if isEditingAddress {
                    Button(action: cancelEditing) {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 40, height: 40)
                            .background(Color(.secondarySystemBackground), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel")
                    .accessibilityIdentifier("addressCancel")
                }
            }

            // Like Safari: page buttons step aside while searching, so the field hugs the keyboard.
            if !isEditingAddress {
                toolbarRow
            }
        }
        .bottomChromeBand(bottomPadding: isEditingAddress ? 8 : 0)
        .overlay(alignment: .top) {
            // Thin load progress on the chrome's top edge (no layout shift while loading).
            if webStore.isLoading && hasPage {
                GeometryReader { g in
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: g.size.width * max(0.08, min(1, webStore.progress)), height: 2)
                }
                .frame(height: 2)
                .allowsHitTesting(false)
            }
        }
    }

    /// Toolbar: ‹  ›  ⋯ (evenly spaced). Reader is the icon in the address field and the ⋯ popover's
    /// bottom-right Reader toggle; Bookmarks / Saved / History live in the ⋯ popover and on the
    /// start page.
    private var toolbarRow: some View {
        // Five equal slots shared with the reader: `[‹][›][Search][ ][⋯]` (Nav I).
        BottomToolbarLayout {
            toolbarButton("chevron.backward", label: "Back", id: "browseBack") { webStore.goBack() }
                .disabled(!webStore.canGoBack)
            toolbarButton("chevron.forward", label: "Forward", id: "browseForward") { webStore.goForward() }
                .disabled(!webStore.canGoForward)
            // One tap to a new search: the field, focused and empty (Recent Searches); ✕ / tap
            // outside restores the page's address.
            toolbarButton("magnifyingglass", label: "Search", id: "browseSearch", action: startNewSearch)
            moreMenu
        }
        .foregroundStyle(.primary)
        .simultaneousGesture(browserToolbarSwipe)
    }

    private var browserToolbarSwipe: some Gesture {
        DragGesture(minimumDistance: SwipeGesturePolicy.horizontalMinimumDistance)
            .onEnded { value in
                guard let direction = SwipeGesturePolicy.horizontalDirection(
                    translation: value.translation,
                    predicted: value.predictedEndTranslation
                ) else { return }
                switch direction {
                case .right:
                    if webStore.canGoBack { webStore.goBack() }
                case .left:
                    if webStore.canGoForward { webStore.goForward() }
                }
            }
    }

    private func toolbarButton(_ systemImage: String, label: String, id: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage).toolbarIconFrame()
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    private var shareURL: URL? {
        guard hasPage, let url = webStore.currentURL,
              url.scheme == "http" || url.scheme == "https" else { return nil }
        return url
    }

    /// ⋯ → Safari-style menu panel (see `BrowseMoreMenu`, `MorphMenuOverlay`).
    private var moreMenu: some View {
        Button { showMore = true } label: {
            Group {
                if isBusy && busyIsSave {
                    ProgressView()
                } else {
                    Image(systemName: "ellipsis")
                }
            }
            .toolbarIconFrame()
        }
        .accessibilityLabel("More")
        .accessibilityIdentifier("browseMore")
        .morphMenuButtonHidden(showMore)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { if $0 != moreAnchor { moreAnchor = $0 } }
    }

    private var moreMenuPanel: some View {
        BrowseMoreMenu(
            hasPage: hasPage,
            // Off on the start page and on pages that can't be read (Reader mode itself has
            // its own ⋯ with this toggle selected).
            canToggleReader: canOpenReader,
            isReaderOn: false,
            isSaved: currentSavedArticle != nil,
            canSave: hasPage && !isBusy,
            isBookmarked: currentBookmark != nil,
            canBookmark: bookmarkableURL != nil,
            canShare: shareURL != nil,
            showsDebug: speech.developerOptionsEnabled,
            fakeExtractionFailure: $useFakeFailure
        ) { action in
            switch action {
            case .newSearch, .toggleSave, .toggleBookmark, .reload:
                showMore = false
                runMoreAction(action)
            case .share, .voiceSettings, .bookmarks, .saved, .history, .toggleReader, .listenDebug, .openWebsite:
                // Present once the panel has started collapsing.
                pendingMoreAction = action
                showMore = false
            }
        }
    }

    private func runMoreAction(_ action: BrowseMoreMenu.Action) {
        switch action {
        case .newSearch: showStartLanding()
        case .toggleReader: Task { await runReader() }
        case .listenDebug: speech.showListenDebug = true
        case .toggleSave: Task { await toggleSaveFromBrowser() }
        case .toggleBookmark: Task { await toggleBookmark() }
        case .bookmarks: showBookmarks = true
        case .reload: webStore.refresh()
        case .share: if let shareURL { shareItem = ShareItem(url: shareURL) }
        case .voiceSettings: showVoiceSettings = true
        case .saved: showLibrary = true
        case .history: showHistory = true
        case .openWebsite: break // reader context only
        }
    }

    private var canOpenReader: Bool { hasPage && webStore.isReaderable && !isBusy }

    private var currentBookmark: SiteBookmark? {
        hasPage ? bookmarkStore.bookmark(for: webStore.currentURL) : nil
    }

    /// Leading slot of the address field: a spinner while extracting, the reader icon (Safari's
    /// page-format button) when readable, the search glyph while editing, or an empty spacer.
    @ViewBuilder
    private var addressLeading: some View {
        if !isEditingAddress && isBusy && !busyIsSave {
            ProgressView()
                .controlSize(.small)
                .frame(width: 30, height: 30)
        } else if !isEditingAddress && hasPage && webStore.isReaderable {
            Button { Task { await runReader() } } label: {
                Image(systemName: "doc.plaintext")
                    .font(.body)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open in Reader")
            .accessibilityIdentifier("addressReader")
            .transition(.opacity)
        } else if isEditingAddress {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .accessibilityHidden(true)
        } else {
            Color.clear
                .frame(width: 16)
                .accessibilityHidden(true)
        }
    }

    private var addressBar: some View {
        HStack(spacing: 8) {
            addressLeading

            TextField(isDictating && addressText.isEmpty ? "Listening…" : "Search or enter address",
                      text: $addressText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.webSearch)
                .submitLabel(.go)
                .focused($addressFocused)
                .onSubmit(submitAddress)
                .accessibilityIdentifier("addressField")
                .onChange(of: addressFocused) { _, focused in
                    if focused {
                        if isEditingAddress {
                            // Re-focus after swipe-down: keep typed text; do not re-select / reset.
                            startingNewSearch = false
                        } else {
                            // Entering search session.
                            isEditingAddress = true
                            if isDictating || startingNewSearch {
                                startingNewSearch = false
                                addressText = ""
                            } else if let url = webStore.currentURL, url.scheme != "about" {
                                addressText = url.absoluteString
                                selectAllInFocusedField() // like Safari: typing replaces the URL
                            }
                            focusStartText = addressText
                        }
                    }
                    // Losing focus alone does not exit search (swipe-down). ✕ / submit clears it.
                }

            micButton
        }
        .bottomChromeField()
        .overlay {
            if isDictating {
                Capsule().strokeBorder(Color.accentColor, lineWidth: 1.5)
            }
        }
    }

    private var micButton: some View {
        let listening = dictation?.isListening == true
        return Button(action: micTapped) {
            Image(systemName: isDictating ? "waveform" : "mic")
                .foregroundStyle(isDictating ? Color.accentColor : Color.secondary)
                .symbolEffect(.variableColor.iterative, isActive: listening)
                .fieldControlFrame()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isDictating ? "Stop dictation" : "Dictate")
        .accessibilityIdentifier("addressMic")
    }

    /// Full-bleed search UI (Safari): opaque background + Recent Searches / suggestions list.
    /// Swipe down lowers the keyboard; ✕ exits search mode.
    private var searchSessionOverlay: some View {
        ZStack(alignment: .top) {
            Color(.systemBackground)
                .ignoresSafeArea(edges: .bottom)

            if showsRecentSearches || !addressSuggestions.isEmpty {
                ScrollView {
                    suggestionsContent
                        .padding(.top, 4)
                        .background(GeometryReader { g in
                            Color.clear.preference(key: SuggestionsTopOffsetKey.self,
                                                   value: g.frame(in: .named("suggestScroll")).minY)
                        })
                }
                .coordinateSpace(name: "suggestScroll")
                .onPreferenceChange(SuggestionsTopOffsetKey.self) { suggestionsAtTop = $0 >= -1 }
                .scrollDismissesKeyboard(.never)
                .simultaneousGesture(pullDownToLowerKeyboard(requireTop: true))
            } else {
                // Empty session (no recents / not enough typed yet): still swipe-dismiss keyboard.
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(pullDownToLowerKeyboard(requireTop: false))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("addressEditBackdrop")
    }

    @ViewBuilder
    private var suggestionsContent: some View {
        if showsRecentSearches {
            recentSearchesPanel
        } else {
            suggestionsPanel
        }
    }

    private var recentSearchesPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Recent Searches")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Clear All") { recentSearchesRaw = "" }
                    .font(.body)
                    .accessibilityIdentifier("recentSearchesClear")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ForEach(recentSearches, id: \.self) { term in
                Divider().padding(.leading, 52)
                HStack(spacing: 0) {
                    Button {
                        addressText = term
                        submitAddress()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                                .frame(width: 22)
                            Text(term)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.leading, 16)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(term)

                    // Safari fill-into-field affordance: put the term in the field without navigating.
                    Button {
                        fillSearchField(term)
                    } label: {
                        Image(systemName: "arrow.up.backward")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Insert into search field")
                    .padding(.trailing, 6)
                }
            }
        }
    }

    private var suggestionsPanel: some View {
        VStack(spacing: 0) {
            ForEach(addressSuggestions) { row in
                HStack(spacing: 0) {
                    Button {
                        applySuggestion(row)
                    } label: {
                        HStack(spacing: 12) {
                            suggestionLeading(for: row)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.title)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                if let subtitle = row.subtitle {
                                    Text(subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.leading, 16)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        fillSearchField(row.query)
                    } label: {
                        Image(systemName: "arrow.up.backward")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Insert into search field")
                    .padding(.trailing, 6)
                }

                if row.id != addressSuggestions.last?.id {
                    Divider().padding(.leading, 52)
                }
            }
        }
    }

    @ViewBuilder
    private func suggestionLeading(for row: AddressSuggestion) -> some View {
        switch row.kind {
        case .recent, .saved:
            FaviconImage(data: row.faviconData, host: row.host, size: 28)
        case .google:
            Image(systemName: "magnifyingglass")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
        }
    }

    // MARK: - Start page

    private var startPage: some View {
        BrowseStartPage(
            bookmarks: bookmarkStore.bookmarks,
            continueListening: continueListeningArticles,
            saved: articles,
            recentSearches: recentSearches,
            onOpenBookmark: openBookmark,
            onShowBookmarks: { showBookmarks = true },
            onDeleteBookmark: { bookmarkStore.remove(id: $0.id) },
            onRenameBookmark: { bookmarkStore.rename(id: $0.id, to: $1) },
            onOpenArticle: { openSaved($0.id) },
            onShowLibrary: { showLibrary = true },
            onSearch: { term in
                addressText = term
                submitAddress()
            },
            onClearSearches: { recentSearchesRaw = "" }
        )
        .task(id: bookmarkStore.bookmarks.count) { await backfillBookmarkIcons() }
    }

    private func openBookmark(_ bookmark: SiteBookmark) {
        guard let url = bookmark.url else { return }
        if showReader { hideReader() } // picked from the reader's ⋯ → Bookmarks
        isEditingAddress = false
        addressFocused = false
        googleSuggestions = []
        webStore.load(url)
        syncAddressField(from: url)
    }

    /// ⋯ → Bookmark / Remove Bookmark for the current page (URL, title, icon only).
    private var bookmarkableURL: URL? {
        guard hasPage, let url = webStore.currentURL, BookmarkStore.isBookmarkable(url) else { return nil }
        return url
    }

    @MainActor
    private func toggleBookmark() async {
        guard let url = bookmarkableURL else { return }
        if let existing = bookmarkStore.bookmark(for: url) {
            bookmarkStore.remove(id: existing.id)
            return
        }
        let liveTitle = webStore.webView?.title.flatMap { $0.isEmpty ? nil : $0 }
        let added = bookmarkStore.add(url: url, title: liveTitle ?? webStore.pageTitle,
                                      faviconData: recentFavicon(for: url))
        if !FaviconFetcher.isTileSized(added.faviconData), let icon = await fetchFavicon(for: url),
           added.faviconData == nil || FaviconFetcher.isTileSized(icon) {
            bookmarkStore.setFavicon(icon, for: added.id)
        }
    }

    /// Bookmarks without a tile-sized icon (seeded, or the page only had a 16 px favicon): try
    /// the site's icon once per launch. A smaller icon never replaces a usable one.
    /// Fetches run concurrently; a bookmark only counts as tried once its fetch finished, so a
    /// cancelled pass (the view went away, the list changed) retries next time.
    @MainActor
    private func backfillBookmarkIcons() async {
        let pending = bookmarkStore.bookmarks.filter {
            !FaviconFetcher.isTileSized($0.faviconData) && !Self.iconTried.contains($0.id)
        }
        guard !pending.isEmpty else { return }
        await withTaskGroup(of: (UUID, Data?).self) { group in
            for bookmark in pending {
                let host = bookmark.host
                group.addTask { (bookmark.id, await FaviconFetcher.fetch(forHost: host)) }
            }
            for await (id, icon) in group {
                guard !Task.isCancelled else { return }
                Self.iconTried.insert(id)
                guard let icon, let current = bookmarkStore.bookmarks.first(where: { $0.id == id }),
                      current.faviconData == nil || FaviconFetcher.isTileSized(icon) else { continue }
                bookmarkStore.setFavicon(icon, for: id)
            }
        }
    }

    @MainActor private static var iconTried = Set<UUID>()

    /// UI-test hooks: `-resetBookmarks` clears the bookmark store; `-seedBookmarks` also adds a few.
    private func seedBookmarksIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-resetBookmarks") || args.contains("-seedBookmarks") else { return }
        bookmarkStore.removeAll()
        guard args.contains("-seedBookmarks") else { return }
        let seeds: [(String, String)] = [
            ("https://www.royalroad.com/fiction/193675/the-witchs-bond", "The Witch's Bond"),
            ("https://en.wikipedia.org/wiki/Speech_synthesis", "Speech synthesis"),
            ("https://news.ycombinator.com/", "Hacker News"),
            ("https://www.theverge.com/", "The Verge"),
            ("https://example.com/", "Example"),
        ]
        for (url, title) in seeds {
            if let u = URL(string: url) { bookmarkStore.add(url: u, title: title, faviconData: nil) }
        }
    }

    /// Start page row / mini player / crash resume: the saved article in the ✕ reader.
    private func openSaved(_ id: UUID) {
        Task { @MainActor in
            var shown = false
            await ReaderArticle.loadSaved(id: id, in: modelContext) { article in
                guard !shown || readerArticle?.id == article.id else { return }
                readerArticle = article
                if !shown {
                    shown = true
                    withAnimation(.easeInOut(duration: 0.2)) { showReader = true }
                }
            }
        }
    }

    /// Mini player tap: open the reader for whatever is loaded.
    private func openNowPlaying() {
        guard let id = speech.activeSessionID else { return }
        if articles.contains(where: { $0.id == id }) {
            openSaved(id)
        } else if let article = openedArticles[id] {
            readerArticle = article
            withAnimation(.easeInOut(duration: 0.2)) { showReader = true }
        }
    }

    /// Kokoro crashed last session: reopen the article at the paragraph that was playing — playing
    /// again (on the ONNX route, once it's loaded) if the crash just happened, else paused there.
    private func resumeAfterCrashIfNeeded() async {
        let tts = speech.localTTS
        // The target may predate paragraph layout v3; migrate first (no-op once done) so its
        // paragraph and the article's blocks use the same numbering.
        ArticleLibrary.migrateParagraphLayout(in: modelContext, localTTS: tts)
        guard let target = tts.takePendingResume() else { return }
        guard let article = articles.first(where: { target.matches($0.id) }) else {
            ListenTimingLog.log("kokoro_resume", ["ok": false, "why": "article not found", "key": String(target.articleKey.prefix(8))])
            return
        }
        let session = SpeechSession.saved(article)
        let p = min(max(0, target.paragraph), max(0, session.document.count - 1))
        article.playbackParagraphIndex = p
        openSaved(article.id)
        if target.autoPlay {
            // Wait (≤20 s) for the Kokoro host so the resume doesn't start on Apple.
            var waited = 0
            while !tts.usesLocalEngine, tts.pendingEngineID != nil, waited < 100 {
                try? await Task.sleep(nanoseconds: 200_000_000)
                waited += 1
            }
            speech.start(session, fromParagraph: p)
        } else {
            speech.prepare(session, startingParagraph: p)
        }
        ListenTimingLog.log("kokoro_resume", [
            "ok": true, "key": ListenTimingLog.shortKey(article.id), "p": p, "auto_play": target.autoPlay,
            "local": tts.usesLocalEngine,
        ])
    }

    // MARK: - Suggestions

    private func scheduleSuggestFetch() {
        suggestTask?.cancel()
        let q = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard addressFocused, q.count >= 1 else {
            googleSuggestions = []
            return
        }
        // Skip Google for paste-looking full URLs.
        if q.contains("://") || (q.contains(".") && !q.contains(" ") && q.count > 4) {
            googleSuggestions = []
            return
        }
        suggestTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            let latest = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard latest == q else { return }
            let results = await GoogleSuggestClient.suggestions(for: q)
            guard !Task.isCancelled else { return }
            googleSuggestions = results
        }
    }

    private func applySuggestion(_ row: AddressSuggestion) {
        addressText = row.query
        submitAddress()
    }

    // MARK: - Editing

    /// ✕: leave search mode and put the page's address back.
    private func cancelEditing() {
        dictation?.cancel()
        suggestTask?.cancel()
        googleSuggestions = []
        isEditingAddress = false
        addressFocused = false
        if let url = webStore.currentURL, url.scheme != "about" {
            syncAddressField(from: url)
        } else {
            addressText = ""
        }
    }

    /// Swipe down: dismiss keyboard / lower the field, but stay in search mode (keep text + ✕).
    private func pullDownToLowerKeyboard(requireTop: Bool) -> some Gesture {
        DragGesture(minimumDistance: SwipeGesturePolicy.verticalMinimumDistance)
            .onChanged { _ in
                if dragStartedAtTop == nil { dragStartedAtTop = suggestionsAtTop }
            }
            .onEnded { value in
                let startedAtTop = dragStartedAtTop ?? suggestionsAtTop
                dragStartedAtTop = nil
                guard isEditingAddress, addressFocused, !requireTop || startedAtTop else { return }
                if SwipeGesturePolicy.shouldCommitVerticalDismiss(
                    translation: value.translation,
                    predicted: value.predictedEndTranslation
                ) {
                    addressFocused = false
                }
            }
    }

    /// Put a recent / suggestion term into the field without navigating (Safari fill arrow).
    private func fillSearchField(_ term: String) {
        addressText = term
        focusStartText = "\u{0}" // force recent panel to hide so suggestions can appear
        if !addressFocused { addressFocused = true }
    }

    private func micTapped() {
        guard let dictation else { return }
        if dictation.isActive {
            dictation.stop()
            return
        }
        dictation.start() // `.starting` now — clear field for a fresh transcript
        addressText = ""
        focusStartText = ""
        isEditingAddress = true
        if !addressFocused { addressFocused = true }
    }

    private func startNewSearch() {
        startingNewSearch = true
        addressText = ""
        focusStartText = ""
        isEditingAddress = true
        addressFocused = true
    }

    private func selectAllInFocusedField() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil)
        }
    }

    // MARK: - Navigation

    private func submitAddress() {
        let raw = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = BrowseURLParser.destination(from: raw) else { return }
        if RecentSearches.isSearch(raw) {
            recentSearchesRaw = RecentSearches.encode(RecentSearches.adding(raw, to: recentSearches))
        }
        isEditingAddress = false
        addressFocused = false
        googleSuggestions = []
        webStore.load(url)
        syncAddressField(from: url)
    }

    private func openRecent(_ visit: RecentVisit) {
        guard let url = visit.url else { return }
        if showReader { hideReader() } // picked from the reader's ⋯ → History
        isEditingAddress = false
        addressFocused = false
        googleSuggestions = []
        webStore.load(url)
        syncAddressField(from: url)
    }

    private func showStartLanding() {
        isEditingAddress = false
        addressFocused = false
        addressText = ""
        googleSuggestions = []
        if let blank = URL(string: "about:blank") {
            webStore.load(blank)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            webStore.currentURL = nil
            webStore.pageTitle = nil
            webStore.canGoBack = webStore.webView?.canGoBack ?? false
            webStore.canGoForward = webStore.webView?.canGoForward ?? false
        }
    }

    private func syncAddressField(from url: URL?) {
        guard let url, url.scheme != "about" else {
            if !addressFocused && !isEditingAddress { addressText = "" }
            return
        }
        guard !isEditingAddress else { return }
        if let host = url.host {
            let path = url.path == "/" ? "" : url.path
            addressText = host + path
        } else {
            addressText = url.absoluteString
        }
    }

    // MARK: - Recents

    @MainActor
    private func recordRecentVisitIfNeeded() async {
        guard let url = webStore.currentURL ?? webStore.webView?.url else { return }
        guard url.scheme == "http" || url.scheme == "https" else { return }
        var icon: Data?
        if let webView = webStore.webView {
            icon = await FaviconFetcher.fetch(from: webView)
        }
        if icon == nil, let host = url.host {
            icon = await FaviconFetcher.fetch(forHost: host)
        }
        RecentVisitRecorder.record(
            url: url,
            title: webStore.pageTitle,
            faviconData: icon,
            in: modelContext
        )
    }

    // MARK: - Extract / save

    private func activeExtractor() -> any ArticleExtracting {
        useFakeFailure ? FakeArticleExtractor(mode: .failure) : extractor
    }

    @MainActor
    private func makeContext() async throws -> ExtractionContext {
        guard let url = webStore.currentURL, url.scheme != "about" else {
            throw ExtractionError.unavailable(reason: "Open a page first.")
        }
        let html = try await webStore.snapshotHTML()
        return ExtractionContext(
            url: url,
            pageTitle: webStore.pageTitle,
            htmlSnapshot: html
        )
    }

    @MainActor
    private func runReader() async {
        isBusy = true
        busyIsSave = false
        defer { isBusy = false }
        do {
            let context = try await makeContext()
            let extracted = try await activeExtractor().extract(from: context)
            // Identity v2: saved row for this canonical URL → its id/playhead/bookmark.fill,
            // else the URL-derived key. Same key on every reopen → cached audio is reused.
            var article = ArticleLibrary.readerArticle(url: context.url, extracted: extracted, in: modelContext)
            if article.faviconData == nil {
                article.faviconData = recentFavicon(for: context.url)
            }
            readerArticle = article
            withAnimation(.easeInOut(duration: 0.2)) {
                showReader = true
            }
            if article.faviconData == nil {
                let id = article.id
                let icon = await fetchFavicon(for: context.url)
                if readerArticle?.id == id, readerArticle?.faviconData == nil {
                    readerArticle?.faviconData = icon
                }
            }
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    /// Bottom-bar bookmark (web page, Reader hidden). Idempotent save / unsave by canonical URL.
    /// Reader Mode's own bookmark lives in `ArticleReaderScreen`.
    @MainActor
    private func toggleSaveFromBrowser() async {
        if let saved = currentSavedArticle {
            let id = saved.id
            let canonical = saved.canonicalURL
            ArticleLibrary.unsave(id: id, canonicalURL: canonical, in: modelContext)
            speech.localTTS.markListenCacheEphemeral(id, canonicalURL: canonical)
            return
        }
        isBusy = true
        busyIsSave = true
        defer { isBusy = false; busyIsSave = false }
        do {
            let context = try await makeContext()
            let extracted = try await activeExtractor().extract(from: context)
            var article = ArticleLibrary.readerArticle(url: context.url, extracted: extracted, in: modelContext)
            article.faviconData = article.faviconData ?? recentFavicon(for: context.url)
            if article.faviconData == nil {
                article.faviconData = await fetchFavicon(for: context.url)
            }
            let row = ArticleLibrary.save(article, in: modelContext)
            speech.localTTS.prepareListenIdentity(
                key: row.id,
                paragraphs: article.document.paragraphs,
                trustedParagraphs: article.trustedParagraphs,
                legacyKeys: article.legacyCacheKeys,
                isLivePlayback: speech.activeSessionID == row.id
            )
            speech.localTTS.migrateListenCache(from: row.id, to: row.id)
            speech.localTTS.startBakeIfNeeded(
                articleID: row.id,
                paragraphs: article.document.paragraphs,
                rate: Float(speech.rateMultiplier),
                voiceID: speech.cacheVoiceID
            )
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func recentFavicon(for url: URL) -> Data? {
        guard let host = url.host else { return nil }
        let urlString = url.absoluteString
        return recentVisits.first(where: {
            $0.urlString == urlString || $0.host.caseInsensitiveCompare(host) == .orderedSame
        })?.faviconData
    }

    @MainActor
    private func fetchFavicon(for url: URL) async -> Data? {
        var icon: Data?
        if let webView = webStore.webView {
            icon = await FaviconFetcher.fetch(from: webView)
        }
        if icon == nil, let host = url.host {
            icon = await FaviconFetcher.fetch(forHost: host)
        }
        return icon
    }
}

private struct ShareItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// Notes when listening starts (Continue listening order) without making the browser re-render
/// on every playhead tick: only this empty view observes the speech controller.
private struct ListenHistoryRecorder: View {
    @Bindable var speech: SpeechController
    var onChange: () -> Void

    private struct Key: Equatable {
        let id: UUID?
        let playing: Bool
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onChange(of: Key(id: speech.activeSessionID, playing: speech.isPlaying)) { _, key in
                if let id = key.id, key.playing { ListenHistory.record(id) }
                onChange()
            }
    }
}

private struct SuggestionsTopOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
