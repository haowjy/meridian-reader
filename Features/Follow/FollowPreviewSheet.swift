import SwiftUI

/// A chapter's preview in Follow's Review: the app's own sheet (`Sheet`, as the Reader rises) over
/// the list, holding the chapter's real page in Browse's web view (`WebView`, the browser's
/// website data, so signed in as there). It is a preview and nothing more: the page stays put
/// (`WebViewStore.staysOnPage`: links, forms and back / forward go nowhere), there is no Save
/// and no ⋯. At the bottom, the browser's field at the browser's place (`BandFieldRow`, the
/// swap's room left empty): the chapter's address, and 📄, which swaps the page for its Reader
/// text and back, as on the browser. The header's box keeps or leaves out the chapter.
///
/// The page and the Reader text scroll; a pull down closes the sheet when it begins on the header
/// or with the text at its top (`SheetPullHandoff`), as in the Reader.
///
/// ```
///                    ───
/// Author's Note: Hiatus                        ☐   ← the box: keep / leave out
/// ┌ the chapter's page (or its Reader text) ┐       ← scrolls
/// [   ] ( 📄 royalroad.com/…/chapter/309114/authors-note )   ← where the browser's field is
/// ```
///
/// A page that doesn't load stays blank, as in the browser.
struct FollowPreviewSheet: View {
    let chapter: TableOfContents.Chapter
    let isKept: Bool
    let onToggle: () -> Void
    let onClose: () -> Void

    @Environment(\.articleExtractor) private var extractor
    @Environment(ShellState.self) private var shell
    /// The preview's own web view, which stays on the chapter.
    @State private var page = WebViewStore(staysOnPage: true)
    /// The Reader text, in the page's place.
    @State private var reader: ReaderArticle?
    @State private var extracting: Task<Void, Never>?

    var body: some View {
        Sheet(onDismiss: onClose) {
            header
        } content: {
            ZStack {
                WebView(store: page)
                    .handsPullToSheet(from: page.webView?.scrollView)
                    .opacity(reader == nil ? 1 : 0)
                if let reader {
                    HTMLReadingView(html: reader.readingHTML,
                                    heading: ReaderHeading(title: reader.title, detail: Self.detail(of: reader)),
                                    activeParagraphIndex: nil) { _ in }
                        .accessibilityIdentifier("followPreviewReader")
                        .transition(.opacity)
                }
            }
            .animation(Motion.snappy, value: reader?.id)
            .safeAreaInset(edge: .bottom, spacing: 0) { band }
        }
        .onAppear { page.load(chapter.url) }
        // A script took the page elsewhere: the Reader text was the page before.
        .onChange(of: page.currentURL) { reader = nil }
        .onDisappear { extracting?.cancel() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("followPreview")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            Text(chapter.title)
                .typeStyle(.heading)
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onToggle) {
                FollowCheckbox(symbol: isKept ? Icons.included : Icons.excluded)
                    .tapTarget(BottomChrome.minTapTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Include")
            .accessibilityValue(isKept ? "Selected" : "Not selected")
            .accessibilityHint("Keeps or leaves out the chapter")
            .accessibilityIdentifier("followPreviewToggle")
        }
        .padding(.horizontal, Spacing.pageMargin)
        .padding(.bottom, Spacing.xs)
    }

    // MARK: - The band

    /// The browser's field row at the browser's place, its swap's room empty, and the toolbar's
    /// row under it empty too, so the field sits exactly where the browser's does.
    private var band: some View {
        VStack(spacing: BottomChrome.rowSpacing) {
            BandFieldRow(keepsSwapRoom: true) {
                AddressField(reader: readerButton, onOpenReader: toggleReader) {
                    ChapterAddress(url: page.currentURL ?? chapter.url)
                }
            }
            Color.clear.frame(height: BottomChrome.rowHeight)
        }
        .bottomChromeBand()
        .overlay(alignment: .top) { LoadProgressLine(web: page) }
    }

    /// 📄 as on the browser: on a readable page, a spinner while the text is read, filled while the
    /// Reader text shows.
    private var readerButton: AddressField<ChapterAddress, EmptyView>.ReaderButton {
        if reader != nil { return .showing }
        if extracting != nil { return .extracting }
        return page.hasPage && page.isReaderable ? .available : .hidden
    }

    // MARK: - The Reader swap

    /// 📄: the page's Reader text in its place, read from the page as it is (as the browser's
    /// Reader is: no second request), or back to the page.
    private func toggleReader() {
        guard reader == nil else { return reader = nil }
        guard extracting == nil, let url = page.currentURL else { return }
        extracting = Task {
            defer { extracting = nil }
            do {
                let source = SingleWebPageSource(url: url, pageTitle: page.pageTitle,
                                                 htmlSnapshot: try await page.snapshotHTML(), extractor: extractor)
                let content = try await source.content(of: source.page)
                guard !Task.isCancelled else { return }
                reader = ReaderArticle(id: UUID(), url: url, extracted: content.extracted, document: content.document)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                shell.showToast(ShellToast(message: String(localized: "Couldn’t show the Reader text"),
                                           systemImage: Icons.warning))
            }
        }
    }

    /// The source and the length, as the Reader's heading has them.
    private static func detail(of article: ReaderArticle) -> [String] {
        let minutes = ListeningTime.minutes(utf16Length: article.document.utf16Length, rate: 1)
        return [article.sourceLabel, minutes > 0 ? ListeningTime.label(minutes: minutes) : ""].filter { !$0.isEmpty }
    }
}

/// The chapter's address in the field, as the browser's idle field shows its page's.
private struct ChapterAddress: View {
    let url: URL

    var body: some View {
        Text(ShellState.addressText(for: url))
            .lineLimit(1)
            .truncationMode(.middle)
    }
}
