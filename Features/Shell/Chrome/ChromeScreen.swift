import SwiftUI

/// What the chrome host needs from a destination to draw its first row: the field (and its search
/// session) and the arrows. Each destination builds one; the rest of the chrome (the pill, Listen,
/// the fold) is the host's. The chrome has no ⋯: a screen's menu is on its title line, the
/// Browser's on its field's leading glyph.
struct ChromeScreen {
    /// nil: no field to search in.
    var session: SearchSession?
    /// The ✕ that ends a search: its accessibility identifier and action.
    var cancelID = ""
    var onCancel: () -> Void = {}
    /// Starts the session when the idle field is tapped.
    var begin: () -> Void = {}
    /// ‹ and ›. In the Browser ‹ always shows (`canGoBack` false dims it) and › only when `canGoForward`;
    /// elsewhere ‹ shows only when `canGoBack`.
    var canGoBack = false
    var canGoForward = false
    var backID = ""
    var forwardID = ""
    var onBack: () -> Void = {}
    var onForward: () -> Void = {}
    /// The field (a `SearchField`, an `AddressField`): the host passes the focus binding it keeps in
    /// sync with `session.isFocused`.
    var field: (FocusState<Bool>.Binding) -> AnyView = { _ in AnyView(EmptyView()) }
    /// What the bubble names once a scroll down has folded both rows: the page's domain in the Browser, a
    /// screen, folder or article's title in the Library, the source in the Browser's reader mode, Settings.
    var bubbleTitle = ""
    /// Library Edit: replaces the pill on row 2 with the selection's actions.
    var editBar: AnyView?
}
