import SwiftData
import XCTest
@testable import Reader

/// The two-store layout against the real models, on file-backed stores: today's store opens
/// under the "local" configuration, the library sits in its own file, an older build's view of
/// the store (and a later one without `SavedArticle`) still opens, folder deletes nullify, and
/// every `LibraryQueries` predicate runs.
@MainActor
final class LibraryStoreConfigurationTests: XCTestCase {
    private var dir: URL!
    private var localURL: URL { dir.appending(path: "default.store") }
    private var libraryURL: URL { dir.appending(path: "library.store") }

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appending(path: "LibraryStoreConfig-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// The container the app opened before the library existed: `ModelContainer(for:)`'s
    /// unnamed configuration over the two old models.
    private func oldStyleContainer() throws -> ModelContainer {
        let schema = Schema([SavedArticle.self, RecentVisit.self])
        return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: localURL))
    }

    private func seedOldStore() throws -> (UUID, UUID) {
        let container = try oldStyleContainer()
        let context = container.mainContext
        let a = SavedArticle(urlString: "https://example.com/a", title: "Legacy A", siteDomain: "example.com",
                             cleanedHTML: "<p>A</p>", plainText: "A", wordCount: 1, estimatedMinutes: 1, excerpt: "",
                             playbackParagraphIndex: 3, faviconData: Data([1, 2, 3, 4]))
        let b = SavedArticle(urlString: "https://example.com/b", title: "Legacy B", siteDomain: "example.com",
                             cleanedHTML: "<p>B</p>", plainText: "B", wordCount: 1, estimatedMinutes: 1, excerpt: "")
        context.insert(a)
        context.insert(b)
        context.insert(RecentVisit(urlString: "https://example.com/r", title: "Recent", host: "example.com",
                                   faviconData: Data([9, 9, 9])))
        try context.save()
        return (a.id, b.id)
    }

    func testOldStoreOpensUnderTheTwoConfigurationsAndSurvivesARollback() throws {
        let (a, b) = try seedOldStore()

        do {
            let container = try LibraryStoreConfiguration.makeContainer(localURL: localURL, libraryURL: libraryURL)
            let context = container.mainContext
            let rows = try context.fetch(FetchDescriptor<SavedArticle>(sortBy: [SortDescriptor(\.title)]))
            XCTAssertEqual(rows.map(\.id), [a, b])
            XCTAssertEqual(rows.first?.faviconData, Data([1, 2, 3, 4]), "external storage read intact")
            XCTAssertEqual(rows.first?.playbackParagraphIndex, 3)
            XCTAssertEqual(try context.fetch(FetchDescriptor<RecentVisit>()).first?.faviconData, Data([9, 9, 9]))

            let folder = Folder(name: "Reading", kind: .plain)
            let page = Page(key: a, title: "Legacy A", byline: "example.com", urlString: "https://example.com/a",
                            contentState: .saved, addedAt: .now)
            context.insert(folder)
            context.insert(page)
            page.setFolder(folder)
            try context.save()
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: libraryURL.path), "the library has its own file")

        // Rollback: the previous build opens only the old store, old-style.
        do {
            let container = try oldStyleContainer()
            let rows = try container.mainContext.fetch(FetchDescriptor<SavedArticle>())
            XCTAssertEqual(Set(rows.map(\.id)), [a, b], "the old build still sees its saves")
        }

        // Forward again: the library file was never opened by the old build, so nothing is lost.
        do {
            let container = try LibraryStoreConfiguration.makeContainer(localURL: localURL, libraryURL: libraryURL)
            let context = container.mainContext
            let pages = try context.fetch(FetchDescriptor<Page>())
            XCTAssertEqual(pages.map(\.key), [a])
            XCTAssertEqual(pages.first?.folder?.name, "Reading")
            XCTAssertEqual(try context.fetch(FetchDescriptor<SavedArticle>()).count, 2)
        }
    }

    /// The "local" configuration's file is the one `ModelContainer(for: SavedArticle.self,
    /// RecentVisit.self)` used, and the app (this test's host) opened it there.
    func testLocalConfigurationIsTodaysDefaultStore() {
        let todays = ModelConfiguration(for: SavedArticle.self, RecentVisit.self)
        XCTAssertEqual(todays.url.standardizedFileURL.path, LibraryStoreConfiguration.localURL.standardizedFileURL.path)
        let unnamed = ModelConfiguration(schema: Schema([SavedArticle.self, RecentVisit.self]))
        XCTAssertEqual(unnamed.url.standardizedFileURL.path, LibraryStoreConfiguration.localURL.standardizedFileURL.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: LibraryStoreConfiguration.localURL.path),
                      "the host app opened the local store at today's URL")
        XCTAssertTrue(FileManager.default.fileExists(atPath: LibraryStoreConfiguration.libraryURL.path),
                      "and the library beside it")
    }

    /// A later release drops `SavedArticle` from the local configuration: the store still opens
    /// and keeps the rest.
    func testLocalConfigurationWithoutSavedArticleOpens() throws {
        _ = try seedOldStore()
        do {
            let container = try LibraryStoreConfiguration.makeContainer(localURL: localURL, libraryURL: libraryURL)
            container.mainContext.insert(Page(key: UUID(), title: "Kept", byline: "example.com",
                                              urlString: "https://example.com/kept", contentState: .saved, addedAt: .now))
            try container.mainContext.save()
        }
        let localModels: [any PersistentModel.Type] = [RecentVisit.self]
        let libraryModels = LibraryStoreConfiguration.libraryModels
        let local = ModelConfiguration("local", schema: Schema(localModels), url: localURL)
        let library = ModelConfiguration("library", schema: Schema(libraryModels), url: libraryURL)
        let container = try ModelContainer(for: Schema(localModels + libraryModels), configurations: [local, library])
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<RecentVisit>()).map(\.title), ["Recent"])
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<Page>()).map(\.title), ["Kept"])
    }

    func testDeletingAFolderNullifiesItsSubfoldersAndPages() throws {
        let container = try LibraryStoreConfiguration.makeContainer(localURL: localURL, libraryURL: libraryURL)
        let context = container.mainContext
        let parent = Folder(name: "Parent")
        let child = Folder(name: "Child")
        let page = Page(key: UUID(), title: "Page", byline: "example.com", urlString: "https://example.com/p",
                        contentState: .saved, addedAt: .now)
        context.insert(parent)
        context.insert(child)
        context.insert(page)
        child.parent = parent
        page.setFolder(parent)
        try context.save()
        XCTAssertEqual(parent.children?.count, 1)
        XCTAssertEqual(parent.pages?.count, 1)

        context.delete(parent)
        try context.save()

        let fresh = ModelContext(container)
        let folders = try fresh.fetch(FetchDescriptor<Folder>())
        XCTAssertEqual(folders.map(\.name), ["Child"])
        XCTAssertNil(folders.first?.parent)
        let pages = try fresh.fetch(FetchDescriptor<Page>())
        XCTAssertEqual(pages.count, 1, "the page survives")
        XCTAssertNil(pages.first?.folder)
    }

    func testEveryLibraryQueryRuns() throws {
        let container = try LibraryStoreConfiguration.makeContainer(localURL: localURL, libraryURL: libraryURL)
        let context = container.mainContext
        let now = Date()
        let old = now.addingTimeInterval(-10 * 24 * 3600)
        func page(_ title: String, state: PageContentState = .saved, added: Date? = now) -> Page {
            let p = Page(key: UUID(), title: title, byline: "example.com", urlString: "https://example.com/\(title)",
                         contentState: state, addedAt: added)
            context.insert(p)
            return p
        }
        let favorites = Folder(name: "", kind: .favorites)
        let book = Folder(name: "A Book", kind: .book)
        context.insert(favorites)
        context.insert(book)
        book.lastPlayedAt = now

        let loose = page("loose")
        loose.lastPlayedAt = now
        loose.positionParagraph = 2
        let undated = page("undated")
        undated.positionParagraph = 1
        let link = page("link", state: .link)
        link.setFolder(favorites)
        link.lastPlayedAt = old
        let unsavedOld = page("unsaved-old", added: nil)
        unsavedOld.lastPlayedAt = old
        let unsavedNew = page("unsaved-new", added: nil)
        unsavedNew.lastPlayedAt = now.addingTimeInterval(-60)
        let chapter = page("chapter")
        chapter.setFolder(book)
        try context.save()

        func titles(_ d: FetchDescriptor<Page>) throws -> Set<String> { Set(try context.fetch(d).map(\.title)) }
        let cutoff = now.addingTimeInterval(-7 * 24 * 3600)
        XCTAssertEqual(try titles(LibraryQueries.inLibrary), ["loose", "undated", "link", "chapter"])
        XCTAssertEqual(try titles(LibraryQueries.savedInLibrary), ["loose", "undated", "chapter"],
                       "saved and in the Library: not the link, not the pages played without saving")
        for sort in PageSort.allCases {
            XCTAssertEqual(try titles(LibraryQueries.loosePages(sort: sort)), ["loose", "undated"], "\(sort)")
        }
        XCTAssertEqual(try titles(LibraryQueries.pages(inFolder: favorites.id)), ["link"])
        XCTAssertEqual(try titles(LibraryQueries.pages(inFolder: book.id)), ["chapter"])
        XCTAssertEqual(try context.fetch(LibraryQueries.recentlyPlayed).map(\.title).first, "loose")
        XCTAssertEqual(try titles(LibraryQueries.recentlyPlayed), ["loose", "link", "unsaved-old", "unsaved-new"])
        XCTAssertEqual(try titles(LibraryQueries.undatedInProgress), ["undated"])
        XCTAssertEqual(try titles(LibraryQueries.search("LOOS")), ["loose"])
        XCTAssertEqual(try titles(LibraryQueries.search("unsaved")), [], "pages not in the Library aren't found")
        XCTAssertEqual(try titles(LibraryQueries.prunable(before: cutoff)), ["unsaved-old"])
        XCTAssertEqual(try titles(LibraryQueries.staleLinkCaches(before: cutoff)), ["link"])
        XCTAssertEqual(try titles(LibraryQueries.page(key: loose.key!)), ["loose"])
        XCTAssertEqual(try titles(LibraryQueries.pages(canonicalURL: "https://example.com/link")), ["link"])
        XCTAssertEqual(try context.fetch(LibraryQueries.continueFolders).map(\.name), ["A Book"])
        XCTAssertEqual(try context.fetch(LibraryQueries.folder(id: book.id)).map(\.name), ["A Book"])
        XCTAssertEqual(try context.fetch(LibraryQueries.favorites).count, 1)
        XCTAssertEqual(try context.fetch(LibraryQueries.searchFolders("book")).map(\.name), ["A Book"])
    }
}
