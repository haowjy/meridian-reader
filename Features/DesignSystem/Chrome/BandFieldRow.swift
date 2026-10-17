import SwiftUI

/// The bottom band's field row: the swap (a toolbar button, 44 pt, tight to the leading edge),
/// then the field capsule filling the rest. The browser and the Library draw it in their band
/// (`SurfaceBand`); Follow's chapter preview draws its field at the same place.
///
/// ```
/// [📚/🌐] ( field capsule                                  )
/// ```
///
/// `swap` nil: the swap steps aside (the field alone, while searching), or, with
/// `keepsSwapRoom`, leaves its room empty so the field keeps the browser's frame (Follow's
/// preview, which goes nowhere else).
struct BandFieldRow<Field: View>: View {
    var swap: BandSwap?
    var keepsSwapRoom = false
    @ViewBuilder var field: Field

    var body: some View {
        HStack(spacing: Spacing.xxs) {
            if swap == nil, keepsSwapRoom {
                Color.clear.frame(width: BottomChrome.rowHeight, height: BottomChrome.rowHeight)
            }
            if let swap {
                BandToolbarButton(systemImage: swap.systemImage, label: swap.label,
                                  identifier: swap.identifier, weight: .light, action: swap.action)
                    .accessibilityHint(swap.hint)
                    .frame(width: BottomChrome.rowHeight, height: BottomChrome.rowHeight)
                    .tint(Palette.ink)
            }
            field
        }
    }
}

/// The swap at the leading edge of the field row: to the other surface (📚 / 🌐).
struct BandSwap {
    let systemImage: String
    let label: String
    let hint: String
    let identifier: String
    let action: () -> Void
}

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
