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

/// The Downloads list itself: the sheet's, and Settings › Downloads & Storage › Downloads.
struct DownloadsList: View {
    @Environment(DownloadCenter.self) private var downloads
    @Environment(LibraryStore.self) private var library
    @Environment(ShellState.self) private var shell
    @Environment(FollowCenter.self) private var follow
    @Environment(\.speechController) private var speech
    /// Bytes on disk of each finished download, by its id (measured off the main actor).
    @State private var sizes: [UUID: Int64] = [:]

    var body: some View {
        let overview = downloads.overview
        List {
            if overview.isEmpty {
                Section {
                    EmptyState(String(localized: "Nothing Downloaded"), symbol: Icons.downloads,
                               description: Text("Download a page from its \(Text.symbol(Icons.more)) in the Library, or a folder or book with \(Text.symbol(Icons.download)) on its screen. Its audio is made ahead of time, so it plays offline."))
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("downloadsEmpty")
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            let now = overview.queued.filter { downloads.isActive($0.id) }
            let waiting = overview.queued.filter { !downloads.isActive($0.id) }
            if !now.isEmpty { nowSection(now, anyRunning: overview.queued.contains { !$0.record.isPaused }) }
            if !waiting.isEmpty { waitingSection(waiting, pauseAll: now.isEmpty) }
            if !overview.done.isEmpty { done(overview.done) }
            if !overview.differentVoice.isEmpty { differentVoice(overview.differentVoice) }
        }
        .cardListStyle()
        .animation(Motion.standard, value: overview)
        .navigationTitle(Verbs.downloads)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: SizeKey(overview)) { sizes = await measure(overview.done + overview.differentVoice) }
    }

    // MARK: - Sections

    /// *Pause All* / *Resume All* over everything still to download.
    private func pauseAllHeader(_ title: String, count: Int?, anyRunning: Bool) -> SectionHeader {
        SectionHeader(title: title, count: count, actionTitle: anyRunning ? Verbs.pauseAll : Verbs.resumeAll,
                      actionIdentifier: "downloadsPauseAll") {
            downloads.setAllPaused(anyRunning)
        }
    }

    /// The download rendering now (C92).
    private func nowSection(_ items: [DownloadOverview.Item], anyRunning: Bool) -> some View {
        section(items, header: pauseAllHeader(String(localized: "Now"), count: nil, anyRunning: anyRunning),
                headerID: "downloadsNowHeader") {
            EmptyView()
        }
    }

    /// The downloads waiting their turn, in queue order, each with its place and wait (C92).
    private func waitingSection(_ items: [DownloadOverview.Item], pauseAll: Bool) -> some View {
        let title = String(localized: "Waiting")
        let header = pauseAll ? pauseAllHeader(title, count: items.count, anyRunning: items.contains { !$0.record.isPaused })
            : SectionHeader(title: title, count: items.count)
        return section(items, header: header, headerID: "downloadsWaitingHeader") {
            if !speech.localTTS.wantsLocalBake {
                waitingNote
                    .listFooter()
            }
        }
    }

    private func done(_ items: [DownloadOverview.Item]) -> some View {
        section(items, header: SectionHeader(title: Verbs.downloaded, count: items.count),
                headerID: "downloadsDoneHeader") {
            let total = items.compactMap { sizes[$0.id] }.reduce(0, +)
            if total > 0 {
                Text(String(localized: "\(FileSizes.label(total)) on this iPhone"))
                    .accessibilityIdentifier("downloadsStorage")
                    .listFooter()
            }
        }
    }

    private func differentVoice(_ items: [DownloadOverview.Item]) -> some View {
        section(items, header: SectionHeader(title: String(localized: "Different Voice"), count: items.count),
                headerID: "downloadsDifferentVoiceHeader") {
            if let voice = speech.localTTS.downloadVoice {
                Text(String(localized: "Downloads now render in \(voiceLabel(voice)). A download’s menu has Re-download, to hear it in that voice, and Keep, to keep it as it is."))
                    .listFooter()
            }
        }
    }

    /// A section of downloads under `header` (identified `headerID`), with `footer` below.
    private func section<Footer: View>(
        _ items: [DownloadOverview.Item], header: SectionHeader, headerID: String, @ViewBuilder footer: () -> Footer
    ) -> some View {
        let footer = footer()
        return Section {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                row(item, place: index)
            }
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

    private func row(_ item: DownloadOverview.Item, place: Int) -> some View {
        let record = item.record
        let shown = DownloadShown(record: record, library: library)
        let parts = detail(item, noun: shown.noun, place: place)
        let downloadMenu = DownloadMenu(item: item, downloads: downloads)
        let menu = AnyView(downloadMenu)
        return ListRow(kind: shown.kind, title: shown.title, subtitle: parts.first, details: Array(parts.dropFirst()),
                       download: item.status == .done ? .downloaded : .notDownloaded, folderHasDetails: shown.hasDetails,
                       menu: menu, accessory: transfer(item), showsListening: false)
            .opensOnTap { open(record.target) }
            .contextMenu { menu }
            .swipeActions(edge: .trailing) {
                // The menu's *Remove Download(s)*. The record goes at once (`remove` is
                // synchronous), so the role's early row removal agrees with the list.
                downloadMenu.rows.swipeRow("menuRemoveDownload")?.swipeButton(role: .destructive)
            }
            .accessibilityIdentifier("downloadRow")
    }

    /// The voice, then where it is: "4 of 12   ~2 h left" (rendering now),
    /// the voice alone while waiting (the Waiting section already says it is next, C96),
    /// "Kokoro Heart   12 MB".
    private func detail(_ item: DownloadOverview.Item, noun: String?, place: Int) -> [String] {
        let record = item.record
        let voice = item.voice.map(voiceLabel)
        let count = noun.map { String(localized: "\(record.finishedCount) of \(record.entries.count) \($0)") }
        let size = sizes[record.id].map(FileSizes.label)
        func percent(_ f: Double) -> String { "\(Int((f * 100).rounded()))%" }
        switch item.status {
        case .downloading(let f):
            // Short enough for one line on a phone (C95): the count without its noun (a page's
            // download: its percent), then the time left. The voice and percent are left out:
            // the voice shows once done, the mark fills with the percent.
            let left = downloads.renderSecondsLeft(record).map { String(localized: "\(DownloadCenter.estimate($0)) left") }
            let done = noun == nil ? percent(f) : String(localized: "\(record.finishedCount) of \(record.entries.count)")
            return [done, left].compactMap { $0 }
        case .fetching:
            return [voice, count, String(localized: "Getting the page")].compactMap { $0 }
        case .queued:
            return [voice].compactMap { $0 }
        case .paused(let f):
            return [voice, String(localized: "Paused"), f > 0 ? percent(f) : nil].compactMap { $0 }
        case .waitingForVoice:
            return [String(localized: "Waiting for an on-device voice")]
        case .done, .differentVoice:
            let failed = record.failedCount
            let live = record.entries.allSatisfy { $0.state == .speaksLive }
            return [live ? String(localized: "Plays with Apple’s voice") : voice, size,
                    failed > 0 ? String(localized: "\(failed) couldn’t download") : nil].compactMap { $0 }
        }
    }

    /// A queued download's control: its `DownloadMark` filling as it renders (a tap pauses it),
    /// grey while paused (a tap resumes it). None once done.
    private func transfer(_ item: DownloadOverview.Item) -> AnyView? {
        guard let fraction = item.status.fraction else { return nil }
        let paused = item.record.isPaused
        return AnyView(
            Button { downloads.setPaused(item.id, !paused) } label: {
                DownloadMark(state: paused ? .paused(fraction: fraction)
                             : downloads.isActive(item.id) ? .downloading(fraction: fraction)
                             : .queued(fraction: fraction))
                    .frame(width: BottomChrome.minTapTarget, height: BottomChrome.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(paused ? String(localized: "Resume Download") : String(localized: "Pause Download"))
            .accessibilityValue(String(localized: "\(Int((fraction * 100).rounded())) percent"))
            .accessibilityIdentifier(paused ? "downloadResume" : "downloadPause")
        )
    }

    /// A page opens in the Reader (Now Playing when it is what you hear); a folder in the Library.
    private func open(_ target: DownloadRecord.Target) {
        switch target {
        case .page(let key):
            guard let page = library.page(key: key) else { return }
            shell.sheet = nil
            LibraryActions(library: library, speech: speech, shell: shell, follow: follow).open(page)
        case .folder(let id):
            guard let folder = library.folder(id: id) else { return }
            shell.sheet = nil
            shell.showLibrary(at: library.path(to: folder))
        }
    }

    // MARK: - Storage

    /// What the sizes depend on: the finished downloads and how far each got.
    private struct SizeKey: Hashable {
        var ids: [UUID]
        var finished: [Int]

        init(_ overview: DownloadOverview) {
            let items = overview.done + overview.differentVoice
            ids = items.map(\.id)
            finished = items.map(\.record.finishedCount)
        }
    }

    /// Each download's audio on disk: its pages' cache folders, allocated bytes.
    private func measure(_ items: [DownloadOverview.Item]) async -> [UUID: Int64] {
        let cache = speech.localTTS.audioCache
        let folders = items.map { item in (item.id, item.record.entries.map { cache.directory(for: $0.key) }) }
        return await Task.detached(priority: .utility) {
            var sizes: [UUID: Int64] = [:]
            for (id, urls) in folders { sizes[id] = urls.reduce(0) { $0 + FileSizes.allocatedBytes(at: $1) } }
            return sizes
        }.value
    }
}

/// How a download looks in the list: its page's or folder's current title and artwork (the title
/// it was asked for once it is gone), and what its pages are called (`Folder.itemNoun`; nothing
/// for one page).
@MainActor
private struct DownloadShown {
    let title: String
    let kind: ListRow.Kind
    let hasDetails: Bool
    let noun: String?

    init(record: DownloadRecord, library: LibraryStore) {
        switch record.target {
        case .page(let key):
            let page = library.page(key: key)
            title = page?.lineOne ?? record.title
            kind = .page(artwork: page?.artworkImage, letter: page?.artworkLetter ?? String(title.prefix(1)))
            hasDetails = false
            noun = nil
        case .folder(let id):
            let folder = library.folder(id: id)
            title = folder?.name ?? record.title
            kind = .folder(symbol: folder?.rowSymbol ?? Icons.folder, count: [],
                           cover: folder?.hasDetails == true ? folder?.coverImage : nil)
            hasDetails = folder?.hasDetails == true
            noun = folder?.itemNoun ?? String(localized: "pages")
        }
    }
}
