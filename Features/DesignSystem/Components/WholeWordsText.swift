import SwiftUI

/// Text that wraps between words and never inside one: its ideal width is its widest word, so a
/// `ViewThatFits` around it moves on to its next layout (an action under the message, a name
/// left out) before a word would break or truncate. The toast's message, a swatch's name.
struct WholeWordsText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        WholeWordsLayout {
            Text(text)
            ForEach(Array(text.split(whereSeparator: \.isWhitespace).enumerated()), id: \.offset) { _, word in
                Text(word).hidden().accessibilityHidden(true)
            }
        }
    }
}

/// The first subview is the text; the rest, hidden, are its words, measured for the ideal width.
private struct WholeWordsLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let text = subviews.first else { return .zero }
        let width = proposal.width ?? subviews.dropFirst().map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        return text.sizeThatFits(ProposedViewSize(width: width, height: proposal.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
        for word in subviews.dropFirst() { word.place(at: bounds.origin, proposal: .zero) }
    }
}
