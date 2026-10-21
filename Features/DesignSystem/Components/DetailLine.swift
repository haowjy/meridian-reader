import SwiftUI

/// A secondary line made of separate parts: a row's site and time left, a book's author, kind and
/// chapter count, the scrubber's time played and left. The parts are set apart by space and ink,
/// never joined with a separator character:
///
/// ```
/// investing.example.com   9 min left        lead in secondary ink, the rest in tertiary
/// Jane Austen   Book   61 chapters
/// ```
///
/// The first part (the lead) is what gives way: it truncates when the rest need the room. The
/// other parts never truncate; when they would leave the lead less than a third of the line
/// (large text), the parts wrap onto further lines instead (`DetailLineLayout`). The caller sets
/// the font (`typeStyle`). VoiceOver reads the parts as one label, joined with commas.
struct DetailLine: View {
    let parts: [DetailPart]

    @Environment(\.readingPalette) private var reading
    /// `Spacing.s` at the default text size, growing with the caption it separates.
    @ScaledMetric(relativeTo: TypeStyle.caption.relativeTo) private var spacing = Spacing.s

    /// Empty and nil parts are left out.
    init(_ parts: [String?]) {
        self.init(parts: parts.compactMap { $0 }.map { DetailPart($0) })
    }

    /// Parts that may carry a symbol or a listening ring (`DetailPart.finished`); empty ones are
    /// left out.
    init(parts: [DetailPart]) {
        self.parts = parts.filter { !$0.text.isEmpty }
    }

    var body: some View {
        DetailLineLayout(spacing: spacing) {
            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                HStack(spacing: Spacing.xxs) {
                    if let ring = part.ring { ProgressRing(fraction: ring) }
                    if let symbol = part.symbol {
                        // The prepared ↓ takes the accent, as the Prepare control does (C97).
                        if symbol == Icons.prepared { Image(systemName: symbol).foregroundStyle(Palette.accent) }
                        else { Image(systemName: symbol) }
                    }
                    Text(part.text)
                }
                .foregroundStyle(index == 0 ? DetailLine.leadInk(reading) : DetailLine.restInk(reading))
                .lineLimit(index == 0 ? 1 : nil)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DetailLine.accessibilityLabel(parts.map { $0.spoken ?? $0.text }))
    }

    /// The lead part's ink.
    static func leadInk(_ reading: ReadingPalette?) -> Color { reading?.secondaryInk ?? Palette.secondaryInk }
    /// The ink of the parts after the lead.
    static func restInk(_ reading: ReadingPalette?) -> Color { reading?.tertiaryInk ?? Palette.tertiaryInk }

    /// The parts as VoiceOver reads them: "investing.example.com, 9 min left".
    static func accessibilityLabel(_ parts: [String?]) -> String {
        parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

/// One part of a `DetailLine`: its text, after a symbol or a listening ring when it has one.
struct DetailPart: Hashable, ExpressibleByStringLiteral {
    let text: String
    var symbol: String?
    /// A listening `ProgressRing` before the text, this full (0–1). Rings mean listening only.
    var ring: Double?
    /// What VoiceOver reads for it, when the symbol says something the text doesn't.
    var spoken: String?

    init(_ text: String, symbol: String? = nil, ring: Double? = nil, spoken: String? = nil) {
        self.text = text
        self.symbol = symbol
        self.ring = ring
        self.spoken = spoken
    }

    init(stringLiteral text: String) {
        self.init(text)
    }

    /// A page heard to its end: the listening ring, full, and "Finished", as a row's status draws
    /// it (no ✓: that is selection's only).
    static var finished: DetailPart { DetailPart(ListeningTime.finishedLabel, ring: 1) }

    /// `text` after the accent filled ↓ a prepared row starts its second line with (a page's, a
    /// download's, a voice model's in Settings).
    static func prepared(_ text: String) -> DetailPart {
        DetailPart(text, symbol: Icons.prepared, spoken: "\(Verbs.prepared), \(text)")
    }
}

/// The parts of a `DetailLine` (or a row's second line), side by side `spacing` apart on their
/// first text baseline. One line when they fit; one line with the first part truncated while it
/// keeps at least a third of the width; otherwise each part flows onto the next line when it
/// doesn't fit beside the one before (a part wider than the line gets the line's width).
struct DetailLineLayout: Layout {
    var spacing: CGFloat = Spacing.s

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for item in arrange(width: bounds.width, subviews: subviews).items {
            subviews[item.index].place(at: CGPoint(x: bounds.minX + item.origin.x, y: bounds.minY + item.origin.y),
                                       anchor: .topLeading,
                                       proposal: ProposedViewSize(width: item.width, height: nil))
        }
    }

    private struct Item {
        let index: Int
        var origin: CGPoint
        let width: CGFloat
    }

    private struct Arrangement {
        var items: [Item] = []
        var size: CGSize = .zero
    }

    private func arrange(width: CGFloat?, subviews: Subviews) -> Arrangement {
        guard !subviews.isEmpty else { return Arrangement() }
        let ideal = subviews.map { $0.sizeThatFits(.unspecified).width }
        let total = ideal.reduce(0, +) + spacing * CGFloat(subviews.count - 1)

        // Rows of (index, width): one row when everything fits or the lead can give way enough.
        var rows: [[(index: Int, width: CGFloat)]]
        // Half a point of slack: placed in exactly the width it asked for (centred), the bounds
        // can come back a rounding error narrower.
        if let width, total > width + 0.5 {
            let rest = total - ideal[0]
            let leadRoom = width - rest
            if subviews.count > 1, leadRoom >= min(ideal[0], width / 3) {
                rows = [[(0, leadRoom)] + (1..<subviews.count).map { ($0, ideal[$0]) }]
            } else {
                rows = [[]]
                var x: CGFloat = 0
                for index in subviews.indices {
                    let w = min(ideal[index], max(0, width))
                    if !rows[rows.count - 1].isEmpty, x + spacing + w > width {
                        rows.append([])
                        x = 0
                    }
                    if !rows[rows.count - 1].isEmpty { x += spacing }
                    rows[rows.count - 1].append((index, w))
                    x += w
                }
            }
        } else {
            rows = [subviews.indices.map { ($0, ideal[$0]) }]
        }

        // Each row on its first text baseline.
        var result = Arrangement()
        var y: CGFloat = 0
        for row in rows {
            let measured = row.map { entry -> (index: Int, width: CGFloat, height: CGFloat, baseline: CGFloat) in
                let d = subviews[entry.index].dimensions(in: ProposedViewSize(width: entry.width, height: nil))
                return (entry.index, entry.width, d.height, d[VerticalAlignment.firstTextBaseline])
            }
            let ascent = measured.map(\.baseline).max() ?? 0
            let descent = measured.map { $0.height - $0.baseline }.max() ?? 0
            var x: CGFloat = 0
            for m in measured {
                result.items.append(Item(index: m.index, origin: CGPoint(x: x, y: y + ascent - m.baseline), width: m.width))
                x += m.width + spacing
            }
            result.size.width = max(result.size.width, x - spacing)
            y += ascent + descent
        }
        result.size.height = y
        return result
    }
}

#if DEBUG
struct DetailLineGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("site and time left") {
                DetailLine(["investing.example.com", "9 min left"]).typeStyle(.caption)
            }
            PreviewState("finished") {
                DetailLine(parts: [.finished]).typeStyle(.caption)
            }
            PreviewState("three parts") {
                DetailLine(["Jane Austen", "61 chapters"]).typeStyle(.caption)
            }
            PreviewState("a long lead gives way") {
                DetailLine(["a-very-long-subdomain.investing.example.com", "6 h 10 min left"])
                    .typeStyle(.caption)
                    .frame(width: 240, alignment: .leading)
            }
            PreviewState("on a dark reading page") {
                DetailLine(["example.com", "12 min left"]).typeStyle(.caption)
                    .onReadingPreview()
            }
        }
    }
}

#Preview("DetailLine · light", traits: .sizeThatFitsLayout) { DetailLineGallery().previewVariant(.light) }
#Preview("DetailLine · dark", traits: .sizeThatFitsLayout) { DetailLineGallery().previewVariant(.dark) }
#Preview("DetailLine · AX5", traits: .sizeThatFitsLayout) { DetailLineGallery().previewVariant(.largestText) }
#endif
