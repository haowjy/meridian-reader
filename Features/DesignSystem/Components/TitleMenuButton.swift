import SwiftUI

/// ⋯ at the end of a screen's title line (the Library home, a folder's navigation bar, Settings,
/// Library Read): the screen's menu as a system menu, a section per block (`MenuRows`). Plain ink by
/// default, or `face` for a round glass face where it floats over text.
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

/// The title line's ⋯: the toolbar's glyph in the ink, a 44 pt tap.
struct TitleMenuGlyph: View {
    var body: some View {
        Image(systemName: Icons.more)
            .font(.system(size: Glyph.regular))
            .foregroundStyle(Palette.ink)
            .frame(width: Control.tap, height: Control.tap)
            .contentShape(Rectangle())
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
            trailing
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
                        MenuRow(id: "b", title: "Import from…", icon: Icons.importFile),
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
