import SwiftUI

/// One fixed-layout choice row: title, optional one-line subtitle (a downloaded model's starts
/// with the accent filled ↓, as every prepared row's line two does), a fixed-size trailing accessory slot
/// (a prepare's progress, a voice's preview), and a fixed-size slot for the selection ✓. State
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
                .frame(width: Control.small, height: Control.small)

            ZStack {
                if selected {
                    Image(systemName: Icons.checkmark)
                        .foregroundStyle(Palette.accent)
                        .fontWeight(.semibold)
                }
            }
            .frame(width: Glyph.regular, height: Glyph.regular)
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

/// A row that opens a page of choices (`route`, pushed on Settings' stack): its name, the current
/// choice in secondary ink, then ›. One line; the value truncates first. At Accessibility sizes
/// the value goes under the name, whole, as Settings does: beside it, it shrank to a letter.
struct SettingsLinkRow: View {
    let title: String
    let value: String
    let accessibilityID: String
    let route: SettingsRoute

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationLink(value: route) {
            if dynamicTypeSize.isAccessibilitySize {
                SymbolRow(title, subtitle: DetailPart(value), symbol: nil)
            } else {
                SymbolRow(title, symbol: nil) {
                    Text(value)
                        .typeStyle(.row)
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityIdentifier(accessibilityID)
    }
}

/// A switch and its name.
struct SettingsToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    let accessibilityID: String

    var body: some View {
        Toggle(isOn: $isOn) {
            SymbolRow(title, symbol: nil)
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
        // The card adds no inset above or below a row (`listCard`).
        .padding(.vertical, Spacing.s)
    }
}

/// A voice model downloading (tap = cancel): the `DownloadMark` filling as it downloads, as every
/// prepare shows; a spinner while the fraction is unknown (preparing, compiling).
struct ModelDownloadMark: View {
    let fraction: Double?

    var body: some View {
        Group {
            if let fraction, fraction < 1 {
                PrepareMark(state: .preparing(fraction: fraction), size: Glyph.slot)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(width: Glyph.slot, height: Glyph.slot)
        .contentShape(Rectangle())
    }
}

/// Search Settings (the Settings destination's field): which of the settings list's rows show. A row
/// shows when its title or its section's title contains the text; a section shows when one of its
/// rows does. Each section lists its rows' titles (`Group`), the same strings the rows draw.
struct SettingsSearch: Equatable {
    /// A section of the settings list: its header ("" for none) and its rows' titles.
    struct Group: Equatable {
        let title: String
        let rows: [String]
    }

    var text = ""

    private var term: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isFiltering: Bool { !term.isEmpty }

    func shows(_ row: String, in group: Group) -> Bool {
        guard isFiltering else { return true }
        return group.title.localizedStandardContains(term) || row.localizedStandardContains(term)
    }

    func shows(_ group: Group) -> Bool {
        group.rows.contains { shows($0, in: group) }
    }
}

extension EnvironmentValues {
    /// What Search Settings has typed, for the settings list's sections.
    @Entry var settingsSearch = SettingsSearch()
}
