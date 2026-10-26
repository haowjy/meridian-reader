import SwiftUI

/// The row under a sheet's grabber, the same in the Reader and Now Playing (decision D24): the
/// close pill at the leading edge, the controls at the trailing edge (Aa, `TextAppearanceButton`,
/// then ☝︎, `JumpModeButton`), at the page margin. Both sheets build their header from it, so the
/// pill, Aa and ☝︎ sit at the same place whichever sheet is up.
///
/// ```
/// ( ‹ Browser )                  (Aa) (☝︎)    the Reader
/// ( ⌄ Pride and Prejudice )      (Aa) (☝︎)    Now Playing
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
            .accessibilityIdentifier(identifier)
    }

    /// The Reader's and Now Playing's pills sit at the same place (D24) but are told apart: a
    /// Reader can stay under Now Playing.
    private var identifier: String {
        switch kind {
        case .back: "readerClose"
        case .collapse: "nowPlayingClose"
        }
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
/// control (36 pt, 44 pt to tap) at the trailing end of both sheets' top bars, on the card fill
/// at rest and the highlight while on, in the reading page's colours.
struct JumpModeButton: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        RoundIconButton(symbol: isOn ? Icons.jumpOn : Icons.jump,
                        label: isOn ? "Cancel listen from a paragraph" : "Listen from a paragraph",
                        identifier: "listenJump", isOn: isOn, action: action)
    }
}

#if DEBUG
struct SheetTopBarGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("the Reader") {
                SheetTopBar { SheetClosePill(kind: .back("Browser")) } trailing: {
                    TextAppearanceButton(isOpen: false) {}
                    JumpModeButton(isOn: false) {}
                }
            }
            PreviewState("the Reader, ☝︎ on") {
                SheetTopBar { SheetClosePill(kind: .back("Library")) } trailing: {
                    TextAppearanceButton(isOpen: false) {}
                    JumpModeButton(isOn: true) {}
                }
            }
            PreviewState("Now Playing, Sepia") {
                SheetTopBar {
                    SheetClosePill(kind: .collapse("Pride and Prejudice"))
                } trailing: {
                    TextAppearanceButton(isOpen: true) {}
                    JumpModeButton(isOn: false) {}
                }
                .onReadingPreview(.sepia)
            }
            PreviewState("Now Playing, Dark, ☝︎ on, a long name") {
                SheetTopBar {
                    SheetClosePill(kind: .collapse("The Collected Letters of a Lighthouse Keeper"))
                } trailing: {
                    TextAppearanceButton(isOpen: false) {}
                    JumpModeButton(isOn: true) {}
                }
                .onReadingPreview(.dark)
            }
        }
    }
}

#Preview("SheetTopBar · light", traits: .sizeThatFitsLayout) { SheetTopBarGallery().previewVariant(.light) }
#Preview("SheetTopBar · dark", traits: .sizeThatFitsLayout) { SheetTopBarGallery().previewVariant(.dark) }
#Preview("SheetTopBar · AX5", traits: .sizeThatFitsLayout) { SheetTopBarGallery().previewVariant(.largestText) }
#endif
