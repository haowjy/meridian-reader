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
            (.page, .row, savedLoose, "read download favorite move finished share save"),
            (.page, .row, chapter, "read download favorite move finished playback[markAllAbove,skip] save"),
            (.page, .reader, chapter, "download favorite move finished playback[skip]"),
            (.page, .row, unsavedWeb, "read download(grey) favorite move finished(grey) share save removeFromRecent"),
            (.page, .browser, R.Facts(), "download(grey) favorite(grey) move finished(grey) removeFromRecent(grey)"),
            (.page, .bar, savedLoose, "read download favorite move finished share save stopListening(grey)"),
            (.page, .history, unsavedWeb, "read download(grey) favorite move finished(grey) share save removeFromRecent removeFromHistory"),
            (.page, .nowPlaying, savedLoose, "goTo download favorite move finished share"),
            (.folder, .row, R.Facts(), "continueFolder(grey) folderDownload(grey) folderFavorite folderMove editDetails deleteFolder"),
            (.folder, .header, { var f = R.Facts(); f.hasPagesToPlay = true; f.hasPages = true; return f }(),
             "playFromStart removeDownloads(grey) folderFavorite folderMove editDetails deleteFolder"),
            (.download, .downloads, { var f = R.Facts(); f.isQueued = true; return f }(), "redownload(grey) keep(grey) removeDownload"),
            (.screen, .libraryHome, R.Facts(), "sort downloads settings"),
            (.screen, .folderScreen, R.Facts(), "sort downloads settings"),
            (.screen, .folderScreen, { var f = R.Facts(); f.isFixedOrder = true; return f }(), "downloads settings"),
            (.screen, .add, R.Facts(), "newFolder importFile follow"),
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
