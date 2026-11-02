import SwiftUI

/// One sheet from entering an address through reviewing its chapters. A known page’s
/// Follow action starts reading immediately and uses the same review and save actions.
struct FollowSheet: View {
    @Bindable var flow: FollowFlow
    @State private var detent: PresentationDetent = .medium
    @FocusState private var addressFocused: Bool
    @Environment(LibraryStore.self) private var library
    @Environment(ShellState.self) private var shell

    var body: some View {
        // ✕ stays usable while a save runs: closing the sheet cancels it (`FollowFlow.cancel`), so
        // a browser page whose extraction hangs never holds the sheet up.
        InputSheet(title: title, onCancel: { shell.sheet = nil }) {
            content
        } actions: {
            if let error = flow.saveError {
                Text(error).footnote().foregroundStyle(Palette.destructive)
            }
            actions.disabled(flow.isSaving)
        }
        // While a chapter preview is up the card holds at large and can't be pulled away. The preview
        // is the app's own sheet (`Sheet`) drawn inside this card, closed by its own pull; with a
        // second detent the card's drag would take that pull and shrink the card to medium under
        // the preview instead of closing it.
        .presentationDetents(flow.previewed == nil ? [.medium, .large] : [.large], selection: $detent)
        .interactiveDismissDisabled(flow.previewed != nil)
        .onChange(of: flow.previewed != nil) { _, previewing in
            if previewing { detent = .large }
        }
        .overlay {
            if let chapter = flow.previewed {
                FollowPreviewSheet(chapter: chapter, isKept: flow.isKept(chapter),
                                   onToggle: { flow.toggle(chapter) },
                                   onClose: { flow.closePreview() })
                    .id(chapter.canonicalURL)
            }
        }
        .sheetToastLayer()
        .onChange(of: isReview, initial: true) { _, review in
            if review { addressFocused = false; detent = .large }
        }
        .onChange(of: isSaved, initial: true) { _, saved in
            guard saved else { return }
            shell.sheet = nil
            if flow.wasInLibrary {
                shell.showToast(ShellToast(message: String(localized: "Already in your Library"), systemImage: Icons.library))
            }
        }
        .onDisappear { flow.cancel() }
        .accessibilityIdentifier("followSheet")
    }

    private var isReview: Bool { if case .review = flow.step { true } else { false } }
    private var isSaved: Bool { if case .saved = flow.step { true } else { false } }
    private var title: String {
        if case .review(let contents) = flow.step { return contents.title }
        return flow.isAddingLink ? Verbs.title(Verbs.addLink) : String(localized: "Follow")
    }

    @ViewBuilder private var content: some View {
        switch flow.step {
        case .address:
            VStack(alignment: .leading, spacing: Spacing.s) {
                TextField(String(localized: "example.com/article"), text: $flow.address)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($addressFocused)
                    .onSubmit(read)
                    .inputSheetField()
                    .accessibilityIdentifier("addLinkField")
                Text("An article, or a blog or story to follow.").footnote()
            }
            .padding(Spacing.pageMargin)
            .onAppear { addressFocused = true }
        case .reading(let url):
            FollowMessage(symbol: nil, title: String(localized: "Reading the page…"),
                          detail: ShellState.addressText(for: url))
                .accessibilityIdentifier("followReading")
        case .failed(let url, let message):
            FollowMessage(symbol: Icons.warning, title: message, detail: ShellState.addressText(for: url))
        case .alreadyFollowing(let id):
            FollowMessage(symbol: Icons.follow, title: String(localized: "You already follow this story"),
                          detail: library.folder(id: id)?.name ?? "")
        case .review(let contents):
            FollowReview(flow: flow, contents: contents)
        case .saved:
            EmptyView()
        }
    }

    @ViewBuilder private var actions: some View {
        switch flow.step {
        case .address:
            PillButton(String(localized: "Add"), style: flow.typedURL == nil ? .neutral : .filled,
                       expands: true, action: read)
                .disabled(flow.typedURL == nil)
                .accessibilityIdentifier("addLinkAdd")
        case .review(let contents):
            let count = flow.keptChapters(of: contents).count
            PillButton(contents.kind == .posts ? String(localized: "Follow \(count) Posts") : String(localized: "Follow \(count) Chapters"),
                       style: count == 0 ? .neutral : .filled, expands: true) { follow(contents) }
                .disabled(count == 0 || flow.isSaving)
                .accessibilityIdentifier("followOK")
            savePageButton
        case .alreadyFollowing(let id):
            PillButton(String(localized: "Open Folder"), expands: true) { open(id) }
            savePageButton
        case .failed(let url, _):
            if !flow.isAddingLink {
                PillButton(String(localized: "Try Again"), expands: true) { flow.read(url) }
            }
            savePageButton
        case .reading, .saved:
            EmptyView()
        }
    }

    private var savePageButton: some View {
        Button(String(localized: "Save This Page Only"), action: flow.savePage)
        .typeStyle(.row)
        .frame(minHeight: Control.tap)
        .disabled(flow.isSaving)
        .accessibilityIdentifier("followSavePage")
    }

    private func read() {
        guard let url = flow.typedURL else { return }
        addressFocused = false
        flow.read(url)
    }

    private func follow(_ contents: TableOfContents) {
        guard let folder = shell.attempt(String(localized: "Couldn’t follow"), { try flow.follow(contents) })
        else { return }
        shell.sheet = nil
        shell.showLibrary(at: library.path(to: folder))
        shell.showToast(ShellToast(message: String(localized: "Following \(folder.name)"), systemImage: Icons.follow))
    }

    private func open(_ id: UUID) {
        guard let folder = library.folder(id: id) else { return }
        shell.sheet = nil
        shell.showLibrary(at: library.path(to: folder))
    }
}

/// The chapter selection shared by Add a Link and a page’s Follow action.
private struct FollowReview: View {
    let flow: FollowFlow
    let contents: TableOfContents

    var body: some View {
        List {
            Section {
                selectAllRow
                ForEach(contents.chapters, id: \.canonicalURL) { chapter in
                    FollowChapterRow(chapter: chapter, isKept: flow.isKept(chapter),
                                     onToggle: { flow.toggle(chapter) }, onOpen: { flow.showPreview(of: chapter) })
                }
            } header: {
                // How many it found; how many are kept is on Follow's button.
                SectionHeader(title: contents.kind == .posts ? Verbs.posts : Verbs.chapters, count: contents.chapters.count)
                    .listHeader()
                    .accessibilityIdentifier("followFound")
            }
            .listRowInsets(EdgeInsets())
            .listCard()
        }
        .cardListStyle()
    }

    private var selectAllRow: some View {
        let kept = flow.keptChapters(of: contents).count
        let symbol = kept == contents.chapters.count ? Icons.included : kept == 0 ? Icons.excluded : Icons.partlyIncluded
        return Button { flow.toggleAll(in: contents) } label: {
            SymbolRow(String(localized: "Select All")) { FollowCheckbox(symbol: symbol) } trailing: { EmptyView() }
                .padding(.horizontal, RowMetrics.edgeInset)
        }
        .buttonStyle(.plain)
        .accessibilityValue(kept == contents.chapters.count ? "All" : kept == 0 ? "None" : "Some")
        .accessibilityIdentifier("followSelectAll")
    }
}

/// A chapter in Review: its box (keep or leave out), then its title and address, which open its
/// preview. Two controls in one row's geometry (`RowColumns`, a two-line `rowHeight`, as Select All's
/// `SymbolRow` and every two-line row): the box in the leading column, the rest after it.
private struct FollowChapterRow: View {
    let chapter: TableOfContents.Chapter
    let isKept: Bool
    let onToggle: () -> Void
    let onOpen: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        RowColumns(leading: checkbox, leadingIsControl: true) {
            Button(action: onOpen) {
                HStack(spacing: RowMetrics.columnGap) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(chapter.title)
                            .typeStyle(.row)
                            .foregroundStyle(isKept ? Palette.ink : Palette.tertiaryInk)
                            .lineLimit(RowMetrics.titleLines(dynamicTypeSize))
                        // The address keeps both ends: the story's place and the chapter's.
                        DetailLine(parts: [DetailPart(FollowText.shortAddress(chapter.url), isLit: true)], wraps: false)
                            .typeStyle(.caption)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: Icons.disclosure)
                        .disclosureSymbol()
                        .foregroundStyle(Palette.tertiaryInk)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(chapter.title)
            .accessibilityHint("Shows a preview")
            .accessibilityIdentifier("followChapter")
        }
        .padding(.horizontal, RowMetrics.edgeInset)
        .rowHeight(lines: 2)
    }

    /// The box, tapped across the column and the row's height.
    private var checkbox: some View {
        Button(action: onToggle) {
            FollowCheckbox(symbol: isKept ? Icons.included : Icons.excluded)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(chapter.title)
        .accessibilityValue(isKept ? "Selected" : "Not selected")
        .accessibilityIdentifier("followChapterBox")
    }
}

/// Review's box: kept, left out, or (Select All) some. The preview's header has it too.
struct FollowCheckbox: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .glyphSize(Glyph.regular)
            .foregroundStyle(symbol == Icons.excluded ? Palette.tertiaryInk : Palette.accent)
            .accessibilityHidden(true)
    }
}

/// A step that is a message: `DownloadMark`'s spinning arc (no symbol) or a symbol, a line, the address, and its
/// buttons.
private struct FollowMessage: View {
    let symbol: String?
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: Spacing.s) {
            if let symbol {
                Image(systemName: symbol)
                    .glyphSize(Glyph.regular)
                    .foregroundStyle(Palette.secondaryInk)
            } else {
                // Reading the story's contents: one request, no fraction.
                DownloadMark(state: .waiting, size: Control.small)
            }
            Text(title)
                .typeStyle(.row, weight: .semibold)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
            Text(detail)
                .typeStyle(.caption)
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .padding(Spacing.pageMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.paper)
    }
}
