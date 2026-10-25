import SwiftUI

/// Draws the compact chrome's pieces where `ChromeLayout` puts them. Animatable in the fold
/// (`ChromeState.progress`): while a finger scrolls, the host feeds it the smoothed progress
/// (`ChromeScroll.displayed`) and this body runs every frame, so every piece is the mockups' `mix(expanded, collapsed, progress)` and the
/// pill's lit segment travels into the screen icon. Anything else that changes (the keyboard, the
/// arrows, ▶) is a discrete step the host animates as the frames move.
///
/// A piece is in the tree only while `ChromePiece.isShown`.
struct ChromePieces: View, Animatable {
    @Environment(ShellState.self) private var shell
    var state: ChromeState
    let width: CGFloat
    let screen: ChromeScreen
    let card: ChromeCard?
    let readerTitle: String
    let play: ChromePlayButton?
    let hasReader: Bool
    let underColor: Color
    let focus: FocusState<Bool>.Binding
    let onSelect: (ChromeDestination) -> Void
    let onExpand: () -> Void

    var animatableData: CGFloat {
        get { state.progress }
        set { state.progress = newValue }
    }

    private typealias K = ChromeMetrics

    var body: some View {
        let layout = ChromeLayout(width: width, state: state)
        ZStack(alignment: .topLeading) {
            piece(layout.nav) {
                ChromeNavigation(showsForward: state.canGoForward, backID: screen.backID, forwardID: screen.forwardID,
                                 onBack: screen.onBack, onForward: screen.onForward)
            }
            fieldPiece(layout)
            piece(layout.play) { play }
            piece(layout.pill) {
                ChromePill(lit: state.destination, hasReader: hasReader, fold: layout.fold,
                           expandedWidth: layout.expandedPillWidth, onSelect: onSelect, onExpand: onExpand)
            }
            piece(layout.editBar) {
                screen.editBar.frame(maxHeight: .infinity).chromeSurface(Capsule())
            }
            piece(layout.more) { more }
        }
        .chromeGlassContainer()
        .frame(width: width, height: K.readerFootprint, alignment: .topLeading)
        .background(alignment: .bottom) {
            if let top = layout.top { ChromeFade(top: top, underColor: underColor) }
        }
        .overlay(alignment: .top) {
            if let top = layout.top {
                VStack(spacing: 0) {
                    PrepareProgressEdge()
                    ShellToastLayer()
                }
                .offset(y: top - K.topPadding)
            }
        }
    }

    // MARK: - Pieces

    /// `content` in `piece`'s rect. A piece that is not shown is not in the tree at all: inside the
    /// glass container an `opacity` above a piece's glass is ignored (the shape stays at full
    /// strength), so one that only faded would stay drawn. It comes and goes as the glass
    /// materializes in and out, with its content cross-fading (`ChromeHost` animates the step). The
    /// whole host's opacity, outside the container, does fade glass: that is the Reduce Motion dip.
    @ViewBuilder
    private func piece(_ piece: ChromePiece, @ViewBuilder _ content: () -> some View) -> some View {
        if piece.isShown {
            content()
                .frame(width: piece.rect.width, height: piece.rect.height)
                .offset(x: piece.rect.minX, y: piece.rect.minY)
                .transition(.opacity)
        }
    }

    /// The address, the search, or on the Reader the card that folds into the title chip. The first
    /// two draw their own capsule; the Reader's is this piece's glass, so one surface morphs.
    @ViewBuilder
    private func fieldPiece(_ layout: ChromeLayout) -> some View {
        let field = layout.field
        if state.destination == .reader {
            piece(field) {
                ZStack(alignment: .topLeading) {
                    if let card {
                        card.content
                            .frame(width: field.rect.width, height: K.card, alignment: .top)
                            .opacity(1 - ChromeMetrics.ramp(layout.fold, 0...0.3))
                            .allowsHitTesting(layout.fold < 0.3)
                    }
                    ChromeTitleChip(title: readerTitle, action: onExpand)
                        .frame(width: field.rect.width, height: K.barHeight)
                        .opacity(ChromeMetrics.ramp(layout.fold, 0.25...0.6))
                        .allowsHitTesting(layout.fold > 0.5)
                }
                .frame(width: field.rect.width, height: field.rect.height, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: field.radius, style: .continuous))
                .chromeSurface(RoundedRectangle(cornerRadius: field.radius, style: .continuous), interactive: false)
            }
        } else {
            piece(field) {
                screen.field(focus)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("bandField")
                    .environment(\.isChromeField, true)
                    .environment(\.chromeFieldWidth, field.rect.width)
                    .overlay {
                        if state.destination == .browse {
                            LoadProgressLine(web: shell.web).frame(maxHeight: .infinity, alignment: .bottom).clipShape(Capsule())
                        }
                    }
            }
        }
    }

    /// ⋯, or ✕ while a search is editing.
    @ViewBuilder
    private var more: some View {
        if state.keyboard {
            Button(action: screen.onCancel) { ChromeRoundLabel(symbol: Icons.close, label: Verbs.cancel) }
                .buttonStyle(.plain)
                .accessibilityLabel(Verbs.cancel)
                .accessibilityIdentifier(screen.cancelID)
        } else {
            screen.more
        }
    }
}
