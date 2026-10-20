import SwiftUI

/// One fixed-layout choice row: title, optional one-line subtitle (a downloaded model's starts
/// with the grey filled ↓, as every downloaded row's line two does), a fixed-size trailing accessory slot
/// (a download's progress, a voice's preview), and a fixed-size slot for the selection ✓. State
/// changes swap contents inside the slots, so the row's size never changes.
struct SettingsChoiceRow<Accessory: View>: View {
    let title: String
    /// Line two: a model's state, a voice's detail (`DetailPart.downloaded` once downloaded).
    let subtitle: DetailPart?
    let selected: Bool
    var enabled: Bool = true
    let accessibilityID: String
    let action: () -> Void
    @ViewBuilder let accessory: () -> Accessory

    init(
        title: String,
        subtitle: DetailPart?,
        selected: Bool,
        enabled: Bool = true,
        accessibilityID: String,
        action: @escaping () -> Void,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) {
        self.title = title
        self.subtitle = subtitle
        self.selected = selected
        self.enabled = enabled
        self.accessibilityID = accessibilityID
        self.action = action
        self.accessory = accessory
    }

    var body: some View {
        HStack(spacing: Spacing.s) {
            Button(action: action) {
                SymbolRow(title, subtitle: subtitle, symbol: nil, ink: enabled ? nil : Palette.secondaryInk)
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .accessibilityIdentifier(accessibilityID)
            .accessibilityAddTraits(selected ? .isSelected : [])

            accessory()
                .frame(width: Glyph.control, height: Glyph.control)

            ZStack {
                if selected {
                    Image(systemName: Icons.checkmark)
                        .foregroundStyle(Palette.accent)
                        .fontWeight(.semibold)
                }
            }
            .frame(width: Glyph.mark, height: Glyph.mark)
            .accessibilityHidden(true)
        }
    }
}

extension SettingsChoiceRow where Accessory == EmptyView {
    init(title: String, subtitle: DetailPart?, selected: Bool, enabled: Bool = true, accessibilityID: String,
         action: @escaping () -> Void) {
        self.init(title: title, subtitle: subtitle, selected: selected, enabled: enabled,
                  accessibilityID: accessibilityID, action: action) { EmptyView() }
    }
}

/// A row that opens a page of choices: its symbol (nil: none, as the rest of its card), its name,
/// the current choice in secondary ink, then ›. One line; the value truncates first.
struct SettingsLinkRow<Destination: View>: View {
    let title: String
    let symbol: String?
    let value: String
    let accessibilityID: String
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination) {
            SymbolRow(title, symbol: symbol) {
                Text(value)
                    .typeStyle(.row)
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
            }
        }
        .accessibilityIdentifier(accessibilityID)
    }
}

/// A switch with a symbol and a name.
struct SettingsToggleRow: View {
    let title: String
    let symbol: String
    @Binding var isOn: Bool
    let accessibilityID: String

    var body: some View {
        Toggle(isOn: $isOn) {
            SymbolRow(title, symbol: symbol)
        }
        .tint(Palette.accent)
        .accessibilityIdentifier(accessibilityID)
    }
}

/// A control that takes a whole card row (swatches, a segmented choice), under a small caption
/// naming it.
struct SettingsControlRow<Control: View>: View {
    let title: String
    @ViewBuilder let control: () -> Control

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .typeStyle(.caption, weight: .semibold)
                .foregroundStyle(Palette.secondaryInk)
            control()
        }
        .padding(.vertical, Spacing.xs)
    }
}

/// A voice model downloading (tap = cancel): the `DownloadMark` filling as it downloads, as every
/// download shows; a spinner while the fraction is unknown (preparing, compiling).
struct ModelDownloadMark: View {
    let fraction: Double?

    var body: some View {
        Group {
            if let fraction, fraction < 1 {
                DownloadMark(state: .downloading(fraction: fraction), size: Glyph.modelDownload)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(width: Glyph.modelDownload, height: Glyph.modelDownload)
        .contentShape(Rectangle())
    }
}
