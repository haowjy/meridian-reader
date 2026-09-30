import SwiftUI
import SwiftData

/// Library as a full-screen surface that reuses the browser's bottom chrome shell
/// (`BottomChrome` field capsule + five-slot toolbar), not a plain sheet.
///
/// ```
/// ┌ bar ────────────────────────────────────┐
/// │ ( 🔍 Search saved…                   ) │  ← same field capsule as the address bar
/// │  [ ]   [ ]   [Search]  [🌐]  [⋯]       │  ← slot 4 = Browser (swap back); ⋯ stays
/// └──────────────────────────── home indicator ┘
/// ```
///
/// Opening an article pushes the ‹ reader inside the surface (path non-empty hides this chrome;
/// the reader draws its own). Leaving via 🌐 restores the prior browse surface.
struct LibrarySurface: View {
    @Binding var path: [UUID]
    @Binding var searchText: String
    var isMoreOpen: Bool
    var onMoreAnchor: (CGRect) -> Void
    var onOpenMore: () -> Void
    var onLeaveToBrowser: () -> Void
    /// Bumped by the parent to focus the library search field (toolbar Search).
    var focusSearchToken: Int = 0

    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            SavedListView(path: $path, searchText: $searchText, usesExternalSearch: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if path.isEmpty {
                libraryChrome
            }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .onChange(of: focusSearchToken) { _, _ in
            searchFocused = true
        }
    }

    /// Same band / field capsule / five-slot toolbar as Browse (`BottomChrome`).
    private var libraryChrome: some View {
        VStack(spacing: BottomChrome.rowSpacing) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                    .accessibilityHidden(true)

                TextField("Search saved", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($searchFocused)
                    .accessibilityIdentifier("librarySearchField")

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .fieldControlFrame()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .bottomChromeField(leading: 12, trailing: searchText.isEmpty ? 12 : 4)

            BottomToolbarLayout {
                Color.clear.frame(minHeight: BottomChrome.rowHeight)
                Color.clear.frame(minHeight: BottomChrome.rowHeight)
                Button {
                    searchFocused = true
                } label: {
                    Image(systemName: "magnifyingglass").toolbarIconFrame()
                }
                .accessibilityLabel("Search")
                .accessibilityIdentifier("librarySearch")

                Button(action: onLeaveToBrowser) {
                    Image(systemName: "globe").toolbarIconFrame()
                }
                .accessibilityLabel("Browser")
                .accessibilityIdentifier("libraryBrowser")
                .accessibilityHint("Return to the browser")

                Button(action: onOpenMore) {
                    Image(systemName: "ellipsis").toolbarIconFrame()
                }
                .accessibilityLabel("More")
                .accessibilityIdentifier("libraryMore")
                .morphMenuButtonHidden(isMoreOpen)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { onMoreAnchor($0) }
            }
            .foregroundStyle(.primary)
        }
        .bottomChromeBand()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("libraryChrome")
    }
}
