import SwiftUI

/// A section's title with an optional trailing action ("Show All ›", "Clear All", ＋), on the Library
/// home and the start page.
///
/// ```
/// Pages  48                              Show All ›
/// ```
///
/// A count sits after the title in the title's size, regular weight and tertiary ink, so it
/// reads as a quieter label of its own rather than part of the title. The title wraps between
/// words; when its longest word and the action can't share the line, the action goes under it.
struct SectionHeader: View {
    enum Size {
        /// Under a screen title (the Library's lists): `row` semibold in secondary ink, so the
        /// screen title stays the largest thing.
        case list
        /// Settings root only: `caption` semibold in secondary ink — denser than Library headers.
        case settings
        /// The top level of a screen without a title (the start page): `heading`.
        case page
    }

    let title: String
    /// How many things the section holds, after the title; nil: none.
    var count: Int?
    var size: Size = .list
    /// The trailing action's title; nil: no action.
    var actionTitle: String?
    /// Draws a › after the action's title (it goes somewhere rather than doing something).
    var actionNavigates = false
    /// The action button's accessibility identifier.
    var actionIdentifier: String?
    var action: () -> Void = {}

    /// The action's text height, for its 44 pt tap area.
    @ScaledMetric(relativeTo: TypeStyle.row.relativeTo) private var actionHeight = TypeStyle.row.size

    private var titleStyle: TypeStyle {
        switch size {
        case .list: return .row
        case .settings: return .caption
        case .page: return .heading
        }
    }

    var body: some View {
        // The title wraps between words, never inside one (its ideal width is its widest word): when
        // that word and the action don't fit side by side, the action moves under the title.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                label
                Spacer(minLength: Spacing.xs)
                actionButton
            }
            VStack(alignment: .leading, spacing: 0) {
                label
                actionButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var label: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            WholeWordsText(title)
                .typeStyle(titleStyle, weight: size == .page ? nil : .semibold)
                .foregroundStyle(size == .page ? Palette.ink : Palette.secondaryInk)
            if let count {
                Text("\(count)")
                    .typeStyle(titleStyle, weight: .regular)
                    .monospacedDigit()
                    .foregroundStyle(Palette.tertiaryInk)
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(count.map { "\(title), \($0)" } ?? title)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var actionButton: some View {
        if let actionTitle {
            Button(action: action) {
                HStack(spacing: Spacing.xxs) {
                    Text(actionTitle).fixedSize()
                    if actionNavigates {
                        Image(systemName: Icons.disclosure).font(.caption.weight(.semibold))
                    }
                }
                .typeStyle(.row)
                .foregroundStyle(Palette.accent)
                .tapTarget(actionHeight)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(actionIdentifier ?? "")
        }
    }
}

#if DEBUG
struct SectionHeaderGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("title only") { SectionHeader(title: "Chapters") }
            PreviewState("page size, the start page") {
                SectionHeader(title: "Frequently Visited", size: .page, actionTitle: "Show All", actionNavigates: true)
            }
            PreviewState("with Show All") {
                SectionHeader(title: "Pages", count: 48, actionTitle: "Show All", actionNavigates: true)
            }
            PreviewState("with an action") { SectionHeader(title: "Recent Searches", actionTitle: "Clear All") }
        }
    }
}

#Preview("SectionHeader · light", traits: .sizeThatFitsLayout) { SectionHeaderGallery().previewVariant(.light) }
#Preview("SectionHeader · dark", traits: .sizeThatFitsLayout) { SectionHeaderGallery().previewVariant(.dark) }
#Preview("SectionHeader · AX5", traits: .sizeThatFitsLayout) { SectionHeaderGallery().previewVariant(.largestText) }
#endif
