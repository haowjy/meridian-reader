import SwiftUI

/// ⋯ at the end of a screen's title line (the Library home, a folder's navigation bar, Settings,
/// Library Read): the screen's menu as a system menu, a section per block (`MenuRows`). A glass circle by
/// default (`TitleMenuGlyph`), or `face`.
struct TitleMenuButton<Face: View>: View {
    let id: String
    let blocks: [[MenuRow]]
    @ViewBuilder var face: Face

    var body: some View {
        Menu {
            MenuRows(blocks: blocks)
        } label: {
            face
        }
        .accessibilityLabel(Verbs.more)
        .accessibilityIdentifier(id)
    }
}

extension TitleMenuButton where Face == TitleMenuGlyph {
    init(id: String, blocks: [[MenuRow]]) {
        self.init(id: id, blocks: blocks) { TitleMenuGlyph() }
    }
}

/// The title line's ⋯: the same glass circle as the reading pages' ⋯ (`ChromeCircleFace`, `Control.chrome`),
/// so every screen's ⋯ is one bubble.
struct TitleMenuGlyph: View {
    var body: some View {
        ChromeCircleFace(symbol: Icons.more, label: Verbs.more)
            .frame(width: Control.chrome, height: Control.chrome)
            .environment(\.chromeSkin, ChromeSkin.current)
    }
}

/// A screen's ⋯ in a system navigation bar (a folder, Prepared Audio): the bare symbol in ink, since the
/// bar draws the bubble itself (iOS 26's glass, at the bar's own size) and a framed face would be padded
/// twice. It goes last on the trailing side (`ScreenMenuToolbarItem`), its own bubble, after Edit or a
/// sheet's Done.
struct TitleMenuToolbarGlyph: View {
    var body: some View {
        Image(systemName: Icons.more).foregroundStyle(Palette.ink)
    }
}

/// A screen's ⋯ as a system navigation bar's last trailing item, set apart from the item before it
/// (Edit, a sheet's Done) so each is its own bubble. Every pushed page and sheet with a screen menu
/// puts it here.
struct ScreenMenuToolbarItem<Content: View>: ToolbarContent {
    @ViewBuilder var menu: Content

    var body: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
        }
        ToolbarItem(placement: .topBarTrailing) { menu }
    }
}

/// A screen title with ⋯ at the end of its line (the Library home, Settings in place).
struct TitleLine<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.s) {
            ScreenTitle(title)
                .frame(maxWidth: .infinity, alignment: .leading)
            // The title keeps the page margin; its ⋯ sits where every top bar's buttons sit
            // (`Spacing.topBarMargin` from the edge), so ⋯ lands in one place on every screen.
            trailing
                .offset(x: Spacing.pageMargin - Spacing.topBarMargin)
        }
    }
}

#if DEBUG
struct TitleMenuButtonGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("the Library home's title line") {
                TitleLine(title: "Library") {
                    TitleMenuButton(id: "preview", blocks: [[
                        MenuRow(id: "a", title: "New Folder…", icon: Icons.newFolder),
                        MenuRow(id: "b", title: "Import a File…", icon: Icons.importFile),
                    ], [MenuRow(id: "c", title: "Sort", icon: Icons.sort)]])
                }
            }
        }
    }
}

#Preview("TitleMenuButton · light", traits: .sizeThatFitsLayout) { TitleMenuButtonGallery().previewVariant(.light) }
#Preview("TitleMenuButton · dark", traits: .sizeThatFitsLayout) { TitleMenuButtonGallery().previewVariant(.dark) }
#Preview("TitleMenuButton · AX5", traits: .sizeThatFitsLayout) { TitleMenuButtonGallery().previewVariant(.largestText) }
#endif
