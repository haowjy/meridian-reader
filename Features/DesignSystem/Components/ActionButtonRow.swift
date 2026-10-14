import SwiftUI

/// How much of its label a button in an `ActionButtonRow` shows.
enum ActionLabelFit: CaseIterable {
    /// The title and its detail: *▶ **Continue**  4 of 18*, *⏮ From Start*.
    case full
    /// The short title (`PillButton.shortTitle`, else the title), still with its detail:
    /// *▶ **Continue**  4 of 18*, *⏮ Start*.
    case short
    /// The short title without its detail: *▶ **Continue***, *⏮ Start*.
    case titleOnly
    /// The symbol alone, on a round button; VoiceOver and the large content viewer keep the title.
    case icon
}

/// A row of action buttons that never wraps: a folder header's *Continue* / *From Start* /
/// Download, the Library's first-run card, a download's *Re-download* / *Keep*. The row is drawn
/// once per `ActionLabelFit` and the first that fits the width is shown: every label in full,
/// then the short titles, then without details, then symbols alone. The symbols-only row is the last resort, taken even
/// when it doesn't fit, so the buttons stay on one line at every width and text size.
///
/// ```
/// ( ▶ Continue  4 of 18     ) ( ⏮ From Start ) (⬇)     full
/// ( ▶ Continue  4 of 18          ) ( ⏮ Start ) (⬇)     short
/// ( ▶ Continue                   ) ( ⏮ Start ) (⬇)     titleOnly
/// (            ▶                      ) (⏮) (⬇)     icon
/// ```
///
/// Give each button its symbol (`PillButton(systemImage:)`, a `PlayStateButton` pill): the icon
/// row shows nothing else. A button that stretches (`expands`) still does in every fit.
struct ActionButtonRow<Content: View>: View {
    var spacing: CGFloat = Spacing.s
    /// The row's buttons, drawn for `fit`.
    @ViewBuilder var content: (_ fit: ActionLabelFit) -> Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(.full)
            row(.short)
            row(.titleOnly)
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
                        PlayStateButton(state: .idle, look: .pill(title: "Continue", detail: "4 of 18", expands: true,
                                                                   fit: fit)) {}
                        PillButton("From Start", shortTitle: "Start", systemImage: "backward.end.fill", style: .neutral,
                                   fit: fit) {}
                        DownloadStateButton(state: .available, look: .round) {}
                    }
                    .frame(width: width)
                }
            }
            PreviewState("compact choices") {
                ActionButtonRow(spacing: Spacing.xs) { fit in
                    PillButton("Re-download", shortTitle: "Redo", systemImage: "arrow.clockwise", size: .compact,
                               fit: fit) {}
                    PillButton("Keep", systemImage: "checkmark", style: .neutral, size: .compact, fit: fit) {}
                }
            }
        }
    }
}

#Preview("ActionButtonRow · light", traits: .sizeThatFitsLayout) { ActionButtonRowGallery().previewVariant(.light) }
#Preview("ActionButtonRow · dark", traits: .sizeThatFitsLayout) { ActionButtonRowGallery().previewVariant(.dark) }
#Preview("ActionButtonRow · AX5", traits: .sizeThatFitsLayout) { ActionButtonRowGallery().previewVariant(.largestText) }
#endif
