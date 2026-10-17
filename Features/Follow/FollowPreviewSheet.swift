import SwiftUI

/// A chapter's preview in Follow's Review: the app's own sheet (`Sheet`, as the Reader rises),
/// over the list, with the chapter's title and box, how long it reads, and its text, which
/// scrolls. A pull down on the header, or on the text when it is at its top, closes it. At the
/// bottom, the browser's field row (`BandFieldRow`) at the browser's place: 🌐, the field's 📄 (the
/// Reader swap, here from the text to the page) and the chapter's address all leave Follow for the
/// chapter's page in the browser; under it *Include* / *Leave Out* sets the box and closes the
/// preview.
///
/// ```
///                    ───
/// Author's Note: Hiatus                        ☐
/// Preview   1 min
/// Hi everyone. Just a short note to say that the next chapter will be a little late…  ← scrolls
/// [🌐] ( 📄 royalroad.com/…/chapter/309114/authors-note )   ← where the browser's [📚] ( 📄 … ) is
///              ( ☑ Include )
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
            VStack(alignment: .leading, spacing: Spacing.xxs) {
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
                if case .loaded(let content) = preview {
                    DetailLine([String(localized: "Preview"),
                                String(localized: "\(ListeningTime.minutes(words: WordCount.count(content.plainText), rate: 1)) min")])
                        .typeStyle(.caption)
                }
            }
            .padding(.horizontal, Spacing.pageMargin)
            .padding(.bottom, Spacing.xs)
        } content: {
            FollowPreviewBody(preview: preview)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    FollowPreviewBand(url: chapter.url, isKept: isKept, onToggle: onToggle,
                                      onOpenInBrowser: onOpenInBrowser)
                }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("followPreview")
    }
}

/// The chapter's text, scrolling; a pull down from its top goes to the sheet.
private struct FollowPreviewBody: View {
    let preview: FollowFlow.Preview

    var body: some View {
        ScrollView {
            Group {
                switch preview {
                case .loading:
                    ProgressView()
                        .tint(Palette.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Spacing.xl)
                        .accessibilityLabel("Loading the chapter")
                case .failed(let message):
                    Label(message, systemImage: Icons.warning)
                        .typeStyle(.row)
                        .foregroundStyle(Palette.secondaryInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .loaded(let content):
                    LazyVStack(alignment: .leading, spacing: Spacing.m) {
                        ForEach(Array(content.document.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                            if !paragraph.isEmpty {
                                Text(paragraph)
                                    .typeStyle(.body)
                                    .foregroundStyle(Palette.ink)
                                    .lineSpacing(Spacing.xxs)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("followPreviewText")
                }
            }
            .padding(.horizontal, Spacing.pageMargin)
            .padding(.vertical, Spacing.xs)
            .handsPullToSheet()
        }
    }
}

/// The browser's field row at the browser's place: the swap is 🌐 (to the chapter's page in the
/// browser), the field the chapter's address with 📄, which go there too. Under it, in the toolbar's
/// row, *Include* / *Leave Out*, which also closes the preview.
private struct FollowPreviewBand: View {
    let url: URL
    let isKept: Bool
    let onToggle: () -> Void
    let onOpenInBrowser: () -> Void

    @Environment(\.dismissSheet) private var dismissSheet

    var body: some View {
        VStack(spacing: BottomChrome.rowSpacing) {
            BandFieldRow(swap: BandSwap(systemImage: Icons.browser, label: String(localized: "Browser"),
                                        hint: String(localized: "Opens the chapter in the browser"),
                                        identifier: "followPreviewBrowser", action: onOpenInBrowser)) {
                Button(action: onOpenInBrowser) {
                    AddressField(reader: .available, onOpenReader: onOpenInBrowser,
                                 readerLabel: String(localized: "Open in Browser")) {
                        Text(ShellState.addressText(for: url))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ShellState.addressText(for: url))
                .accessibilityHint("Opens the chapter in the browser")
                .accessibilityIdentifier("followPreviewAddress")
            }
            BottomToolbarSpanLayout {
                Color.clear
                PillButton(isKept ? String(localized: "Leave Out") : String(localized: "Include"),
                           systemImage: isKept ? Icons.excluded : Icons.included, size: .compact, expands: true) {
                    onToggle()
                    dismissSheet()
                }
                .accessibilityIdentifier("followPreviewToggle")
                Color.clear
            }
        }
        .bottomChromeBand()
    }
}
