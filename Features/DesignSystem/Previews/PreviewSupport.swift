#if DEBUG
import SwiftUI

/// The variants every component's previews are shown in: light, dark and the largest
/// Dynamic Type size. Environment values (not `preferredColorScheme`), so a gallery also renders
/// through `ImageRenderer` (a probe's snapshot of every variant).
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

extension View {
    /// A component as it sits on the reading page (the Reader, Now Playing) in `theme`: on its
    /// background, with its environment.
    func onReadingPreview(_ theme: ReadingTheme = .dark) -> some View {
        let palette = theme.palette(accent: AppAppearance.shared.accent)
        return padding(Spacing.s)
            .background(palette.background, in: RoundedRectangle(cornerRadius: Radius.card))
            .readingSurface(palette)
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
/// Stand-in reading text for the sheets' previews: paragraphs in the reading page's colours
/// (`readingPalette`, the app's when unset), under a heading or, with `card`, Now Playing's title
/// card. With `spoken` the second paragraph is spoken: on the highlight in full ink, its sentence
/// underlined, the others dimmed.
struct SampleReading: View {
    let title: String
    let detail: [String]
    var spoken = false
    var card = false

    @Environment(\.readingPalette) private var reading

    var body: some View {
        let palette = reading ?? .app
        let other = spoken ? palette.dimInk : palette.ink
        VStack(alignment: .leading, spacing: Spacing.m) {
            if card {
                TitleCard(title: title, detail: detail, artworkLetter: title, palette: palette)
                    .padding(.horizontal, Spacing.m - Spacing.pageMargin)
                    .padding(.bottom, Spacing.l - Spacing.m)
            } else {
                ReadingHeading(title: title, detail: detail)
            }
            Text("Tides rise and fall twice a day along most coasts, pulled by the moon and, more weakly, the sun.")
                .foregroundStyle(other)
            (Text("Where a bay narrows, the water piles up.").underline(spoken, color: palette.underline)
                + Text(" The difference between high and low water can reach several metres."))
                .foregroundStyle(palette.ink)
                .padding(.vertical, spoken ? Spacing.xs : 0)
                .padding(.horizontal, spoken ? Spacing.xs : 0)
                .background(spoken ? palette.highlight : Color.clear,
                            in: RoundedRectangle(cornerRadius: Spacing.xs))
                .padding(.horizontal, spoken ? -Spacing.xs : 0)
            Text("Fishermen read the tables the way farmers read the weather.")
                .foregroundStyle(other)
        }
        .typeStyle(.body)
        .padding(.horizontal, Spacing.pageMargin)
        .padding(.top, Spacing.xs)
    }
}
#endif
