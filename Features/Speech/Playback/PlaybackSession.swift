import Foundation

/// Listen phase — single source of truth for UI. See docs/LISTEN_PLAYBACK.md.
enum PlaybackPhase: Equatable, Sendable {
    case idle
    case prepared
    case playing
    case paused
    case finished
}

/// What the UI / controller wants. On a finished page, `resume`, `toggle` and `play(from:)` at
/// the playhead play it again from its top, whatever spot the voice finished at: the on-screen ▶,
/// headphones, the lock screen and CarPlay all do the same.
enum PlaybackIntent: Equatable {
    case play(from: Int)
    case pause
    case resume
    case toggle
    case stop
    case skip(delta: Int)
    /// Scrubber commit: document UTF-16 offset of a sentence start.
    case seekOffset(utf16: Int)
}

/// Facts reported by the bound engine. Phase and position change only through these and intents.
enum PlaybackEngineEvent: Equatable {
    case becameAudible
    case becamePaused
    /// The spot being spoken: document paragraph and UTF-16 offset.
    case position(paragraph: Int, utf16: Int)
    /// Listen-bar status the engine has no other event for changed (waiting for audio, where the
    /// audio comes from). For the controller; the session ignores it.
    case statusChanged
    case finished
}

/// Live snapshot of the active adapter — used to decide toggle/pause without trusting phase alone.
struct PlaybackEngineSnapshot: Equatable {
    var isAudible: Bool
    var isPaused: Bool
}

/// Commands the session asks the controller to run on adapters / producer. A play or seek speaks
/// from the position the session settled before it asked (`playhead` + `utf16Offset`).
enum PlaybackCommand: Equatable {
    case enginePlay
    case enginePause
    case engineResume
    case engineStop
    /// Speak from the position, held paused when the phase is paused.
    case engineSeek
}

/// Owns the document, the position (`playhead` paragraph + document `utf16Offset`) and the phase.
/// The scrubber, highlight, Now Playing and crash-resume all read the position from here. Engines
/// report facts (`PlaybackEngineEvent`); UI binds here only.
@MainActor
struct PlaybackSessionState: Equatable {
    private(set) var articleID: UUID?
    /// The folder the page is in, which playback carries on through (nil: it plays to its end
    /// and stops).
    private(set) var folderID: UUID?
    private(set) var document: ParagraphDocument = .empty
    /// The text `document` holds (`ArticleIdentity.contentFingerprint` of its paragraphs), set
    /// with it: hashed once per page bound, never per position. Progress is stored on a page, and
    /// the session follows its key to another page, only while that page holds this text
    /// (`LibraryStore.holds`). nil while nothing is bound.
    private(set) var textFingerprint: String?
    var playhead: Int = 0
    var utf16Offset: Int = 0
    var phase: PlaybackPhase = .idle

    var isPrepared: Bool { articleID != nil && !document.isEmpty }
    var paragraphCount: Int { document.count }

    /// What crash-resume reopens: the article and paragraph while playing, with the text the
    /// paragraph is in; nil when paused, stopped or finished (nothing to auto-play).
    var resumePoint: ResumePoint? {
        guard phase == .playing, let articleID, isPrepared else { return nil }
        return ResumePoint(article: articleID, paragraph: playhead, text: textFingerprint)
    }

    struct ResumePoint: Equatable {
        var article: UUID
        var paragraph: Int
        var text: String?
    }

    /// Move the position to document offset `utf16` (clamped to the text): where the next
    /// engine play starts.
    mutating func moveTo(utf16 offset: Int) {
        let length = (document.joinedText as NSString).length
        let clamped = max(0, min(offset, length))
        utf16Offset = clamped
        playhead = document.isEmpty ? 0 : document.index(containingUTF16Offset: clamped)
    }

    /// Binds `document` at `spot` (a stored or chosen start: its offset when that lies in its
    /// paragraph, else the paragraph's start).
    mutating func bind(articleID: UUID, document: ParagraphDocument, at spot: ListenSpot = .top,
                       folderID: UUID? = nil) {
        self.articleID = articleID
        self.folderID = folderID
        self.document = document
        textFingerprint = ArticleIdentity.contentFingerprint(paragraphs: document.paragraphs)
        (playhead, utf16Offset) = spot.resolved(in: document)
        phase = document.isEmpty ? .idle : .prepared
    }

    /// Save landed on a different id than the reader key: the same session continues under `id`.
    mutating func rekey(to id: UUID) {
        guard articleID != nil else { return }
        articleID = id
    }

    mutating func clear() {
        articleID = nil
        folderID = nil
        document = .empty
        textFingerprint = nil
        playhead = 0
        utf16Offset = 0
        phase = .idle
    }

    /// Carrying on through a folder: the next chapter replaces the page in place, at its start.
    /// Playing stays playing (the engine is told to play it); paused stays paused there. No stop
    /// in between. The controller decides before the session sees the engine's `finished`
    /// (`SpeechController+Advance`); only the end of the folder reaches `.finished`.
    mutating func advance(to key: UUID, document next: ParagraphDocument, folderID folder: UUID) -> [PlaybackCommand] {
        articleID = key
        folderID = folder
        document = next
        textFingerprint = ArticleIdentity.contentFingerprint(paragraphs: next.paragraphs)
        playhead = 0
        utf16Offset = 0
        guard !next.isEmpty else {
            phase = .idle
            return []
        }
        if phase == .paused { return [] }
        phase = .playing
        return [.enginePlay]
    }

    /// Intent → commands. Phase updates that need engine confirmation stay tentative only where noted.
    mutating func handle(
        _ intent: PlaybackIntent,
        engine: PlaybackEngineSnapshot
    ) -> [PlaybackCommand] {
        switch intent {
        case .play(let from):
            if phase == .finished, from == playhead { return replay() }
            // Play from the playhead keeps its spot inside the paragraph (scrubbed, or stored).
            (playhead, utf16Offset) = ListenSpot(paragraph: from, utf16Offset: utf16Offset).resolved(in: document)
            // Tentative playing; engine `becameAudible` confirms. Allows UI to show pause affordance
            // while first local unit prepares — reconcile snaps back if engine never starts.
            phase = .playing
            return [.enginePlay]

        case .pause:
            guard engine.isAudible || engine.isPaused || phase == .playing || phase == .paused else { return [] }
            return pause(engine: engine)

        case .resume:
            if phase == .finished { return replay() }
            if engine.isAudible {
                phase = .playing
                return []
            }
            if engine.isPaused || phase == .paused {
                phase = .playing
                return [.engineResume]
            }
            // Nothing to resume — fall through to play from playhead.
            phase = .playing
            return [.enginePlay]

        case .toggle:
            if phase == .finished { return replay() }
            // The engine first: audible is playing whatever the phase says, and a phase left
            // playing or paused with nothing held is prepared again.
            reconcile(with: engine)
            if engine.isAudible || phase == .playing {
                return pause(engine: engine)
            }
            if engine.isPaused || phase == .paused {
                phase = .playing
                return [.engineResume]
            }
            if isPrepared {
                phase = .playing
                return [.enginePlay]
            }
            return []

        case .stop:
            phase = .idle
            return [.engineStop]

        case .skip(let delta):
            guard isPrepared else { return [] }
            let next = max(0, min(document.count - 1, playhead + delta))
            playhead = next
            utf16Offset = document.startUTF16Offset(forParagraph: next)
            if phase == .playing || phase == .paused || engine.isAudible || engine.isPaused {
                let resumePaused = phase == .paused && !engine.isAudible
                phase = resumePaused ? .paused : .playing
                return [.engineSeek]
            }
            return []

        case .seekOffset(let utf16):
            guard isPrepared else { return [] }
            let length = (document.joinedText as NSString).length
            let clamped = max(0, min(utf16, max(0, length - 1)))
            return seek(toParagraph: document.index(containingUTF16Offset: clamped), utf16: clamped, engine: engine)
        }
    }

    /// A finished page plays again from its very start (both coordinates: on a one-paragraph page
    /// the playhead is already paragraph 0).
    private mutating func replay() -> [PlaybackCommand] {
        guard isPrepared else { return [] }
        playhead = 0
        utf16Offset = 0
        phase = .playing
        return [.enginePlay]
    }

    /// The phase turns paused when the engine confirms (`becamePaused`); an engine already
    /// holding its audio confirms through the snapshot.
    private mutating func pause(engine: PlaybackEngineSnapshot) -> [PlaybackCommand] {
        if engine.isPaused {
            phase = .paused
            return []
        }
        return [.enginePause]
    }

    /// Scrubber commit. Playing keeps playing from the new spot; paused stays paused there (the
    /// engine re-queues at the new spot without sounding, so Play resumes from it); prepared /
    /// finished just move the playhead (and offset) that Play starts from.
    private mutating func seek(toParagraph next: Int, utf16: Int, engine: PlaybackEngineSnapshot) -> [PlaybackCommand] {
        playhead = next
        utf16Offset = utf16
        if phase == .playing || engine.isAudible {
            phase = .playing
            return [.engineSeek]
        }
        if phase == .paused || engine.isPaused {
            phase = .paused
            return [.engineSeek]
        }
        if phase == .finished { phase = .prepared }
        return []
    }

    /// The engines lost their audio objects (a media-services reset): a page playing or paused is
    /// held paused at its spot, bound to the engine again without sounding, so Play speaks from
    /// there through new ones.
    mutating func holdForRebuiltEngines() -> [PlaybackCommand] {
        guard isPrepared, phase == .playing || phase == .paused else { return [] }
        phase = .paused
        return [.engineSeek]
    }

    mutating func handle(_ event: PlaybackEngineEvent) {
        switch event {
        case .becameAudible:
            phase = .playing

        case .becamePaused:
            phase = .paused

        case .position(let paragraph, let utf16):
            playhead = paragraph
            utf16Offset = utf16

        case .statusChanged:
            break

        case .finished:
            phase = .finished
        }
    }

    /// Reconcile phase from a fresh engine snapshot (toggle / icon / timer).
    mutating func reconcile(with engine: PlaybackEngineSnapshot) {
        if engine.isAudible {
            phase = .playing
        } else if engine.isPaused {
            phase = .paused
        } else if phase == .playing || phase == .paused {
            phase = articleID == nil ? .idle : .prepared
        }
    }
}
