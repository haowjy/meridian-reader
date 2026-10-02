import SwiftUI

/// A Safari-style search session in a bottom-chrome field (the browser's address field, the
/// library's search field). It begins when the field gets focus or Search is tapped, survives the
/// keyboard being lowered (swipe down), and ends only with ✕ or by leaving (submit, navigate).
@MainActor
@Observable
final class SearchSession {
    enum Phase: Equatable {
        case idle
        /// `startText`: the field's text when the session began (the page address, or empty). nil
        /// once a term was filled in from a suggestion, so the field no longer counts as untouched.
        case active(startText: String?)
    }

    private(set) var phase: Phase = .idle
    /// The field's text: what is typed during a session, the idle text (e.g. the page address)
    /// otherwise.
    var text = ""
    /// The field has keyboard focus. `SearchSessionChrome` keeps this and the field in sync.
    var isFocused = false

    var isActive: Bool { phase != .idle }

    /// Searching, and the text is empty or still what the session started with: show recent
    /// searches rather than suggestions.
    var isUntouched: Bool {
        guard case .active(let startText) = phase else { return false }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text == startText
    }

    /// Starts (or restarts) a session with `initialText` in the field, keyboard up.
    func begin(with initialText: String = "") {
        phase = .active(startText: initialText)
        text = initialText
        isFocused = true
    }

    /// The field got or lost focus. Focus while idle starts a session with `beginText()`.
    func focusChanged(_ focused: Bool, beginText: () -> String) {
        isFocused = focused
        if focused, !isActive { begin(with: beginText()) }
    }

    /// Puts a recent search or suggestion in the field without submitting it.
    func fill(_ term: String) {
        text = term
        phase = .active(startText: nil)
        isFocused = true
    }

    /// Swipe down: the keyboard goes, the session (text and ✕) stays.
    func lowerKeyboard() {
        isFocused = false
    }

    /// ✕ or leaving: back to idle, showing `idleText`.
    func end(showing idleText: String) {
        phase = .idle
        text = idleText
        isFocused = false
    }
}
