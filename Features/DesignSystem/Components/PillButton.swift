import SwiftUI

/// A labelled capsule button: a sheet's close pill ("‹ Browser", "⌄ Library") and Listen, a book's Continue. `Control.bar` tall (`Control.small` compact) at the default text size, growing with
/// Dynamic Type up to `Control.maxTextGrowth` like the rest of the band; a true capsule at every size.
///
/// A `detail` follows the title in regular weight, set apart by space rather than a separator:
/// *▶ **Listen**  9 min*, *▶ **Continue**  Ch 24*. When the pill is short of room (large text)
/// the detail is left out; VoiceOver still reads it. In an `ActionButtonRow` whose labels don't fit
/// (`.icon`) it draws its leading symbol alone on a round button.
struct PillButton<Leading: View>: View {
    enum Style {
        /// Accent fill: the main action on a screen (Listen, Continue).
        case filled
        /// Chrome fill, ink text: navigation (a sheet's close pill), secondary actions. On the
        /// player: its card fill and ink.
        case neutral
    }

    enum Size {
        case regular
        case compact

        var height: CGFloat {
            switch self {
            case .regular: Control.bar
            case .compact: Control.small
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
    /// How much of the label shows (`ActionButtonRow`).
    var fit: ActionLabelFit = .full
    let action: () -> Void
    @ViewBuilder var leading: Leading

    @ScaledMetric(relativeTo: .callout) private var scale: CGFloat = 1
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.readingPalette) private var reading

    var body: some View {
        let height = Control.grown(size.height * scale, from: size.height)
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
            .background(background, in: Capsule(style: .continuous))
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
        case .full:
            // Without room for both (large text), the title alone.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                    titleText(title)
                    if let detail {
                        Text(detail)
                            .typeStyle(.row)
                            .monospacedDigit()
                    }
                }
                titleText(title)
            }
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
        }
    }

    private var background: Color {
        switch style {
        case .filled: reading?.accent ?? Palette.accent
        case .neutral: BottomChrome.fieldFill(reading)
        }
    }
}

extension PillButton where Leading == PillSymbol {
    /// A pill with an SF Symbol before its title (nil: the title alone).
    init(_ title: String, detail: String? = nil, systemImage: String? = nil,
         style: Style = .filled, size: Size = .regular, expands: Bool = false, fit: ActionLabelFit = .full,
         action: @escaping () -> Void) {
        self.init(title: title, detail: detail, style: style, size: size, expands: expands, fit: fit, action: action) {
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
                .glyphSize(Glyph.small, weight: .semibold)
                .accessibilityHidden(true)
        }
    }
}

/// A sheet's *Done*, *Cancel* or *Save* in its navigation bar: a plain `Button` the system styles
/// (glass on iOS 26), so every sheet's buttons look like the system's. This type owns the
/// identifier and placement rule.
///
/// With a `systemImage` it is the system's close button, `title` its VoiceOver label: an input
/// sheet's ✕ (`InputSheet`).
///
/// ```
/// ( Cancel )            Edit Details             ( Save )
/// ( ✕ )                  Add a Link
/// ```
struct SheetBarButton: ToolbarContent {
    let placement: ToolbarItemPlacement
    let title: String
    /// The close button in place of the title (the symbol is the system's).
    var isClose = false
    let identifier: String
    var isDisabled = false
    let action: () -> Void

    init(_ title: String, isClose: Bool = false, placement: ToolbarItemPlacement, identifier: String,
         isDisabled: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isClose = isClose
        self.placement = placement
        self.identifier = identifier
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some ToolbarContent {
        ToolbarItem(placement: placement) {
            button
                .disabled(isDisabled)
                .accessibilityIdentifier(identifier)
        }
    }

    @ViewBuilder
    private var button: some View {
        if !isClose {
            Button(title, action: action)
        } else if #available(iOS 26.0, *) {
            Button(role: .close, action: action).accessibilityLabel(title)
        } else {
            Button(action: action) { Image(systemName: Icons.close) }.accessibilityLabel(title)
        }
    }
}

/// Pressed: the pill (or the transport disc) dims a little, like a system button.
struct PillPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? Palette.pressedOpacity : 1)
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
            PreviewState("disabled") {
                PillButton("Listen", systemImage: Icons.play) {}.disabled(true)
            }
        }
    }
}

#Preview("PillButton · light", traits: .sizeThatFitsLayout) { PillButtonGallery().previewVariant(.light) }
#Preview("PillButton · dark", traits: .sizeThatFitsLayout) { PillButtonGallery().previewVariant(.dark) }
#Preview("PillButton · AX5", traits: .sizeThatFitsLayout) { PillButtonGallery().previewVariant(.largestText) }

struct SheetBarButtonGallery: View {
    var body: some View {
        NavigationStack {
            List { Text("Rows") }
                .cardListStyle()
                .navigationTitle("Edit Details")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    SheetBarButton(Verbs.cancel, placement: .cancellationAction, identifier: "previewCancel") {}
                    SheetBarButton("Save", placement: .confirmationAction, identifier: "previewSave") {}
                }
        }
    }
}

/// The icon form, as an input sheet's ✕.
struct SheetBarIconGallery: View {
    var body: some View {
        NavigationStack {
            List { Text("Rows") }
                .cardListStyle()
                .navigationTitle("Add a Link")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    SheetBarButton(Verbs.cancel, isClose: true, placement: .cancellationAction,
                                   identifier: "previewClose") {}
                }
        }
    }
}

#Preview("SheetBarButton · light") { SheetBarButtonGallery().previewVariant(.light) }
#Preview("SheetBarButton · dark") { SheetBarButtonGallery().previewVariant(.dark) }
#Preview("SheetBarButton · AX5") { SheetBarButtonGallery().previewVariant(.largestText) }
#Preview("SheetBarButton icon · light") { SheetBarIconGallery().previewVariant(.light) }
#Preview("SheetBarButton icon · dark") { SheetBarIconGallery().previewVariant(.dark) }
#Preview("SheetBarButton icon · AX5") { SheetBarIconGallery().previewVariant(.largestText) }
#endif
