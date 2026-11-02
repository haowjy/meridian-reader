import SwiftUI

/// A sheet's *Done*, *Cancel* or *Save* in its navigation bar: a plain `Button` the system styles
/// (glass on iOS 26), so every sheet's buttons look like the system's. This type owns the
/// identifier and placement rule.
///
/// ```
/// ( Cancel )            Edit Details             ( Save )
/// ```
struct SheetBarButton: ToolbarContent {
    let title: String
    let placement: ToolbarItemPlacement
    let identifier: String
    var isDisabled = false
    let action: () -> Void

    init(_ title: String, placement: ToolbarItemPlacement, identifier: String,
         isDisabled: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.placement = placement
        self.identifier = identifier
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some ToolbarContent {
        ToolbarItem(placement: placement) {
            Button(title, action: action)
                .disabled(isDisabled)
                .accessibilityIdentifier(identifier)
        }
    }
}

#if DEBUG
struct SheetBarButtonGallery: View {
    var body: some View {
        NavigationStack {
            List { Text("Rows") }
                .cardListStyle()
                .navigationTitle("Edit Details")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    SheetBarButton(Verbs.cancel, placement: .cancellationAction, identifier: "previewCancel") {}
                    SheetBarButton("Save", placement: .confirmationAction, identifier: "previewSave") {}
                }
        }
    }
}

#Preview("SheetBarButton · light") { SheetBarButtonGallery().previewVariant(.light) }
#Preview("SheetBarButton · dark") { SheetBarButtonGallery().previewVariant(.dark) }
#Preview("SheetBarButton · AX5") { SheetBarButtonGallery().previewVariant(.largestText) }
#endif
