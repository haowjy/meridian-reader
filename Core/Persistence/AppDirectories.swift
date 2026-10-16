import Foundation

/// Where the app keeps its files: all of them under Application Support, named here. The names
/// are persisted: an install finds its library, audio and settings files only where they are. A
/// voice library's own model files are named in its engine folder, under `applicationSupport`.
enum AppDirectories {
    /// `Library/Application Support` in the app's container.
    static var applicationSupport: URL { URL.applicationSupportDirectory }

    /// The library's two SwiftData store files (`LibraryStoreConfiguration`).
    static var localStore: URL { applicationSupport.appending(path: "default.store") }
    static var libraryStore: URL { applicationSupport.appending(path: "library.store") }

    /// Rendered audio, a folder per page key (`ArticleAudioCache`).
    static var audioCache: URL { applicationSupport.appending(path: "TTSCache", directoryHint: .isDirectory) }
    /// Bake jobs waiting for the on-device engine (`PendingBakeJobStore`).
    static var pendingBakeJobs: URL { applicationSupport.appending(path: "PendingBakeJobs.json") }
    /// The download list (`DownloadListStore`).
    static var downloads: URL { applicationSupport.appending(path: "Downloads.json") }
    /// A book's file while it is imported (`BookImportFiles`).
    static var imports: URL { applicationSupport.appending(path: "Imports", directoryHint: .isDirectory) }
    /// The frozen bookmarks file the library migration reads (`LegacyBookmarks`).
    static var legacyBookmarks: URL { applicationSupport.appending(path: "Bookmarks/bookmarks.json") }

    /// The timing log (`ListenTimingLog`) and the engine crash guard's markers (`EngineCrashGuard`).
    static var listenTiming: URL { applicationSupport.appending(path: "ListenTiming", directoryHint: .isDirectory) }
    /// The crash-resume point (`ListenResumePointStore`).
    static var listenResumePoint: URL { listenTiming.appending(path: "listen_resume.json") }
}
