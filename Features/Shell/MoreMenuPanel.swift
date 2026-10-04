import SwiftUI

/// The ⋯ menu panel's content (shown by `MorphMenuOverlay`): action rows, a divider, then a row
/// of big buttons whose rightmost one is the panel's focus point (`morphMenuFocus`). Every row
/// closes the panel and runs its action once the panel has started collapsing.
struct MoreMenuPanel: View {
    let context: MenuContext
    let close: MorphMenuClose

    var body: some View {
        VStack(spacing: 0) {
            switch context {
            case .browse(let menu, let perform): browse(menu) { action in close { perform(action) } }
            case .reader(let menu, let perform): reader(menu) { action in close { perform(action) } }
            case .library(let perform): library { action in close { perform(action) } }
            }
        }
        .padding(.vertical, Spacing.xs)
        .frame(width: 300)
    }

    // MARK: - Contexts

    @ViewBuilder
    private func browse(_ menu: BrowseMenu, run: @escaping (BrowseMenu.Action) -> Void) -> some View {
        row("New search", "magnifyingglass", id: "moreNewSearch") { run(.newSearch) }
        saveRow(isSaved: menu.isSaved) { run(.toggleSave) }
            .disabled(!menu.canSave)
        bookmarkRow(isBookmarked: menu.isBookmarked) { run(.toggleBookmark) }
            .disabled(!menu.canBookmark)
        shareRow { run(.share) }
            .disabled(!menu.canShare)
        row("Reload", "arrow.clockwise", id: "moreReload") { run(.reload) }
            .disabled(!menu.hasPage)
        voiceRow { run(.voiceSettings) }
        if let fakeFailure = menu.fakeExtractionFailure {
            Menu {
                Toggle("Fake extraction failure", isOn: fakeFailure)
            } label: {
                rowLabel("Debug", "ladybug", trailing: "chevron.right")
            }
            .accessibilityIdentifier("moreDebug")
        }
        divider
        tiles {
            tile("Bookmarks", "star", id: "moreBookmarks") { run(.bookmarks) }
            tile("Saved", "books.vertical", id: "moreLibrary") { run(.saved) }
            tile("History", "clock", id: "moreHistory") { run(.history) }
            tile("Reader", "doc.plaintext", id: "moreReaderToggle", focus: true) { run(.openReader) }
                .disabled(!menu.canOpenReader)
                .accessibilityLabel("Reader")
                .accessibilityHint("Open in Reader")
        }
    }

    @ViewBuilder
    private func reader(_ menu: ReaderMenu, run: @escaping (ReaderMenu.Action) -> Void) -> some View {
        voiceRow { run(.voiceSettings) }
        saveRow(isSaved: menu.isSaved) { run(.toggleSave) }
            .disabled(!menu.canSave)
        bookmarkRow(isBookmarked: menu.isBookmarked) { run(.toggleBookmark) }
            .disabled(!menu.canBookmark)
        shareRow { run(.share) }
            .disabled(!menu.canShare)
        if menu.showsDebug {
            row("Debug", "ladybug", id: "moreDebug") { run(.listenDebug) }
        }
        divider
        tiles {
            tile("Bookmarks", "star", id: "moreBookmarks") { run(.bookmarks) }
            tile("Saved", "books.vertical", id: "moreLibrary") { run(.saved) }
            tile("History", "clock", id: "moreHistory") { run(.history) }
            // Reader off = the article's own web page, wherever the reader was opened from.
            // Playback keeps going.
            tile("Website", "globe", id: "moreWebsite", focus: true) { run(.openWebsite) }
                .disabled(!menu.canOpenWebsite)
                .accessibilityLabel("View Website")
                .accessibilityHint("Opens the article's web page")
        }
    }

    @ViewBuilder
    private func library(run: @escaping (LibraryMenuAction) -> Void) -> some View {
        voiceRow { run(.voiceSettings) }
        divider
        tiles {
            tile("Bookmarks", "star", id: "moreBookmarks") { run(.bookmarks) }
            tile("History", "clock", id: "moreHistory") { run(.history) }
            tile("Browser", "globe", id: "moreBrowser", focus: true) { run(.browser) }
                .accessibilityLabel("Browser")
                .accessibilityHint("Return to the browser")
        }
    }

    // MARK: - Shared rows

    private func saveRow(isSaved: Bool, action: @escaping () -> Void) -> some View {
        // Saved article = the bookmark glyph (same as the reader's save button); site bookmarks
        // use the star.
        row(isSaved ? "Remove from Saved" : "Save article", isSaved ? "bookmark.slash" : "bookmark",
            id: "moreSave", action: action)
    }

    private func bookmarkRow(isBookmarked: Bool, action: @escaping () -> Void) -> some View {
        row(isBookmarked ? "Remove Bookmark" : "Bookmark", isBookmarked ? "star.slash" : "star",
            id: "moreBookmark", action: action)
    }

    private func shareRow(action: @escaping () -> Void) -> some View {
        row("Share", "square.and.arrow.up", id: "moreShare", action: action)
    }

    private func voiceRow(action: @escaping () -> Void) -> some View {
        row("Voice settings", "person.wave.2", id: "moreVoice", action: action)
    }

    private var divider: some View {
        Divider()
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.xs)
    }

    // MARK: - Building blocks

    private func row(_ title: String, _ icon: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { rowLabel(title, icon) }
            .buttonStyle(MenuRowStyle())
            .accessibilityIdentifier(id)
    }

    private func rowLabel(_ title: String, _ icon: String, trailing: String? = nil) -> some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: icon)
                .font(.body)
                .frame(width: 24)
            Text(title)
                .typeStyle(.row)
            Spacer(minLength: 0)
            if let trailing {
                Image(systemName: trailing)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.s)
        .contentShape(Rectangle())
    }

    private func tiles<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 0) { content() }
            .padding(.horizontal, Spacing.xs)
    }

    /// A big button. `focus`: its icon is the panel's focus point (placed by `MorphMenuOverlay`
    /// slightly up and left of the ⋯ glyph).
    private func tile(_ title: String, _ icon: String, id: String, focus: Bool = false,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(.title3)
                    .morphMenuFocus(focus)
                Text(title)
                    .typeStyle(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowStyle(cornerRadius: Radius.card))
        .accessibilityIdentifier(id)
    }
}

/// Pressed-state highlight for menu panel rows (like a system menu).
private struct MenuRowStyle: ButtonStyle {
    var cornerRadius: CGFloat = 0
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? 1 : 0.35)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Palette.ink.opacity(configuration.isPressed ? 0.08 : 0))
            )
    }
}

/// The ⋯ toolbar button (browser, library, reader listen bar): opens `menu()` in the shell's
/// morph panel, grown from this button's frame. Its glyph fades while a menu is open, so the
/// button reads as turning into the panel.
struct MoreMenuButton: View {
    let id: String
    /// Shows a spinner instead of the glyph (⋯ → Save extracting).
    var isBusy = false
    let menu: () -> MenuContext

    @Environment(ShellState.self) private var shell
    @State private var frame: CGRect = .zero

    var body: some View {
        Button { shell.openMenu(menu(), from: frame) } label: {
            Group {
                if isBusy {
                    ProgressView()
                } else {
                    Image(systemName: "ellipsis")
                }
            }
            .toolbarIconFrame()
        }
        .accessibilityLabel("More")
        .accessibilityIdentifier(id)
        .morphMenuButtonHidden(shell.menu != nil)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
    }
}
