import SwiftUI

/// A short message that floats over the bottom chrome and goes away by itself: "Nothing to
/// listen to on this page", "Added to Favorites" with *Change Folder*. Present it by inserting it; the
/// owner removes it after a few seconds (`Toast.duration`, longer with an action). Without an
/// action it takes no taps, so it never blocks what is under it.
struct Toast: View {
    let message: String
    var systemImage: String?
    /// A button after the message ("Change Folder").
    var actionTitle: String?
    var action: () -> Void = {}

    /// How long a toast stays up.
    static let duration: Duration = .seconds(2.5)
    /// How long a toast with an action stays up: long enough to reach for it.
    static let actionDuration: Duration = .seconds(5)

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(Palette.secondaryInk)
                    .accessibilityHidden(true)
            }
            Text(message)
                .typeStyle(.row)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("toast")
            if let actionTitle {
                Button(action: action) {
                    Text(actionTitle)
                        .typeStyle(.row, weight: .semibold)
                        .foregroundStyle(Palette.accent)
                        .frame(minHeight: BottomChrome.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("toastAction")
            }
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, actionTitle == nil ? Spacing.s : 0)
        .background(.regularMaterial, in: Capsule())
        .floatingShadow()
        .allowsHitTesting(actionTitle != nil)
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
struct ToastGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("message") {
                Toast(message: "Nothing to listen to on this page", systemImage: Icons.listen)
            }
            PreviewState("with an action") {
                Toast(message: "Added to Favorites", systemImage: Icons.favorited, actionTitle: "Change Folder")
            }
        }
    }
}

#Preview("Toast · light", traits: .sizeThatFitsLayout) { ToastGallery().previewVariant(.light) }
#Preview("Toast · dark", traits: .sizeThatFitsLayout) { ToastGallery().previewVariant(.dark) }
#Preview("Toast · AX5", traits: .sizeThatFitsLayout) { ToastGallery().previewVariant(.largestText) }
#endif
