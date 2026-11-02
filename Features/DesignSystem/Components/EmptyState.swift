import SwiftUI

/// Every empty screen says so the same way: a heading, one line under it, and its ways out as
/// `ActionTile`s in an `ActionTileGrid`. It sits a fixed way down from the top of
/// whatever holds it (less at the accessibility sizes), never centred, so every empty screen lines up,
/// and scrolls when what holds it is too short for it. Search results with no match
/// use the system's search view instead. It takes the width it is given: in a card list that is the
/// cards' width; elsewhere the caller pads it by `Spacing.pageMargin`, the same edge.
struct EmptyState<Tiles: View>: View {
    let title: String
    var description: Text?
    @ViewBuilder var tiles: () -> Tiles

    @Environment(\.dynamicTypeSize) private var typeSize

    init(_ title: String, description: Text? = nil, @ViewBuilder tiles: @escaping () -> Tiles) {
        self.title = title
        self.description = description
        self.tiles = tiles
    }

    init(_ title: String, description: String, @ViewBuilder tiles: @escaping () -> Tiles) {
        self.init(title, description: Text(description), tiles: tiles)
    }

    var body: some View {
        // Where what holds it is too short for all of it (Listen's sheet on a small phone at the
        // largest sizes) it scrolls, rather than cut its heading or its line short.
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
    }

    private var content: some View {
        VStack(spacing: Spacing.m) {
            VStack(spacing: Spacing.xs) {
                Text(title)
                    .typeStyle(.heading, weight: .semibold)
                    .foregroundStyle(Palette.ink)
                if let description {
                    description
                        .typeStyle(.row)
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
            tiles()
        }
        // Less at the accessibility sizes, where the heading, its line and the tiles need the height.
        .padding(.top, typeSize.isAccessibilitySize ? Spacing.xl : Spacing.xl * 4)
    }
}

#if DEBUG
struct EmptyStateGallery: View {
    var body: some View {
        PreviewGallery {
            // The app's empty screens all show these five (`AddToLibraryTiles`).
            PreviewState("four tiles and a wide one") {
                EmptyState("Start Your Library", description: "Save from the web, a file, text or a link, or follow a site.") {
                    ActionTileGrid(tiles: [
                        ActionTile(title: "Browse the Web", symbol: Icons.browser, prominent: true) {},
                        ActionTile(title: Verbs.followSite, symbol: Icons.follow) {},
                        ActionTile(title: "Import a File", symbol: Icons.importFile) {},
                        ActionTile(title: "Paste Text", symbol: Icons.paste) {},
                    ], wide: ActionTile(title: "Add a Link", symbol: Icons.link) {})
                }
            }
        }
    }
}

#Preview("EmptyState · light", traits: .sizeThatFitsLayout) { EmptyStateGallery().previewVariant(.light) }
#Preview("EmptyState · dark", traits: .sizeThatFitsLayout) { EmptyStateGallery().previewVariant(.dark) }
#Preview("EmptyState · AX5", traits: .sizeThatFitsLayout) { EmptyStateGallery().previewVariant(.largestText) }
#endif
