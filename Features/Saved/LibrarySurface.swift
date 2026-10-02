import SwiftUI
import SwiftData

/// Library as a full-screen surface that reuses the browser's bottom chrome shell
/// (`BottomChrome` field capsule + five-slot toolbar), not a plain sheet.
///
/// ```
/// ┌ bar ────────────────────────────────────┐
/// │ ( 🔍 Search saved…                   ) │  ← same field capsule as the address bar
/// │  [ ]   [ ]   [Search]  [🌐]  [⋯]       │  ← idle: slot 4 = Browser; ⋯ stays
/// └──────────────────────────── home indicator ┘
///
/// While searching (the same session as the browser's address field):
/// │ ( 🔍 Search saved…              )  (✕) │  ← toolbar hidden; ✕ exits search
/// ```
///
/// Opening an article pushes the ‹ reader inside the surface (path non-empty hides this chrome;
/// the reader draws its own). Leaving via 🌐 restores the prior browse surface.
struct LibrarySurface: View {
    @Binding var path: [UUID]

    @Environment(ShellState.self) private var shell
    @State private var search = SearchSession()

    var body: some View {
        VStack(spacing: 0) {
            SavedListView(path: $path, searchText: search.text)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scrollDismissesKeyboard(.interactively)

            if path.isEmpty {
                SearchSessionChrome(session: search, cancelID: "librarySearchCancel",
                                    onCancel: { search.end(showing: "") }) { focus in
                    searchField(focus)
                } toolbar: {
                    toolbar
                }
                .lowersKeyboardOnPullDown(search)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("libraryChrome")
            }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
    }

    private func searchField(_ focus: FocusState<Bool>.Binding) -> some View {
        let clearable = search.isActive && !search.text.isEmpty
        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .accessibilityHidden(true)

            TextField("Search saved", text: Bindable(search).text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused(focus)
                .accessibilityIdentifier("librarySearchField")

            if clearable {
                Button {
                    search.text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .fieldControlFrame()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .bottomChromeField(leading: 12, trailing: clearable ? 4 : 12)
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
        .tint(.primary)
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
