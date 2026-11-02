import SwiftUI

/// Segments side by side, all as wide as the widest needs: asked for its ideal width (as a
/// `ViewThatFits` asks) it answers that many of the widest label, so a row only "fits" when
/// every label shows whole; given a width it splits it evenly. The Aa panel's choices and the compact
/// chrome's pill.
struct EqualSegmentsLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let gaps = spacing * CGFloat(subviews.count - 1)
        let width = proposal.width
            ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max()! * CGFloat(subviews.count) + gaps
        let segment = max(0, (width - gaps) / CGFloat(subviews.count))
        let height = subviews.map { $0.sizeThatFits(ProposedViewSize(width: segment, height: nil)).height }.max()!
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let gaps = spacing * CGFloat(subviews.count - 1)
        let segment = max(0, (bounds.width - gaps) / CGFloat(subviews.count))
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + CGFloat(index) * (segment + spacing), y: bounds.midY),
                          anchor: .leading, proposal: ProposedViewSize(width: segment, height: bounds.height))
        }
    }
}
