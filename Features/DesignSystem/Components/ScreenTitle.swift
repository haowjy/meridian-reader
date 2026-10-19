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
