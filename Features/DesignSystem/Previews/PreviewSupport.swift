#if DEBUG
import SwiftUI

/// The variants every component's previews are shown in: light, dark and the largest
/// Dynamic Type size. Environment values (not `preferredColorScheme`) so the same galleries also
/// render through `ImageRenderer` in `DesignSystemGalleryTests`.
enum PreviewVariant: String, CaseIterable {
    case light
    case dark
    case largestText

    func apply<V: View>(_ view: V) -> some View {
        view
            .environment(\.sheetRisesOnAppear, false)
            .environment(\.colorScheme, self == .dark ? .dark : .light)
            .dynamicTypeSize(self == .largestText ? .accessibility5 : .large)
    }
}

extension View {
    /// The gallery as `variant` shows it: on paper, in that appearance and text size.
    func previewVariant(_ variant: PreviewVariant) -> some View {
        variant.apply(
            self.frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.paper)
        )
    }
}

/// A gallery's page: its states stacked, each under a caption naming it, 390 pt wide (an
/// iPhone in portrait). Not scrolling, so previews use `.sizeThatFitsLayout` and
/// `ImageRenderer` sees the whole gallery.
struct PreviewGallery<Content: View>: View {
    static var width: CGFloat { 390 }
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) { content }
            .padding(Spacing.pageMargin)
            .frame(width: Self.width, alignment: .leading)
            .background(Palette.paper)
    }
}

/// One named state in a gallery.
struct PreviewState<Content: View>: View {
    let name: String
    @ViewBuilder var content: Content

    init(_ name: String, @ViewBuilder content: () -> Content) {
        self.name = name
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(name.uppercased())
                .typeStyle(.caption, weight: .semibold)
                .foregroundStyle(Palette.secondaryInk)
            content
        }
    }
}
/// Stand-in reading text for the sheets' previews: a heading and serif paragraphs, the second
/// tinted as the spoken one (with its sentence underlined) when `spoken` is on.
struct SampleReading: View {
    let title: String
    let detail: String
    var spoken = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            ReadingHeading(title: title, detail: detail)
            Text("Tides rise and fall twice a day along most coasts, pulled by the moon and, more weakly, the sun.")
            (Text("Where a bay narrows, the water piles up.").underline(spoken, color: Palette.accent)
                + Text(" The difference between high and low water can reach several metres."))
                .padding(.vertical, spoken ? Spacing.xs : 0)
                .padding(.horizontal, spoken ? Spacing.s : 0)
                .background(spoken ? Palette.playingTint : Color.clear,
                            in: RoundedRectangle(cornerRadius: Radius.card))
                .padding(.horizontal, spoken ? -Spacing.s : 0)
            Text("Fishermen read the tables the way farmers read the weather.")
        }
        .typeStyle(.body)
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, Spacing.pageMargin)
        .padding(.top, Spacing.xs)
    }
}
#endif
