import Foundation

/// A screen pushed in the Library: a folder at any depth (a book or series too), or the top
/// level's pages (*Pages · Show All*). Folder ids, so a path survives a relaunch.
enum LibraryRoute: Hashable, Codable {
    case folder(UUID)
    case pages
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
}

/// Where `SurfaceMemory` is kept. The key is persisted and never changes.
struct SurfaceMemoryStore {
    static let key = "shell.lastSurface"

    var defaults: UserDefaults

    static var standard: SurfaceMemoryStore { SurfaceMemoryStore(defaults: .standard) }

    func load() -> SurfaceMemory? {
        defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(SurfaceMemory.self, from: $0) }
    }

    func save(_ memory: SurfaceMemory) {
        guard let data = try? JSONEncoder().encode(memory) else { return }
        defaults.set(data, forKey: Self.key)
    }

    func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}
