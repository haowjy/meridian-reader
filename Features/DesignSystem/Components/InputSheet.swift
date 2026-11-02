import SwiftUI

/// The shared frame for typed input and its review: ✕ (the system's close button), an inline
/// title, content and bottom actions. Feature state and saving stay with the caller; ✕ is always
/// usable, and the caller cancels whatever is under way when the sheet goes.
struct InputSheet<Content: View, Actions: View>: View {
    let title: String
    let onCancel: () -> Void
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Palette.paper)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: Spacing.s) { actions }
                        .padding(.horizontal, Spacing.pageMargin)
                        .padding(.vertical, Spacing.s)
                        .frame(maxWidth: .infinity)
                        .background(Palette.paper)
                }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { closeButton }
                }
        }
        .presentationDragIndicator(.visible)
    }

    private var closeButton: some View {
        Group {
            if #available(iOS 26.0, *) {
                Button(role: .close, action: onCancel)
            } else {
                Button(action: onCancel) { Image(systemName: Icons.close) }
            }
        }
        .accessibilityLabel(Verbs.cancel)
        .accessibilityIdentifier("inputSheetCancel")
    }
}

extension View {
    /// A single-line input's capsule, scaled by its text and the shared tap floor.
    func inputSheetField() -> some View {
        typeStyle(.row)
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.s)
            .frame(minHeight: Control.tap)
            .background(Palette.chrome, in: Capsule())
    }
}

#if DEBUG
private struct InputSheetPreview: View {
    @State private var address = ""
    var body: some View {
        InputSheet(title: "Add a Link", onCancel: {}) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                TextField("example.com/article", text: $address).inputSheetField()
                Text("An article, or a story’s chapter list to follow.").footnote()
            }
            .padding(Spacing.pageMargin)
        } actions: {
            PillButton("Add", style: address.isEmpty ? .neutral : .filled, expands: true) {}
                .disabled(address.isEmpty)
        }
    }
}
#Preview("InputSheet · light") { InputSheetPreview().previewVariant(.light) }
#Preview("InputSheet · dark") { InputSheetPreview().previewVariant(.dark) }
#Preview("InputSheet · AX5") { InputSheetPreview().previewVariant(.largestText) }
#endif
