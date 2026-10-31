import SwiftUI

/// Every empty screen says so the same way: a heading, a line under it when there is something to
/// say, and the ways to fill it as `ActionTile`s, two to a row (stacked at the accessibility sizes,
/// where two side by side would break their words). It sits a fixed way down from the top of
/// whatever holds it, never centred, so every empty screen lines up. Search results with no match
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
            if typeSize.isAccessibilitySize {
                VStack(spacing: Spacing.s) { tiles() }
            } else {
                HStack(spacing: Spacing.s) { tiles() }
            }
        }
        .padding(.top, Spacing.xl * 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
struct EmptyStateGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("one tile") {
                EmptyState("No History Yet", description: "Pages you open show up here.") {
                    ActionTile(title: "Browse the Web", symbol: Icons.browser, prominent: true) {}
                }
            }
            PreviewState("two tiles") {
                EmptyState("Start Your Library") {
                    ActionTile(title: "Browse the Web", symbol: Icons.browser, prominent: true) {}
                    ActionTile(title: "Import a Book", symbol: Icons.book) {}
                }
            }
        }
    }
}

#Preview("EmptyState · light", traits: .sizeThatFitsLayout) { EmptyStateGallery().previewVariant(.light) }
#Preview("EmptyState · dark", traits: .sizeThatFitsLayout) { EmptyStateGallery().previewVariant(.dark) }
#Preview("EmptyState · AX5", traits: .sizeThatFitsLayout) { EmptyStateGallery().previewVariant(.largestText) }
#endif
