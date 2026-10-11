import SwiftUI
import SwiftData

/// The shell's one sheet (`ShellState.sheet`). Picking a history entry loads it in the browser;
/// Favorites, the Move tree and the import sheet are the Library's screens.
struct ShellSheetView: View {
    let sheet: ShellSheet

    @Environment(ShellState.self) private var shell
    @Environment(\.speechController) private var speech
    @Query(sort: \RecentVisit.visitedAt, order: .reverse) private var recentVisits: [RecentVisit]

    var body: some View {
        switch sheet {
        case .favorites(let folder):
            FavoritesSheet(folderID: folder)
        case .moveTo(let request):
            MoveTreeSheet(request: request)
        case .importBook(let flow):
            BookImportSheet(flow: flow)
        case .downloads:
            DownloadsSheet()
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
