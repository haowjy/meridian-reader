import SwiftUI

/// Safari (iOS 26)–style ⋯ menu: the button grows into the menu panel instead of an arrow
/// popover floating above it. The panel is placed so its focus point (`morphMenuFocus`, the
/// bottom-right button's icon: Reader / Website) sits slightly up and to the left of the ⋯
/// glyph (Nav J — Safari's feel; measured ~12 pt left / 10 pt up from a Safari screenshot),
/// and it grows out of the ⋯. Without a focus point the panel's bottom-right corner sits on
/// the button's bottom-right corner. The rest of the screen dims; tap outside, swipe the
/// panel down, or Escape (VoiceOver two-finger scrub / hardware Esc) collapses it back into
/// the button.
///
/// The morph is an animatable progress, not a SwiftUI transition (a transition on a view nested in
/// the inserted container never runs, which silently turned the morph into a plain fade). The
/// overlay unmounts once it has collapsed.
///
/// Used by the browser toolbar ⋯ and the reader listen bar ⋯. The owner keeps `isPresented`,
/// reports the button's global frame as `anchor`, and fades its ⋯ glyph out while open (see
/// `morphMenuButtonHidden`) so the button reads as turning into the panel.
struct MorphMenuOverlay<Panel: View>: View {
    @Binding var isPresented: Bool
    /// The ⋯ button's frame in global coordinates.
    let anchor: CGRect
    /// How far the panel's bottom-right corner reaches past the button's bottom-right corner.
    var overhang: CGFloat = 0
    /// Focus icon offset from the ⋯ center: positive width = left, positive height = up (Nav J).
    var focusOffset: CGSize = MorphMenu.focusOffsetFromAnchor
    @ViewBuilder var panel: () -> Panel

    /// In the hierarchy (open, or still collapsing back into the button).
    @State private var mounted = false
    /// Drives the morph: false = button-sized (collapsed), true = full panel.
    @State private var expanded = false
    @State private var panelSize = CGSize(width: 300, height: 420)
    @State private var dragOffset: CGFloat = 0
    /// The focus icon's center in panel coordinates (unscaled).
    @State private var focus: CGPoint?

    static var cornerRadius: CGFloat { 28 }

    var body: some View {
        ZStack {
            if mounted {
                GeometryReader { geo in
                    let origin = geo.frame(in: .global).origin
                    let local = anchor == .zero
                        ? CGRect(x: geo.size.width - 60, y: geo.size.height - 60, width: 44, height: 44)
                        : anchor.offsetBy(dx: -origin.x, dy: -origin.y)
                    let edges = panelEdges(container: geo.size, button: local)
                    let trailing = edges.width
                    let bottom = edges.height

                    ZStack(alignment: .bottomTrailing) {
                        Color.black.opacity(expanded ? 0.16 : 0)
                            .contentShape(Rectangle())
                            .onTapGesture(perform: dismiss)
                            .accessibilityElement()
                            .accessibilityLabel("Close menu")
                            .accessibilityAddTraits(.isButton)
                            .accessibilityIdentifier("moreMenuDismiss")
                            .accessibilityAction(.default, dismiss)

                        panelView(buttonSize: local.size)
                            .padding(.trailing, trailing)
                            .padding(.bottom, bottom)
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
        .onChange(of: isPresented) { _, open in open ? present() : collapse() }
        .onAppear { if isPresented { present() } }
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
        return CGSize(width: max(8, container.width - button.maxX - overhang),
                      height: max(8, container.height - button.maxY - overhang))
    }

    private func panelView(buttonSize: CGSize) -> some View {
        let start = CGSize(
            width: min(1, max(0.08, buttonSize.width / max(1, panelSize.width))),
            height: min(1, max(0.05, buttonSize.height / max(1, panelSize.height)))
        )
        let anchor = focus.map { UnitPoint(x: $0.x / max(1, panelSize.width), y: $0.y / max(1, panelSize.height)) }
            ?? .bottomTrailing
        return panel()
            .coordinateSpace(name: MorphMenu.panelSpace)
            .onPreferenceChange(MorphMenuFocusKey.self) { focus = $0 }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                if size.width > 0, size.height > 0 { panelSize = size }
            }
            .overlay(alignment: .topLeading) {
                // UI tests: where the focus icon's center really ends up on screen.
                if MorphMenu.exposesFocus, let focus {
                    Color.clear
                        .frame(width: 2, height: 2)
                        .offset(x: focus.x - 1, y: focus.y - 1)
                        .allowsHitTesting(false)
                        .accessibilityElement()
                        .accessibilityLabel("Menu focus")
                        .accessibilityIdentifier("moreMenuFocus")
                }
            }
            .modifier(MorphPanelEffect(progress: expanded ? 1 : 0, startScale: start, anchor: anchor))
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
                withAnimation(MorphMenu.animation) { expanded = true }
            }
    }

    private func present() {
        dragOffset = 0
        if mounted {
            // Re-opened while collapsing: grow back from where it is.
            withAnimation(MorphMenu.animation) { expanded = true }
        } else {
            expanded = false
            mounted = true
        }
    }

    private func collapse() {
        guard mounted else { return }
        withAnimation(MorphMenu.animation) {
            expanded = false
        } completion: {
            if !isPresented { mounted = false }
        }
    }

    private var swipeDownToDismiss: some Gesture {
        DragGesture(minimumDistance: SwipeGesturePolicy.verticalMinimumDistance)
            .onChanged { value in
                dragOffset = SwipeGesturePolicy.verticalOffset(for: value.translation)
            }
            .onEnded { value in
                if SwipeGesturePolicy.shouldCommitVerticalDismiss(
                    translation: value.translation,
                    predicted: value.predictedEndTranslation
                ) {
                    dismiss()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { dragOffset = 0 }
                }
            }
    }

    private func dismiss() {
        isPresented = false
    }
}

enum MorphMenu {
    static let panelSpace = "morphMenuPanel"
    /// Nav J: Website / Reader icon sits this far left and up of the ⋯ (Safari's feel).
    /// Estimated from a Safari iOS 26 screenshot where All Tabs sits inset of the tabs/⋯ control
    /// rather than covering it dead-on.
    static let focusOffsetFromAnchor = CGSize(width: 12, height: 10)
    /// `-uiTesting`: expose the focus point as an accessibility element (alignment test).
    static let exposesFocus = ProcessInfo.processInfo.arguments.contains("-uiTesting")

    /// `-slowMenuAnimation` (UI tests) slows the morph so a mid-animation frame can be captured.
    static var animation: Animation {
        ProcessInfo.processInfo.arguments.contains("-slowMenuAnimation")
            ? .easeInOut(duration: 3)
            : .spring(response: 0.36, dampingFraction: 0.86)
    }
}

/// The morph, as one animatable progress (0 = the ⋯ button's size, 1 = the full panel). The panel
/// scales from the button's size with the bottom-right corners pinned, so it visibly grows out of
/// (and shrinks back into) the button; the glass shows at once and the rows fade / un-blur in
/// over the second half.
private struct MorphPanelEffect: ViewModifier, Animatable {
    var progress: CGFloat
    let startScale: CGSize
    var anchor: UnitPoint = .bottomTrailing

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let p = min(1, max(0, progress))
        let rows = Double(min(1, max(0, (p - 0.35) / 0.65)))
        return content
            .opacity(rows)
            .blur(radius: (1 - p) * 6)
            .background { MorphMenuPanelBackground() }
            .clipShape(RoundedRectangle(cornerRadius: MorphMenuOverlay<EmptyView>.cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.18 * Double(p)), radius: 28, y: 10)
            .scaleEffect(x: startScale.width + (1 - startScale.width) * p,
                         y: startScale.height + (1 - startScale.height) * p,
                         anchor: anchor)
            .opacity(Double(min(1, p * 5)))
    }
}

/// Light glass like Safari's menu panel (iOS 26); a thick material before that.
private struct MorphMenuPanelBackground: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: MorphMenuOverlay<EmptyView>.cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            shape
                .fill(Color(.systemBackground).opacity(0.55))
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
        opacity(hidden ? 0 : 1)
            .animation(MorphMenu.animation, value: hidden)
    }
}
