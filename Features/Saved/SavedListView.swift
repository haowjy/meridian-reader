import SwiftUI
import SwiftData

/// The library list: every kept article, filtered by `searchText`. Hosted inside `LibrarySurface`,
/// whose bottom field capsule owns the search text. Opening an article shows it in the Reader
/// sheet (Now Playing when it is what you hear).
struct SavedListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.speechController) private var speech
    @Environment(ShellState.self) private var shell
    @Query(sort: \SavedArticle.savedAt, order: .reverse) private var articles: [SavedArticle]

    let searchText: String

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
        NavigationStack {
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
                            SavedRowView(article: article, speech: speech) {
                                shell.openSaved(article.id, in: modelContext)
                            }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Saved")
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
        let saver = ArticleSaveCoordinator(context: modelContext, speech: speech)
        for row in offsets.map({ filtered[$0] }) {
            saver.delete(row)
        }
    }
}

private struct SavedRowView: View {
    let article: SavedArticle
    @Bindable var speech: SpeechController
    let onOpen: () -> Void

    private var rowLabel: some View {
                HStack(alignment: .top, spacing: Spacing.s) {
                    FaviconImage(data: article.faviconData, host: article.siteDomain)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(article.title)
                            .typeStyle(.row, weight: .semibold)
                            .foregroundStyle(Palette.ink)
                            .lineLimit(2)
                        Text("\(article.siteDomain) · \(article.savedAt.formatted(date: .abbreviated, time: .omitted))")
                            .typeStyle(.caption)
                            .foregroundStyle(Palette.secondaryInk)
                        if !article.excerpt.isEmpty {
                            Text(article.excerpt)
                                .typeStyle(.caption)
                                .foregroundStyle(Palette.secondaryInk)
                                .lineLimit(2)
                        }
                    }
                }
    }

    var body: some View {
        HStack(spacing: Spacing.s) {
            rowLabel
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpen)

            let state = speech.playState(of: .page(article.id))
            Button {
                speech.press(.page(article.id)) {
                    speech.toggle(.saved(article), resumeParagraph: article.playbackParagraphIndex,
                                  resumeUTF16Offset: article.playbackUTF16Offset)
                }
            } label: {
                Image(systemName: state == .playing ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(state == .playing ? "Pause" : "Play")
        }
        .padding(.vertical, Spacing.xxs)
        .contextMenu {
            if speech.localTTS.hasListenAudio(for: article.id) {
                Button("Clear listen audio", role: .destructive) {
                    try? speech.localTTS.clearListenAudio(for: article.id)
                }
            }
        }
    }
}
