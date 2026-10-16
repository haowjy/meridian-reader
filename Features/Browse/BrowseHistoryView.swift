import SwiftUI

/// Recently visited pages (the bounded `RecentVisit` list), newest first, in the Library's rows:
/// the site's icon (or its letter tile), the title, then the site and how long ago. Tap to open.
///
/// ```
/// History                                           ( Done )
/// ▣  Speech synthesis
///    en.wikipedia.org   2 hr ago
/// ```
struct BrowseHistoryView: View {
    let visits: [RecentVisit]
    var onOpen: (RecentVisit) -> Void
    var onDone: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if visits.isEmpty {
                    ContentUnavailableView("No history yet", systemImage: Icons.history,
                                           description: Text("Pages you open show up here."))
                        .background(Palette.paper)
                } else {
                    List {
                        Section {
                            ForEach(visits, id: \.id) { visit in
                                row(visit)
                            }
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Palette.chrome)
                        }
                    }
                    .libraryListStyle()
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                SheetBarButton(Verbs.done, placement: .confirmationAction, identifier: "historyDone", action: onDone)
            }
        }
        .accessibilityIdentifier("browseHistory")
    }

    private func row(_ visit: RecentVisit) -> some View {
        ListRow(kind: .page(artwork: visit.faviconData.flatMap(UIImage.init(data:)).map(Image.init(uiImage:)),
                            letter: visit.host.siteLetter),
                title: visit.title.isEmpty ? visit.host : visit.title, subtitle: visit.host,
                note: visit.visitedAt.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated)))
            .opensOnTap { onOpen(visit) }
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("historyRow")
    }
}
