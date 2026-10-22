import SwiftUI

/// ⋯ → *Follow…* (`ShellSheet.follow`, covering the screen): from a story's address to a folder
/// of its chapters.
///
/// ```
/// ( Cancel )        The Copper Orchard
/// Found 109 chapters   107 selected
/// ☑ Select All
/// ☑ 1. First Frost                                  ›
///   …/chapter/900001/1-first-frost
/// ☐ Author's Note: Hiatus                           ›   (left out: lighter)
///   …/chapter/900002/authors-note
/// A folder is made at once; the chapters' text is fetched one at a time.
/// (            OK   Follow 107 Chapters            )
/// ```
///
/// A folder's ⋯ asks for the address first; the browser's ⋯ reads its page's story at once.
/// While the table of contents is read: a spinner and the address. A chapter row's box keeps or
/// leaves out the chapter; the rest of the row opens its preview, the app's sheet rising over the
/// list with the chapter's page (`FollowPreviewSheet`), which a pull down closes. OK makes the
/// folder and opens it.
struct FollowSheet: View {
    let flow: FollowFlow

    @Environment(LibraryStore.self) private var library
    @Environment(ShellState.self) private var shell

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    SheetBarButton(Verbs.cancel, placement: .cancellationAction, identifier: "followCancel") {
                        shell.sheet = nil
                    }
                }
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
        .onDisappear { flow.cancel() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("followSheet")
    }

    private var title: String {
        if case .review(let contents) = flow.step { return contents.title }
        return String(localized: "Follow")
    }

    @ViewBuilder
    private var content: some View {
        switch flow.step {
        case .address:
            FollowAddressStep(flow: flow)
        case .reading(let url):
            FollowMessage(symbol: nil, title: String(localized: "Reading table of contents…"),
                          detail: ShellState.addressText(for: url),
                          note: String(localized: "One request, signed in as in the browser."))
                .accessibilityIdentifier("followReading")
        case .failed(let url, let message):
            FollowMessage(symbol: Icons.warning, title: message, detail: ShellState.addressText(for: url)) {
                ActionButtonRow { fit in
                    PillButton(String(localized: "Try Again"), systemImage: Icons.reload, expands: true, fit: fit) {
                        flow.read(url)
                    }
                    .accessibilityIdentifier("followTryAgain")
                    PillButton(String(localized: "Edit Address"), systemImage: Icons.rename, style: .neutral, fit: fit) {
                        flow.editAddress()
                    }
                }
            }
        case .alreadyFollowing(let id):
            FollowMessage(symbol: Icons.follow, title: String(localized: "You follow this story already"),
                          detail: library.folder(id: id)?.name ?? "") {
                PillButton(String(localized: "Open Its Folder"), systemImage: Icons.folder, expands: true) { open(id) }
                    .accessibilityIdentifier("followOpenExisting")
            }
        case .review(let contents):
            FollowReview(flow: flow, contents: contents) { follow(contents) }
        }
    }

    // MARK: - Doing

    /// OK: the folder, made at once in the place the flow began, then shown.
    private func follow(_ contents: TableOfContents) {
        let parent = flow.parentID.flatMap(library.folder(id:))
        guard let folder = shell.attempt(String(localized: "Couldn’t follow"), { try flow.follow(contents, in: parent) })
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

/// A folder's ⋯: the story's address, then *Read Contents*.
private struct FollowAddressStep: View {
    @Bindable var flow: FollowFlow
    @FocusState private var focused: Bool

    var body: some View {
        List {
            Section {
                TextField(String(localized: "royalroad.com/fiction/…"), text: $flow.address)
                    .typeStyle(.row)
                    .foregroundStyle(Palette.ink)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($focused)
                    .onSubmit(read)
                    .padding(.horizontal, Spacing.m)
                    .frame(minHeight: BottomChrome.minTapTarget)
                    .accessibilityIdentifier("followAddress")
            } header: {
                SectionHeader(title: String(localized: "Story Address"))
                    .listHeader()
            } footer: {
                Text("A page that lists the story’s chapters: a Royal Road story page, or another site’s table of contents.")
                    .listFooter()
            }
            .listRowInsets(EdgeInsets())
            .listCard()
        }
        .cardListStyle()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PillButton(String(localized: "Read Contents"), systemImage: Icons.follow, expands: true, action: read)
                .disabled(flow.typedURL == nil)
                .padding(.horizontal, Spacing.pageMargin)
                .padding(.vertical, Spacing.s)
                .accessibilityIdentifier("followRead")
        }
        .onAppear { focused = true }
    }

    private func read() {
        guard let url = flow.typedURL else { return }
        flow.read(url)
    }
}

/// Review: every chapter the table of contents lists, kept or left out, then OK.
private struct FollowReview: View {
    let flow: FollowFlow
    let contents: TableOfContents
    let onFollow: () -> Void

    var body: some View {
        let keptCount = flow.keptChapters(of: contents).count
        List {
            Section {
                selectAllRow
                ForEach(contents.chapters, id: \.canonicalURL) { chapter in
                    FollowChapterRow(chapter: chapter, isKept: flow.isKept(chapter),
                                     onToggle: { flow.toggle(chapter) }, onOpen: { flow.showPreview(of: chapter) })
                }
            } header: {
                // How many it found; how many are kept is on Follow's button.
                SectionHeader(title: Verbs.chapters, count: contents.chapters.count)
                    .listHeader()
                    .accessibilityIdentifier("followFound")
            }
            .listRowInsets(EdgeInsets())
            .listCard()
        }
        .cardListStyle()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("A folder is made at once. The chapters’ text is fetched one at a time while the app is open.")
                    .footnote()
                PillButton(Verbs.ok, detail: String(localized: "Follow \(keptCount) Chapters"),
                           systemImage: Icons.follow, expands: true, action: onFollow)
                    .disabled(keptCount == 0)
                    .accessibilityIdentifier("followOK")
            }
            .padding(.horizontal, Spacing.pageMargin)
            .padding(.vertical, Spacing.s)
            .background(Palette.paper)
            .overlay(alignment: .top) { Palette.hairline.frame(height: 1) }
        }
    }

    private var selectAllRow: some View {
        let kept = flow.keptChapters(of: contents).count
        let symbol = kept == contents.chapters.count ? Icons.included : kept == 0 ? Icons.excluded : Icons.partlyIncluded
        return Button { flow.toggleAll(in: contents) } label: {
            SymbolRow(String(localized: "Select All")) { FollowCheckbox(symbol: symbol) } trailing: { EmptyView() }
                .padding(.horizontal, Spacing.m)
        }
        .buttonStyle(.plain)
        .accessibilityValue(kept == contents.chapters.count ? "All" : kept == 0 ? "None" : "Some")
        .accessibilityIdentifier("followSelectAll")
    }
}

/// A chapter in Review: its box (keep or leave out), then its title and address, which open its
/// preview. Two controls in a `SymbolRow`'s shape: the box in its leading column, at its height.
private struct FollowChapterRow: View {
    let chapter: TableOfContents.Chapter
    let isKept: Bool
    let onToggle: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onToggle) {
                FollowCheckbox(symbol: isKept ? Icons.included : Icons.excluded)
                    .frame(width: Glyph.rowLeading)
                    .padding(.leading, Spacing.m)
                    .padding(.trailing, Spacing.s)
                    .frame(minHeight: RowHeight.compact)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(chapter.title)
            .accessibilityValue(isKept ? "Selected" : "Not selected")
            .accessibilityIdentifier("followChapterBox")
            Button(action: onOpen) {
                HStack(spacing: Spacing.s) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(chapter.title)
                            .typeStyle(.row)
                            .foregroundStyle(isKept ? Palette.ink : Palette.tertiaryInk)
                            .lineLimit(1)
                        Text(FollowText.shortAddress(chapter.url))
                            .typeStyle(.caption)
                            .foregroundStyle(Palette.accent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: Icons.disclosure)
                        .disclosureSymbol()
                        .foregroundStyle(Palette.tertiaryInk)
                }
                .padding(.trailing, Spacing.m)
                .padding(.vertical, Spacing.xxs)
                .frame(minHeight: RowHeight.compact)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(chapter.title)
            .accessibilityHint("Shows a preview")
            .accessibilityIdentifier("followChapter")
        }
    }
}

/// Review's box: kept, left out, or (Select All) some. The preview's header has it too.
struct FollowCheckbox: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .tileSymbol()
            .foregroundStyle(symbol == Icons.excluded ? Palette.tertiaryInk : Palette.accent)
            .accessibilityHidden(true)
    }
}

/// A step that is a message: a spinner (no symbol) or a symbol, a line, the address, and its
/// buttons.
private struct FollowMessage<Actions: View>: View {
    let symbol: String?
    let title: String
    let detail: String
    var note: String?
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: Spacing.s) {
            if let symbol {
                Image(systemName: symbol)
                    .tileSymbol()
                    .foregroundStyle(Palette.secondaryInk)
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(Palette.accent)
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
            if let note {
                Text(note)
                    .typeStyle(.caption)
                    .foregroundStyle(Palette.tertiaryInk)
                    .multilineTextAlignment(.center)
            }
            actions
                .padding(.top, Spacing.s)
        }
        .padding(Spacing.pageMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.paper)
    }
}

extension FollowMessage where Actions == EmptyView {
    init(symbol: String?, title: String, detail: String, note: String? = nil) {
        self.init(symbol: symbol, title: title, detail: detail, note: note) { EmptyView() }
    }
}
