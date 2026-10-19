import SwiftUI

/// A short message that floats over the bottom chrome and goes away by itself: "Nothing to
/// listen to on this page", "Downloading…" with *View*. Present it by inserting it; the
/// owner removes it after a few seconds (`Toast.duration`, longer with an action). Without an
/// action it takes no taps, so it never blocks what is under it.
///
/// A long message wraps at word boundaries (two lines at most text sizes), and the action stays
/// beside it while every word of the message still fits there; when one wouldn't (the largest
/// text sizes), the action goes under the message, and then the symbol goes, so no word is
/// broken while one could fit the toast. One line draws as a capsule; taller, its corners stay at
/// `Radius.pill`, as a pill button's do. Over the Reader and Now Playing it takes the reading
/// theme's card and inks, as everything floating on the reading page does.
struct Toast: View {
    let message: String
    var systemImage: String?
    /// A button after the message ("View").
    var actionTitle: String?
    var action: () -> Void = {}

    /// How long a toast stays up.
    static let duration: Duration = .seconds(2.5)
    /// How long a toast with an action stays up: long enough to reach for it.
    static let actionDuration: Duration = .seconds(5)

    @Environment(\.readingPalette) private var reading

    var body: some View {
        // The first that fits: the message's ideal width is its widest word (`WholeWordsText`),
        // so the action leaves the line, then the symbol goes, before a word would break.
        ViewThatFits(in: .horizontal) {
            if let actionTitle {
                HStack(spacing: Spacing.xs) {
                    messageLine(withSymbol: true)
                    actionButton(actionTitle)
                }
                VStack(spacing: 0) {
                    messageLine(withSymbol: true)
                    actionButton(actionTitle)
                }
                VStack(spacing: 0) {
                    messageLine(withSymbol: false)
                    actionButton(actionTitle)
                }
            } else {
                messageLine(withSymbol: true)
                messageLine(withSymbol: false)
            }
        }
        .padding(.horizontal, Spacing.m)
        .background { background }
        .floatingShadow()
        .allowsHitTesting(actionTitle != nil)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
        if let reading {
            shape.fill(reading.card)
        } else {
            shape.fill(.regularMaterial)
        }
    }

    private func messageLine(withSymbol: Bool) -> some View {
        HStack(spacing: Spacing.xs) {
            if withSymbol, let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(reading?.secondaryInk ?? Palette.secondaryInk)
                    .accessibilityHidden(true)
            }
            WholeWordsText(message)
                .accessibilityIdentifier("toast")
                .typeStyle(.row)
                .foregroundStyle(reading?.ink ?? Palette.ink)
                .multilineTextAlignment(.center)
                .padding(.vertical, Spacing.s)
        }
    }

    private func actionButton(_ title: String) -> some View {
        Button(action: action) {
            Text(title)
                .typeStyle(.row, weight: .semibold)
                .foregroundStyle(reading?.accent ?? Palette.accent)
                .frame(minHeight: BottomChrome.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("toastAction")
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
                Toast(message: "Downloading…", systemImage: Icons.download, actionTitle: "View")
            }
            PreviewState("a long message") {
                Toast(message: "New pages in “A Folder With a Longer Name” will download", systemImage: Icons.download)
            }
            PreviewState("a long message with an action") {
                Toast(message: "“A Folder With a Longer Name” is already downloading",
                      systemImage: Icons.download, actionTitle: "View")
            }
            PreviewState("on a reading page") {
                Toast(message: "Downloading…", systemImage: Icons.download, actionTitle: "View")
                    .onReadingPreview()
            }
        }
    }
}

#Preview("Toast · light", traits: .sizeThatFitsLayout) { ToastGallery().previewVariant(.light) }
#Preview("Toast · dark", traits: .sizeThatFitsLayout) { ToastGallery().previewVariant(.dark) }
#Preview("Toast · AX5", traits: .sizeThatFitsLayout) { ToastGallery().previewVariant(.largestText) }
#endif
