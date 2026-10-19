import SwiftUI

/// One row of a menu, as every renderer draws it: a row's ⋯ and long press (`MenuRows`, in a
/// SwiftUI `Menu` or `.contextMenu`) and the ⋯ panel (`MoreMenuPanel`). An item kind's menu (a
/// page's, a folder's, a download's) is one ordered list of these, built once by its definition
/// and rendered unchanged by every entry point, so order, names, symbols, red and dimming are
/// decided in one place. Its title comes from `Verbs` and its symbol from `Icons`; whether it
/// shows, dimmed or not, from `MenuAvailability` (DR-09). A destructive row is red in every
/// renderer.
struct MenuRow: Identifiable {
    /// The row's accessibility identifier, the same in every renderer (`menuDownload`).
    let id: String
    let title: String
    /// nil: a submenu's choice drawn as its title alone (a Sort choice not picked).
    let icon: String?
    var isDestructive = false
    var availability: MenuAvailability = .enabled
    /// A submenu (the ⋯ panel's *Sort*): its rows open instead of an action.
    var submenu: [MenuRow] = []
    /// VoiceOver's label and hint, when they differ from the title (a big button's).
    var accessibilityLabel: String?
    var accessibilityHint: String?
    var action: () -> Void = {}

    init(id: String, title: String, icon: String?, isDestructive: Bool = false,
         availability: MenuAvailability = .enabled, submenu: [MenuRow] = [],
         accessibilityLabel: String? = nil, accessibilityHint: String? = nil,
         action: @escaping () -> Void = {}) {
        self.id = id
        self.title = title
        self.icon = icon
        self.isDestructive = isDestructive
        self.availability = availability
        self.submenu = submenu
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        self.action = action
    }

    var isShown: Bool { availability != .hidden }

    /// The row as its list row's swipe (a swipe is its menu row): its name and symbol, red, its
    /// action. `role: .destructive` only where the action takes the row out of the list's data at
    /// once; a row that can stay (it asks first, or a save can fail) takes the tint alone
    /// (AGENTS.md's swipe rule).
    func swipeButton(role: ButtonRole? = nil) -> some View {
        Button(role: role, action: action) {
            if let icon { Label(title, systemImage: icon) } else { Text(title) }
        }
        .tint(Palette.destructive)
    }
}

extension [MenuRow] {
    /// The first of the rows `ids` that deletes and can run now: the one a swipe offers.
    func swipeRow(_ ids: String...) -> MenuRow? {
        ids.lazy.compactMap { id in first { $0.id == id } }
            .first { $0.isDestructive && $0.availability == .enabled }
    }
}

/// Menu rows as a system menu's buttons (a `Menu`'s or a `.contextMenu`'s content). Each block
/// is a section, so the item's own rows and a screen's rows after them are set apart by the
/// system's divider. Hidden rows are left out, dimmed ones disabled, destructive ones red.
struct MenuRows: View {
    let blocks: [[MenuRow]]

    init(_ rows: [MenuRow]) {
        blocks = [rows]
    }

    init(blocks: [[MenuRow]]) {
        self.blocks = blocks
    }

    var body: some View {
        let shown = blocks.map { $0.filter(\.isShown) }.filter { !$0.isEmpty }
        ForEach(shown.indices, id: \.self) { index in
            Section {
                ForEach(shown[index]) { row in
                    button(row)
                }
            }
        }
    }

    @ViewBuilder
    private func button(_ row: MenuRow) -> some View {
        if row.submenu.isEmpty {
            Button(role: row.isDestructive ? .destructive : nil, action: row.action) { label(row) }
                .disabled(row.availability == .disabled)
                .accessibilityIdentifier(row.id)
        } else {
            Menu { MenuRows(row.submenu) } label: { label(row) }
                .disabled(row.availability == .disabled)
                .accessibilityIdentifier(row.id)
        }
    }

    @ViewBuilder
    private func label(_ row: MenuRow) -> some View {
        if let icon = row.icon { Label(row.title, systemImage: icon) } else { Text(row.title) }
    }
}
