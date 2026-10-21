import SwiftUI
import XCTest
@testable import MeridianReader

/// The menu registry (C98, docs/MENUS.md) as a table: kind × place × state → which options show,
/// in order, and which are greyed. One assertion per menu the app builds.
final class MenuRegistryTests: XCTestCase {
    typealias R = MenuRegistry
    private func shown(_ kind: R.Kind, _ place: R.Place, _ facts: R.Facts) -> String {
        R.entries(kind, at: place, facts).map { entry in
            let name = entry.option.rawValue + (entry.availability == .disabled ? "(grey)" : "")
            let kids = entry.children.map { $0.option.rawValue + ($0.availability == .disabled ? "(grey)" : "") }
            return kids.isEmpty ? name : "\(name)[\(kids.joined(separator: ","))]"
        }.joined(separator: " ")
    }

    private var savedLoose: R.Facts {
        var f = R.Facts(); f.inLibrary = true; f.isSaved = true; f.canSave = true; f.canPlay = true
        f.canFavorite = true; f.hasShareURL = true; return f
    }
    private var chapter: R.Facts { var f = savedLoose; f.inFolder = true; f.hasShareURL = false; return f }
    private var unsavedWeb: R.Facts {
        var f = R.Facts(); f.offersSave = true; f.canSave = true; f.canFavorite = true; f.hasShareURL = true
        f.inRecent = true; return f
    }

    func testTable() {
        let cases: [(R.Kind, R.Place, R.Facts, String)] = [
            (.article, .row, savedLoose, "read download favorite move finished share save"),
            (.article, .row, chapter, "read download favorite move finished playback[markAllAbove,skip] save"),
            (.article, .reader, chapter, "download favorite move finished playback[skip]"),
            (.article, .row, unsavedWeb, "read download(grey) favorite move finished(grey) share save removeFromRecent"),
            (.article, .browser, R.Facts(), "download(grey) favorite(grey) move finished(grey) removeFromRecent(grey)"),
            (.article, .bar, savedLoose, "read download favorite move finished share save stopListening(grey)"),
            (.article, .history, unsavedWeb, "read download(grey) favorite move finished(grey) share save removeFromRecent removeFromHistory"),
            (.article, .nowPlaying, savedLoose, "goTo download favorite move finished share"),
            (.folder, .row, R.Facts(), "continueFolder(grey) folderDownload(grey) folderFavorite folderMove editDetails deleteFolder"),
            (.folder, .header, { var f = R.Facts(); f.hasArticlesToPlay = true; f.hasArticles = true; return f }(),
             "playFromStart removeDownloads(grey) folderFavorite folderMove editDetails deleteFolder"),
            (.download, .downloads, { var f = R.Facts(); f.isQueued = true; return f }(), "redownload(grey) keep(grey) removeDownload"),
            (.screen, .libraryHome, R.Facts(), "sort downloads settings"),
            (.screen, .folderScreen, R.Facts(), "sort downloads settings"),
            (.screen, .folderScreen, { var f = R.Facts(); f.isFixedOrder = true; return f }(), "downloads settings"),
            (.screen, .add, R.Facts(), "newFolder importFile saveFromWebsite paste(grey) follow"),
            (.screen, .add, { var f = R.Facts(); f.canPaste = true; return f }(), "newFolder importFile saveFromWebsite paste follow"),
            (.screen, .add, { var f = R.Facts(); f.isFixedOrder = true; return f }(), ""),
            (.screen, .edit, R.Facts(), "newFolder importFile saveFromWebsite paste(grey) follow"),
            (.screen, .edit, { var f = R.Facts(); f.isFixedOrder = true; return f }(), ""),
            (.screen, .browser, { var f = R.Facts(); f.canFollow = false; return f }(), "follow(grey) reload(grey) downloads settings"),
            (.screen, .reader, R.Facts(), "downloads settings"),
        ]
        for (kind, place, facts, expected) in cases {
            XCTAssertEqual(shown(kind, place, facts), expected, "\(kind) at \(place)")
        }
    }

    /// Every option has one spec, and every spec shows somewhere.
    func testOneDefinitionEach() {
        XCTAssertEqual(Set(R.specs.map(\.option)).count, R.specs.count)
        XCTAssertEqual(Set(R.specs.map(\.option)), Set(R.Option.allCases))
        XCTAssertFalse(R.table.isEmpty)
        try? R.table.write(toFile: "/tmp/menu-table.md", atomically: true, encoding: .utf8)
    }
}

/// Rows in Edit (no ⋯) and out (with ⋯) are one component, `ListRow`, at one height (C123).
@MainActor
final class ListRowHeightTests: XCTestCase {
    private func height(_ row: ListRow) -> CGFloat {
        let host = UIHostingController(rootView: row.frame(width: 390))
        return host.sizeThatFits(in: CGSize(width: 390, height: 1000)).height
    }

    func testEditAndNormalRowsAreTheSameHeight() {
        let menu = AnyView(Button("Play", systemImage: Icons.play) {})
        for kind: ListRow.Kind in [.folder(count: ["4 articles"]), .folder(count: [])] {
            let normal = height(ListRow(kind: kind, title: "Bonds", subtitle: "1 min", menu: menu))
            let editing = height(ListRow(kind: kind, title: "Bonds", subtitle: "1 min", menu: nil))
            XCTAssertEqual(normal, editing, accuracy: 0.5, "\(kind): normal \(normal), Edit \(editing)")
            XCTAssertEqual(normal, RowHeight.content, accuracy: 0.5, "the 56 pt row")
        }
    }
}
