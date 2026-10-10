import SwiftUI
import SwiftData

/// The library list: the saved pages in no folder (favorites show on the start page instead),
/// newest first, filtered by `searchText`. Hosted inside `LibrarySurface`, whose bottom field
/// capsule owns the search text. Opening an article shows it in the Reader sheet (Now Playing
/// when it is what you hear).
struct SavedListView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.speechController) private var speech
    @Environment(ShellState.self) private var shell
    @Query(LibraryQueries.loosePages(sort: .newest)) private var articles: [Page]

    let searchText: String

    private var filtered: [Page] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return articles }
        return articles.filter {
            $0.title.localizedCaseInsensitiveContains(q)
                || $0.byline.localizedCaseInsensitiveContains(q)
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
                        ForEach(filtered, id: \.listenKey) { article in
                            SavedRowView(article: article, speech: speech) {
                                shell.openSaved(article.listenKey, in: library)
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
        let saver = ArticleSaveCoordinator(library: library, speech: speech)
        for row in offsets.map({ filtered[$0] }) {
            saver.delete(row)
        }
    }
}

private struct SavedRowView: View {
    let article: Page
    @Bindable var speech: SpeechController
    let onOpen: () -> Void

    private var rowLabel: some View {
                HStack(alignment: .top, spacing: Spacing.s) {
                    FaviconImage(data: article.artworkData, host: article.byline)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(article.title)
                            .typeStyle(.row, weight: .semibold)
                            .foregroundStyle(Palette.ink)
                            .lineLimit(2)
                        Text("\(article.byline) · \((article.addedAt ?? .now).formatted(date: .abbreviated, time: .omitted))")
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

            let state = speech.playState(of: .page(article.listenKey))
            Button {
                speech.press(.page(article.listenKey)) {
                    speech.toggle(.page(article), resumeParagraph: article.positionParagraph,
                                  resumeUTF16Offset: article.positionUTF16)
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
            if speech.localTTS.hasListenAudio(for: article.listenKey) {
                Button("Clear listen audio", role: .destructive) {
                    try? speech.localTTS.clearListenAudio(for: article.listenKey)
                }
            }
        }
    }
}
