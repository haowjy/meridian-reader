import SwiftUI

/// Shown once on the first launch of a new marketing version (not on a fresh install).
/// Flat app styling, design system tokens, one dismiss button.
struct WhatsNewSheet: View {
    let notes: [String]
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("What's New")
                .typeStyle(.heading)
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, Spacing.xl)
                .padding(.bottom, Spacing.m)
                .padding(.horizontal, Spacing.pageMargin)

            VStack(alignment: .leading, spacing: Spacing.s) {
                ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                        Image(systemName: Icons.checkmark)
                            .foregroundStyle(Palette.accent)
                        Text(note)
                            .typeStyle(.row)
                            .foregroundStyle(Palette.ink)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.pageMargin)

            Spacer(minLength: Spacing.xl)

            Button(action: onDismiss) {
                Text("Continue")
                    .typeStyle(.row, weight: .semibold)
                    .foregroundStyle(Palette.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: BottomChrome.minTapTarget)
                    .background(Palette.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Spacing.pageMargin)
            .padding(.bottom, Spacing.xl)
        }
        .background(Palette.paper)
        .accessibilityIdentifier("whatsNewSheet")
    }
}

#if DEBUG
#Preview("What's New · light") {
    WhatsNewSheet(notes: [
        "Listen to web articles with high-quality on-device voices.",
        "Save articles and listen offline — no account needed.",
        "Follow web serials and get new chapters automatically.",
        "Import EPUB books and listen chapter by chapter.",
    ]) {}
    .previewVariant(.light)
}

#Preview("What's New · dark") {
    WhatsNewSheet(notes: [
        "Listen to web articles with high-quality on-device voices.",
        "Save articles and listen offline — no account needed.",
    ]) {}
    .previewVariant(.dark)
}
#endif
