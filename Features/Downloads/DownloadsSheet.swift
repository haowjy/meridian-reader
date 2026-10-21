import SwiftUI

/// ⋯ › Downloads (decision D16): what is downloading and what is downloaded, with the voice each
/// is in. Sections, each only when it has rows:
///
/// ```
/// Downloads                                         Done
/// Now                                        Pause All
/// ▣  Pride and Prejudice                    (◔)    ⋯   the ↓ filling as it renders
///    4 of 12   ~2 h 45 min left
/// Waiting  2
/// [i] Notes on Tides                        (✻)    ⋯   in queue order, spinner (C93)
///    Kokoro Heart
/// [i] Bond Ladders                          (◔)    ⋯   paused: the mark in grey
///    Kokoro Heart   Paused
/// Downloaded  1
/// [i] Coupon Basics                                 ⋯
///    ↓ Kokoro Heart   12 MB
/// 12 MB on this iPhone
/// Different Voice  1
/// [i] Seven-Day Yield                               ⋯
///    Kokoro Bella   9 MB
/// Downloads now render in Kokoro Heart. …
/// ```
///
/// Every row is a `ListRow`: a tap opens what was downloaded (the Reader for a page, the Library
/// at a folder); a queued one has its pause / resume control before the ⋯; ⋯ and the long press
/// are the download's menu (`DownloadMenu`, the same in every section); swipe left is its
/// *Remove Download* (*Remove Downloads* on a folder).
struct DownloadsSheet: View {
    @Environment(ShellState.self) private var shell

    var body: some View {
        NavigationStack {
            DownloadsList()
                .toolbar {
                    SheetBarButton(Verbs.done, placement: .confirmationAction, identifier: "downloadsDone") {
                        shell.sheet = nil
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheetToastLayer()
        .accessibilityIdentifier("downloadsSheet")
    }
}

/// The Downloads list itself: the sheet's, and Settings › Downloads & Storage › Downloads. Every
/// row is one page (C110), a folder's pages each on their own row: its status mark before line
/// two (a spinner waiting, the accent ↓ filling with its own progress, filled once done), line two
/// its folder's name (its site when it is in no folder). Waiting is in the order pages render.
/// A folder's own download (its toggle, *Turn Off Download*) stays on the folder's screen.
struct DownloadsList: View {
    @Environment(DownloadCenter.self) private var downloads
    @Environment(LibraryStore.self) private var library
    @Environment(ShellState.self) private var shell
    @Environment(FollowCenter.self) private var follow
    @Environment(\.speechController) private var speech
    /// Bytes on disk of each downloaded page, by its key (measured off the main actor).
    @State private var sizes: [UUID: Int64] = [:]
    /// From Listening (C135): articles with audio made while listening, not prepared, newest
    /// played first, with their sizes.
    @State private var listening: [UUID] = []
    @State private var listeningSizes: [UUID: Int64] = [:]
    @State private var confirmingDeleteAll = false
    @State private var confirmingClear = false

    var body: some View {
        let overview = downloads.pageOverview
        let records = downloads.overview.queued
        let revision = speech.localTTS.audioCache.contentRevision
        List {
            if overview.isEmpty && listening.isEmpty {
                Section {
                    EmptyState(String(localized: "Nothing Downloaded"), symbol: Icons.downloads,
                               description: Text("Download an article from its \(Text.symbol(Icons.more)) in the Library, or a folder with \(Text.symbol(Icons.download)) on its screen. Its audio is made ahead of time, so it plays offline."))
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("downloadsEmpty")
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            let anyRunning = records.contains { !$0.record.isPaused }
            if !overview.now.isEmpty {
                section(overview.now, header: pauseAllHeader(String(localized: "Now"), count: nil, anyRunning: anyRunning),
                        headerID: "downloadsNowHeader") { EmptyView() }
            }
            if !overview.waiting.isEmpty {
                let title = String(localized: "Waiting")
                section(overview.waiting,
                        header: overview.now.isEmpty ? pauseAllHeader(title, count: overview.waiting.count, anyRunning: anyRunning)
                            : SectionHeader(title: title, count: overview.waiting.count),
                        headerID: "downloadsWaitingHeader") {
                    if !speech.localTTS.wantsLocalBake { waitingNote.listFooter() }
                }
            }
            if !overview.done.isEmpty {
                section(overview.done, header: SectionHeader(title: Verbs.downloaded, count: overview.done.count),
                        headerID: "downloadsDoneHeader") {
                    let total = overview.done.compactMap { sizes[$0.key] }.reduce(0, +)
                    if total > 0 {
                        Text(String(localized: "\(FileSizes.label(total)) on this iPhone"))
                            .accessibilityIdentifier("downloadsStorage")
                            .listFooter()
                    }
                }
            }
            if !listening.isEmpty {
                let items = listening.map { DownloadArticles.Item(recordID: $0, key: $0, status: .done, voice: nil) }
                Section {
                    ForEach(items) { item in listeningRow(item) }
                        .listRowInsets(EdgeInsets())
                        .listCard()
                } header: {
                    SectionHeader(title: String(localized: "From Listening"), count: items.count)
                        .listHeader()
                        .accessibilityIdentifier("preparedListeningHeader")
                } footer: {
                    let total = listening.compactMap { listeningSizes[$0] }.reduce(0, +)
                    Text(String(localized: "Audio made while you listen. It’s cleared once its article leaves the last \(LibraryStore.recentLimit) in Recent.")
                         + (total > 0 ? " " + String(localized: "\(FileSizes.label(total)) on this iPhone.") : ""))
                        .listFooter()
                }
            }
            if !overview.differentVoice.isEmpty {
                section(overview.differentVoice,
                        header: SectionHeader(title: String(localized: "Different Voice"), count: overview.differentVoice.count),
                        headerID: "downloadsDifferentVoiceHeader") {
                    if let voice = speech.localTTS.downloadVoice {
                        Text(String(localized: "Downloads now render in \(voiceLabel(voice)). A download’s menu has Re-download, to hear it in that voice, and Keep, to keep it as it is."))
                            .listFooter()
                    }
                }
            }
        }
        .cardListStyle()
        .animation(Motion.standard, value: overview)
        .navigationTitle(Verbs.downloads)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: overview.done.map(\.key)) { sizes = await measure(overview.done.map(\.key)) }
        .task(id: "\(revision)-\(downloads.records.count)") { await loadListening() }
        .toolbar {
            let rows = listMenuRows(hasPrepared: !overview.isEmpty)
            if !rows.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    Menu { MenuRows(rows) } label: { Image(systemName: Icons.more) }
                        .accessibilityLabel(Verbs.more)
                        .accessibilityIdentifier("preparedMore")
                }
            }
        }
        .alert(String(localized: "Delete \(downloads.heldArticleKeys.count) articles and their prepared audio? This can’t be undone."),
               isPresented: $confirmingDeleteAll) {
            Button(Verbs.delete, role: .destructive) {
                shell.attempt(String(localized: "Couldn’t delete the articles")) { try downloads.deleteAll() }
            }
            .accessibilityIdentifier("preparedDeleteAllConfirm")
            Button(Verbs.cancel, role: .cancel) {}
        }
        .alert(String(localized: "Clear the audio from listening? The articles stay."), isPresented: $confirmingClear) {
            Button(Verbs.clear, role: .destructive) { clearListening() }
            Button(Verbs.cancel, role: .cancel) {}
        }
    }

    // MARK: - From Listening (C135)

    /// The list's ⋯: *Delete All…* over Prepared, *Clear Audio From Listening…* over From
    /// Listening, each only while its section has rows (`MenuRegistry`).
    private func listMenuRows(hasPrepared: Bool) -> [MenuRow] {
        var facts = MenuRegistry.Facts()
        facts.hasPrepared = hasPrepared && !downloads.heldArticleKeys.isEmpty
        facts.hasListeningAudio = !listening.isEmpty
        return MenuRegistry.rows(.screen, at: .downloads, facts) { option in
            if option == .deleteAllPrepared {
                return MenuRow(id: "preparedDeleteAll", title: Verbs.deleteAllPrepared, icon: Icons.delete,
                               isDestructive: true) { confirmingDeleteAll = true }
            }
            return MenuRow(id: "preparedClearListening", title: Verbs.clearListeningAudio, icon: Icons.delete,
                           isDestructive: true) { confirmingClear = true }
        }
    }

    private func listeningRow(_ item: DownloadArticles.Item) -> some View {
        let article = library.article(key: item.key)
        let title = article?.lineOne ?? ""
        let kind: ListRow.Kind = .article(artwork: article?.artworkImage, letter: article?.artworkLetter ?? String(title.prefix(1)))
        let place = article.flatMap { $0.folder?.name ?? ArticleRowTitle.lineTwoSource(title: $0.givenTitle, source: $0.byline) }
        let menu = DownloadMenu(item: item, downloads: downloads, library: library, isListeningAudio: true,
                                needsAudio: speech.localTTS.listeningNeedsKey)
        // No accent ↓: that mark is for prepared audio only (C135).
        return ListRow(kind: kind, title: title, subtitle: place,
                       details: [listeningSizes[item.key].map(FileSizes.label)].compactMap { $0 },
                       menu: AnyView(menu), showsListening: false)
            .opensOnTap { open(article) }
            .contextMenu { AnyView(menu) }
            .swipeActions(edge: .trailing) { menu.removeRow.swipeButton(role: .destructive) }
            .accessibilityIdentifier("listeningAudioRow")
    }

    /// Articles in the Library or Recent with audio on disk that no prepare record holds, newest
    /// played first.
    private func loadListening() async {
        let held = Set(downloads.heldArticleKeys)
        let keys = speech.localTTS.audioCache.cachedArticleKeys().filter { !held.contains($0) }
        let articles = keys.compactMap(library.article(key:))
            .sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
        listening = articles.compactMap(\.key)
        listeningSizes = await measure(listening)
    }

    private func clearListening() {
        let needs = speech.localTTS.listeningNeedsKey
        for key in listening where !needs(key) {
            if let article = library.article(key: key) { library.deleteDownloads(article) }
        }
        Task { await loadListening() }
    }

    // MARK: - Sections

    /// *Pause All* / *Resume All* over everything still to download.
    private func pauseAllHeader(_ title: String, count: Int?, anyRunning: Bool) -> SectionHeader {
        SectionHeader(title: title, count: count, actionTitle: anyRunning ? Verbs.pauseAll : Verbs.resumeAll,
                      actionIdentifier: "downloadsPauseAll") {
            downloads.setAllPaused(anyRunning)
        }
    }

    private func section<Footer: View>(
        _ items: [DownloadArticles.Item], header: SectionHeader, headerID: String, @ViewBuilder footer: () -> Footer
    ) -> some View {
        let footer = footer()
        return Section {
            ForEach(items) { item in row(item) }
                .listRowInsets(EdgeInsets())
                .listCard()
        } header: {
            header
                .listHeader()
                .accessibilityIdentifier(headerID)
        } footer: {
            footer
        }
    }

    /// "Kokoro Heart" for a cache voice key.
    private func voiceLabel(_ voice: String) -> String {
        speech.localTTS.engines.voiceLabel(forCacheVoice: voice)
    }

    private var waitingNote: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(String(localized: "Downloads render with an on-device voice. Choose one in Settings to go on."))
            PillButton(Verbs.settings, systemImage: Icons.settings, style: .neutral, size: .compact) {
                shell.present(.settings)
            }
                .accessibilityIdentifier("downloadsSettings")
        }
        .padding(.top, Spacing.xxs)
    }

    // MARK: - A row

    private func row(_ item: DownloadArticles.Item) -> some View {
        let article = library.article(key: item.key)
        let title = article?.lineOne ?? downloads.records.first { $0.id == item.recordID }?.title ?? ""
        let kind: ListRow.Kind = .article(artwork: article?.artworkImage, letter: article?.artworkLetter ?? String(title.prefix(1)))
        // Line two as a row's anywhere: its folder, else its site.
        let place = article.flatMap { $0.folder?.name ?? ArticleRowTitle.lineTwoSource(title: $0.givenTitle, source: $0.byline) }
        let downloadMenu = DownloadMenu(item: item, downloads: downloads, library: library)
        let menu = AnyView(downloadMenu)
        return ListRow(kind: kind, title: title, subtitle: place, details: detail(item),
                       download: mark(item), menu: menu, showsListening: false)
            .opensOnTap { open(article) }
            .contextMenu { menu }
            .swipeActions(edge: .trailing) {
                downloadMenu.removeRow.swipeButton(role: .destructive)
            }
            .accessibilityIdentifier("downloadRow")
    }

    /// The row's one status mark (C102): filling with its own progress, waiting, paused, done.
    private func mark(_ item: DownloadArticles.Item) -> DownloadState {
        switch item.status {
        case .downloading(let f), .fetching(let f): .downloading(fraction: f)
        case .queued, .waitingForVoice: .queued(fraction: 0)
        case .paused: .paused(fraction: 0)
        case .done: item.failed ? .notDownloaded : .downloaded
        case .differentVoice: .downloaded
        }
    }

    private func detail(_ item: DownloadArticles.Item) -> [String] {
        let voice = item.voice.map(voiceLabel)
        switch item.status {
        case .downloading(let f): return ["\(Int((f * 100).rounded()))%"]
        case .fetching: return [String(localized: "Getting the article")]
        case .queued: return [voice].compactMap { $0 }
        case .paused: return [String(localized: "Paused")]
        case .waitingForVoice: return [String(localized: "Needs a voice")]
        case .done, .differentVoice:
            if item.failed { return [String(localized: "Couldn’t download")] }
            return [voice, sizes[item.key].map(FileSizes.label)].compactMap { $0 }
        }
    }

    /// A page opens in the Reader (Now Playing when it is what you hear).
    private func open(_ article: Article?) {
        guard let article else { return }
        shell.sheet = nil
        LibraryActions(library: library, speech: speech, shell: shell, follow: follow).open(article)
    }

    // MARK: - Storage

    /// Each page's audio on disk, allocated bytes.
    private func measure(_ keys: [UUID]) async -> [UUID: Int64] {
        let cache = speech.localTTS.audioCache
        let folders = keys.map { ($0, cache.directory(for: $0)) }
        return await Task.detached(priority: .utility) {
            var sizes: [UUID: Int64] = [:]
            for (key, url) in folders { sizes[key] = FileSizes.allocatedBytes(at: url) }
            return sizes
        }.value
    }
}
