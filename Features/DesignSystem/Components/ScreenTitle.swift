import SwiftUI

/// A screen's own title in its content, not in the navigation bar: the Library home's *Library*,
/// a folder's name in its header and over its search results. The title type in ink, read as a
/// header. A book's or a folder-with-details' header uses the smaller `heading` size under its cover.
struct ScreenTitle: View {
    let text: String
    var size: TypeStyle = .title

    init(_ text: String, size: TypeStyle = .title) {
        self.text = text
        self.size = size
    }

    var body: some View {
        Text(text)
            .typeStyle(size, design: .default)
            .foregroundStyle(Palette.ink)
            .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    /// A screen with no navigation bar (the Library home, Settings in place): paper behind the
    /// status bar, so rows scrolled up pass under it rather than under the clock.
    func statusBarBacking() -> some View {
        // A line with no height at the safe area's top; its paper reaches up through the status
        // bar. (The list itself runs edge to edge, so an overlay of it starts above the clock.)
        safeAreaInset(edge: .top, spacing: 0) {
            Color.clear
                .frame(height: 0)
                .background(Palette.paper.ignoresSafeArea(edges: .top))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

#if DEBUG
struct ScreenTitleGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("the Library home") { ScreenTitle("Library") }
            PreviewState("a book's header, under its cover") { ScreenTitle("Pride and Prejudice", size: .heading) }
        }
    }
}

#Preview("ScreenTitle · light", traits: .sizeThatFitsLayout) { ScreenTitleGallery().previewVariant(.light) }
#Preview("ScreenTitle · dark", traits: .sizeThatFitsLayout) { ScreenTitleGallery().previewVariant(.dark) }
#Preview("ScreenTitle · AX5", traits: .sizeThatFitsLayout) { ScreenTitleGallery().previewVariant(.largestText) }
#endif
