import SwiftUI

/// What the chrome host needs from a destination to draw its first row and ⋯: the field (and its
/// search session), the arrows, the ⋯ button. The browser and the Library each build one; the rest
/// of the chrome (the pill, the play button, the fold) is the host's.
struct ChromeScreen {
    /// nil: no field to search in (the Reader).
    var session: SearchSession?
    /// The ✕ that ends a search: its accessibility identifier and action.
    var cancelID = ""
    var onCancel: () -> Void = {}
    /// Starts the session when the idle field is tapped.
    var begin: () -> Void = {}
    /// ‹ and ›. `canGoBack` / `canGoForward` false drops the button (› alone) or both (a new page).
    var canGoBack = false
    var canGoForward = false
    var backID = ""
    var forwardID = ""
    var onBack: () -> Void = {}
    var onForward: () -> Void = {}
    /// The field (a `SearchField`, an `AddressField`): the host passes the focus binding it keeps in
    /// sync with `session.isFocused`.
    var field: (FocusState<Bool>.Binding) -> AnyView = { _ in AnyView(EmptyView()) }
    /// The ⋯ button, filling the frame the host gives it.
    let more: AnyView
    /// The Browser's reader mode: the round control that listens to the page, at the end of row 1.
    var listen: AnyView?
    /// What the capsule names once a scroll down has folded both rows: the page's domain in the Browser, a
    /// screen, folder or article's title in the Library, the source in the Browser's reader mode.
    var capsuleTitle = ""
    /// Library Edit: replaces the pill and ⋯ on row 2 with the selection's actions.
    var editBar: AnyView?
}
