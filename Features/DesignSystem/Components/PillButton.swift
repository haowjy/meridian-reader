import SwiftUI

/// A labelled capsule button: the Reader's back pill ("‹ Browser") and Listen, a book's Continue,
/// Now Playing's "Back to audio". 48 pt tall (36 compact) at the default text size, growing with
/// Dynamic Type so the label never clips; radius `Radius.pill`.
struct PillButton<Leading: View>: View {
    enum Style {
        /// Accent fill: the main action on a screen (Listen, Continue).
        case filled
        /// Chrome fill, ink text: navigation (the back pill), secondary actions.
        case neutral
        /// Playing tint, accent text: the playing state of a filled pill.
        case tinted
        /// Ink fill, paper text: a floating pill over reading text (Back to audio).
        case inverted
    }

    enum Size {
        case regular
        case compact

        var height: CGFloat {
            switch self {
            case .regular: Radius.pill * 2
            case .compact: 36
            }
        }
    }

    let title: String
    var style: Style = .filled
    var size: Size = .regular
    /// Stretches to the width it is offered (Listen between 🔖 and ⋯).
    var expands = false
    let action: () -> Void
    @ViewBuilder var leading: Leading

    @ScaledMetric(relativeTo: .callout) private var scale: CGFloat = 1
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                leading
                Text(title)
                    .typeStyle(.row, weight: .semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, Spacing.m)
            .frame(maxWidth: expands ? .infinity : nil, minHeight: size.height * max(1, scale))
            .background(background, in: RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            .opacity(isEnabled ? 1 : 0.4)
            .tapTarget(size.height)
        }
        .buttonStyle(PillPressStyle())
    }

    private var foreground: Color {
        switch style {
        case .filled: Palette.onAccent
        case .neutral: Palette.ink
        case .tinted: Palette.accent
        case .inverted: Palette.paper
        }
    }

    private var background: Color {
        switch style {
        case .filled: Palette.accent
        case .neutral: Palette.chrome
        case .tinted: Palette.playingTint
        case .inverted: Palette.ink
        }
    }
}

extension PillButton where Leading == PillSymbol {
    /// A pill with an SF Symbol before its title (nil: the title alone).
    init(_ title: String, systemImage: String? = nil, style: Style = .filled, size: Size = .regular,
         expands: Bool = false, action: @escaping () -> Void) {
        self.init(title: title, style: style, size: size, expands: expands, action: action) {
            PillSymbol(name: systemImage)
        }
    }
}

/// The optional glyph before a pill's title.
struct PillSymbol: View {
    let name: String?

    var body: some View {
        if let name {
            Image(systemName: name)
                .typeStyle(.row, weight: .semibold)
                .accessibilityHidden(true)
        }
    }
}

/// Pressed: the pill dims a little, like a system button.
private struct PillPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}

#if DEBUG
struct PillButtonGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("filled · Listen") {
                PillButton("Listen · 9 min", systemImage: "play.fill", expands: true) {}
            }
            PreviewState("neutral · back pill") {
                PillButton("Browser", systemImage: "chevron.backward", style: .neutral) {}
            }
            PreviewState("tinted · playing") {
                PillButton("Playing · Ch 24", systemImage: "waveform", style: .tinted) {}
            }
            PreviewState("inverted compact · Back to audio") {
                PillButton("Back to audio", systemImage: "arrow.down", style: .inverted, size: .compact) {}
            }
            PreviewState("disabled") {
                PillButton("Listen", systemImage: "play.fill") {}.disabled(true)
            }
        }
    }
}

#Preview("PillButton · light", traits: .sizeThatFitsLayout) { PillButtonGallery().previewVariant(.light) }
#Preview("PillButton · dark", traits: .sizeThatFitsLayout) { PillButtonGallery().previewVariant(.dark) }
#Preview("PillButton · AX5", traits: .sizeThatFitsLayout) { PillButtonGallery().previewVariant(.largestText) }
#endif
