import SwiftUI

/// Recently visited pages (the bounded `RecentVisit` list). Tap to open.
struct BrowseHistoryView: View {
    let visits: [RecentVisit]
    var onOpen: (RecentVisit) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if visits.isEmpty {
                    ContentUnavailableView("No history yet", systemImage: Icons.history,
                                           description: Text("Pages you open show up here."))
                } else {
                    List(visits, id: \.id) { visit in
                        Button { onOpen(visit) } label: {
                            HStack(spacing: 12) {
                                FaviconImage(data: visit.faviconData, host: visit.host, size: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(visit.title)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(visit.host)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                Text(visit.visitedAt, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityIdentifier("browseHistory")
    }
}
