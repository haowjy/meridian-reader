import SwiftUI

/// A prepare's menu: the one definition the Prepared Audio list's rows show from their ⋯ and their
/// long press, the same rows in every section. Which options show and greyed or not is
/// `MenuRegistry`'s (C98): *Prepare Again* (grey while queued), *Keep* (grey unless its audio is in
/// another voice than prepared audio now use), *Remove Prepare(s)* (red). No *Pause* / *Resume*: the
/// row's ↓ mark does that.
///
/// Every row is a page (C110): *Prepare Again* renders that page again, *Keep* keeps the voice of the
/// prepare it came from, and *Remove Prepare* (the row's swipe too) is the page's own, as in its
/// menu (`PrepareCenter.deletePrepared audio(of:)`). A folder's prepare is turned off on its screen.
struct PrepareMenu: View {
    let item: PrepareArticles.Item
    let preparedAudio: PrepareCenter
    let library: LibraryStore
    /// A From Listening row: only *Delete Audio* (C135).
    var isListeningAudio = false
    /// Listening needs this audio now (the playing article): *Delete Audio* leaves it.
    var needsAudio: (UUID) -> Bool = { _ in false }

    var body: some View {
        MenuRows(rows)
    }

    var rows: [MenuRow] {
        let id = item.recordID, key = item.key
        let otherVoice: String? = if case .differentVoice(let voice) = item.status { voice } else { nil }
        var facts = MenuRegistry.Facts()
        facts.isQueued = item.status.fraction != nil
        facts.isOtherVoice = otherVoice != nil
        facts.isListeningAudio = isListeningAudio
        return MenuRegistry.rows(.prepare, at: .preparedAudio, facts) { option in
            switch option {
            case .reprepare:
                return MenuRow(id: "menuReprepare", title: Verbs.reprepare, icon: Icons.reprepare) { preparedAudio.reprepare(article: key) }
            case .keep:
                return MenuRow(id: "menuKeep", title: Verbs.keep, icon: Icons.keep) {
                    if let otherVoice { preparedAudio.keep(id, voice: otherVoice) }
                }
            default:
                return removeRow
            }
        }
    }

    /// *Remove Prepare* for a page, *Remove Prepared audio* for a folder, as their own menus say; the
    /// row's swipe too.
    var removeRow: MenuRow {
        MenuRow(id: "menuDeleteAudio", title: Verbs.deleteAudio, icon: Icons.delete, isDestructive: true) {
            if isListeningAudio {
                // Only the audio; the article stays (C135).
                if !needsAudio(item.key), let article = library.article(key: item.key) { library.deletePreparedAudio(article) }
            } else if let article = library.article(key: item.key) {
                preparedAudio.deletePreparedAudio(of: article)
            } else {
                preparedAudio.remove(item.recordID)
            }
        }
    }
}
