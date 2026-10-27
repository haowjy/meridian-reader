import SwiftUI

/// A labelled capsule button: a sheet's close pill ("‹ Browser", "⌄ Library") and Listen, a book's Continue. 48 pt tall (36 compact) at the default text size, growing with
/// Dynamic Type up to `BottomChrome.maxTextGrowth` like the rest of the band; radius `Radius.pill`.
///
/// A `detail` follows the title in regular weight, set apart by space rather than a separator:
/// *▶ **Listen**  9 min*, *▶ **Continue**  Ch 24*. When the pill is short of room (large text)
/// the detail is left out; VoiceOver still reads it. In an `ActionButtonRow` it draws for the
/// row's `fit`: the short title alone, or (`.icon`) its leading symbol alone on a round button.
struct PillButton<Leading: View>: View {
    enum Style {
        /// Accent fill: the main action on a screen (Listen, Continue).
        case filled
        /// Chrome fill, ink text: navigation (a sheet's close pill), secondary actions. On the
        /// player: its card fill and ink.
        case neutral
        /// Playing tint, accent text: the playing state of a filled pill.
        case tinted
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
    /// The title when the row is short of room ("Start" for "From Start"); nil: the title.
    var shortTitle: String?
    /// How much of the label shows (`ActionButtonRow`).
    var fit: ActionLabelFit = .full
    let action: () -> Void
    @ViewBuilder var leading: Leading

    @ScaledMetric(relativeTo: .callout) private var scale: CGFloat = 1
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.readingPalette) private var reading

    var body: some View {
        let height = BottomChrome.grown(size.height * scale, from: size.height)
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                leading
                label
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(PillButton.accessibilityLabel(title: title, detail: detail))
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, fit == .icon ? 0 : Spacing.m)
            // Icon only: a circle the pill's height, or a capsule when it stretches.
            .frame(minWidth: fit == .icon ? height : nil, maxWidth: expands ? .infinity : nil, minHeight: height)
            .background(background, in: RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            .opacity(isEnabled ? 1 : Palette.disabledOpacity)
            .tapTarget(size.height)
        }
        .buttonStyle(PillPressStyle())
        .accessibilityLabel(PillButton.accessibilityLabel(title: title, detail: detail))
        .accessibilityShowsLargeContentViewer { Text(title) }
    }

    @ViewBuilder
    private var label: some View {
        switch fit {
        case .full, .short:
            let shown = fit == .full ? title : shortTitle ?? title
            // Without room for both (large text), the title alone.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                    titleText(shown)
                    if let detail {
                        Text(detail)
                            .typeStyle(.row)
                            .monospacedDigit()
                    }
                }
                titleText(shown)
            }
        case .titleOnly:
            titleText(shortTitle ?? title)
        case .icon:
            EmptyView()
        }
    }

    private func titleText(_ text: String) -> some View {
        Text(text).typeStyle(.row, weight: .semibold)
    }

    /// The title and detail as VoiceOver reads them: "Listen, 9 min".
    static func accessibilityLabel(title: String, detail: String?) -> String {
        detail.map { "\(title), \($0)" } ?? title
    }

    private var foreground: Color {
        switch style {
        case .filled: reading?.onAccent ?? Palette.onAccent
        case .neutral: reading?.ink ?? Palette.ink
        case .tinted: reading?.accent ?? Palette.accent
        }
    }

    private var background: Color {
        switch style {
        case .filled: reading?.accent ?? Palette.accent
        case .neutral: BottomChrome.fieldFill(reading)
        case .tinted: reading?.highlight ?? Palette.playingTint
        }
    }
}

extension PillButton where Leading == PillSymbol {
    /// A pill with an SF Symbol before its title (nil: the title alone).
    init(_ title: String, detail: String? = nil, shortTitle: String? = nil, systemImage: String? = nil,
         style: Style = .filled, size: Size = .regular, expands: Bool = false, fit: ActionLabelFit = .full,
         action: @escaping () -> Void) {
        self.init(title: title, detail: detail, style: style, size: size, expands: expands, shortTitle: shortTitle,
                  fit: fit, action: action) {
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
                PillButton("Listen", detail: "9 min", systemImage: Icons.play, expands: true) {}
            }
            PreviewState("neutral · back pill") {
                PillButton("Browser", systemImage: Icons.back, style: .neutral) {}
            }
            PreviewState("neutral on a dark reading page, close pill") {
                PillButton("Library", systemImage: Icons.collapse, style: .neutral, size: .compact) {}
                    .onReadingPreview()
            }
            PreviewState("tinted · playing") {
                PillButton("Playing", detail: "Ch 24", systemImage: Icons.playing, style: .tinted) {}
            }
            PreviewState("disabled") {
                PillButton("Listen", systemImage: Icons.play) {}.disabled(true)
            }
        }
    }
}

#Preview("PillButton · light", traits: .sizeThatFitsLayout) { PillButtonGallery().previewVariant(.light) }
#Preview("PillButton · dark", traits: .sizeThatFitsLayout) { PillButtonGallery().previewVariant(.dark) }
#Preview("PillButton · AX5", traits: .sizeThatFitsLayout) { PillButtonGallery().previewVariant(.largestText) }
#endif
