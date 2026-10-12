import SwiftUI

/// A labelled capsule button: the Reader's back pill ("‹ Browser") and Listen, a book's Continue,
/// Now Playing's "Jump to Audio". 48 pt tall (36 compact) at the default text size, growing with
/// Dynamic Type up to `BottomChrome.maxTextGrowth` like the rest of the band; radius `Radius.pill`.
///
/// A `detail` follows the title in regular weight, set apart by space rather than a separator:
/// *▶ **Listen**  9 min*, *▶ **Continue**  Ch 24*. When the pill is short of room (large text)
/// the detail is left out; VoiceOver still reads it.
struct PillButton<Leading: View>: View {
    enum Style {
        /// Accent fill: the main action on a screen (Listen, Continue).
        case filled
        /// Chrome fill, ink text: navigation (the back pill), secondary actions.
        case neutral
        /// Playing tint, accent text: the playing state of a filled pill.
        case tinted
        /// Ink fill, paper text: a floating pill over reading text (Jump to Audio).
        case inverted
    }

    enum Size {
        case regular
        case compact

        var height: CGFloat {
            switch self {
            case .regular: 48
            case .compact: 36
            }
        }
    }

    let title: String
    /// After the title, lighter: "9 min", "6 min left", "Ch 24".
    var detail: String?
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
                // Without room for both (large text), the title alone.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                        titleText
                        if let detail {
                            Text(detail)
                                .typeStyle(.row)
                                .monospacedDigit()
                        }
                    }
                    titleText
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(PillButton.accessibilityLabel(title: title, detail: detail))
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, Spacing.m)
            .frame(maxWidth: expands ? .infinity : nil, minHeight: BottomChrome.grown(size.height * scale, from: size.height))
            .background(background, in: RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            .opacity(isEnabled ? 1 : 0.4)
            .tapTarget(size.height)
        }
        .buttonStyle(PillPressStyle())
    }

    private var titleText: some View {
        Text(title).typeStyle(.row, weight: .semibold)
    }

    /// The title and detail as VoiceOver reads them: "Listen, 9 min".
    static func accessibilityLabel(title: String, detail: String?) -> String {
        detail.map { "\(title), \($0)" } ?? title
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
    init(_ title: String, detail: String? = nil, systemImage: String? = nil, style: Style = .filled,
         size: Size = .regular, expands: Bool = false, action: @escaping () -> Void) {
        self.init(title: title, detail: detail, style: style, size: size, expands: expands, action: action) {
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

/// Pressed: the pill (or the transport disc) dims a little, like a system button.
struct PillPressStyle: ButtonStyle {
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
                PillButton("Listen", detail: "9 min", systemImage: "play.fill", expands: true) {}
            }
            PreviewState("neutral · back pill") {
                PillButton("Browser", systemImage: "chevron.backward", style: .neutral) {}
            }
            PreviewState("tinted · playing") {
                PillButton("Playing", detail: "Ch 24", systemImage: "waveform", style: .tinted) {}
            }
            PreviewState("inverted compact · Jump to Audio") {
                PillButton("Jump to Audio", style: .inverted, size: .compact) {}
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
