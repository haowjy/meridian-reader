import SwiftUI

/// The shared sheet: it rises over the surface underneath, carries a grabber, and closes with a
/// pull down on its header (never on its content, so scrolling and text selection stay free) or
/// through `dismissSheet` from inside (a back pill, ⌄). While pulled it looks like a system sheet
/// (`PullDownLook`): it shrinks a little and the dim behind it lifts. Top corners `Radius.card`.
/// Used by the Reader sheet, Now Playing, Move to… and Import.
///
/// Its `look` is paper, or the player (Now Playing): deep jade in light and dark, a heavier dim
/// behind it so the strip above reads dark, light status bar content, and the dark colour scheme
/// plus `onPlayerPalette` for what it holds.
///
/// Present it by inserting it (`if … { Sheet(…) }`); it animates its own rise and, once closed,
/// calls `onDismiss` for the owner to remove it. Under Reduce Motion it fades instead of moving.
/// With `sheetRisesOnAppear` off it starts already up (a sheet restored at launch, a still
/// render).
struct Sheet<Header: View, Content: View>: View {
    let onDismiss: () -> Void
    var look: SheetLook = .paper
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sheetRisesOnAppear) private var risesOnAppear
    @State private var risen = false
    @State private var closed = false
    @State private var pull: CGFloat = 0
    @State private var pullAxis: Axis?
    @State private var height: CGFloat = 0
    /// `onDismiss` has run (it runs once, whichever of the completion and its fallback is first).
    @State private var dismissed = false

    var body: some View {
        let pullLook = PullDownLook(offset: pull, screenHeight: height, maxDim: look.maxDim)
        let isUp = risesOnAppear ? risen : !closed
        ZStack(alignment: .bottom) {
            Color.black.opacity(isUp ? pullLook.dim : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            if isUp {
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        SheetGrabber()
                        header
                    }
                    .contentShape(Rectangle())
                    .gesture(pullDown)
                    content
                        .frame(maxHeight: .infinity, alignment: .top)
                }
                .background {
                    UnevenRoundedRectangle(topLeadingRadius: Radius.card, topTrailingRadius: Radius.card,
                                           style: .continuous)
                        .fill(look.background)
                        .ignoresSafeArea(edges: .bottom)
                }
                .modifier(SheetPalette(look: look))
                .padding(.top, Spacing.xs)
                .scaleEffect(pullLook.scale, anchor: .top)
                .offset(y: pull)
                .transition(.sheet(reduceMotion: reduceMotion))
                .environment(\.dismissSheet, SheetDismissAction(close))
                .accessibilityAction(.escape, close)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .lightStatusBar(look == .player && isUp)
        .onAppear {
            if risesOnAppear { withAnimation(Motion.standard) { risen = true } }
        }
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
                guard vertical, SwipeGesturePolicy.shouldCommitDownwardDismiss(
                    translation: value.translation.height, predicted: value.predictedEndTranslation.height
                ) else {
                    withAnimation(Motion.settle) { pull = 0 }
                    return
                }
                guard !reduceMotion, height > 0 else { return close() }
                withAnimation(Motion.dismiss(velocity: value.velocity.height, distance: height - pull)) {
                    pull = height
                } completion: {
                    finish()
                }
                finishAfterAnimation()
            }
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

extension Sheet where Header == EmptyView {
    init(onDismiss: @escaping () -> Void, look: SheetLook = .paper, @ViewBuilder content: () -> Content) {
        self.init(onDismiss: onDismiss, look: look, header: { EmptyView() }, content: content)
    }
}

/// A sheet's palette.
enum SheetLook: Equatable {
    /// Paper, following the appearance: the Reader, Move to…, Import.
    case paper
    /// Now Playing: deep jade in both appearances.
    case player

    var background: Color { self == .player ? Palette.playerBackground : Palette.paper }

    /// The dim behind the sheet at rest. The player's is heavier: the strip above it carries light
    /// status bar content, so it has to read dark over a light surface.
    var maxDim: Double { self == .player ? 0.7 : PullDownLook.maxDim }
}

/// What a player sheet holds draws on the player palette: the dark colour scheme for system
/// controls and materials, `onPlayerPalette` for the components that sit on both.
private struct SheetPalette: ViewModifier {
    let look: SheetLook
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .environment(\.colorScheme, look == .player ? .dark : colorScheme)
            .environment(\.onPlayerPalette, look == .player)
    }
}

/// The bar at the top of a sheet that says it can be pulled down.
struct SheetGrabber: View {
    @Environment(\.onPlayerPalette) private var onPlayer

    var body: some View {
        Capsule()
            .fill((onPlayer ? Palette.playerSecondaryInk : Palette.secondaryInk).opacity(0.35))
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
/// sheet's at rest), reaching nothing once the sheet is off the screen.
struct PullDownLook: Equatable {
    var scale: CGFloat
    var dim: Double

    static let minScale: CGFloat = 0.96
    static let maxDim = 0.2

    init(offset: CGFloat, screenHeight: CGFloat, maxDim: Double = Self.maxDim) {
        guard screenHeight > 0, offset > 0 else {
            self.init(scale: 1, dim: maxDim)
            return
        }
        let progress = min(1, offset / screenHeight)
        self.init(scale: 1 - (1 - Self.minScale) * min(1, progress * 3),
                  dim: maxDim * Double(1 - progress))
    }

    private init(scale: CGFloat, dim: Double) {
        self.scale = scale
        self.dim = dim
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
            Color.black.opacity(look.dim)
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
