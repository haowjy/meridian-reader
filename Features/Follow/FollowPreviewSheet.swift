import SwiftUI

/// A chapter's preview in Follow's Review: the app's own sheet (`Sheet`, as the Reader rises) over
/// the list, holding the chapter's real page in Browse's web view (`WebView`, the browser's
/// website data, so signed in as there). It is a preview and nothing more: the page stays put
/// (`WebViewStore.staysOnPage`: links, forms and back / forward go nowhere), there is no Save, no
/// ⋯ and no bar at the bottom; the sheet covers what is under it and leaves it as it is.
///
/// The header says it is a passing look: the chapter's title and the box that keeps or leaves it
/// out, then its address as a label, not a field (`AddressLabel`), with 📄 at its end, which
/// swaps the page for its Reader text and back. The page's load runs along the header's foot.
///
/// The page and the Reader text scroll; a pull down closes the sheet when it begins on the header
/// or with the text at its top (`SheetPullHandoff`), as in the Reader.
///
/// ```
///                    ───
/// Author's Note: Hiatus                        ☐   ← the box: keep / leave out
/// ( royalroad.com/…/chapter/900002/authors-note  📄 )   ← the address, read only; 📄 the swap
/// ┌ the chapter's page (or its Reader text) ┐       ← scrolls, to the screen's foot
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
                    // No bar below: the page runs to the screen's foot, its scroll view
                    // insetting its end above the home indicator. (The Reader text keeps to the
                    // safe area: its view sets its own insets.)
                    .ignoresSafeArea(edges: .bottom)
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
        }
        .onAppear { page.load(chapter.url) }
        // A script took the page elsewhere: the Reader text, shown or on its way, was the page
        // before. The cancelled read clears `extracting` itself when it ends.
        .onChange(of: page.currentURL) {
            extracting?.cancel()
            reader = nil
        }
        .onDisappear { extracting?.cancel() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("followPreview")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
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
            AddressLabel(address: ShellState.addressText(for: page.currentURL ?? chapter.url),
                         swap: readerSwap, onSwap: toggleReader)
        }
        .padding(.horizontal, Spacing.pageMargin)
        .padding(.bottom, Spacing.xs)
        .overlay(alignment: .bottom) { LoadProgressLine(web: page) }
    }

    /// 📄: on a readable page, a spinner while the text is read, filled while the Reader text
    /// shows; dimmed until the page can be read.
    private var readerSwap: AddressLabel.ReaderSwap {
        if reader != nil { return .reader }
        if extracting != nil { return .extracting }
        return page.hasPage && page.isReaderable ? .page : .unavailable
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
                let source = SingleWebPageSource(url: url, htmlSnapshot: try await page.snapshotHTML(), extractor: extractor)
                let content = try await source.content(of: source.article)
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
