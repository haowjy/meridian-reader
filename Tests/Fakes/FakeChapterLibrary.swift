import Foundation
@testable import Reader

/// A book (or series) for playback to carry on through, in memory: `NextChapterProviding`
/// without SwiftData. Records the chapters it was told finished and the fetches it was asked for;
/// a link chapter's fetch answers `fetchResult` after `fetchDelay`, and turns it saved.
@MainActor
final class FakeChapterLibrary: NextChapterProviding {
    struct Spec {
        var title: String
        var paragraphs = ["The first paragraph of a chapter.", "Its second paragraph.", "And its third."]
        var skips = false
        var isLink = false
        var blockedReason: String?
    }

    let folder: PlaybackFolder
    private(set) var sessions: [SpeechSession]
    private(set) var chapters: [ChapterAdvance.Chapter]
    private(set) var finished: [UUID] = []
    private(set) var fetched: [UUID] = []
    var fetchResult = true
    var fetchDelay: TimeInterval = 0

    init(name: String = "The Book", _ specs: [Spec]) {
        let folder = PlaybackFolder(id: UUID(), name: name)
        self.folder = folder
        sessions = specs.map { spec in
            SpeechSession(id: UUID(), document: ParagraphDocument(parts: spec.paragraphs.map { "\(spec.title): \($0)" }),
                          detectedLanguage: "en", title: spec.title, site: "An Author", folderID: folder.id,
                          folderName: name)
        }
        chapters = zip(sessions, specs).map { session, spec in
            ChapterAdvance.Chapter(key: session.id, isLink: spec.isLink, skipsInPlayback: spec.skips,
                                   blockedReason: spec.blockedReason)
        }
    }

    /// Chapters titled "Chapter 1"…, none skipped.
    convenience init(chapters count: Int) {
        self.init((1...count).map { Spec(title: "Chapter \($0)") })
    }

    func key(_ index: Int) -> UUID { sessions[index].id }

    func folder(containing pageKey: UUID) -> PlaybackFolder? {
        sessions.contains { $0.id == pageKey } ? folder : nil
    }

    func chapters(of folderID: UUID) -> [ChapterAdvance.Chapter] {
        folderID == folder.id ? chapters : []
    }

    func load(_ pageKey: UUID) -> SpeechSession? {
        guard let index = sessions.firstIndex(where: { $0.id == pageKey }), !chapters[index].isLink else { return nil }
        return sessions[index]
    }

    func fetch(_ pageKey: UUID) async -> Bool {
        fetched.append(pageKey)
        if fetchDelay > 0 { try? await Task.sleep(nanoseconds: UInt64(fetchDelay * 1_000_000_000)) }
        if fetchResult, let index = sessions.firstIndex(where: { $0.id == pageKey }) { chapters[index].isLink = false }
        return fetchResult
    }

    func pageFinished(key: UUID, text: String?) {
        finished.append(key)
        if let index = sessions.firstIndex(where: { $0.id == key }) { chapters[index].isFinished = true }
    }
}
