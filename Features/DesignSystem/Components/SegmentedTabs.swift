import SwiftUI
import UIKit

/// Tabs over a list: the system's segmented control at the tap floor's height (`Control.tap`),
/// a little taller than SwiftUI's segmented `Picker` (32 pt, or 48 at `.large`, with no size
/// between). Its text follows Dynamic Type up to `Control.maxTextGrowth`, and the control grows with it.
struct SegmentedTabs<Value: Hashable>: UIViewRepresentable {
    let label: String
    let options: [(value: Value, title: String)]
    @Binding var selection: Value

    func makeUIView(context: Context) -> UISegmentedControl {
        let control = UISegmentedControl()
        control.accessibilityLabel = label
        control.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return control
    }

    func updateUIView(_ control: UISegmentedControl, context: Context) {
        context.coordinator.parent = self
        if control.numberOfSegments != options.count
            || options.indices.contains(where: { control.titleForSegment(at: $0) != options[$0].title }) {
            control.removeAllSegments()
            for (index, option) in options.enumerated() {
                control.insertSegment(withTitle: option.title, at: index, animated: false)
            }
        }
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(context.environment.dynamicTypeSize))
        let base = UIFont.preferredFont(forTextStyle: .subheadline,
                                        compatibleWith: UITraitCollection(preferredContentSizeCategory: .large))
        let font = UIFontMetrics(forTextStyle: .subheadline)
            .scaledFont(for: base, maximumPointSize: base.pointSize * Control.maxTextGrowth, compatibleWith: traits)
        control.setTitleTextAttributes([.font: font], for: .normal)
        control.setTitleTextAttributes([.font: UIFont.systemFont(ofSize: font.pointSize, weight: .semibold)], for: .selected)
        control.selectedSegmentIndex = options.firstIndex { $0.value == selection } ?? UISegmentedControl.noSegment
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UISegmentedControl, context: Context) -> CGSize? {
        let natural = uiView.intrinsicContentSize.height
        return CGSize(width: proposal.width ?? uiView.intrinsicContentSize.width,
                      height: max(Control.tap, natural + Spacing.s))
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject {
        var parent: SegmentedTabs

        init(parent: SegmentedTabs) { self.parent = parent }

        @objc func changed(_ control: UISegmentedControl) {
            guard parent.options.indices.contains(control.selectedSegmentIndex) else { return }
            parent.selection = parent.options[control.selectedSegmentIndex].value
        }
    }
}
