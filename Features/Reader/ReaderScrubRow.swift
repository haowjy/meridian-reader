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

    /// Bubble label (nil at normal speed).
    var label: String? {
        switch self {
        case .normal: return nil
        case .half: return "Half-speed scrubbing"
        case .quarter: return "Quarter-speed scrubbing"
        case .fine: return "Fine scrubbing"
        }
    }
}

/// Reader bottom row above the listen controls: [scrubber][select paragraph][bookmark] (thumb
/// reach). The scrubber fills with progress and shows rendered audio as a lighter "buffered" fill
/// ahead of it. Dragging:
/// - grabbing the thumb moves it relative to the finger (no jump); touching elsewhere jumps there;
/// - sliding the finger up away from the track scrubs slower (½, ¼, fine) for small precise moves;
/// - it snaps to sentence starts: a haptic tick per sentence, the bubble shows the paragraph /
///   sentence and the sentence's first words, and release seeks to that sentence (not the
///   paragraph start); the text scrolls to the paragraph under the thumb (the only time the text
///   scrolls on its own).
/// The touch area covers the whole capsule height and its rounded leading end.
struct ReaderScrubRow: View {
    let map: ReaderScrubMap
    /// 0…1 current position.
    let position: Double
    /// Rendered-audio stretches (0…1), drawn lighter than the progress fill.
    var buffered: [ClosedRange<Double>] = []
    let isSaved: Bool
    let jumpMode: Bool
    let jumpEnabled: Bool
    var onToggleJump: () -> Void
    var onToggleSaved: () -> Void
    /// Paragraph under the thumb while dragging (nil when the drag ends).
    var onScrubPreview: (Int?) -> Void
    /// Release: the sentence to play from.
    var onScrubCommit: (ReaderScrubMap.Target) -> Void

    @State private var dragFraction: Double?
    @State private var anchor: (fraction: Double, x: CGFloat) = (0, 0)
    @State private var startY: CGFloat = 0
    @State private var grabbedThumb = false
    @State private var speed: ScrubSpeed = .normal
    @State private var lastTarget: ReaderScrubMap.Target?
    @State private var lastPreview: Int?
    @State private var haptics = UISelectionFeedbackGenerator()
    @State private var speedHaptics = UIImpactFeedbackGenerator(style: .light)

    /// Grab radius around the thumb (points): a touch this close drags the thumb, no jump.
    static let grabRadius: CGFloat = 26
    private static let space = "readerScrubTrack"

    var body: some View {
        // Styled exactly like the browser's address field: the same field capsule
        // (`bottomChromeField`), with Jump / bookmark sized and coloured like its mic button.
        HStack(spacing: 4) {
            scrubber
                .padding(.trailing, 4)

            Button(action: onToggleJump) {
                Image(systemName: jumpMode ? "hand.tap.fill" : "hand.tap")
                    .foregroundStyle(jumpMode ? Color.accentColor : Color.secondary)
                    .fieldControlFrame()
                    .background(Circle().fill(jumpMode ? Color.accentColor.opacity(0.15) : Color.clear))
            }
            .buttonStyle(.plain)
            .disabled(!jumpEnabled)
            .accessibilityIdentifier("listenJump")
            .accessibilityLabel(jumpMode ? "Cancel jump to paragraph" : "Jump to a paragraph")

            Button(action: onToggleSaved) {
                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                    .foregroundStyle(isSaved ? Color.accentColor : Color.secondary)
                    .fieldControlFrame()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("readerBookmark")
            .accessibilityLabel(isSaved ? "Remove from Saved" : "Save")
            .accessibilityValue(isSaved ? "Saved" : "Not saved")
        }
        .bottomChromeField(leading: 14, trailing: 4)
        .onAppear(perform: showDemoBubbleIfRequested)
    }

    /// Screenshot hook (`LaunchOptions.scrubBubbleDemo`): freeze a mid-drag frame (fine-scrubbing,
    /// thumb 40% in) so the bubble can be captured.
    private func showDemoBubbleIfRequested() {
        guard LaunchOptions.current.scrubBubbleDemo else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            speed = .quarter
            dragFraction = 0.42
        }
    }

    private var dragging: Bool { dragFraction != nil }

    private var scrubber: some View {
        GeometryReader { g in
            let w = max(1, g.size.width)
            let shown = min(max(0, dragFraction ?? position), 1)
            let thumb: CGFloat = dragging ? 20 : 12
            let track: CGFloat = dragging ? 6 : 4
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.22)).frame(height: track)
                ForEach(Array(buffered.enumerated()), id: \.offset) { _, span in
                    Capsule()
                        .fill(Color.accentColor.opacity(0.28))
                        .frame(width: max(track, w * (span.upperBound - span.lowerBound)), height: track)
                        .offset(x: w * span.lowerBound)
                }
                .accessibilityHidden(true)
                Capsule().fill(Color.accentColor).frame(width: w * shown, height: track)
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: thumb, height: thumb)
                    .shadow(color: .black.opacity(dragging ? 0.18 : 0), radius: 3, y: 1)
                    .offset(x: w * shown - thumb / 2)
            }
            .frame(width: w, height: g.size.height)
            .overlay(alignment: .bottomLeading) {
                if let f = dragFraction {
                    bubble(for: map.target(at: f))
                        .frame(width: w + 14, alignment: .leading)
                        .offset(x: -10, y: -(g.size.height + 10))
                        .allowsHitTesting(false)
                }
            }
            // Bigger touch target: the whole capsule height and its rounded leading end.
            .overlay {
                Color.clear
                    .contentShape(Rectangle())
                    .padding(.vertical, -6)
                    .padding(.leading, -14)
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                            .onChanged { v in scrub(v, width: w) }
                            .onEnded { v in endScrub(v, width: w) }
                    )
            }
            .coordinateSpace(name: Self.space)
        }
        .frame(height: BottomChrome.fieldControlSize)
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

    /// Paragraph · sentence · speed, then the sentence's first words.
    private func bubble(for t: ReaderScrubMap.Target) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text("¶ \(t.paragraph + 1) of \(map.paragraphCount)")
                if map.sentenceCount(paragraph: t.paragraph) > 1 {
                    Text("· sentence \(t.sentence + 1) of \(map.sentenceCount(paragraph: t.paragraph))")
                        .foregroundStyle(.secondary)
                }
                if let label = speed.label {
                    Text("· \(label)")
                        .foregroundStyle(Color.accentColor)
                        .accessibilityIdentifier("readerScrubSpeed")
                }
            }
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            Text(map.snippet(for: t))
                .font(.footnote)
                .lineLimit(2)
                .foregroundStyle(.primary)
                .accessibilityIdentifier("readerScrubSnippet")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("readerScrubBubble")
    }

    private func scrub(_ v: DragGesture.Value, width w: CGFloat) {
        if dragFraction == nil {
            haptics.prepare()
            speedHaptics.prepare()
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
        dragFraction = f
        // Tick at every sentence start crossed.
        let target = map.target(at: f)
        if let lastTarget, target != lastTarget {
            haptics.selectionChanged()
            haptics.prepare()
        }
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
