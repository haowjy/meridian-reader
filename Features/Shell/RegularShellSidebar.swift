import SwiftData
import SwiftUI

/// Regular-width left column (~280 pt): Library / Browse surface swap, Favorites + folder tree,
/// Search, Settings. Compact devices never show this; they keep today's bottom band.
struct RegularShellSidebar: View {
    @Environment(ShellState.self) private var shell
    @Environment(LibraryStore.self) private var library
    @Query(LibraryQueries.folders) private var allFolders: [Folder]

    private var topFolders: [Folder] {
        LibraryStore.ordered(LibraryQueries.topLevel(allFolders.filter(\.isLive)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
                .padding(.horizontal, Spacing.m)
                .padding(.top, Spacing.m)
                .padding(.bottom, Spacing.s)

            surfaceRow(surface: .library, title: Verbs.library, symbol: Icons.library,
                       identifier: "sidebarLibrary")
            surfaceRow(surface: .browse, title: Verbs.browser, symbol: Icons.browser,
                       identifier: "sidebarBrowse")

            sidebarButton(title: Verbs.search, symbol: Icons.search, identifier: "sidebarSearch",
                          selected: false, action: beginSearch)
                .padding(.top, Spacing.xxs)

            Divider().padding(.vertical, Spacing.s).padding(.horizontal, Spacing.m)

            Text(String(localized: "Folders"))
                .typeStyle(.caption, weight: .semibold)
                .foregroundStyle(Palette.secondaryInk)
                .padding(.horizontal, Spacing.m)
                .padding(.bottom, Spacing.xs)

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    sidebarButton(title: Verbs.favorites, symbol: Icons.favorited,
                                  identifier: "sidebarFavorites",
                                  selected: shell.isInLibrary && shell.homeTab == .favorites
                                      && shell.libraryPath.isEmpty,
                                  action: shell.showFavorites)

                    ForEach(topFolders, id: \.id) { folder in
                        sidebarButton(title: folder.name, symbol: Icons.folder,
                                      identifier: "sidebarFolder-\(folder.id.uuidString)",
                                      selected: isSelected(folder),
                                      action: { shell.showLibrary(at: library.path(to: folder)) })
                    }
                }
                .padding(.horizontal, Spacing.xs)
            }
            .frame(maxHeight: .infinity, alignment: .top)

            sidebarButton(title: Verbs.settings, symbol: Icons.settings, identifier: "sidebarSettings",
                          selected: isSettingsUp, action: { shell.present(.settings) })
                .padding(.horizontal, Spacing.xs)
                .padding(.bottom, Spacing.m)
        }
        .frame(width: RegularLayout.sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.chrome.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("regularShellSidebar")
    }

    private var brand: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: Icons.library)
                .foregroundStyle(Palette.accent)
                .tileSymbol()
            Text("Meridian")
                .typeStyle(.heading, weight: .bold)
                .foregroundStyle(Palette.ink)
            Spacer(minLength: 0)
            Button {
                withAnimation(Motion.snappy) { shell.sidebarCollapsed = true }
            } label: {
                Image(systemName: Icons.back)
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(width: BottomChrome.minTapTarget, height: BottomChrome.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Hide sidebar"))
            .accessibilityIdentifier("sidebarCollapse")
        }
    }

    private var isSettingsUp: Bool {
        if case .settings = shell.sheet { return true }
        return false
    }

    private func isSelected(_ folder: Folder) -> Bool {
        guard shell.isInLibrary, case .folder(let id) = shell.libraryPath.last else { return false }
        return id == folder.id
    }

    private func surfaceRow(surface: ShellState.Surface, title: String, symbol: String,
                            identifier: String) -> some View {
        let selected = surface == .library ? shell.isInLibrary : shell.isBrowsing
        return sidebarButton(title: title, symbol: symbol, identifier: identifier, selected: selected) {
            if surface == .library {
                shell.openLibrary()
            } else {
                shell.leaveLibrary()
            }
        }
        .padding(.horizontal, Spacing.xs)
    }

    private func sidebarButton(title: String, symbol: String, identifier: String, selected: Bool,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.s) {
                Image(systemName: symbol)
                    .frame(width: Glyph.rowLeading, alignment: .center)
                Text(title)
                    .typeStyle(.row, weight: selected ? .semibold : .regular)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? Palette.accent : Palette.ink)
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, Spacing.xs)
            .frame(maxWidth: .infinity, minHeight: RowHeight.compact, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(selected ? Palette.playingTint : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    private func beginSearch() {
        if shell.isInLibrary {
            shell.beginLibrarySearch()
        } else {
            shell.addressSearch.begin(with: shell.web.currentURL?.absoluteString ?? "")
        }
    }
}

/// Floating control that restores the sidebar when it was collapsed for focus reading.
struct RegularSidebarRevealButton: View {
    @Environment(ShellState.self) private var shell

    var body: some View {
        Button {
            withAnimation(Motion.snappy) { shell.sidebarCollapsed = false }
        } label: {
            Image(systemName: Icons.forward)
                .foregroundStyle(Palette.ink)
                .frame(width: BottomChrome.minTapTarget, height: BottomChrome.minTapTarget)
                .background(Palette.chrome, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(Spacing.s)
        .accessibilityLabel(String(localized: "Show sidebar"))
        .accessibilityIdentifier("sidebarReveal")
    }
}
