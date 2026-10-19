import SwiftUI

/// ⋯ › Downloads (decision D16): what is downloading and what is downloaded, with the voice each
/// is in. Sections, each only when it has rows:
///
/// ```
/// Downloads                                         Done
/// Queued  2                                  Pause All
/// ▣  Pride and Prejudice                       (◔⏸)
///    Kokoro Heart   4 of 12 chapters   38%
/// [i] Notes on Tides                           (◔⏸)
///    Kokoro Heart   Queued
/// Downloaded  1
/// [i] Coupon Basics
///    Kokoro Heart   12 MB
/// 12 MB on this iPhone
/// Different Voice  1
/// [i] Seven-Day Yield
///    Kokoro Bella   9 MB
///    ( Re-download )  ( Keep )
/// Downloads now render in Kokoro Heart. …
/// ```
///
/// A row opens what was downloaded (the Reader for a page, the Library at a folder). Swipe left
/// removes a download, its audio with it; the long-press menu has the row's other choices.
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
                Section { emptyCard }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            if !overview.queued.isEmpty { queued(overview.queued) }
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

    private func queued(_ items: [DownloadOverview.Item]) -> some View {
        let anyRunning = items.contains { !$0.record.isPaused }
        let header = SectionHeader(title: String(localized: "Queued"), count: items.count,
                                   actionTitle: anyRunning ? String(localized: "Pause All") : String(localized: "Resume All"),
                                   actionIdentifier: "downloadsPauseAll") {
            downloads.setAllPaused(anyRunning)
        }
        return section(items, header: header, headerID: "downloadsQueuedHeader") { item in
            if item.record.isPaused {
                Button("Resume", systemImage: Icons.download) { downloads.setPaused(item.id, false) }
            } else {
                Button("Pause", systemImage: Icons.pause) { downloads.setPaused(item.id, true) }
            }
        } footer: {
            if !speech.localTTS.wantsLocalBake {
                waitingNote
                    .listFooter()
            }
        }
    }

    private func done(_ items: [DownloadOverview.Item]) -> some View {
        section(items, header: SectionHeader(title: String(localized: "Downloaded"), count: items.count),
                headerID: "downloadsDoneHeader") { item in
            Button("Re-download", systemImage: Icons.redownload) { downloads.redownload(item.id) }
        } footer: {
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
                headerID: "downloadsDifferentVoiceHeader") { item in
            Button("Re-download", systemImage: Icons.redownload) { downloads.redownload(item.id) }
            Button("Keep", systemImage: Icons.keep) {
                if let voice = item.voice { downloads.keep(item.id, voice: voice) }
            }
            .menuAvailability(MenuAvailability(when: item.voice != nil))
        } footer: {
            if let voice = speech.localTTS.downloadVoice {
                Text(String(localized: "Downloads now render in \(voiceLabel(voice)). Re-download one to hear it in that voice, or keep it as it is."))
                    .listFooter()
            }
        }
    }

    /// A section of downloads: each row with its long-press `menu` and *Remove* last, under
    /// `header` (identified `headerID`), with `footer` below.
    private func section<Menu: View, Footer: View>(
        _ items: [DownloadOverview.Item], header: SectionHeader, headerID: String,
        @ViewBuilder menu: @escaping (DownloadOverview.Item) -> Menu, @ViewBuilder footer: () -> Footer
    ) -> some View {
        let footer = footer()
        return Section {
            ForEach(items) { item in
                row(item)
                    .contextMenu {
                        menu(item)
                        removeButton(item)
                    }
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

    private func removeButton(_ item: DownloadOverview.Item) -> some View {
        Button("Remove", systemImage: Icons.delete, role: .destructive) { downloads.remove(item.id) }
    }

    private var waitingNote: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(String(localized: "Downloads render with an on-device voice. Choose one in Settings to go on."))
            PillButton(Verbs.settings, systemImage: Icons.settings, style: .neutral, size: .compact) {
                shell.present(.settings)
            }
                .accessibilityIdentifier("downloadsSettings")
        }
        .padding(.top, Spacing.xs)
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Nothing downloaded")
                .typeStyle(.row, weight: .semibold)
                .foregroundStyle(Palette.ink)
            Text("Download a page from its \(Text.symbol(Icons.more)) in the Library, or a folder or book with \(Text.symbol(Icons.download)) on its screen. Its audio is made ahead of time, so it plays offline.")
                .typeStyle(.row)
                .foregroundStyle(Palette.secondaryInk)
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.chrome, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("downloadsEmpty")
    }

    // MARK: - A row

    private func row(_ item: DownloadOverview.Item) -> some View {
        let record = item.record
        let shown = DownloadShown(record: record, library: library)
        return DownloadRow(leading: shown.leading, title: shown.title, detail: detail(item, unit: shown.unit),
                           transfer: transfer(item), choices: choices(item))
            .opensOnTap { open(record.target) }
            .swipeActions(edge: .trailing) {
                Button("Remove", role: .destructive) { downloads.remove(item.id) }
            }
            .accessibilityIdentifier("downloadRow")
    }

    /// The voice, then where it is: "Kokoro Heart   4 of 12 chapters   38%", "Kokoro Heart   12 MB".
    private func detail(_ item: DownloadOverview.Item, unit: String?) -> [String] {
        let record = item.record
        let voice = item.voice.map(voiceLabel)
        let count = unit.map { String(localized: "\(record.finishedCount) of \(record.entries.count) \($0)") }
        let size = sizes[record.id].map(FileSizes.label)
        func percent(_ f: Double) -> String { "\(Int((f * 100).rounded()))%" }
        switch item.status {
        case .downloading(let f):
            return [voice, count, percent(f)].compactMap { $0 }
        case .fetching:
            return [voice, count, String(localized: "Getting the page")].compactMap { $0 }
        case .queued:
            return [voice, count, String(localized: "Queued")].compactMap { $0 }
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

    private func transfer(_ item: DownloadOverview.Item) -> DownloadRow.Transfer? {
        guard let fraction = item.status.fraction else { return nil }
        let paused = item.record.isPaused
        return DownloadRow.Transfer(fraction: fraction, isPaused: paused) { downloads.setPaused(item.id, !paused) }
    }

    private func choices(_ item: DownloadOverview.Item) -> [DownloadRow.Choice] {
        guard case .differentVoice(let voice) = item.status else { return [] }
        return [
            .init(title: String(localized: "Re-download"), systemImage: Icons.redownload, isPrimary: true, identifier: "downloadRedownload") {
                downloads.redownload(item.id)
            },
            .init(title: String(localized: "Keep"), systemImage: Icons.keep, identifier: "downloadKeep") { downloads.keep(item.id, voice: voice) },
        ]
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
/// it was asked for once it is gone), and what its pages are called ("chapters" in a book or
/// series, "pages" in a folder, nothing for one page).
@MainActor
private struct DownloadShown {
    let title: String
    let leading: DownloadRow.Leading
    let unit: String?

    init(record: DownloadRecord, library: LibraryStore) {
        switch record.target {
        case .page(let key):
            let page = library.page(key: key)
            title = page?.lineOne ?? record.title
            leading = .page(artwork: page?.artworkImage, letter: page?.artworkLetter ?? title)
            unit = nil
        case .folder(let id):
            let folder = library.folder(id: id)
            title = folder?.name ?? record.title
            leading = .folder(symbol: folder?.rowSymbol ?? Icons.folder, cover: folder?.coverImage)
            unit = folder?.kind.isBookOrSeries == true ? String(localized: "chapters") : String(localized: "pages")
        }
    }
}
