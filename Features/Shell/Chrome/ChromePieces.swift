import SwiftUI

/// Draws the compact chrome's pieces where `ChromeLayout` puts them. Animatable in the fold
/// (`ChromeState.progress`): while a finger scrolls, the host feeds it the smoothed progress
/// (`ChromeScroll.displayed`) and this body runs every frame, so the pieces shrink into the capsule
/// as the finger moves. Anything else that changes (the keyboard, the arrows, ▶) is a discrete
/// step the host animates as the frames move.
///
/// A piece is in the tree only while `ChromePiece.isShown`.
struct ChromePieces: View, Animatable {
    @Environment(ShellState.self) private var shell
    var state: ChromeState
    let width: CGFloat
    let screen: ChromeScreen
    let card: ChromeCard?
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
    /// The largest text the field, and the card draw: they sit in pieces of a fixed
    /// height, where larger text clips or overlaps. Every glyph still offers the large content viewer.
    private static let largestText = DynamicTypeSize.xxxLarge

    var body: some View {
        let layout = ChromeLayout(width: width, state: state)
        ZStack(alignment: .topLeading) {
            piece(layout.nav) {
                ChromeNavigation(showsBack: layout.navShowsBack, showsForward: layout.navShowsForward,
                                 canGoBack: state.canGoBack, canGoForward: state.canGoForward, backID: screen.backID, forwardID: screen.forwardID,
                                 onBack: screen.onBack, onForward: screen.onForward)
            }
            fieldPiece(layout)
            piece(layout.play) { play }
            piece(layout.pill) {
                ChromePill(lit: state.destination, hasReader: hasReader, expandedWidth: layout.expandedPillWidth, onSelect: onSelect)
            }
            piece(layout.editBar) {
                screen.editBar.frame(maxHeight: .infinity).chromeSurface(Capsule())
            }
            piece(layout.listen) { screen.listen }
            piece(layout.more) { more }
            capsulePiece(layout.capsule)
        }
        .chromeGlassContainer()
        .frame(width: width, height: K.readerFootprint, alignment: .topLeading)
        .background(alignment: .bottom) {
            if let top = layout.top { ChromeFade(top: top, underColor: underColor) }
        }
        .background(alignment: .bottom) {
            // While the rows are up, the whole footprint is the chrome's: a tap between the rows, beside
            // them, or in the home indicator's strip under them never reaches the page behind.
            if let top = layout.top, state.collapse < 0.5 {
                Color.clear
                    .contentShape(Rectangle())
                    .frame(height: K.readerFootprint - top + K.topPadding)
                    .ignoresSafeArea(.container, edges: .bottom)
                    .frame(height: K.readerFootprint, alignment: .bottom)
                    .onTapGesture {}
            }
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
                .frame(width: piece.fullWidth, height: piece.fullHeight)
                .scaleEffect(piece.scale, anchor: .topLeading)
                // Labels and glyphs go early, so what is left to converge on the capsule is bare glass.
                .opacity(K.ramp(piece.scale, 0.5...0.9))
                .frame(width: piece.rect.width, height: piece.rect.height, alignment: .topLeading)
                .offset(x: piece.rect.minX, y: piece.rect.minY)
                .transition(.opacity)
        }
    }

    /// The folded chrome: the page's name in a small capsule whose tap brings both rows back. Its
    /// hit area is `minTapTarget` tall, `capsuleHitOutset` past the capsule on every side, down to
    /// the safe area's edge.
    @ViewBuilder
    private func capsulePiece(_ piece: ChromePiece) -> some View {
        if piece.isShown {
            let outset = K.capsuleHitOutset, title = screen.capsuleTitle
            Button(action: onExpand) {
                // The title is laid out at the capsule's final width and clipped by the growing glass, so it
                // never reflows through "p…", "pa…" on its way.
                Text(title)
                    .font(.system(size: K.capsuleFontSize, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, K.capsuleSidePadding)
                    .frame(width: state.capsuleWidth)
                    .opacity(K.ramp(piece.rect.height, K.capsuleHeight * 0.7...K.capsuleHeight))
                    .frame(width: piece.rect.width, height: piece.rect.height)
                    .clipped()
                    .background(Palette.capsuleFill, in: Capsule())
                    .chromeSurface(Capsule())
                    .padding(outset)
                    .contentShape(Rectangle())
                    .chromeLargeContent(title, symbol: state.destination.symbol)
            }
            .buttonStyle(.plain)
            .frame(width: piece.rect.width + 2 * outset, height: piece.rect.height + 2 * outset)
            .offset(x: piece.rect.minX - outset, y: piece.rect.minY - outset)
            .accessibilityLabel(title)
            .accessibilityHint(String(localized: "Shows the bar"))
            .accessibilityIdentifier("chromeCapsule")
            .transition(.opacity)
        }
    }

    /// The address, the search, or on Listen the player card, which is its own glass (never folded).
    @ViewBuilder
    private func fieldPiece(_ layout: ChromeLayout) -> some View {
        let field = layout.field
        if state.destination == .reader {
            piece(field) {
                ZStack(alignment: .topLeading) {
                    if let card {
                        card.content
                            .frame(width: field.fullWidth, height: K.card, alignment: .top)
                    }
                }
                .frame(width: field.fullWidth, height: field.fullHeight, alignment: .topLeading)
                .dynamicTypeSize(...Self.largestText)
                .clipShape(RoundedRectangle(cornerRadius: field.radius, style: .continuous))
                .chromeSurface(RoundedRectangle(cornerRadius: field.radius, style: .continuous), interactive: false)
            }
        } else {
            piece(field) {
                screen.field(focus)
                    .dynamicTypeSize(...Self.largestText)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("bandField")
                    .environment(\.isChromeField, true)
                    .environment(\.chromeFieldWidth, field.fullWidth)
                    .overlay {
                        if state.destination == .browse {
                            LoadProgressLine(web: shell.web).frame(maxHeight: .infinity, alignment: .bottom).clipShape(Capsule())
                        }
                    }
            }
        }
    }

    /// ⋯, or the word Cancel while a search is editing (a text button in the accent, as Clear All is).
    @ViewBuilder
    private var more: some View {
        if state.keyboard {
            Button(action: screen.onCancel) {
                Text(Verbs.cancel)
                    .typeStyle(.row)
                    .foregroundStyle(Palette.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .dynamicTypeSize(...Self.largestText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .chromeLargeContent(Verbs.cancel, symbol: Icons.close)
            }
            .buttonStyle(.plain)
                .accessibilityLabel(Verbs.cancel)
                .accessibilityIdentifier(screen.cancelID)
        } else {
            screen.more
        }
    }
}
