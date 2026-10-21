import SwiftUI
import UIKit

/// Scrub speed by how far the finger has moved vertically away from the track, like
/// the Music / Podcasts scrubbers: the further up, the finer — for precise small moves back.
enum ScrubSpeed: Equatable, CaseIterable {
    case normal, half, quarter, fine

    /// Vertical distance (points) where each finer tier begins.
    static let thresholds: [CGFloat] = [50, 110, 170]

    init(verticalDistance d: CGFloat) {
        let d = abs(d)
        if d < Self.thresholds[0] { self = .normal }
        else if d < Self.thresholds[1] { self = .half }
        else if d < Self.thresholds[2] { self = .quarter }
        else { self = .fine }
    }

    /// Thumb movement per finger movement.
    var multiplier: Double {
        switch self {
        case .normal: return 1
        case .half: return 0.5
        case .quarter: return 0.25
        case .fine: return 0.1
        }
    }

    /// Spoken name of the speed (nil at normal speed).
    var label: String? {
        switch self {
        case .normal: return nil
        case .half: return String(localized: "Half-speed scrubbing")
        case .quarter: return String(localized: "Quarter-speed scrubbing")
        case .fine: return String(localized: "Fine scrubbing")
        }
    }

    /// The bubble's speed chip (nil at normal speed).
    var chip: String? {
        switch self {
        case .normal: return nil
        case .half: return String(localized: "½×", comment: "The scrub bubble's chip at half speed")
        case .quarter: return String(localized: "¼×", comment: "The scrub bubble's chip at quarter speed")
        case .fine: return String(localized: "Fine", comment: "The scrub bubble's chip at fine speed")
        }
    }
}

/// A haptic for one scrubber movement. Ticks carry meaning instead of buzzing: a sentence or
/// paragraph boundary ticks only when that sentence / paragraph is at least `minSpacing` points
/// wide on screen at the current speed, so at normal speed long articles tick on paragraphs (or
/// not at all when those are dense too) and the finer speeds spread sentences out until each one
/// ticks. Reaching either end of the track gives a firmer tick.
enum ScrubTick: Equatable {
    /// Crossed into a sentence or paragraph (selection tick).
    case boundary
    /// Reached the start or the end of the article (rigid tick).
    case end

    static let minSpacing: CGFloat = 7

    /// The tick for the thumb moving from `old` to `new`. `pointsPerFraction` is the track width
    /// divided by the speed multiplier: how far the finger travels across the whole article.
    static func between(_ old: (fraction: Double, target: ReaderScrubMap.Target),
                        _ new: (fraction: Double, target: ReaderScrubMap.Target),
                        map: ReaderScrubMap, pointsPerFraction: CGFloat) -> ScrubTick? {
        if new.fraction != old.fraction, new.fraction <= 0 || new.fraction >= 1 { return .end }
        guard new.target != old.target else { return nil }
        let width = new.target.paragraph != old.target.paragraph
            ? map.paragraphWidth(new.target.paragraph)
            : map.sentenceWidth(new.target)
        return CGFloat(width) * pointsPerFraction >= minSpacing ? .boundary : nil
    }
}

/// Now Playing's row above the listen controls: [scrubber][trailing] in one field capsule, the
/// trailing control the speed (`SpeedButton`). The scrubber fills with progress and shows rendered audio as a lighter "buffered" fill
/// ahead of it. Dragging:
/// - grabbing the thumb moves it relative to the finger (no jump); touching elsewhere jumps there;
/// - sliding the finger up away from the track scrubs slower (½, ¼, fine) for small precise moves;
/// - it snaps to sentence starts: release seeks to the sentence under the thumb (not the
///   paragraph start), and haptics tick on sentences or paragraphs that are far enough apart to
///   feel (`ScrubTick`); the text scrolls to the paragraph under the thumb (the only time the
///   text scrolls on its own);
/// - a bubble rides above the finger showing the speed, paragraph / sentence and the sentence's
///   first words. The band around the row draws it across its full width
///   (`readerScrubBubble()`), so it never truncates and the thumb never covers it.
/// The touch area covers the whole capsule height and its rounded leading end.
struct ReaderScrubRow<Trailing: View>: View {
    let map: ReaderScrubMap
    /// 0…1 current position.
    let position: Double
    /// Rendered-audio stretches (0…1), drawn lighter than the progress fill.
    var buffered: [ClosedRange<Double>] = []
    /// Paragraph under the thumb while dragging (nil when the drag ends).
    var onScrubPreview: (Int?) -> Void
    /// Release: the sentence to play from.
    var onScrubCommit: (ReaderScrubMap.Target) -> Void
    /// At the capsule's trailing end, like the mic in the browser's address field.
    @ViewBuilder var trailing: Trailing
    /// When false the row renders without the field capsule wrapper, for use inside a player card.
    var isCapsule: Bool = true

    @State private var dragFraction: Double?
    @State private var anchor: (fraction: Double, x: CGFloat) = (0, 0)
    @State private var startY: CGFloat = 0
    @State private var grabbedThumb = false
    @State private var speed: ScrubSpeed = .normal
    @State private var lastTarget: ReaderScrubMap.Target?
    @State private var lastPreview: Int?
    /// The finger's height in the track's coordinates (negative = above it).
    @State private var fingerY: CGFloat = 0
    @State private var haptics = UISelectionFeedbackGenerator()
    @State private var speedHaptics = UIImpactFeedbackGenerator(style: .light)
    @State private var endHaptics = UIImpactFeedbackGenerator(style: .rigid)
    #if DEBUG
    @Environment(\.showsScrubBubbleDemo) private var showsDemoBubble
    #endif

    /// Grab radius around the thumb (points): a touch this close drags the thumb, no jump.
    static var grabRadius: CGFloat { 26 }
    /// Room before the track inside the capsule (its rounded end); the drag area reaches into it.
    /// Fixed geometry, not spacing: tap-to-seek positions depend on where the track starts.
    private static var fieldLeading: CGFloat { 14 }
    /// How far the drag area reaches above and below the track: the capsule's padding plus 2 pt.
    private static var dragOvershoot: CGFloat { BottomChrome.fieldVerticalPadding + 2 }
    private static var space: String { "readerScrubTrack" }

    var body: some View {
        if isCapsule {
            // Styled like the browser's address field: same field capsule, trailing control in a
            // field control's frame like the mic.
            rowContent
                .bottomChromeField(leading: Self.fieldLeading, trailing: Spacing.xxs)
                #if DEBUG
                .onAppear(perform: showDemoBubbleIfRequested)
                #endif
        } else {
            // Bare row for use inside a floating card (no capsule wrapper).
            rowContent
                #if DEBUG
                .onAppear(perform: showDemoBubbleIfRequested)
                #endif
        }
    }

    private var rowContent: some View {
        HStack(spacing: Spacing.xxs) {
            scrubber
                .padding(.trailing, Spacing.xxs)
            trailing
        }
    }

    #if DEBUG
    /// Screenshot hook (`showsScrubBubbleDemo`): freeze a mid-drag frame (fine-scrubbing, thumb
    /// 40% in) so the bubble can be captured.
    private func showDemoBubbleIfRequested() {
        guard showsDemoBubble else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            speed = .quarter
            fingerY = -120
            dragFraction = 0.42
        }
    }
    #endif

    private var dragging: Bool { dragFraction != nil }

    private var scrubber: some View {
        GeometryReader { g in
            let w = max(1, g.size.width)
            ScrubTrack(value: dragFraction ?? position, buffered: buffered, isDragging: dragging)
            .frame(width: w, height: g.size.height)
            // Bigger touch target: the whole capsule height and (for capsule mode) its rounded end.
            .overlay {
                Color.clear
                    .contentShape(Rectangle())
                    .padding(.vertical, -Self.dragOvershoot)
                    .padding(.leading, isCapsule ? -Self.fieldLeading : 0)
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                            .onChanged { v in scrub(v, width: w) }
                            .onEnded { v in endScrub(v, width: w) }
                    )
            }
            .coordinateSpace(name: Self.space)
        }
        .frame(height: BottomChrome.fieldControlSize)
        .anchorPreference(key: ReaderScrubBubble.Key.self, value: .bounds) { track in
            dragFraction.map { ReaderScrubBubble(map: map, target: map.target(at: $0), speed: speed,
                                                 track: track, fingerY: fingerY) }
        }
        .animation(Motion.snappy, value: dragging)
        .accessibilityElement()
        .accessibilityIdentifier("readerScrubber")
        .accessibilityLabel("Article position")
        .accessibilityValue("Paragraph \(map.paragraph(at: position) + 1) of \(map.paragraphCount)")
        .accessibilityAdjustableAction { direction in
            let p = map.paragraph(at: position)
            switch direction {
            case .increment: onScrubCommit(map.target(paragraph: min(p + 1, map.paragraphCount - 1), offset: 0))
            case .decrement: onScrubCommit(map.target(paragraph: max(p - 1, 0), offset: 0))
            @unknown default: break
            }
        }
    }

    private func scrub(_ v: DragGesture.Value, width w: CGFloat) {
        if dragFraction == nil {
            haptics.prepare()
            speedHaptics.prepare()
            endHaptics.prepare()
            let thumbX = w * CGFloat(min(max(0, position), 1))
            grabbedThumb = abs(v.startLocation.x - thumbX) <= Self.grabRadius
            // Grab the thumb: move relative to it. Elsewhere: jump to the finger.
            anchor = (grabbedThumb ? position : Double(v.startLocation.x / w), v.startLocation.x)
            startY = v.startLocation.y
            speed = .normal
            lastTarget = nil
        }
        let newSpeed = ScrubSpeed(verticalDistance: v.location.y - startY)
        if newSpeed != speed {
            // Re-anchor so changing speed never makes the thumb jump.
            anchor = (dragFraction ?? anchor.fraction, v.location.x)
            speed = newSpeed
            speedHaptics.impactOccurred(intensity: 0.5)
        }
        let f = min(max(0, anchor.fraction + Double((v.location.x - anchor.x) / w) * speed.multiplier), 1)
        let target = map.target(at: f)
        if let previous = dragFraction, let lastTarget {
            switch ScrubTick.between((previous, lastTarget), (f, target), map: map,
                                     pointsPerFraction: w / CGFloat(speed.multiplier)) {
            case .boundary:
                haptics.selectionChanged()
                haptics.prepare()
            case .end:
                endHaptics.impactOccurred()
                endHaptics.prepare()
            case nil:
                break
            }
        }
        dragFraction = f
        fingerY = v.location.y
        lastTarget = target
        if target.paragraph != lastPreview {
            lastPreview = target.paragraph
            onScrubPreview(target.paragraph)
        }
    }

    private func endScrub(_ v: DragGesture.Value, width w: CGFloat) {
        let moved = hypot(v.translation.width, v.translation.height)
        let f = dragFraction ?? Double(v.location.x / w)
        let tappedThumb = grabbedThumb && moved < 4
        dragFraction = nil
        lastTarget = nil
        lastPreview = nil
        grabbedThumb = false
        speed = .normal
        onScrubPreview(nil)
        // A tap on the thumb itself is not a seek (it would jump back to the sentence start).
        guard !tappedThumb else { return }
        onScrubCommit(map.target(at: f))
    }
}

/// The scrub bubble while dragging, handed up from `ReaderScrubRow` to the band that draws it.
struct ReaderScrubBubble {

    let map: ReaderScrubMap
    let target: ReaderScrubMap.Target
    let speed: ScrubSpeed
    /// The scrubber track's bounds.
    let track: Anchor<CGRect>
    /// The finger's height in the track's coordinates (negative = above it).
    let fingerY: CGFloat

    /// Gap between the bubble and the track (finger resting on the track).
    static let trackGap: CGFloat = 10
    /// Gap between the bubble and the finger once it slides up (clears the thumb).
    static let fingerGap: CGFloat = 44

    /// Where the bubble's bottom edge goes, in the coordinates `track` resolves to: just above
    /// the track, or above the finger once it slides up past that, so it rides with the finger.
    static func bottom(track: CGRect, fingerY: CGFloat) -> CGFloat {
        min(track.minY - trackGap, track.minY + fingerY - fingerGap)
    }

    struct Key: PreferenceKey {
        static var defaultValue: ReaderScrubBubble? { nil }
        static func reduce(value: inout ReaderScrubBubble?, nextValue: () -> ReaderScrubBubble?) {
            value = value ?? nextValue()
        }
    }
}

extension View {
    /// Draws the scrub bubble of a `ReaderScrubRow` inside this view across this view's full
    /// width (the reader's scrub band), above the finger.
    func readerScrubBubble() -> some View {
        overlayPreferenceValue(ReaderScrubBubble.Key.self, alignment: .topLeading) { bubble in
            if let bubble {
                GeometryReader { proxy in
                    ReaderScrubBubbleView(bubble: bubble)
                        // A zero-height frame aligned to the bottom: the bubble grows upward from
                        // `bottom`, whatever its height.
                        .frame(width: proxy.size.width, height: 0, alignment: .bottom)
                        .offset(y: ReaderScrubBubble.bottom(track: proxy[bubble.track], fingerY: bubble.fingerY))
                }
                .allowsHitTesting(false)
            }
        }
    }
}

/// Speed chip, then the paragraph and the sentence (spaced apart, the sentence in secondary ink)
/// over the sentence's first words, on the reading page's card. The text wraps rather than
/// truncating at large text sizes.
private struct ReaderScrubBubbleView: View {
    let bubble: ReaderScrubBubble

    @Environment(\.readingPalette) private var reading

    private var palette: ReadingPalette { reading ?? .app }

    var body: some View {
        let map = bubble.map
        let t = bubble.target
        HStack(alignment: .top, spacing: Spacing.xs) {
            if let chip = bubble.speed.chip {
                Text(chip)
                    .typeStyle(.caption, weight: .bold)
                    .foregroundStyle(palette.onAccent)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, Spacing.xxs)
                    .background(palette.accent, in: Capsule())
                    .accessibilityLabel(bubble.speed.label ?? chip)
                    .accessibilityIdentifier("readerScrubSpeed")
            }
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                header(t, map: map)
                    .typeStyle(.caption, weight: .semibold)
                    .foregroundStyle(palette.ink)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                Text(map.snippet(for: t))
                    .typeStyle(.caption)
                    .lineLimit(2)
                    .foregroundStyle(palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("readerScrubSnippet")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.xs)
        .background(palette.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(palette.hairline, lineWidth: 1))
        .shadow(color: Palette.scrim.opacity(0.12), radius: 8, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("readerScrubBubble")
    }

    private func header(_ t: ReaderScrubMap.Target, map: ReaderScrubMap) -> some View {
        let sentences = map.sentenceCount(paragraph: t.paragraph)
        return DetailLineLayout {
            Text("¶ \(t.paragraph + 1) of \(map.paragraphCount)")
            if sentences > 1 {
                Text("sentence \(t.sentence + 1) of \(sentences)").foregroundStyle(palette.secondaryInk)
            }
        }
    }
}

#if DEBUG
extension EnvironmentValues {
    /// The scrubber freezes a mid-drag frame for a screenshot (`-scrubBubbleDemo`, set by the
    /// launch).
    @Entry var showsScrubBubbleDemo = false
}
#endif
