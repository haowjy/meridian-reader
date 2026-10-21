import SwiftUI

/// A download's menu: the one definition the Downloads list's rows show from their ⋯ and their
/// long press, the same rows in every section. Which options show and greyed or not is
/// `MenuRegistry`'s (C98): *Re-download* (grey while queued), *Keep* (grey unless its audio is in
/// another voice than downloads now use), *Remove Download(s)* (red). No *Pause* / *Resume*: the
/// row's ↓ mark does that.
///
/// Every row is a page (C110): *Re-download* renders that page again, *Keep* keeps the voice of the
/// download it came from, and *Remove Download* (the row's swipe too) is the page's own, as in its
/// menu (`DownloadCenter.deleteDownloads(of:)`). A folder's download is turned off on its screen.
struct DownloadMenu: View {
    let item: DownloadArticles.Item
    let downloads: DownloadCenter
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
        return MenuRegistry.rows(.download, at: .downloads, facts) { option in
            switch option {
            case .redownload:
                return MenuRow(id: "menuRedownload", title: Verbs.redownload, icon: Icons.redownload) { downloads.redownload(article: key) }
            case .keep:
                return MenuRow(id: "menuKeep", title: Verbs.keep, icon: Icons.keep) {
                    if let otherVoice { downloads.keep(id, voice: otherVoice) }
                }
            default:
                return removeRow
            }
        }
    }

    /// *Remove Download* for a page, *Remove Downloads* for a folder, as their own menus say; the
    /// row's swipe too.
    var removeRow: MenuRow {
        MenuRow(id: "menuDeleteAudio", title: Verbs.deleteAudio, icon: Icons.delete, isDestructive: true) {
            if isListeningAudio {
                // Only the audio; the article stays (C135).
                if !needsAudio(item.key), let article = library.article(key: item.key) { library.deleteDownloads(article) }
            } else if let article = library.article(key: item.key) {
                downloads.deleteDownloads(of: article)
            } else {
                downloads.remove(item.recordID)
            }
        }
    }
}
