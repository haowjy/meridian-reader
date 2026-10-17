import SwiftUI

/// A chapter's preview in Follow's Review: the app's own sheet (`Sheet`, as the Reader rises),
/// over the list, with the chapter's title and box, its address, the opening of its text and how
/// long it reads. A pull down closes it. *Include* / *Leave Out* sets its box and closes it;
/// *Open in Browser* leaves Follow for the chapter's page.
///
/// ```
///                    ───
/// Author's Note: Hiatus                        ☐
/// royalroad.com/…/chapter/309114/authors-note
/// Hi everyone. Just a short note to say that the next chapter will be a little late…
/// Preview   1 min
/// ( 🌐 Open in Browser )  ( ☑ Include )
/// ```
struct FollowPreviewSheet: View {
    let chapter: TableOfContents.Chapter
    let preview: FollowFlow.Preview
    let isKept: Bool
    let onToggle: () -> Void
    let onOpenInBrowser: () -> Void
    let onClose: () -> Void

    var body: some View {
        Sheet(onDismiss: onClose) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Text(chapter.title)
                    .typeStyle(.heading)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: isKept ? Icons.included : Icons.excluded)
                    .font(.title3)
                    .foregroundStyle(isKept ? Palette.accent : Palette.tertiaryInk)
                    .accessibilityLabel(isKept ? "Selected" : "Not selected")
            }
            .padding(.horizontal, Spacing.pageMargin)
            .padding(.bottom, Spacing.xs)
        } content: {
            FollowPreviewBody(chapter: chapter, preview: preview, isKept: isKept, onToggle: onToggle,
                              onOpenInBrowser: onOpenInBrowser)
        }
        .accessibilityIdentifier("followPreview")
    }
}

private struct FollowPreviewBody: View {
    let chapter: TableOfContents.Chapter
    let preview: FollowFlow.Preview
    let isKept: Bool
    let onToggle: () -> Void
    let onOpenInBrowser: () -> Void

    @Environment(\.dismissSheet) private var dismissSheet

    /// The opening shown: about a screen of text, never scrolled (a pull anywhere closes).
    private static let openingLength = 700

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(ShellState.addressText(for: chapter.url))
                .typeStyle(.caption)
                .foregroundStyle(Palette.accent)
                .lineLimit(1)
                .truncationMode(.middle)
            switch preview {
            case .loading:
                ProgressView()
                    .tint(Palette.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Loading the chapter")
            case .failed(let message):
                Label(message, systemImage: Icons.warning)
                    .typeStyle(.row)
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            case .loaded(let content):
                Text(opening(of: content))
                    .typeStyle(.body)
                    .foregroundStyle(Palette.ink)
                    .lineSpacing(Spacing.xxs)
                    // The room the buttons leave; the text ends with … where it runs out.
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .accessibilityIdentifier("followPreviewText")
                DetailLine([String(localized: "Preview"),
                            String(localized: "\(ListeningTime.minutes(words: WordCount.count(content.plainText), rate: 1)) min")])
                    .typeStyle(.caption)
            }
            ActionButtonRow { fit in
                PillButton(String(localized: "Open in Browser"), systemImage: Icons.browser, style: .neutral,
                           expands: true, fit: fit, action: onOpenInBrowser)
                    .accessibilityIdentifier("followPreviewBrowser")
                PillButton(isKept ? String(localized: "Leave Out") : String(localized: "Include"),
                           systemImage: isKept ? Icons.excluded : Icons.included, expands: true, fit: fit) {
                    onToggle()
                    dismissSheet()
                }
                .accessibilityIdentifier("followPreviewToggle")
            }
        }
        .padding(.horizontal, Spacing.pageMargin)
        .padding(.bottom, Spacing.l)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func opening(of content: PageContent) -> String {
        var text = ""
        for paragraph in content.document.paragraphs where !paragraph.isEmpty {
            if !text.isEmpty { text += "\n\n" }
            text += paragraph
            if text.count >= Self.openingLength { break }
        }
        return text.count > Self.openingLength ? String(text.prefix(Self.openingLength)) + "…" : text
    }
}
