import Foundation

/// A screen pushed in the Library: a folder at any depth (a book or series too). Folder ids, so a
/// path survives a relaunch.
enum LibraryRoute: Hashable, Codable {
    case folder(UUID)
}

/// The surface you left (decision D10): the Library with its path, or the browser with its page.
/// The app reopens on it; a fresh install has none and opens the Library. Device-local
/// (UserDefaults `shell.lastSurface`), never synced.
struct SurfaceMemory: Codable, Equatable {
    enum Base: String, Codable {
        case library
        case browse
    }

    var base: Base
    var libraryPath: [LibraryRoute]
    /// The browser's page (nil: the start page). Reloaded at launch.
    var browserURL: String?

    init(base: Base, libraryPath: [LibraryRoute], browserURL: String?) {
        self.base = base
        self.libraryPath = libraryPath
        self.browserURL = browserURL
    }

    /// A stored path element this version has no screen for (the top level's own pages screen
    /// is one) is dropped, so the path still opens the Library at the folders it names.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        base = try container.decode(Base.self, forKey: .base)
        libraryPath = try container.decode([StoredRoute].self, forKey: .libraryPath).compactMap(\.route)
        browserURL = try container.decodeIfPresent(String.self, forKey: .browserURL)
    }

    /// One element of a stored path: the route, or nil when it isn't one this version knows.
    private struct StoredRoute: Decodable {
        let route: LibraryRoute?

        init(from decoder: Decoder) throws {
            route = try? LibraryRoute(from: decoder)
        }
    }
}

/// Where `SurfaceMemory` is kept, with the Library home's tab beside it. The keys are persisted
/// and never change.
struct SurfaceMemoryStore {
    static let key = "shell.lastSurface"
    static let favoritesTabKey = "library.favoritesTab"
    static let storedKeys = [key, favoritesTabKey]

    var defaults: UserDefaults

    static var standard: SurfaceMemoryStore { SurfaceMemoryStore(defaults: .standard) }

    func load() -> SurfaceMemory? {
        defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(SurfaceMemory.self, from: $0) }
    }

    func save(_ memory: SurfaceMemory) {
        guard let data = try? JSONEncoder().encode(memory) else { return }
        defaults.set(data, forKey: Self.key)
    }

    /// The Library home showed Favorites (false: Everything).
    func loadFavoritesTab() -> Bool {
        defaults.bool(forKey: Self.favoritesTabKey)
    }

    func saveFavoritesTab(_ favoritesOnly: Bool) {
        defaults.set(favoritesOnly, forKey: Self.favoritesTabKey)
    }
}
