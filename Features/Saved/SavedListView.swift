import SwiftUI
import SwiftData

/// The library: every kept article, with search. Presented as a sheet from the browser (⋯ → Saved,
/// or "Show All" on the start page); swipe down returns to the page. Opening an article pushes
/// the reader (‹) inside the sheet.
struct SavedListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.speechController) private var speech
    @Query(sort: \SavedArticle.savedAt, order: .reverse) private var articles: [SavedArticle]
    @State private var searchText = ""
    /// Pushed article ids (value-based navigation).
    @State private var path: [UUID] = []

    private var filtered: [SavedArticle] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return articles }
        return articles.filter {
            $0.title.localizedCaseInsensitiveContains(q)
                || $0.siteDomain.localizedCaseInsensitiveContains(q)
                || $0.excerpt.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if articles.isEmpty {
                    ContentUnavailableView(
                        "No saved articles",
                        systemImage: "books.vertical",
                        description: Text("Find something to listen to, then tap Save in ⋯ or the reader's bookmark.")
                    )
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List {
                        ForEach(filtered, id: \.id) { article in
                            SavedRowView(article: article, speech: speech)
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            // Value-based push: removing the row (Unsave inside the reader) must not pop the
            // open reader or stop its playback.
            .navigationDestination(for: UUID.self) { id in
                OfflineArticleView(articleID: id)
            }
            .navigationTitle("Saved")
            // Pinned under the title (in a sheet the default would float it at the bottom, where
            // it collides with the grabber-less edge and the keyboard).
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search saved")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SpeechSettingsView(speech: speech)
                    } label: {
                        Image(systemName: "person.wave.2")
                    }
                    .accessibilityLabel("Choose voice")
                }
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let article = filtered[index]
            speech.localTTS.handleArticleDeleted(article.id)
            modelContext.delete(article)
        }
    }
}

private struct SavedRowView: View {
    let article: SavedArticle
    @Bindable var speech: SpeechController

    private var rowLabel: some View {
                HStack(alignment: .top, spacing: 12) {
                    FaviconImage(data: article.faviconData, host: article.siteDomain)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(article.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Text("\(article.siteDomain) · \(article.savedAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !article.excerpt.isEmpty {
                            Text(article.excerpt)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
    }

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink(value: article.id) { rowLabel }

            Button {
                speech.toggle(.saved(article), resumeParagraph: article.playbackParagraphIndex)
            } label: {
                Image(systemName: speech.showsPauseIcon(for: article.id) ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(speech.showsPauseIcon(for: article.id) ? "Pause" : "Play")
        }
        .padding(.vertical, 4)
        .contextMenu {
            if speech.localTTS.hasListenAudio(for: article.id) {
                Button("Clear listen audio", role: .destructive) {
                    try? speech.localTTS.clearListenAudio(for: article.id)
                }
            }
        }
    }
}
