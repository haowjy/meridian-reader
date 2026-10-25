import SwiftUI

/// Safari (iOS 26)–style ⋯ menu: the button grows into the menu panel instead of an arrow
/// popover floating above it. The panel is placed so its focus point (`morphMenuFocus`, the
/// bottom-right button's icon) sits slightly up and to the left of the ⋯ glyph
/// (`MorphMenu.focusOffsetFromAnchor`, Safari's feel), and it grows out of the ⋯. Without a focus
/// point the panel's bottom-right corner sits on the button's bottom-right corner. The rest of the
/// screen dims; tap outside, swipe the panel down, or Escape (VoiceOver two-finger scrub /
/// hardware Esc) collapses it back into the button.
///
/// The morph is an animatable progress, not a SwiftUI transition: a transition on a view nested in
/// the inserted container never runs. The overlay unmounts once it has collapsed. Under Reduce
/// Motion the panel only cross-fades in place (no scale, no blur).
///
/// One overlay serves every ⋯ (browser toolbar, library toolbar, reader listen bar): the shell
/// keeps the open menu as `item` (nil = closed) and the button's global frame as `anchor`; the
/// button fades its glyph while open (`morphMenuButtonHidden`) so it reads as turning into the
/// panel. The panel keeps showing the last item while it collapses.
///
/// The panel gets a `MorphMenuClose`: rows close the menu through it and pass the action to run
/// once the panel has started collapsing, so whatever the action presents (a sheet, the library)
/// never competes with the open menu.
struct MorphMenuOverlay<Item, Panel: View>: View {
    @Binding var item: Item?
    /// The ⋯ button's frame in global coordinates.
    let anchor: CGRect
    /// How far the panel's bottom-right corner reaches past the button's bottom-right corner.
    var overhang: CGFloat = 0
    /// Focus icon offset from the ⋯ center: positive width = left, positive height = up.
    var focusOffset: CGSize = MorphMenu.focusOffsetFromAnchor
    /// The reading page's colours when the item was opened on it (the Reader, Now Playing): the
    /// panel is drawn in them. nil: the app's.
    var readingPalette: (Item) -> ReadingPalette? = { _ in nil }
    @ViewBuilder var panel: (Item, MorphMenuClose) -> Panel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.morphMenuAnimation) private var morphAnimation
    @Environment(\.morphMenuMarksFocus) private var marksFocus
    /// The item on screen: set while open and kept while collapsing back into the button
    /// (non-nil = in the hierarchy).
    @State private var shown: Item?
    /// Runs once the panel has started collapsing (see `MorphMenuClose`).
    @State private var afterClose: (() -> Void)?
    /// Drives the morph: false = button-sized (collapsed), true = full panel.
    @State private var expanded = false
    @State private var panelSize = CGSize(width: 300, height: 420)
    @State private var dragOffset: CGFloat = 0
    /// Axis of the panel drag in progress, fixed at its first movement (nil between drags).
    @State private var dragAxis: Axis?
    /// The next collapse's animation when a swipe-down closed the panel: seeded with the
    /// release speed, so a fling shrinks it faster (nil = the standard morph).
    @State private var flingCollapse: Animation?
    /// The focus icon's center in panel coordinates (unscaled).
    @State private var focus: CGPoint?
    /// The status bar's height, read where the safe area still applies (the panel's layer
    /// ignores it).
    @State private var statusBarHeight: CGFloat = 0

    private var isPresented: Bool { item != nil }

    var body: some View {
        ZStack {
            if let shown {
                GeometryReader { geo in
                    let origin = geo.frame(in: .global).origin
                    let local = anchor == .zero
                        ? CGRect(x: geo.size.width - 60, y: geo.size.height - 60, width: 44, height: 44)
                        : anchor.offsetBy(dx: -origin.x, dy: -origin.y)
                    let edges = panelEdges(container: geo.size, button: local)
                    let trailing = edges.width
                    let bottom = edges.height

                    ZStack(alignment: .bottomTrailing) {
                        Palette.scrim.opacity(expanded ? 0.16 : 0)
                            .contentShape(Rectangle())
                            .onTapGesture(perform: dismiss)
                            .accessibilityElement()
                            .accessibilityLabel("Close menu")
                            .accessibilityAddTraits(.isButton)
                            .accessibilityIdentifier("moreMenuDismiss")
                            .accessibilityAction(.default, dismiss)

                        panelView(shown, buttonSize: local.size)
                            .padding(.trailing, trailing)
                            .padding(.bottom, bottom)
                            // A panel taller than the room above the ⋯ stops below the status
                            // bar; its rows scroll (`MoreMenuPanel`).
                            .padding(.top, statusBarHeight + Spacing.xs)
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomTrailing)
                    .accessibilityElement(children: .contain)
                    .accessibilityAddTraits(.isModal)
                }
                .ignoresSafeArea()
                // Collapsing: let touches through to the page / button underneath.
                .allowsHitTesting(isPresented)
            }
        }
        .onChange(of: isPresented) { _, open in
            if open {
                present()
            } else {
                collapse()
                let next = afterClose
                afterClose = nil
                next?()
            }
        }
        .onAppear { if isPresented { present() } }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { statusBarHeight = $0 }
    }

    /// Trailing / bottom distance from the container's edges to the panel.
    private func panelEdges(container: CGSize, button: CGRect) -> CGSize {
        if let focus {
            // Focus icon center = ⋯ center nudged left + up (Safari; not dead-on overlap).
            let originX = button.midX - focusOffset.width - focus.x
            let originY = button.midY - focusOffset.height - focus.y
            return CGSize(width: max(0, container.width - originX - panelSize.width),
                          height: max(0, container.height - originY - panelSize.height))
        }
        return CGSize(width: max(Spacing.xs, container.width - button.maxX - overhang),
                      height: max(Spacing.xs, container.height - button.maxY - overhang))
    }

    private func panelView(_ shown: Item, buttonSize: CGSize) -> some View {
        let anchor = focus.map { UnitPoint(x: $0.x / max(1, panelSize.width), y: $0.y / max(1, panelSize.height)) }
            ?? .bottomTrailing
        let reading = readingPalette(shown)
        return panel(shown, MorphMenuClose { next in
            afterClose = next
            item = nil
        })
            .coordinateSpace(name: MorphMenu.panelSpace)
            .onPreferenceChange(MorphMenuFocusKey.self) { measured in
                if MorphMenu.isNewFocus(measured, comparedTo: focus) { focus = measured }
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                if size.width > 0, size.height > 0 { panelSize = size }
            }
            #if DEBUG
            .overlay(alignment: .topLeading) {
                // UI tests: where the focus icon's center really ends up on screen.
                if marksFocus, let focus {
                    Color.clear
                        .frame(width: 2, height: 2)
                        .offset(x: focus.x - 1, y: focus.y - 1)
                        .allowsHitTesting(false)
                        .accessibilityElement()
                        .accessibilityLabel("Menu focus")
                        .accessibilityIdentifier("moreMenuFocus")
                }
            }
            #endif
            .modifier(MorphPanelEffect(progress: expanded ? 1 : 0, button: reduceMotion ? nil : buttonSize,
                                       panelSize: panelSize, anchor: anchor, blurs: !reduceMotion))
            .offset(y: dragOffset)
            .simultaneousGesture(swipeDownToDismiss)
            // Hardware keyboard Esc.
            .background {
                Button("Close menu", action: dismiss)
                    .keyboardShortcut(.cancelAction)
                    .opacity(0)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Menu")
            .accessibilityIdentifier("moreMenuPanel")
            .accessibilityAction(.escape, dismiss)
            // First frame is button-sized; then grow.
            .onAppear {
                withAnimation(morphAnimation) { expanded = true }
            }
            .readingSurface(reading)
    }

    private func present() {
        dragOffset = 0
        dragAxis = nil
        let collapsing = shown != nil
        shown = item
        if collapsing {
            // Re-opened while collapsing: grow back from where it is.
            withAnimation(morphAnimation) { expanded = true }
        } else {
            expanded = false
        }
    }

    private func collapse() {
        let morph = flingCollapse ?? morphAnimation
        flingCollapse = nil
        guard shown != nil else { return }
        // Shrink back into the button from wherever a swipe left the panel.
        withAnimation(morphAnimation) { dragOffset = 0 }
        withAnimation(morph) {
            expanded = false
        } completion: {
            if !isPresented { shown = nil }
        }
    }

    /// The panel follows a vertical drag (down freely, up with rubber-band resistance); a
    /// horizontal one leaves it in place. Released far enough or flung down, it collapses at the
    /// release speed.
    private var swipeDownToDismiss: some Gesture {
        DragGesture(minimumDistance: SwipeGesturePolicy.verticalMinimumDistance)
            .onChanged { value in
                let axis = dragAxis ?? SwipeGesturePolicy.axis(ofFirstMovement: value.translation)
                dragAxis = axis
                guard axis == .vertical else { return }
                dragOffset = SwipeGesturePolicy.dismissOffset(forVerticalTranslation: value.translation.height)
            }
            .onEnded { value in
                let vertical = dragAxis == .vertical
                dragAxis = nil
                if vertical, SwipeGesturePolicy.shouldCommitDownwardDismiss(
                    translation: value.translation.height,
                    predicted: value.predictedEndTranslation.height
                ) {
                    if !reduceMotion {
                        flingCollapse = Motion.dismiss(velocity: value.velocity.height, distance: panelSize.height)
                    }
                    dismiss()
                } else {
                    withAnimation(Motion.settle) { dragOffset = 0 }
                }
            }
    }

    private func dismiss() {
        item = nil
    }
}

/// Closes the morph menu, then runs `then` once the panel has started collapsing.
struct MorphMenuClose {
    fileprivate let close: (@escaping () -> Void) -> Void

    func callAsFunction(then next: @escaping () -> Void = {}) {
        close(next)
    }
}

enum MorphMenu {
    static let panelSpace = "morphMenuPanel"
    /// The panel's glass. Deliberately rounder than `Radius.card`: it matches the system's menu
    /// glass, and the morph grows it out of the round ⋯ button.
    static let cornerRadius: CGFloat = 28
    /// The Website / Reader icon sits this far left and up of the ⋯ (Safari's feel). Measured
    /// from a Safari iOS 26 screenshot, where All Tabs sits inset of the tabs/⋯ control rather
    /// than covering it dead-on.
    static let focusOffsetFromAnchor = CGSize(width: 12, height: 10)
}

extension EnvironmentValues {
    /// The ⋯ panel's morph and its button's fade. A screenshot run slows it, so a frame mid-way
    /// can be captured.
    @Entry var morphMenuAnimation = Motion.standard
    /// The open ⋯ panel marks where its focus icon's center lands (`moreMenuFocus`), for the UI
    /// tests' geometry checks (Debug builds).
    @Entry var morphMenuMarksFocus = false
}

/// The morph, as one animatable progress (0 = the ⋯ button, 1 = the full panel). The glass is
/// drawn at an in-between frame and corner radius — from the button's (a circle) to the panel's,
/// pinned at `anchor` — so it grows out of (and shrinks back into) the button without ever being
/// stretched: the corners stay round and the glass refracts at its real size. The rows stay full
/// size, clipped to that shape, and fade / un-blur in over the second half. Under Reduce Motion
/// there is no `button`: the glass is panel-sized throughout and the whole panel only fades.
private struct MorphPanelEffect: ViewModifier, Animatable {
    var progress: CGFloat
    /// The ⋯ button's size: the glass at progress 0 (nil = no change of shape).
    let button: CGSize?
    let panelSize: CGSize
    var anchor: UnitPoint = .bottomTrailing
    var blurs = true

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let p = min(1, max(0, progress))
        let rows = Double(min(1, max(0, (p - 0.35) / 0.65)))
        let shape = MorphPanelShape(frame: MorphMenu.morphFrame(progress: p, button: button, panel: panelSize, anchor: anchor),
                                    cornerRadius: MorphMenu.morphCornerRadius(progress: p, button: button))
        return content
            .opacity(rows)
            .blur(radius: blurs ? (1 - p) * 6 : 0)
            .background { MorphMenuPanelBackground(shape: shape) }
            .clipShape(shape)
            .shadow(color: Palette.scrim.opacity(0.18 * Double(p)), radius: 28, y: 10)
            .opacity(Double(min(1, p * 5)))
    }
}

/// The panel's glass at one moment of the morph: a continuous rounded rectangle at `frame`
/// inside the panel's bounds.
private struct MorphPanelShape: Shape {
    var frame: CGRect
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).path(in: frame)
    }
}

extension MorphMenu {
    /// Whether a measured focus point is a real move rather than a rounding nudge. The panel is
    /// placed by its focus point, and pixel rounding of that placement moves the measured point
    /// by a fraction of a point; taking those nudges would place the panel again, and again,
    /// without end.
    static func isNewFocus(_ measured: CGPoint?, comparedTo current: CGPoint?) -> Bool {
        guard let measured, let current else { return measured != current }
        return abs(measured.x - current.x) >= 0.5 || abs(measured.y - current.y) >= 0.5
    }

    /// The glass's frame (panel coordinates) at `progress`: the button's size grown to the
    /// panel's, with `anchor` (the point it grows out of) kept in place. No `button`: the panel.
    static func morphFrame(progress p: CGFloat, button: CGSize?, panel: CGSize, anchor: UnitPoint) -> CGRect {
        guard let button, panel.width > 0, panel.height > 0 else { return CGRect(origin: .zero, size: panel) }
        let width = button.width + (panel.width - button.width) * p
        let height = button.height + (panel.height - button.height) * p
        return CGRect(x: anchor.x * (panel.width - width), y: anchor.y * (panel.height - height),
                      width: width, height: height)
    }

    /// The glass's corner radius at `progress`: the button's (round) to the panel's.
    static func morphCornerRadius(progress p: CGFloat, button: CGSize?) -> CGFloat {
        guard let button else { return cornerRadius }
        let round = min(button.width, button.height) / 2
        return round + (cornerRadius - round) * p
    }
}

/// Light glass like Safari's menu panel (iOS 26); a thick material before that. On a reading page
/// in a theme of its own it is a panel in the theme's card colour, as its other cards. A hairline
/// keeps its edge visible over dark paper.
private struct MorphMenuPanelBackground: View {
    let shape: MorphPanelShape

    @Environment(\.readingPalette) private var reading

    var body: some View {
        glass
            .overlay { shape.stroke(reading?.hairline ?? Palette.hairline, lineWidth: 1) }
    }

    @ViewBuilder
    private var glass: some View {
        if let reading, reading.theme != .matchApp {
            shape.fill(reading.card)
        } else if #available(iOS 26.0, *) {
            shape
                .fill(Palette.paper.opacity(0.55))
                .glassEffect(.regular, in: shape)
        } else {
            shape.fill(.thickMaterial)
        }
    }
}

/// The panel's focus point (see `morphMenuFocus`), in `MorphMenu.panelSpace` coordinates.
struct MorphMenuFocusKey: PreferenceKey {
    static let defaultValue: CGPoint? = nil
    static func reduce(value: inout CGPoint?, nextValue: () -> CGPoint?) {
        value = value ?? nextValue()
    }
}

extension View {
    /// Marks this view's center as the menu panel's focus point: the panel is placed so the
    /// icon sits slightly up and left of the ⋯ (see `MorphMenu.focusOffsetFromAnchor`), and the
    /// morph grows out of the ⋯.
    @ViewBuilder
    func morphMenuFocus(_ isFocus: Bool = true) -> some View {
        if isFocus {
            background {
                GeometryReader { g in
                    let f = g.frame(in: .named(MorphMenu.panelSpace))
                    Color.clear.preference(key: MorphMenuFocusKey.self, value: CGPoint(x: f.midX, y: f.midY))
                }
            }
        } else {
            self
        }
    }

    /// The ⋯ glyph fades while its panel is open, so the button reads as becoming the panel.
    func morphMenuButtonHidden(_ hidden: Bool) -> some View {
        modifier(MorphMenuButtonFade(hidden: hidden))
    }
}

private struct MorphMenuButtonFade: ViewModifier {
    let hidden: Bool
    @Environment(\.morphMenuAnimation) private var animation

    func body(content: Content) -> some View {
        content
            .opacity(hidden ? 0 : 1)
            .animation(animation, value: hidden)
    }
}

#if DEBUG
/// The morph at rest (the ⋯ button), half way, and open, over a stand-in panel.
struct MorphMenuGallery: View {
    private let panel = CGSize(width: 300, height: 236)
    private let button = CGSize(width: BottomChrome.minTapTarget, height: BottomChrome.minTapTarget)

    var body: some View {
        PreviewGallery {
            ForEach([("closed: the ⋯ button", 0.0), ("growing", 0.5), ("open", 1.0)], id: \.1) { name, p in
                PreviewState(name) {
                    MorphMenuSamplePanel()
                        .frame(width: panel.width, height: panel.height)
                        .modifier(MorphPanelEffect(progress: p, button: button, panelSize: panel,
                                                   anchor: UnitPoint(x: 0.85, y: 0.82)))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.xs)
                        .background(Palette.chrome, in: RoundedRectangle(cornerRadius: Radius.card))
                }
            }
        }
    }
}

private struct MorphMenuSamplePanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach([("Settings", Icons.settings), ("Share", Icons.share),
                     ("Reload", Icons.reload)], id: \.0) { title, icon in
                Label(title, systemImage: icon)
                    .typeStyle(.row)
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, Spacing.l)
                    .padding(.vertical, Spacing.s)
            }
            Divider().padding(.horizontal, Spacing.m)
            HStack {
                ForEach([("Settings", Icons.settings), ("Saved", Icons.library), ("Listen", Icons.listen)], id: \.0) { t, i in
                    VStack(spacing: Spacing.xs) {
                        Image(systemName: i).tileSymbol()
                        Text(t).typeStyle(.caption)
                    }
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.s)
                }
            }
            .padding(.horizontal, Spacing.xs)
        }
        .padding(.vertical, Spacing.xs)
    }
}

#Preview("MorphMenu · light", traits: .sizeThatFitsLayout) { MorphMenuGallery().previewVariant(.light) }
#Preview("MorphMenu · dark", traits: .sizeThatFitsLayout) { MorphMenuGallery().previewVariant(.dark) }
#Preview("MorphMenu · AX5", traits: .sizeThatFitsLayout) { MorphMenuGallery().previewVariant(.largestText) }
#endif
