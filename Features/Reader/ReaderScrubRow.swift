import SwiftUI
import UIKit

/// Article position ↔ scrubber fraction. Each paragraph gets width ∝ its length, so the fill tracks
/// how much of the article has been read. Scrubbing snaps to **sentence starts** (Nav I): `ticks`
/// are the fractions where a sentence (or, with a chunk plan, a speech chunk) starts — the scrubber
/// ticks a light haptic at each one — and `target(at:)` is the sentence under the finger.
struct ReaderScrubMap: Equatable, Sendable {
    /// Cumulative weight before each paragraph.
    let starts: [Double]
    let total: Double
    /// Sorted fractions (0, 1] of sentence / chunk / paragraph starts (excluding the article start).
    let ticks: [Double]
    /// Paragraph texts (bubble snippet).
    let texts: [String]
    /// Per paragraph: UTF-16 offsets of its sentence starts (always starts with 0).
    let sentenceStarts: [[Int]]

    var paragraphCount: Int { starts.count }

    /// A scrub destination: the start of sentence `sentence` of `paragraph`, `offset` UTF-16 units
    /// into the paragraph.
    struct Target: Equatable, Sendable {
        var paragraph: Int
        var sentence: Int
        var offset: Int
    }

    init(paragraphs: [String], chunkPlan: ((String) -> [String]?)? = nil, sentences: Bool = true) {
        var starts: [Double] = []
        var weights: [Double] = []
        var acc = 0.0
        for p in paragraphs {
            starts.append(acc)
            let w = Double(max(1, p.utf16.count))
            weights.append(w)
            acc += w
        }
        let total = max(acc, 1)
        var ticks: [Double] = []
        var sentenceStarts: [[Int]] = []
        for (i, p) in paragraphs.enumerated() {
            if i > 0 { ticks.append(starts[i] / total) }
            let sentenceOffsets = sentences ? SentenceStarts.offsets(in: p) : [0]
            sentenceStarts.append(sentenceOffsets)
            for offset in sentenceOffsets.dropFirst() {
                ticks.append((starts[i] + Double(offset)) / total)
            }
            guard let chunks = chunkPlan?(p), chunks.count > 1 else { continue }
            let lens = chunks.map { Double(max(1, $0.utf16.count)) }
            let sum = lens.reduce(0, +)
            var run = 0.0
            for len in lens.dropLast() {
                run += len
                ticks.append((starts[i] + weights[i] * run / sum) / total)
            }
        }
        self.starts = starts
        self.total = total
        var seen = Set<Double>()
        self.ticks = ticks.sorted().filter { seen.insert($0).inserted }
        self.texts = paragraphs
        self.sentenceStarts = sentenceStarts
    }

    func sentenceCount(paragraph: Int) -> Int {
        sentenceStarts.indices.contains(paragraph) ? sentenceStarts[paragraph].count : 1
    }

    /// The sentence containing `offset` (UTF-16, paragraph-relative) of `paragraph`.
    func target(paragraph: Int, offset: Int) -> Target {
        guard !starts.isEmpty else { return Target(paragraph: 0, sentence: 0, offset: 0) }
        let p = min(max(0, paragraph), starts.count - 1)
        let sentences = sentenceStarts.indices.contains(p) ? sentenceStarts[p] : [0]
        let s = sentences.lastIndex { $0 <= offset } ?? 0
        return Target(paragraph: p, sentence: s, offset: sentences[s])
    }

    /// The sentence under `fraction` (its start: releasing mid-sentence plays that sentence).
    func target(at fraction: Double) -> Target {
        guard !starts.isEmpty else { return Target(paragraph: 0, sentence: 0, offset: 0) }
        let p = paragraph(at: fraction)
        let x = min(max(0, fraction), 1) * total - starts[p]
        return target(paragraph: p, offset: Int(x.rounded(.down)))
    }

    /// Fraction of a target's sentence start.
    func fraction(of target: Target) -> Double {
        guard !starts.isEmpty else { return 0 }
        let p = min(max(0, target.paragraph), starts.count - 1)
        return (starts[p] + Double(max(0, target.offset))) / total
    }

    /// Fraction at paragraph offset `offset` (UTF-16) of `paragraph`.
    func fraction(paragraph: Int, offset: Int) -> Double {
        guard !starts.isEmpty else { return 0 }
        let p = min(max(0, paragraph), starts.count - 1)
        let len = texts.indices.contains(p) ? texts[p].utf16.count : 0
        let within = len > 0 ? Double(min(max(0, offset), len)) / Double(len) : 0
        return fraction(paragraph: p, within: min(within, 0.999))
    }

    /// First words of the target's sentence (the drag bubble).
    func snippet(for target: Target, maxLength: Int = 90) -> String {
        guard texts.indices.contains(target.paragraph) else { return "" }
        let text = texts[target.paragraph] as NSString
        let sentences = sentenceStarts[target.paragraph]
        let end = target.sentence + 1 < sentences.count ? sentences[target.sentence + 1] : text.length
        let start = min(max(0, target.offset), text.length)
        var sentence = text.substring(with: NSRange(location: start, length: max(0, min(end, text.length) - start)))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if sentence.count > maxLength {
            let cut = sentence.prefix(maxLength)
            let trimmed = cut.lastIndex(of: " ").map { String(cut[..<$0]) } ?? String(cut)
            sentence = trimmed + "…"
        }
        return sentence
    }

    /// Fraction at `paragraph` plus `within` (0…1) of it.
    func fraction(paragraph: Int, within: Double = 0) -> Double {
        guard !starts.isEmpty else { return 0 }
        let p = min(max(0, paragraph), starts.count - 1)
        let end = p + 1 < starts.count ? starts[p + 1] : total
        let w = min(max(0, within), 1)
        return (starts[p] + (end - starts[p]) * w) / total
    }

    /// Paragraph under `fraction`.
    func paragraph(at fraction: Double) -> Int {
        guard !starts.isEmpty else { return 0 }
        let x = min(max(0, fraction), 1) * total
        var lo = 0, hi = starts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if starts[mid] <= x { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    /// Scrubber stretches covered by `paragraphs` (adjacent paragraphs merge into one span).
    func spans(covering paragraphs: Set<Int>) -> [ClosedRange<Double>] {
        var result: [ClosedRange<Double>] = []
        var runStart: Int?
        for i in 0...starts.count where i < starts.count || runStart != nil {
            let inSet = i < starts.count && paragraphs.contains(i)
            if inSet, runStart == nil { runStart = i }
            if !inSet, let s = runStart {
                result.append(fraction(paragraph: s)...fraction(paragraph: i - 1, within: 1))
                runStart = nil
            }
        }
        return result
    }

    /// How many ticks lie at or before `fraction` (changes by one per boundary crossed).
    func tickIndex(at fraction: Double) -> Int {
        var lo = 0, hi = ticks.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if ticks[mid] <= fraction { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }
}

/// Scrub speed by how far the finger has moved vertically away from the track (Nav I), like
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
/// ahead of it. Dragging (Nav I):
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
        // Styled exactly like the browser's address field (Nav G): the same field capsule
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

    /// Screenshot hook (`-uiTesting -scrubBubbleDemo`): freeze a mid-drag frame (fine-scrubbing,
    /// thumb 40% in) so the bubble can be captured.
    private func showDemoBubbleIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-uiTesting"), args.contains("-scrubBubbleDemo") else { return }
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
        .animation(.easeOut(duration: 0.12), value: dragging)
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
