import SwiftUI

/// A prepared article's menu: Prepare Again, then Delete Audio. Audio made only by listening
/// has Delete Audio alone, disabled while playback needs it. Both actions come from the registry.
struct PrepareMenu: View {
    let item: PrepareArticles.Item
    let preparedAudio: PrepareCenter
    let library: LibraryStore
    /// A From Listening row: only *Delete Audio* (C135).
    var isListeningAudio = false
    /// Listening needs this audio now (the playing article): *Delete Audio* is dimmed.
    var needsAudio: (UUID) -> Bool = { _ in false }

    var body: some View {
        MenuRows(rows)
    }

    private var facts: MenuRegistry.Facts {
        var facts = MenuRegistry.Facts()
        facts.isQueued = item.status.fraction != nil
        facts.isListeningAudio = isListeningAudio
        facts.audioInUse = isListeningAudio && needsAudio(item.key)
        return facts
    }

    var rows: [MenuRow] {
        let key = item.key
        return MenuRegistry.rows(.prepare, at: .preparedAudio, facts) { option in
            switch option {
            case .reprepare:
                return MenuRow(id: "menuReprepare", title: Verbs.reprepare, icon: Icons.reprepare) { preparedAudio.reprepare(article: key) }
            case .removePrepare:
                return removeRow
            default:
                preconditionFailure("No prepare row for \(option)")
            }
        }
    }

    /// *Delete Audio*, the row's swipe too (*Delete* there), dimmed while playback needs the audio
    /// (the registry's availability, so the menu and the swipe agree).
    var removeRow: MenuRow {
        let availability = MenuRegistry.entries(.prepare, at: .preparedAudio, facts)
            .first { $0.option == .removePrepare }?.availability ?? .enabled
        var row = MenuRow(id: "menuDeleteAudio", title: Verbs.deleteAudio, icon: Icons.delete, isDestructive: true,
                          availability: availability) {
            if isListeningAudio {
                // Only the audio; the article stays (C135).
                if !needsAudio(item.key), let article = library.article(key: item.key) { library.deletePreparedAudio(article) }
            } else if let article = library.article(key: item.key) {
                preparedAudio.deletePreparedAudio(of: article)
            } else {
                preparedAudio.remove(item.recordID)
            }
        }
        row.swipeTitle = Verbs.delete
        return row
    }
}
