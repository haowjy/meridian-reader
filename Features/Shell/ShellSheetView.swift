import SwiftUI
import SwiftData

/// The shell's one sheet (`ShellState.sheet`). Picking a bookmark or history entry loads it in
/// the browser.
struct ShellSheetView: View {
    let sheet: ShellSheet

    @Environment(ShellState.self) private var shell
    @Environment(\.speechController) private var speech
    @Environment(LibraryStore.self) private var library
    @Query(sort: \RecentVisit.visitedAt, order: .reverse) private var recentVisits: [RecentVisit]

    var body: some View {
        switch sheet {
        case .bookmarks:
            BookmarksListView(library: library) { bookmark in
                open(bookmark.url)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        case .history:
            BrowseHistoryView(visits: Array(recentVisits.prefix(RecentVisit.maxEntries))) { visit in
                open(visit.url)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        case .voiceSettings:
            NavigationStack {
                SpeechSettingsView(speech: speech)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { shell.sheet = nil }
                        }
                    }
            }
        case .share(let url):
            ActivityShareSheet(items: [url])
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
        }
    }

    private func open(_ url: URL?) {
        shell.sheet = nil
        if let url { shell.navigate(to: url) }
    }
}
