import SwiftUI
import SwiftData

/// Library as a full-screen surface that reuses the browser's bottom chrome shell
/// (`BottomChrome` field capsule + five-slot toolbar), not a plain sheet.
///
/// ```
/// ┌ bar ────────────────────────────────────┐
/// │ ╭ Now Playing bar ────────────────────╮ │  ← what you hear (once something has played)
/// │ ( 🔍 Search saved…                   ) │  ← same field capsule as the address bar
/// │  [ ]   [ ]   [Search]  [🌐]  [⋯]       │  ← idle: slot 4 = Browser; ⋯ stays
/// └──────────────────────────── home indicator ┘
///
/// While searching (the same session as the browser's address field):
/// │ ( 🔍 Search saved…              )  (✕) │  ← toolbar hidden; ✕ exits search
/// ```
///
/// Opening an article shows it in the Reader sheet over the library. Leaving via 🌐 restores the
/// prior browse surface.
struct LibrarySurface: View {
    @Environment(ShellState.self) private var shell
    @Environment(\.speechController) private var speech
    @State private var search = SearchSession()

    var body: some View {
        VStack(spacing: 0) {
            SavedListView(searchText: search.text)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scrollDismissesKeyboard(.interactively)

            SearchSessionChrome(session: search, cancelID: "librarySearchCancel",
                                onCancel: { search.end(showing: "") }) {
                NowPlayingBarView(speech: speech, isCovered: shell.reader != nil)
                    .padding(.bottom, Spacing.xxs)
            } field: { focus in
                searchField(focus)
            } toolbar: {
                toolbar
            }
            .lowersKeyboardOnPullDown(search)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("libraryChrome")
        }
        .background(Palette.paper.ignoresSafeArea())
    }

    private func searchField(_ focus: FocusState<Bool>.Binding) -> some View {
        let clearable = search.isActive && !search.text.isEmpty
        return HStack(spacing: Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
                .frame(width: 16)
                .accessibilityHidden(true)

            TextField("Search saved", text: Bindable(search).text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused(focus)
                .typeStyle(.row)
                .foregroundStyle(Palette.ink)
                .accessibilityIdentifier("librarySearchField")

            if clearable {
                Button {
                    search.text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Palette.secondaryInk)
                        .fieldControlFrame()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .bottomChromeField(leading: Spacing.s, trailing: clearable ? Spacing.xxs : Spacing.s)
    }

    private var toolbar: some View {
        BottomToolbarLayout {
            Color.clear.frame(minHeight: BottomChrome.rowHeight)
            Color.clear.frame(minHeight: BottomChrome.rowHeight)
            Button { search.begin() } label: {
                Image(systemName: "magnifyingglass").toolbarIconFrame()
            }
            .accessibilityLabel("Search")
            .accessibilityIdentifier("librarySearch")

            Button(action: shell.leaveLibrary) {
                Image(systemName: "globe").toolbarIconFrame()
            }
            .accessibilityLabel("Browser")
            .accessibilityIdentifier("libraryBrowser")
            .accessibilityHint("Return to the browser")

            MoreMenuButton(id: "libraryMore") { .library(perform: perform) }
        }
        // Same as the browser toolbar: tint keeps disabled buttons dimmed.
        .tint(Palette.ink)
    }

    /// The library's own ⋯: nothing in it touches the browser's page.
    private func perform(_ action: LibraryMenuAction) {
        switch action {
        case .voiceSettings: shell.present(.voiceSettings)
        case .bookmarks: shell.present(.bookmarks)
        case .history: shell.present(.history)
        case .browser: shell.leaveLibrary()
        }
    }
}
