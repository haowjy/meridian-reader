import SwiftData
import XCTest
@testable import Reader

/// Order among siblings is a fractional `sortKey`: a move writes only what moved, many moves never
/// collide, and the siblings are renumbered in one pass once a gap would get under 1e-9. Edit's
/// drag reorders pages and subfolders through it.
@MainActor
final class LibrarySortKeyTests: XCTestCase {
    private var env: LibraryTestEnvironment!
    private var library: LibraryStore { env.library }

    override func setUp() async throws { env = try LibraryTestEnvironment() }
    override func tearDown() async throws { env.cleanUp() }

    /// A stand-in sibling: only the key matters.
    private final class Item {
        let name: String
        var key: Double
        init(_ name: String, _ key: Double) { self.name = name; self.key = key }
    }

    func testAMoveWritesOnlyTheMovedKeyBetweenItsNeighbours() {
        let items = (0..<4).map { Item("\($0)", Double($0)) }
        FractionalOrder.move([items[3]], among: items, before: items[1], key: \.key)
        XCTAssertEqual(items[3].key, 0.5, accuracy: 1e-12)
        XCTAssertEqual(items.prefix(3).map(\.key), [0, 1, 2], "nothing else written")
    }

    func testManyMovesNeverCollideAndATinyGapRenumbers() {
        let items = (0..<3).map { Item("\($0)", Double($0)) }
        var renumbered = false
        // Halve the gap between 0 and the item after it again and again: 1e-9 comes after ~30.
        for _ in 0..<60 {
            let ordered = items.sorted { $0.key < $1.key }
            FractionalOrder.move([ordered[2]], among: ordered, before: ordered[1], key: \.key)
            let keys = items.map(\.key)
            XCTAssertEqual(Set(keys).count, keys.count, "no two siblings share a key")
            if keys.allSatisfy({ $0 == $0.rounded() }) && keys.sorted() == [0, 1, 2] { renumbered = true }
            let sorted = keys.sorted()
            XCTAssertGreaterThanOrEqual(zip(sorted, sorted.dropFirst()).map { $1 - $0 }.min() ?? 1,
                                        FractionalOrder.minimumGap, "a gap never gets under the limit")
        }
        XCTAssertTrue(renumbered, "the siblings were renumbered once the gap got tiny")
    }

    func testSubfoldersReorderAndFavoritesStaysFirst() throws {
        library.favorites()
        let a = try library.makeFolder(name: "A", in: nil)
        let b = try library.makeFolder(name: "B", in: nil)
        let c = try library.makeFolder(name: "C", in: nil)
        try library.reorderFolders([c], in: nil, before: a)
        XCTAssertEqual(library.topLevelFolders().map(\.displayName), ["Favorites", "C", "A", "B"])
        let shelf = try library.makeFolder(name: "Shelf", in: a)
        let other = try library.makeFolder(name: "Other", in: a)
        try library.reorderFolders([other], in: a, before: shelf)
        XCTAssertEqual(library.subfolders(of: a).map(\.name), ["Other", "Shelf"])
        for _ in 0..<50 {
            try library.reorderFolders([b], in: nil, before: c)
            try library.reorderFolders([c], in: nil, before: b)
        }
        let keys = library.topLevelFolders().filter { $0.kind != .favorites }.map(\.sortKey)
        XCTAssertEqual(Set(keys).count, keys.count, "many moves never collide")
        XCTAssertEqual(library.topLevelFolders().first?.kind, .favorites)
    }
}
