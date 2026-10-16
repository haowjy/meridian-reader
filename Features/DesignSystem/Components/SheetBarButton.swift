import SwiftUI

/// A sheet's *Done*, *Cancel* or *Save* in its navigation bar: the neutral compact pill the
/// Reader's and Now Playing's close pill is (`SheetClosePill`), on every sheet (Downloads,
/// History, Settings, Edit Details, the Move tree, Import Book), without the bar's own glass
/// behind it. So a sheet's buttons look one way, at rest and over a scrolled list, light or dark.
///
/// ```
/// ( Cancel )            Edit Details             ( Save )
/// ```
struct SheetBarButton: ToolbarContent {
    let placement: ToolbarItemPlacement
    let title: String
    let identifier: String
    var isDisabled = false
    let action: () -> Void

    init(_ title: String, placement: ToolbarItemPlacement, identifier: String, isDisabled: Bool = false,
         action: @escaping () -> Void) {
        self.title = title
        self.placement = placement
        self.identifier = identifier
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some ToolbarContent {
        if #available(iOS 26.0, *) {
            item.sharedBackgroundVisibility(.hidden)
        } else {
            item
        }
    }

    private var item: some ToolbarContent {
        ToolbarItem(placement: placement) {
            PillButton(title, style: .neutral, size: .compact, action: action)
                // Its own width: the bar's leading slot would squeeze the title.
                .fixedSize()
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
                .libraryListStyle()
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
