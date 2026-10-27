import SwiftUI

/// A plain icon in a band toolbar slot.
struct BandToolbarButton: View {
    let systemImage: String
    let label: String
    let identifier: String
    /// Optical weight for line-dense glyphs (the swap); the toolbar slots keep the default.
    var weight: Font.Weight = .regular
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage).toolbarIconFrame().fontWeight(weight)
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}
