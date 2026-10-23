import CoreGraphics
import SwiftUI

/// Regular-width (iPad) shell measures from the Proposed iPad layout. Compact keeps the phone
/// chrome; nothing here applies until `horizontalSizeClass == .regular`.
enum RegularLayout {
    /// Persistent left sidebar (Library tree, surface swap, Search, Settings).
    static let sidebarWidth: CGFloat = 280
    /// Serif body column in the Reader (~34–40 em at body size).
    static let readableMeasure: CGFloat = 700
    /// Voice / Settings inset form sheet width (~540–640 pt).
    static let formSheetWidth: CGFloat = 600
    /// Clustered player dock max width inside the main pane (not edge-stretched).
    static let playerClusterWidth: CGFloat = 520
}

extension View {
    /// On regular width, present as an inset form sheet (~form width) instead of a tiny phone card
    /// floating in empty space. Compact is unchanged.
    @ViewBuilder
    func regularInsetFormSheet(isRegular: Bool) -> some View {
        if isRegular {
            self
                .presentationSizing(.form)
                .presentationDragIndicator(.visible)
        } else {
            self
        }
    }

    /// Caps reading content to `RegularLayout.readableMeasure` and centres it on regular width.
    @ViewBuilder
    func regularReadableMeasure(isRegular: Bool) -> some View {
        if isRegular {
            self
                .frame(maxWidth: RegularLayout.readableMeasure)
                .frame(maxWidth: .infinity)
        } else {
            self
        }
    }
}
