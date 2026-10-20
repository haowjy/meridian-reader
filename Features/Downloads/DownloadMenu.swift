import SwiftUI

/// A download's menu: the one definition the Downloads list's rows show from their ⋯ and their
/// long press, the same rows in every section. Which options show and greyed or not is
/// `MenuRegistry`'s (C98): *Re-download* (grey while queued), *Keep* (grey unless its audio is in
/// another voice than downloads now use), *Remove Download(s)* (red). No *Pause* / *Resume*: the
/// row's ↓ mark does that.
///
/// The remove row (and the row's swipe) is the item's own: a page's *Remove Download*, a folder's
/// *Remove Downloads*, the same action as in the page's or folder's menu (`DownloadCenter.remove`).
struct DownloadMenu: View {
    let item: DownloadOverview.Item
    let downloads: DownloadCenter

    var body: some View {
        MenuRows(rows)
    }

    var rows: [MenuRow] {
        let id = item.id
        let otherVoice: String? = if case .differentVoice(let voice) = item.status { voice } else { nil }
        var facts = MenuRegistry.Facts()
        facts.isQueued = item.status.fraction != nil
        facts.isOtherVoice = otherVoice != nil
        return MenuRegistry.rows(.download, at: .downloads, facts) { option in
            switch option {
            case .redownload:
                return MenuRow(id: "menuRedownload", title: Verbs.redownload, icon: Icons.redownload) { downloads.redownload(id) }
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
        MenuRow(id: "menuRemoveDownload",
                title: item.record.target.isFolder ? Verbs.removeDownloads : Verbs.removeDownload,
                icon: Icons.removeDownload, isDestructive: true) { downloads.remove(item.id) }
    }
}
