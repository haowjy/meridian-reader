import SwiftUI

/// Whether a menu row shows, and whether it runs (decision DR-09), for every ⋯ panel and
/// long-press menu. A row that can never apply to the item is hidden (*Share* on a chapter with no
/// web address, a folder's rows on the Library's home, *Play from Here* on a page in no folder). A
/// row that applies but can't run now shows dimmed (*Prepare* while it prepared audio, *Move to…*
/// before the page is saved), so a menu keeps its shape as the item's state changes. A toggle
/// (*Save* / *Remove from Library*, *Mark as Finished* / *Unfinished*) is one row showing the face
/// for the item's state, not two rows. Menus decide each row through this, never a bare `if`.
enum MenuAvailability: Equatable {
    case enabled
    case disabled
    case hidden

    /// `applies`: the item is of a kind that can ever take the action; `canRun`: it can now.
    init(applies: Bool = true, when canRun: Bool = true) {
        self = !applies ? .hidden : canRun ? .enabled : .disabled
    }
}

extension View {
    /// The row as `availability` says: as it is, dimmed and inert, or not there.
    @ViewBuilder
    func menuAvailability(_ availability: MenuAvailability) -> some View {
        switch availability {
        case .enabled: self
        case .disabled: disabled(true)
        case .hidden: EmptyView()
        }
    }
}
