import SwiftUI

/// One fixed-layout choice row: title, optional one-line subtitle, a fixed-size trailing
/// accessory slot, and a fixed-size checkmark slot (checkmark / spinner / empty). State changes
/// swap contents inside the slots, so the row's size never changes.
struct SettingsChoiceRow<Accessory: View>: View {
    let title: String
    let subtitle: String?
    let selected: Bool
    var enabled: Bool = true
    var busy: Bool = false
    let accessibilityID: String
    let action: () -> Void
    @ViewBuilder let accessory: () -> Accessory

    init(
        title: String,
        subtitle: String?,
        selected: Bool,
        enabled: Bool = true,
        busy: Bool = false,
        accessibilityID: String,
        action: @escaping () -> Void,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) {
        self.title = title
        self.subtitle = subtitle
        self.selected = selected
        self.enabled = enabled
        self.busy = busy
        self.accessibilityID = accessibilityID
        self.action = action
        self.accessory = accessory
    }

    var body: some View {
        HStack(spacing: Spacing.s) {
            Button(action: action) {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title)
                            .typeStyle(.row)
                            .foregroundStyle(enabled ? Palette.ink : Palette.secondaryInk)
                            .lineLimit(1)
                        if let subtitle {
                            Text(subtitle)
                                .typeStyle(.caption)
                                .foregroundStyle(Palette.secondaryInk)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    Spacer(minLength: Spacing.xs)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .accessibilityIdentifier(accessibilityID)
            .accessibilityAddTraits(selected ? .isSelected : [])

            accessory()
                .frame(width: Glyph.control, height: Glyph.control)

            ZStack {
                if busy {
                    ProgressView().controlSize(.small)
                } else if selected {
                    Image(systemName: Icons.checkmark)
                        .foregroundStyle(Palette.accent)
                        .fontWeight(.semibold)
                }
            }
            .frame(width: Glyph.mark, height: Glyph.mark)
            .accessibilityHidden(true)
        }
        .frame(minHeight: SettingsMetrics.rowHeight)
    }
}

extension SettingsChoiceRow where Accessory == EmptyView {
    init(title: String, subtitle: String?, selected: Bool, enabled: Bool = true, accessibilityID: String,
         action: @escaping () -> Void) {
        self.init(title: title, subtitle: subtitle, selected: selected, enabled: enabled,
                  accessibilityID: accessibilityID, action: action) { EmptyView() }
    }
}

/// A row that opens a page of choices: its symbol, its name, the current choice in secondary
/// ink, then ›. One line; the value truncates first.
struct SettingsLinkRow<Destination: View>: View {
    let title: String
    let symbol: String
    let value: String
    let accessibilityID: String
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination) {
            SettingsLabel(title: title, symbol: symbol) {
                Text(value)
                    .typeStyle(.row)
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
            }
        }
        .accessibilityIdentifier(accessibilityID)
    }
}

/// A row's symbol and name, then `trailing`; at least a tap target tall.
struct SettingsLabel<Trailing: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: symbol)
                .foregroundStyle(Palette.ink)
                .frame(width: Glyph.mark)
            Text(title)
                .typeStyle(.row)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: Spacing.xs)
            trailing()
        }
        .frame(minHeight: SettingsMetrics.rowHeight)
        .contentShape(Rectangle())
    }
}

extension SettingsLabel where Trailing == EmptyView {
    init(title: String, symbol: String) {
        self.init(title: title, symbol: symbol) { EmptyView() }
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
            SettingsLabel(title: title, symbol: symbol)
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

enum SettingsMetrics {
    /// A settings row: a tap target and a little air, at the default text size.
    static let rowHeight = BottomChrome.minTapTarget + Spacing.xxs
}

extension View {
    /// A note under a settings card: caption, secondary ink, in line with the card.
    func settingsFooter() -> some View {
        typeStyle(.caption)
            .foregroundStyle(Palette.secondaryInk)
            .libraryFooter()
    }

    /// A settings card's section header.
    func settingsCard() -> some View {
        listRowBackground(Palette.chrome)
    }
}

/// Determinate download ring with a stop square (tap = cancel); indeterminate spinner when the
/// fraction is unknown (preparing / compiling).
struct DownloadRing: View {
    let fraction: Double?

    var body: some View {
        ZStack {
            if let fraction, fraction < 1 {
                Circle().stroke(Palette.secondaryInk.opacity(0.25), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: max(0.02, fraction))
                    .stroke(Palette.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Palette.accent)
                    .frame(width: 8, height: 8)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(width: 24, height: 24)
        .contentShape(Rectangle())
    }
}
