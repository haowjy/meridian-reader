import SwiftUI

/// The row under a sheet's grabber, the same in the Reader and Now Playing (decision D24): the
/// close pill at the leading edge, a control at the trailing edge (☝︎, `JumpModeButton`), at the
/// page margin. Both sheets build their header from it, so the pill and ☝︎ sit at the same place
/// whichever sheet is up.
///
/// ```
/// ( ‹ Browser )                       (☝︎)    the Reader
/// ( ⌄ Pride and Prejudice )           (☝︎)    Now Playing
/// ```
struct SheetTopBar<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Spacing.s) {
            leading
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, Spacing.pageMargin)
        .padding(.bottom, Spacing.xs)
    }
}

/// The pill that closes the sheet it sits in, at a `SheetTopBar`'s leading edge:
/// - `.back("Browser")`: "‹ Browser", the Reader; it names what is underneath.
/// - `.collapse("Pride and Prejudice")`: "⌄ Pride and Prejudice", Now Playing; it names where
///   the page plays from and shrinks the sheet back into the bar.
struct SheetClosePill: View {
    enum Kind: Equatable {
        case back(String)
        case collapse(String)
    }

    let kind: Kind
    @Environment(\.dismissSheet) private var dismissSheet

    var body: some View {
        PillButton(title, systemImage: symbol, style: .neutral, size: .compact) { dismissSheet() }
            .accessibilityLabel(label)
            .accessibilityValue(value)
            .accessibilityIdentifier("readerClose")
    }

    private var title: String {
        switch kind {
        case .back(let title), .collapse(let title): title
        }
    }

    private var symbol: String {
        switch kind {
        case .back: Icons.back
        case .collapse: Icons.collapse
        }
    }

    private var label: String {
        switch kind {
        case .back(let title): String(localized: "Back to \(title)")
        case .collapse: String(localized: "Close Now Playing")
        }
    }

    private var value: String {
        switch kind {
        case .back: ""
        case .collapse(let from): String(localized: "Playing from \(from)")
        }
    }
}

/// ☝︎ Listen from a paragraph: on, the next tap on a paragraph plays from there. One round field
/// control (36 pt, 44 pt to tap) at the trailing end of both sheets' top bars, on the chrome fill
/// at rest and the accent wash while on; on the player it takes the player's palette.
struct JumpModeButton: View {
    let isOn: Bool
    let action: () -> Void

    @Environment(\.onPlayerPalette) private var onPlayer

    /// While on, on the player: its glyph on its wash (`ColorContrastTests` checks these).
    static let playerOnGlyph = Palette.playerAccent
    static let playerOnWash = Palette.playerAccentWash

    var body: some View {
        Button(action: action) {
            Image(systemName: isOn ? Icons.jumpOn : Icons.jump)
                .foregroundStyle(glyph)
                .roundFieldControl(fill: fill)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("listenJump")
        .accessibilityLabel(isOn ? "Cancel listen from a paragraph" : "Listen from a paragraph")
    }

    private var glyph: Color {
        switch (isOn, onPlayer) {
        case (true, true): Self.playerOnGlyph
        case (true, false): Palette.accent
        case (false, true): Palette.playerInk
        case (false, false): Palette.ink
        }
    }

    private var fill: Color {
        switch (isOn, onPlayer) {
        case (true, true): Self.playerOnWash
        case (true, false): Palette.playingTint
        case (false, _): BottomChrome.fieldFill(onPlayer: onPlayer)
        }
    }
}

#if DEBUG
struct SheetTopBarGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("the Reader") {
                SheetTopBar { SheetClosePill(kind: .back("Browser")) } trailing: { JumpModeButton(isOn: false) {} }
            }
            PreviewState("the Reader, ☝︎ on") {
                SheetTopBar { SheetClosePill(kind: .back("Library")) } trailing: { JumpModeButton(isOn: true) {} }
            }
            PreviewState("Now Playing") {
                SheetTopBar {
                    SheetClosePill(kind: .collapse("Pride and Prejudice"))
                } trailing: {
                    JumpModeButton(isOn: false) {}
                }
                .onPlayerPreview(Palette.playerBackground)
            }
            PreviewState("Now Playing, ☝︎ on, a long name") {
                SheetTopBar {
                    SheetClosePill(kind: .collapse("The Collected Letters of a Lighthouse Keeper"))
                } trailing: {
                    JumpModeButton(isOn: true) {}
                }
                .onPlayerPreview(Palette.playerBackground)
            }
        }
    }
}

#Preview("SheetTopBar · light", traits: .sizeThatFitsLayout) { SheetTopBarGallery().previewVariant(.light) }
#Preview("SheetTopBar · dark", traits: .sizeThatFitsLayout) { SheetTopBarGallery().previewVariant(.dark) }
#Preview("SheetTopBar · AX5", traits: .sizeThatFitsLayout) { SheetTopBarGallery().previewVariant(.largestText) }
#endif
