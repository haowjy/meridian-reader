import SwiftUI

/// The shared sheet: it rises over the surface underneath, carries a grabber, and closes with a
/// pull down on its header, a pull down on its scrolling body that begins with the body at its top
/// (`SheetPullHandoff`; one that begins mid-content only scrolls), or through `dismissSheet` from
/// inside (a back pill, ⌄). The body hands its pulls over itself: the reading web view does, and
/// any other scroll view through `handsPullToSheet(from:)`. While pulled it looks like a system
/// sheet (`PullDownLook`): it shrinks a little and the dim behind it lifts. Top corners
/// `Radius.card`. Used by Follow's chapter preview and, on regular width, the Reader and Now
/// Playing (compact width shows them in place: `ReadingInPlace`).
///
/// It is drawn in `palette` (the reading theme's colours for the Reader and Now Playing, the same
/// for both), which it sets on what it holds (`readingSurface`). A dark theme over a light app
/// gets a heavier dim behind it, so the strip above reads dark, and light status bar content.
///
/// With a `ReadingChrome` (the Reader and Now Playing on regular width) the text fills the sheet
/// as `ReadingBars` lays it out; full screen also hides the status bar, dims the home indicator
/// and paints the strip above the sheet in the page's colour. Without one (Follow's preview) the
/// header sits above the content and nothing hides.
///
/// Present it by inserting it (`if … { Sheet(…) }`); it animates its own rise and, once closed,
/// calls `onDismiss` for the owner to remove it. Under Reduce Motion it fades instead of moving.
/// With `sheetRisesOnAppear` off it starts already up (a sheet restored at launch, a still
/// render).
struct Sheet<Header: View, Content: View, Band: View, OverText: View>: View {
    let onDismiss: () -> Void
    let palette: ReadingPalette
    /// The reading sheets' bars and full screen; nil: the header above the content, no band.
    private let chrome: ReadingChrome?
    private let header: Header
    private let content: Content
    private let band: Band
    private let overText: OverText

    /// A reading sheet: the text under the header and `band`, `overText` floating over it.
    init(onDismiss: @escaping () -> Void, palette: ReadingPalette = .app, chrome: ReadingChrome,
         @ViewBuilder header: () -> Header, @ViewBuilder content: () -> Content, @ViewBuilder band: () -> Band,
         @ViewBuilder overText: () -> OverText) {
        self.onDismiss = onDismiss
        self.palette = palette
        self.chrome = chrome
        self.header = header()
        self.content = content()
        self.band = band()
        self.overText = overText()
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sheetRisesOnAppear) private var risesOnAppear
    @State private var risen = false
    @State private var closed = false
    @State private var pull: CGFloat = 0
    @State private var pullAxis: Axis?
    @State private var height: CGFloat = 0
    /// The status bar's height (the top safe area), for the player's status bar scrim.
    @State private var statusBarHeight: CGFloat = 0
    /// `onDismiss` has run (it runs once, whichever of the completion and its fallback is first).
    @State private var dismissed = false
    @State private var pullHandoff = SheetPullHandoff()

    var body: some View {
        let pullLook = PullDownLook(offset: pull, screenHeight: height, maxDim: maxDim)
        let isUp = risesOnAppear ? risen : !closed
        let fullScreen = isUp && chrome?.hidden == true
        let _ = wire(pullHandoff)
        ZStack(alignment: .bottom) {
            Palette.scrim.opacity(isUp ? pullLook.dim : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            if palette.isDark, isUp {
                // The status bar stays light until the sheet has gone, so the strip under it stays
                // as dark as at rest however far a finger holds the sheet down.
                Palette.scrim.opacity(pullLook.statusBarScrim)
                    .frame(height: statusBarHeight)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            if chrome != nil, isUp {
                // Full screen: the page runs up to the screen's top edge.
                palette.background
                    .frame(height: statusBarHeight + Self.topGap)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea()
                    .opacity(fullScreen ? 1 : 0)
                    .allowsHitTesting(false)
                    .animation(Motion.standard, value: fullScreen)
            }

            if isUp {
                Group {
                    if let chrome {
                        overlaidBars(chrome)
                    } else {
                        VStack(spacing: 0) {
                            headerBlock
                            content
                                .frame(maxHeight: .infinity, alignment: .top)
                                .environment(\.sheetPullHandoff, pullHandoff)
                        }
                    }
                }
                .background {
                    UnevenRoundedRectangle(topLeadingRadius: Radius.card, topTrailingRadius: Radius.card,
                                           style: .continuous)
                        .fill(palette.background)
                        .ignoresSafeArea(edges: .bottom)
                }
                .readingSurface(palette)
                .padding(.top, Self.topGap)
                .scaleEffect(pullLook.scale, anchor: .top)
                .offset(y: pull)
                .transition(.sheet(reduceMotion: reduceMotion))
                .environment(\.dismissSheet, SheetDismissAction(close))
                .accessibilityAction(.escape, close)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { statusBarHeight = $0 }
        .systemBars(lightStatusBar: palette.isDark && isUp, hidden: fullScreen)
        .onAppear {
            if risesOnAppear { withAnimation(Motion.standard) { risen = true } }
        }
    }

    /// The grabber and the header: pulled down, they pull the sheet.
    private var headerBlock: some View {
        VStack(spacing: 0) {
            SheetGrabber()
            header
        }
        .contentShape(Rectangle())
        .gesture(pullDown)
    }

    /// The reading sheet's layout: the text to the screen's foot, the header and the band over it.
    private func overlaidBars(_ chrome: ReadingChrome) -> some View {
        ReadingBars(chrome: chrome,
                    headerBackground: UnevenRoundedRectangle(topLeadingRadius: Radius.card, topTrailingRadius: Radius.card,
                                                             style: .continuous).fill(palette.background),
                    headerSlide: statusBarHeight + Self.topGap, header: headerBlock, content: content, band: band,
                    overText: overText)
            .environment(\.sheetPullHandoff, pullHandoff)
    }

    /// Follows a vertical pull (down freely, up with rubber-band resistance); released far enough
    /// or flung, it carries on off the screen at the finger's speed, then closes.
    private var pullDown: some Gesture {
        DragGesture(minimumDistance: SwipeGesturePolicy.verticalMinimumDistance, coordinateSpace: .global)
            .onChanged { value in
                let axis = pullAxis ?? SwipeGesturePolicy.axis(ofFirstMovement: value.translation)
                pullAxis = axis
                guard axis == .vertical else { return }
                pull = SwipeGesturePolicy.dismissOffset(forVerticalTranslation: value.translation.height)
            }
            .onEnded { value in
                let vertical = pullAxis == .vertical
                pullAxis = nil
                guard vertical else { return withAnimation(Motion.settle) { pull = 0 } }
                release(translation: value.translation.height, predicted: value.predictedEndTranslation.height,
                        velocity: value.velocity.height)
            }
    }

    /// The scrolling body's pull, handed over at its top: the same follow and release as the
    /// header's (`SheetPullHandoff`). The body only reports pulls down, so there's no rubber band.
    /// Rewired on each pass so the release sees this pass's values (Reduce Motion, `onDismiss`).
    private func wire(_ handoff: SheetPullHandoff) {
        handoff.changed = { offset in
            guard !dismissed, pullAxis == nil else { return }
            pull = offset
        }
        handoff.ended = { offset, velocity in
            guard !dismissed, pullAxis == nil else { return }
            release(translation: offset,
                    predicted: SwipeGesturePolicy.projectedTranslation(offset, velocity: velocity),
                    velocity: velocity)
        }
    }

    /// A vertical pull let go: far enough down or flung, the sheet carries on off the screen at
    /// the finger's speed and closes; otherwise it springs back.
    private func release(translation: CGFloat, predicted: CGFloat, velocity: CGFloat) {
        guard SwipeGesturePolicy.shouldCommitDownwardDismiss(translation: translation, predicted: predicted) else {
            withAnimation(Motion.settle) { pull = 0 }
            return
        }
        guard !reduceMotion, height > 0 else { return close() }
        withAnimation(Motion.dismiss(velocity: velocity, distance: height - pull)) {
            pull = height
        } completion: {
            finish()
        }
        finishAfterAnimation()
    }

    private func close() {
        withAnimation(Motion.standard) {
            risen = false
            closed = true
        } completion: {
            finish()
        }
        finishAfterAnimation()
    }

    /// An animation's completion doesn't always arrive (a transition-only change can end without
    /// one), and a sheet left half-dismissed keeps covering the screen. So the owner also hears
    /// it just after the animation's length.
    private func finishAfterAnimation() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Motion.standardResponse * 1.5) { finish() }
    }

    private func finish() {
        guard !dismissed else { return }
        dismissed = true
        onDismiss()
    }
}

extension Sheet where Band == EmptyView, OverText == EmptyView {
    /// A sheet with its header above its content (Follow's preview): no full screen.
    init(onDismiss: @escaping () -> Void, palette: ReadingPalette = .app, @ViewBuilder header: () -> Header,
         @ViewBuilder content: () -> Content) {
        self.onDismiss = onDismiss
        self.palette = palette
        chrome = nil
        self.header = header()
        self.content = content()
        band = EmptyView()
        overText = EmptyView()
    }
}

extension Sheet where Header == EmptyView, Band == EmptyView, OverText == EmptyView {
    init(onDismiss: @escaping () -> Void, palette: ReadingPalette = .app, @ViewBuilder content: () -> Content) {
        self.init(onDismiss: onDismiss, palette: palette, header: { EmptyView() }, content: content)
    }
}

extension Sheet {
    /// The gap between the status bar and the sheet's top edge; in full screen the page's colour
    /// fills it with the status bar's strip.
    static var topGap: CGFloat { Spacing.xs }

    /// The dim behind the sheet at rest. A dark theme's is heavier: the strip above it carries
    /// light status bar content, so it has to read dark over a light surface.
    static func maxDim(_ palette: ReadingPalette) -> Double {
        palette.isDark ? 0.7 : PullDownLook.maxDim
    }

    private var maxDim: Double { Self.maxDim(palette) }
}

/// The bar at the top of a sheet that says it can be pulled down.
struct SheetGrabber: View {
    @Environment(\.readingPalette) private var reading

    var body: some View {
        Capsule()
            .fill((reading?.secondaryInk ?? Palette.secondaryInk).opacity(0.35))
            .frame(width: 36, height: 5)
            .padding(.top, Spacing.xs)
            .padding(.bottom, Spacing.xxs)
            .accessibilityHidden(true)
    }
}

/// Closes the sheet it is read in (animated, then the sheet's `onDismiss`).
struct SheetDismissAction {
    private let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }

    func callAsFunction() {
        action()
    }
}

extension EnvironmentValues {
    /// Inside a `Sheet`: closes it. Outside one: does nothing.
    @Entry var dismissSheet = SheetDismissAction {}
    /// Whether a `Sheet` animates up when it appears (on) or starts up (off).
    @Entry var sheetRisesOnAppear = true
}

/// How a sheet looks while it is pulled down: like a system sheet, it shrinks a little (to 96%,
/// over the first third of the screen) and the dim behind it lifts as it goes from `maxDim` (the
/// sheet's at rest), reaching nothing once the sheet is off the screen. A sheet with light status
/// bar content (the player) keeps the strip under the status bar at `maxDim` all the way: a scrim
/// there (`statusBarScrim`) makes up what the dim has lifted.
struct PullDownLook: Equatable {
    var scale: CGFloat
    var dim: Double
    /// Black over the status bar strip, on top of `dim`, that keeps the strip at `maxDim`: none at
    /// rest, `maxDim` once the dim has gone.
    var statusBarScrim: Double

    static let minScale: CGFloat = 0.96
    static let maxDim = 0.2

    init(offset: CGFloat, screenHeight: CGFloat, maxDim: Double = Self.maxDim) {
        guard screenHeight > 0, offset > 0 else {
            self.init(scale: 1, dim: maxDim, maxDim: maxDim)
            return
        }
        let progress = min(1, offset / screenHeight)
        self.init(scale: 1 - (1 - Self.minScale) * min(1, progress * 3),
                  dim: maxDim * Double(1 - progress), maxDim: maxDim)
    }

    private init(scale: CGFloat, dim: Double, maxDim: Double) {
        self.scale = scale
        self.dim = dim
        // Black at opacity s over black at opacity d lets through (1 - d)(1 - s) of the surface.
        statusBarScrim = dim < maxDim ? 1 - (1 - maxDim) / (1 - dim) : 0
    }
}

#if DEBUG
struct SheetGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("resting") {
                SheetPreviewFrame(pull: 0)
            }
            PreviewState("pulled a third of the way") {
                SheetPreviewFrame(pull: 120)
            }
        }
    }
}

/// A still sheet over a stand-in surface, at a given pull (`Sheet` itself animates in on appear,
/// which a still render can't show).
private struct SheetPreviewFrame: View {
    let pull: CGFloat
    private let height: CGFloat = 360

    var body: some View {
        let look = PullDownLook(offset: pull, screenHeight: height)
        ZStack(alignment: .top) {
            Palette.chrome
            Palette.scrim.opacity(look.dim)
            VStack(spacing: 0) {
                SheetGrabber()
                Text("Notes on Tides")
                    .typeStyle(.title)
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.pageMargin)
                Spacer(minLength: 0)
            }
            .background(Palette.paper, in: UnevenRoundedRectangle(topLeadingRadius: Radius.card,
                                                                  topTrailingRadius: Radius.card))
            .padding(.top, Spacing.xl)
            .scaleEffect(look.scale, anchor: .top)
            .offset(y: pull)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
    }
}

#Preview("Sheet · light", traits: .sizeThatFitsLayout) { SheetGallery().previewVariant(.light) }
#Preview("Sheet · dark", traits: .sizeThatFitsLayout) { SheetGallery().previewVariant(.dark) }
#Preview("Sheet · AX5", traits: .sizeThatFitsLayout) { SheetGallery().previewVariant(.largestText) }

#Preview("Sheet · live") {
    @Previewable @State var shown = true
    ZStack {
        Palette.chrome.ignoresSafeArea()
        Button("Show sheet") { shown = true }
        if shown {
            Sheet(onDismiss: { shown = false }) {
                Text("Pull the grabber down").padding(Spacing.pageMargin)
            }
        }
    }
}
#endif
