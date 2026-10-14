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
            case .nowPlaying(let menu, let perform): nowPlaying(menu) { action in close { perform(action) } }
            case .library(let menu, let perform): library(menu) { action in close { perform(action) } }
            }
        }
        .padding(.vertical, Spacing.xs)
        .frame(width: 300)
    }

    // MARK: - Contexts

    @ViewBuilder
    private func browse(_ menu: BrowseMenu, run: @escaping (BrowseMenu.Action) -> Void) -> some View {
        row("New Search", "magnifyingglass", id: "moreNewSearch") { run(.newSearch) }
        if menu.isSaved {
            row("Remove from Library", "bookmark.slash", id: "moreSave") { run(.removeFromLibrary) }
                .disabled(!menu.canSave)
        } else {
            row("Save to Library…", "bookmark", id: "moreSave") { run(.saveToLibrary) }
                .disabled(!menu.canSave)
        }
        favoriteRow(isFavorite: menu.isFavorite) { run(.toggleFavorite) }
            .disabled(!menu.canFavorite)
        shareRow { run(.share) }
            .disabled(!menu.canShare)
        row("Reload", "arrow.clockwise", id: "moreReload") { run(.reload) }
            .disabled(!menu.hasPage)
        voiceRow { run(.voiceSettings) }
        downloadsRow { run(.downloads) }
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
            favoritesTile { run(.favorites) }
            tile("History", "clock", id: "moreHistory") { run(.history) }
            tile("Reader", "doc.plaintext", id: "moreReaderToggle", focus: true) { run(.openReader) }
                .disabled(!menu.canOpenReader)
                .accessibilityLabel("Reader")
                .accessibilityHint("Open in Reader")
        }
    }

    @ViewBuilder
    private func reader(_ menu: ReaderMenu, run: @escaping (ReaderMenu.Action) -> Void) -> some View {
        row(menu.isSaved ? "Remove from Library" : "Save to Library", menu.isSaved ? "bookmark.slash" : "bookmark",
            id: "moreSave") { run(.toggleSave) }
            .disabled(!menu.canSave)
        if menu.isSaved {
            row("Move to…", "folder", id: "moreMove") { run(.moveTo) }
        }
        favoriteRow(isFavorite: menu.isFavorite) { run(.toggleFavorite) }
            .disabled(!menu.canFavorite)
        shareRow { run(.share) }
            .disabled(!menu.canShare)
        if menu.canDownload {
            downloadRow("Download") { run(.download) }
        }
        voiceRow { run(.voiceSettings) }
        downloadsRow { run(.downloads) }
        if menu.showsDebug {
            row("Debug", "ladybug", id: "moreDebug") { run(.listenDebug) }
        }
        divider
        tiles {
            favoritesTile { run(.favorites) }
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
    private func nowPlaying(_ menu: NowPlayingMenu, run: @escaping (NowPlayingMenu.Action) -> Void) -> some View {
        voiceRow { run(.voiceSettings) }
        shareRow { run(.share) }
            .disabled(!menu.canShare)
        downloadsRow { run(.downloads) }
        if menu.showsDebug {
            row("Debug", "ladybug", id: "moreDebug") { run(.listenDebug) }
        }
        divider
        tiles {
            favoritesTile { run(.favorites) }
            tile("History", "clock", id: "moreHistory") { run(.history) }
            // The playing page in the browser; playback keeps going.
            tile("Website", "globe", id: "moreWebsite", focus: true) { run(.openWebsite) }
                .disabled(!menu.canOpenWebsite)
                .accessibilityLabel("View Website")
                .accessibilityHint("Opens the playing page in the browser")
        }
    }

    @ViewBuilder
    private func library(_ menu: LibraryMenu, run: @escaping (LibraryMenu.Action) -> Void) -> some View {
        switch menu.screen {
        case .home:
            voiceRow { run(.voiceSettings) }
            if menu.canImportBook { importBookRow { run(.importBook) } }
            row("New Folder", "folder.badge.plus", id: "moreNewFolder") { run(.newFolder) }
        case .folder(let isFavorites):
            sortMenu(menu.sort, run: run)
            row("New Folder Inside", "folder.badge.plus", id: "moreNewFolder") { run(.newFolder) }
            if menu.canImportBook { importBookRow { run(.importBook) } }
            if let title = menu.downloadTitle { downloadRow(title) { run(.download) } }
            row("Delete Downloads", "trash.circle", id: "moreDeleteDownloads") { run(.deleteDownloads) }
            if !isFavorites {
                row("Rename", "pencil", id: "moreRename") { run(.rename) }
                editDetailsRow { run(.editDetails) }
                row("Move…", "folder", id: "moreMove") { run(.move) }
                row("Delete Folder…", "trash", id: "moreDeleteFolder") { run(.deleteFolder) }
            }
        case .pages:
            sortMenu(menu.sort, run: run)
            voiceRow { run(.voiceSettings) }
        }
        downloadsRow { run(.downloads) }
        if menu.showsDebug {
            row("Debug", "ladybug", id: "moreDebug") { run(.listenDebug) }
        }
        divider
        tiles {
            favoritesTile { run(.favorites) }
            tile("History", "clock", id: "moreHistory") { run(.history) }
            tile("Browser", "globe", id: "moreBrowser", focus: true) { run(.browser) }
                .accessibilityLabel("Browser")
                .accessibilityHint("Return to the browser")
        }
    }

    // MARK: - Shared rows

    private func sortMenu(_ current: PageSort, run: @escaping (LibraryMenu.Action) -> Void) -> some View {
        Menu {
            ForEach(PageSort.allCases, id: \.self) { sort in
                Button { run(.sort(sort)) } label: {
                    if sort == current { Label(sort.title, systemImage: "checkmark") } else { Text(sort.title) }
                }
            }
        } label: {
            rowLabel("Sort", "arrow.up.arrow.down", trailing: "chevron.right")
        }
        .accessibilityIdentifier("moreSort")
    }

    private func editDetailsRow(action: @escaping () -> Void) -> some View {
        row("Edit Details", "square.and.pencil", id: "moreEditDetails", action: action)
    }

    private func favoriteRow(isFavorite: Bool, action: @escaping () -> Void) -> some View {
        row(isFavorite ? "Remove from Favorites" : "Add to Favorites", isFavorite ? "star.slash" : "star",
            id: "moreFavorite", action: action)
    }

    private func favoritesTile(action: @escaping () -> Void) -> some View {
        tile("Favorites", "star", id: "moreFavorites", action: action)
    }

    private func shareRow(action: @escaping () -> Void) -> some View {
        row("Share", "square.and.arrow.up", id: "moreShare", action: action)
    }

    private func importBookRow(action: @escaping () -> Void) -> some View {
        row("Import Book…", "book.closed", id: "moreImportBook", action: action)
    }

    private func voiceRow(action: @escaping () -> Void) -> some View {
        row("Voice Settings", "person.wave.2", id: "moreVoice", action: action)
    }

    /// ⋯ › Downloads: the list of what is downloading and downloaded.
    private func downloadsRow(action: @escaping () -> Void) -> some View {
        row("Downloads", "tray.and.arrow.down", id: "moreDownloads", action: action)
    }

    /// *Download* (a page), *Download Folder*.
    private func downloadRow(_ title: String, action: @escaping () -> Void) -> some View {
        row(title, "arrow.down.circle", id: "moreDownload", action: action)
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

extension PageSort {
    /// Its name in the Sort menu.
    var title: String {
        switch self {
        case .manual: String(localized: "Manual")
        case .newest: String(localized: "Newest")
        case .title: String(localized: "Title")
        }
    }
}

/// The ⋯ toolbar button (browser, library, reader listen bar): opens
/// `menu()` in the shell's morph panel, grown from this button's frame. Its glyph fades while a
/// menu is open, so the button reads as turning
/// into the panel.
struct MoreMenuButton: View {
    let id: String
    let menu: () -> MenuContext

    @Environment(ShellState.self) private var shell
    @State private var frame: CGRect = .zero

    private var isOpen: Bool { shell.menu != nil }

    var body: some View {
        Button {
            shell.openMenu(menu(), from: frame)
        } label: {
            Image(systemName: "ellipsis")
                .toolbarIconFrame()
        }
        .accessibilityLabel("More")
        .accessibilityIdentifier(id)
        .morphMenuButtonHidden(isOpen)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
    }
}
