import SwiftUI

/// A section's title with an optional trailing action ("Show All ›", "Clear", ＋), on the Library
/// home and the start page.
///
/// ```
/// Continue                               Show All ›
/// ```
struct SectionHeader: View {
    let title: String
    /// The trailing action's title; nil: no action.
    var actionTitle: String?
    /// Draws a › after the action's title (it goes somewhere rather than doing something).
    var actionNavigates = false
    var action: () -> Void = {}

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .typeStyle(.heading)
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Spacing.xs)
            if let actionTitle {
                Button(action: action) {
                    HStack(spacing: Spacing.xxs) {
                        Text(actionTitle)
                        if actionNavigates {
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        }
                    }
                    .typeStyle(.row)
                    .foregroundStyle(Palette.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#if DEBUG
struct SectionHeaderGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("title only") { SectionHeader(title: "Continue") }
            PreviewState("with Show All") {
                SectionHeader(title: "Pages · 48", actionTitle: "Show All", actionNavigates: true)
            }
            PreviewState("with an action") { SectionHeader(title: "Recent Searches", actionTitle: "Clear") }
        }
    }
}

#Preview("SectionHeader · light", traits: .sizeThatFitsLayout) { SectionHeaderGallery().previewVariant(.light) }
#Preview("SectionHeader · dark", traits: .sizeThatFitsLayout) { SectionHeaderGallery().previewVariant(.dark) }
#Preview("SectionHeader · AX5", traits: .sizeThatFitsLayout) { SectionHeaderGallery().previewVariant(.largestText) }
#endif
