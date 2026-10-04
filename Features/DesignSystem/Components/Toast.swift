import SwiftUI

/// A short message that floats over the bottom chrome and goes away by itself: "Nothing to
/// listen to on this page". Present it by inserting it; the owner removes it after a few seconds
/// (`Toast.duration`). It takes no taps, so it never blocks what is under it.
struct Toast: View {
    let message: String
    var systemImage: String?

    /// How long a toast stays up.
    static let duration: Duration = .seconds(2.5)

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(Palette.secondaryInk)
            }
            Text(message)
                .typeStyle(.row)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        .background(.regularMaterial, in: Capsule())
        .floatingShadow()
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityIdentifier("toast")
    }
}

#if DEBUG
struct ToastGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("message") {
                Toast(message: "Nothing to listen to on this page", systemImage: "headphones")
            }
        }
    }
}

#Preview("Toast · light", traits: .sizeThatFitsLayout) { ToastGallery().previewVariant(.light) }
#Preview("Toast · dark", traits: .sizeThatFitsLayout) { ToastGallery().previewVariant(.dark) }
#Preview("Toast · AX5", traits: .sizeThatFitsLayout) { ToastGallery().previewVariant(.largestText) }
#endif
