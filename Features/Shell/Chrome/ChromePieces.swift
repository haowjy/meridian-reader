import SwiftUI

/// Draws the compact chrome's pieces where `ChromeLayout` puts them. Animatable in the fold
/// (`ChromeState.progress`): while a finger scrolls, the host feeds it the smoothed progress
/// (`ChromeScroll.displayed`) and this body runs every frame, so the pieces fold away
/// as the finger moves (one step, then the other). Anything else that changes (the keyboard, the arrows) is a discrete
/// step the host animates as the frames move.
///
/// A piece is in the tree only while `ChromePiece.isShown`.
struct ChromePieces: View, Animatable {
    @Environment(ShellState.self) private var shell
    @Environment(\.readingPalette) private var reading
    var state: ChromeState
    let width: CGFloat
    let screen: ChromeScreen
    let underColor: Color
    let focus: FocusState<Bool>.Binding
    let onSelect: (ChromeDestination) -> Void
    let onExpand: () -> Void

    var animatableData: CGFloat {
        get { state.progress }
        set { state.progress = newValue }
    }

    private typealias K = ChromeMetrics
    /// The largest text the field draws: it sits in a piece of a fixed
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
            piece(layout.pill) {
                ChromePill(lit: state.destination, onSelect: onSelect)
            }
            piece(layout.editBar) {
                screen.editBar.frame(maxHeight: .infinity).chromeSurface(Capsule())
            }
            piece(layout.listen) { ChromeListenButton() }
            piece(layout.cancel) { cancel }
            bubblePiece(layout)
        }
        .chromeGlassContainer()
        .frame(width: width, height: K.rowsHeight, alignment: .topLeading)
        .background(alignment: .bottom) {
            if let top = layout.top { ChromeFade(top: top, underColor: underColor) }
        }
        .background(alignment: .bottom) {
            // While a row is up, the whole box is the chrome's: a tap between the rows, beside
            // them, or in the home indicator's strip under them never reaches the page behind.
            if let top = layout.top, state.fold < 0.75 {
                Color.clear
                    .contentShape(Rectangle())
                    .frame(height: K.rowsHeight - top + Spacing.xxs)
                    .ignoresSafeArea(.container, edges: .bottom)
                    .frame(height: K.rowsHeight, alignment: .bottom)
                    .onTapGesture {}
            }
        }
        .overlay(alignment: .top) {
            if let top = layout.top {
                VStack(spacing: 0) {
                    PrepareProgressEdge()
                    ShellToastLayer()
                }
                .offset(y: top - Spacing.xxs)
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
                // Labels and glyphs go before their glass.
                .opacity(piece.opacity)
                .offset(x: piece.rect.minX, y: piece.rect.minY)
                .transition(.opacity)
        }
    }

    /// The folded chrome: a small glass capsule naming the page, the field shrunk (Safari's), whose tap
    /// brings both rows back. Its hit area is `bubbleHitOutset` past its glass above and below, `Control.tap` tall.
    @ViewBuilder
    private func bubblePiece(_ layout: ChromeLayout) -> some View {
        let piece = layout.bubble
        if piece.isShown {
            let outset = K.bubbleHitOutset, title = screen.bubbleTitle
            Button(action: onExpand) {
                // The name starts where the field's text was and glides to the centre (`ChromeLayout`).
                Text(title)
                    .font(.system(size: TypeStyle.caption.size, weight: .semibold))
                    .foregroundStyle(reading?.ink ?? Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: max(0, piece.rect.width - layout.bubbleTextX - Spacing.m), alignment: .leading)
                    .scaleEffect(layout.bubbleTextScale, anchor: .leading)
                    .opacity(piece.opacity)
                    .padding(.leading, layout.bubbleTextX)
                    .frame(width: piece.rect.width, height: piece.rect.height, alignment: .leading)
                    .chromeSurface(Capsule(), fill: BottomChrome.fieldFill(reading))
                    .padding(.vertical, outset)
                    .contentShape(Rectangle())
                    .chromeLargeContent(title, symbol: state.destination.symbol)
            }
            .buttonStyle(.plain)
            .frame(width: piece.rect.width, height: piece.rect.height + 2 * outset)
            .offset(x: piece.rect.minX, y: piece.rect.minY - outset)
            .accessibilityLabel(title)
            .accessibilityHint(String(localized: "Shows the controls"))
            .accessibilityIdentifier("chromeBubble")
            .transition(.opacity)
        }
    }

    /// The address or the search field.
    private func fieldPiece(_ layout: ChromeLayout) -> some View {
        let field = layout.field
        return piece(field) {
            screen.field(focus)
                .dynamicTypeSize(...Self.largestText)
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

    /// The word Cancel while a search is editing (a text button in the accent, as Clear All is).
    private var cancel: some View {
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
    }
}
