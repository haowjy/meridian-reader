import SwiftUI

/// Every empty screen says so the same way: a heading, one line under it, and its ways out as
/// `ActionTile`s in an `ActionTileGrid`. It is centred in the room it has: in a card list
/// (`cardListStyle`), what the list leaves visible below the rows above it (a title and tabs, a
/// folder's header) and above whatever floats over its foot (the compact chrome's content margin);
/// elsewhere, the height it is given. Where that is too short for it (the accessibility sizes, a
/// small phone's Listen) it scrolls, with the list or on its own, rather than cut its heading or its
/// line short. Search results with no match use the system's search view instead. It takes the
/// width it is given: in a card list that is the cards' width; elsewhere the caller pads it by
/// `Spacing.pageMargin`, the same edge.
struct EmptyState<Tiles: View>: View {
    let title: String
    var description: Text?
    @ViewBuilder var tiles: () -> Tiles

    @Environment(\.listRoom) private var room
    /// Where it starts on screen with its list at rest (nil until measured): its height doesn't move it.
    @State private var top: CGFloat?

    init(_ title: String, description: Text? = nil, @ViewBuilder tiles: @escaping () -> Tiles) {
        self.title = title
        self.description = description
        self.tiles = tiles
    }

    init(_ title: String, description: String, @ViewBuilder tiles: @escaping () -> Tiles) {
        self.init(title, description: Text(description), tiles: tiles)
    }

    var body: some View {
        Group {
            if let room {
                // In a list: from where it starts to the foot of what the list shows, so the content
                // centres there; never shorter than the content (then the list scrolls).
                content
                    .frame(maxWidth: .infinity, minHeight: top.map { max(0, room.bottom - $0) })
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { minY in
                        // Measured at rest only: a scroll or a rubber band moves it, not where it starts.
                        if room.atRest, top.map({ abs($0 - minY) >= 0.5 }) ?? true { top = minY }
                    }
            } else {
                ViewThatFits(in: .vertical) {
                    content
                    ScrollView { content }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
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
    }
}

/// Where a card list's visible content ends on screen (its foot, less its bottom inset or what floats
/// over it, `scrollFootClearance`, whichever is more), and whether it is scrolled to its top: for an
/// `EmptyState` among its rows to fill what the rows above it leave.
struct ListRoom: Equatable {
    var bottom: CGFloat
    var atRest: Bool
}

extension EnvironmentValues {
    /// The card list around a view (`cardListStyle`); nil outside one.
    @Entry var listRoom: ListRoom?
    /// How far up from a scroll view's foot something floats over it (the compact chrome, set with
    /// its content margin); 0 where nothing does.
    @Entry var scrollFootClearance: CGFloat = 0
}

/// Measures a list's room (`ListRoom`) and hands it to its rows.
struct ListRoomReader: ViewModifier {
    @Environment(\.scrollFootClearance) private var footClearance
    @State private var maxY: CGFloat = 0
    @State private var scroll = Scroll(bottomInset: 0, atRest: true)

    private struct Scroll: Equatable {
        var bottomInset: CGFloat
        var atRest: Bool
    }

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { maxY = $0 }
            .onScrollGeometryChange(for: Scroll.self) { geometry in
                Scroll(bottomInset: geometry.contentInsets.bottom,
                       atRest: abs(geometry.contentOffset.y + geometry.contentInsets.top) < 0.5)
            } action: { _, new in scroll = new }
            .environment(\.listRoom, ListRoom(bottom: maxY - max(scroll.bottomInset, footClearance), atRest: scroll.atRest))
    }
}

#if DEBUG
struct EmptyStateGallery: View {
    var body: some View {
        PreviewGallery {
            // The app's empty screens all show these four (`AddToLibraryTiles`).
            PreviewState("four tiles") {
                EmptyState("Start Your Library", description: "Articles you save show up here.") {
                    ActionTileGrid(tiles: [
                        ActionTile(title: "Browse the Web", symbol: Icons.browser, prominent: true) {},
                        ActionTile(title: "Add a Link", symbol: Icons.link) {},
                        ActionTile(title: "Import a File", symbol: Icons.importFile) {},
                        ActionTile(title: "Paste Text", symbol: Icons.paste) {},
                    ])
                }
            }
        }
    }
}

#Preview("EmptyState · light", traits: .sizeThatFitsLayout) { EmptyStateGallery().previewVariant(.light) }
#Preview("EmptyState · dark", traits: .sizeThatFitsLayout) { EmptyStateGallery().previewVariant(.dark) }
#Preview("EmptyState · AX5", traits: .sizeThatFitsLayout) { EmptyStateGallery().previewVariant(.largestText) }
#endif
