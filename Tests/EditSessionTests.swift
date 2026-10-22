import Foundation
import Testing
@testable import MeridianReader

/// Cancel reverts every edit made during the session (C148).
@MainActor
struct EditSessionTests {
    /// A reorder done during an edit session is undone when the session is cancelled.
    @Test func cancelRevertsReorder() throws {
        let env = try LibraryTestEnvironment()
        defer { env.cleanUp() }
        let library = env.library!

        // Build a folder with three articles in manual order: A, B, C.
        let folder = try library.makeFolder(name: "Folder", in: nil)
        let aURL = "https://example.com/a"
        let bURL = "https://example.com/b"
        let cURL = "https://example.com/c"
        let saved = try library.save(env.article(aURL, title: "A"))
        try library.move([.article(saved)], to: folder)
        let savedB = try library.save(env.article(bURL, title: "B"))
        try library.move([.article(savedB)], to: folder)
        let savedC = try library.save(env.article(cURL, title: "C"))
        try library.move([.article(savedC)], to: folder)

        let originalOrder = library.articles(in: folder).map(\.givenTitle)
        #expect(originalOrder == ["A", "B", "C"])

        // Begin an edit session: all changes stage without saving.
        library.beginEditSession()

        // Reorder: move C before A.
        let c = library.articles(in: folder).first { $0.givenTitle == "C" }!
        let a = library.articles(in: folder).first { $0.givenTitle == "A" }!
        try library.arrange([c], in: folder, before: a, shownIn: .manual)

        let reorderedOrder = library.articles(in: folder).map(\.givenTitle)
        #expect(reorderedOrder == ["C", "A", "B"])

        // Cancel: every change rolls back.
        library.cancelEditSession()

        let restoredOrder = library.articles(in: folder).map(\.givenTitle)
        #expect(restoredOrder == ["A", "B", "C"])
    }
}
