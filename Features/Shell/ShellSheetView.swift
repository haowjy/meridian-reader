import SwiftUI
import SwiftData

/// The shell's one sheet (`ShellState.sheet`), and the one that can show over it
/// (`ShellState.overSheet`). Picking a history entry loads it in the browser; the Move tree, the
/// import sheet and *Edit Details* are Library screens.
struct ShellSheetView: View {
    let sheet: ShellSheet

    @Environment(ShellState.self) private var shell
    @Environment(\.speechController) private var speech
    @Query(sort: \RecentVisit.visitedAt, order: .reverse) private var recentVisits: [RecentVisit]

    var body: some View {
        content(sheet)
            .sheet(item: Binding(get: { shell.overSheet }, set: { shell.overSheet = $0 })) { content($0) }
    }

    @ViewBuilder
    private func content(_ sheet: ShellSheet) -> some View {
        switch sheet {
        case .moveTo(let request):
            MoveTreeSheet(request: request)
        case .importBook(let flow):
            BookImportSheet(flow: flow)
        case .downloads:
            DownloadsSheet()
        case .folderDetails(let id):
            FolderDetailsSheet(folderID: id)
        case .history:
            BrowseHistoryView(visits: Array(recentVisits.prefix(RecentVisit.maxEntries))) { visit in
                open(visit.url)
            } onDone: {
                shell.sheet = nil
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        case .voiceSettings:
            NavigationStack {
                SpeechSettingsView(speech: speech)
                    .toolbar {
                        SheetBarButton(Verbs.done, placement: .confirmationAction, identifier: "voiceSettingsDone") {
                            shell.sheet = nil
                        }
                    }
            }
        case .share(let url):
            ActivityShareSheet(items: [url])
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
        case .listenDebug:
            ListenDebugPanel(speech: speech)
        }
    }

    private func open(_ url: URL?) {
        shell.sheet = nil
        if let url { shell.navigate(to: url) }
    }
}
