import SwiftUI

/// How much of its label a button in an `ActionButtonRow` shows.
enum ActionLabelFit: CaseIterable {
    /// The title and its detail: *▶ **Continue**  4 of 18*, *⏮ From Start*.
    case full
    /// The symbol alone, on a round button; VoiceOver and the large content viewer keep the title.
    case icon
}

/// A row of labelled buttons that never wraps: the Library's first-run card, a prepare's
/// *Prepare Again* / *Keep*. The row is drawn
/// once per `ActionLabelFit` and the first that fits the width is shown: every label in full, then
/// symbols alone. The symbols-only row is the last resort, taken even when it doesn't fit, so the
/// buttons stay on one line at every width and text size. (A pill still drops its detail by itself
/// when its own label is short of room.)
///
/// ```
/// ( ▶ Try Again             ) ( ✎ Edit Address )     full
/// (            ↻                      ) (✎)     icon
/// ```
///
/// Give each button its symbol (`PillButton(systemImage:)`): the icon row shows nothing else. A button that stretches (`expands`) still does in every fit.
struct ActionButtonRow<Content: View>: View {
    var spacing: CGFloat = Spacing.s
    /// The row's buttons, drawn for `fit`.
    @ViewBuilder var content: (_ fit: ActionLabelFit) -> Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(.full)
            row(.icon)
        }
        .accessibilityElement(children: .contain)
    }

    private func row(_ fit: ActionLabelFit) -> some View {
        HStack(spacing: spacing) { content(fit) }
    }
}

#if DEBUG
struct ActionButtonRowGallery: View {
    var body: some View {
        PreviewGallery {
            ForEach([CGFloat(350), 300, 220], id: \.self) { width in
                PreviewState("\(Int(width)) pt") {
                    ActionButtonRow { fit in
                        PillButton("Continue", detail: "4 of 18", systemImage: Icons.play, expands: true, fit: fit) {}
                        PillButton("From Start", systemImage: Icons.previous, style: .neutral, fit: fit) {}
                    }
                    .frame(width: width)
                }
            }
            PreviewState("compact choices") {
                ActionButtonRow(spacing: Spacing.xs) { fit in
                    PillButton("Prepare Again", systemImage: Icons.reprepare, size: .compact,
                               fit: fit) {}
                    PillButton(Verbs.pause, systemImage: Icons.pause, style: .neutral, size: .compact, fit: fit) {}
                }
            }
        }
    }
}

#Preview("ActionButtonRow · light", traits: .sizeThatFitsLayout) { ActionButtonRowGallery().previewVariant(.light) }
#Preview("ActionButtonRow · dark", traits: .sizeThatFitsLayout) { ActionButtonRowGallery().previewVariant(.dark) }
#Preview("ActionButtonRow · AX5", traits: .sizeThatFitsLayout) { ActionButtonRowGallery().previewVariant(.largestText) }
#endif
