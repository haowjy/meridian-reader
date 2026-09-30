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
/// While searching (Browse-matched ✕ session):
/// │ ( 🔍 Search saved…              )  (✕) │  ← toolbar hidden; ✕ exits search
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

    /// Search session (like Browse `isEditingAddress`): survives swipe-down keyboard dismiss.
    @State private var isEditingSearch = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            SavedListView(path: $path, searchText: $searchText, usesExternalSearch: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scrollDismissesKeyboard(.interactively)

            if path.isEmpty {
                libraryChrome
            }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .onChange(of: focusSearchToken) { _, _ in
            beginSearch()
        }
    }

    /// Same band / field capsule / five-slot toolbar as Browse (`BottomChrome`).
    /// While searching, toolbar steps aside (Safari / Browse): field + round ✕ only.
    private var libraryChrome: some View {
        VStack(spacing: BottomChrome.rowSpacing) {
            HStack(spacing: 10) {
                searchField
                if isEditingSearch {
                    Button(action: cancelSearch) {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 40, height: 40)
                            .background(Color(.secondarySystemBackground), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel")
                    .accessibilityIdentifier("librarySearchCancel")
                }
            }

            // Like Browse/Safari: page buttons step aside while searching.
            if !isEditingSearch {
                toolbarRow
            }
        }
        .bottomChromeBand(bottomPadding: isEditingSearch ? 8 : 0)
        .simultaneousGesture(pullDownToLowerKeyboard)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("libraryChrome")
    }

    private var searchField: some View {
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
                .onChange(of: searchFocused) { _, focused in
                    if focused {
                        isEditingSearch = true
                    }
                    // Losing focus alone does not exit search (swipe-down / scroll). ✕ clears it.
                }

            if isEditingSearch && !searchText.isEmpty {
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
        .bottomChromeField(leading: 12, trailing: (isEditingSearch && !searchText.isEmpty) ? 4 : 12)
    }

    private var toolbarRow: some View {
        BottomToolbarLayout {
            Color.clear.frame(minHeight: BottomChrome.rowHeight)
            Color.clear.frame(minHeight: BottomChrome.rowHeight)
            Button {
                beginSearch()
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

    private func beginSearch() {
        isEditingSearch = true
        searchFocused = true
    }

    /// ✕: leave search mode and clear the filter (like Browse restores the page address).
    private func cancelSearch() {
        isEditingSearch = false
        searchFocused = false
        searchText = ""
    }

    /// Swipe down on chrome: dismiss keyboard / lower the field, but stay in search mode.
    private var pullDownToLowerKeyboard: some Gesture {
        DragGesture(minimumDistance: SwipeGesturePolicy.verticalMinimumDistance)
            .onEnded { value in
                guard isEditingSearch, searchFocused else { return }
                if SwipeGesturePolicy.shouldCommitVerticalDismiss(
                    translation: value.translation,
                    predicted: value.predictedEndTranslation
                ) {
                    searchFocused = false
                }
            }
    }
}
