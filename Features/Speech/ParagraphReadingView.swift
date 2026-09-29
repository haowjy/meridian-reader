import SwiftUI

/// Reading surface that highlights the spoken paragraph and supports tap-to-start.
struct ParagraphReadingView: View {
    var title: String? = nil
    let document: ParagraphDocument
    let activeParagraphIndex: Int?
    var jumpMode: Bool = false
    /// Scroll a paragraph into view. Only sent while the user scrubs (never by playback).
    var scrollRequest: ReaderScrollRequest? = nil
    /// Room left above / below the text for the reader's top row and bottom bars.
    var textInsets = ReaderTextInsets()
    let onTapParagraph: (Int) -> Void

    var body: some View {
        // User owns scroll: highlight the active paragraph but never chase it
        // during playback or jump-mode picking.
        ScrollViewReader { proxy in
            ScrollView {
                content
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentMargins(.top, textInsets.top, for: .scrollContent)
            .contentMargins(.bottom, textInsets.bottom, for: .scrollContent)
            .onChange(of: scrollRequest) { _, request in
                if let request { proxy.scrollTo(request.index, anchor: .center) }
            }
        }
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(.title2.bold())
                    .padding(.bottom, 2)
            }

            if document.isEmpty {
                Text("No readable paragraphs.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(document.paragraphs.indices, id: \.self) { index in
                    paragraphRow(index: index)
                }
            }
        }
    }

    @ViewBuilder
    private func paragraphRow(index: Int) -> some View {
        if jumpMode {
            Button {
                onTapParagraph(index)
            } label: {
                rowContent(index: index)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color.accentColor.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    )
            }
            .buttonStyle(.plain)
            .id(index)
            .accessibilityIdentifier("listenParagraph-\(index)")
            .accessibilityLabel("Paragraph \(index + 1)")
            .accessibilityHint("Plays from this paragraph")
        } else {
            rowContent(index: index)
                .id(index)
                .accessibilityIdentifier("listenParagraph-\(index)")
        }
    }

    /// The one reading style: plain text; the current paragraph gets a soft tint. No rail, no
    /// bake marks (readiness shows as the scrubber's buffered fill).
    private func rowContent(index: Int) -> some View {
        let isActive = index == activeParagraphIndex
        return Text(document.paragraphs[index])
            .font(.body)
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? Color.accentColor.opacity(0.08) : Color.clear)
            )
            .padding(.horizontal, -6)
    }
}
