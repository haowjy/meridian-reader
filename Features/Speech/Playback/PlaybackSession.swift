import Foundation

/// Listen phase — single source of truth for UI. See docs/LISTEN_PLAYBACK.md.
enum PlaybackPhase: Equatable, Sendable {
    case idle
    case prepared
    case playing
    case paused
    case finished
}

/// What the UI / controller wants.
enum PlaybackIntent: Equatable {
    case prepare(startingAt: Int)
    case play(from: Int)
    case pause
    case resume
    case toggle
    case stop
    case skip(delta: Int)
    case seek(paragraph: Int)
    /// Scrubber commit inside a paragraph (Nav I): document UTF-16 offset of a sentence start.
    case seekOffset(utf16: Int)
}

/// Facts reported by Apple / local-engine adapters (never set phase from UI alone).
enum PlaybackEngineEvent: Equatable {
    case becameAudible
    case becamePaused
    case playheadAdvanced(paragraph: Int, utf16Offset: Int?)
    /// Producer still working; do not finish the session.
    case queueStarved
    case finished
    case failed
}

/// Live snapshot of the active adapter — used to decide toggle/pause without trusting phase alone.
struct PlaybackEngineSnapshot: Equatable {
    var isAudible: Bool
    var isPaused: Bool
}

/// Commands the session asks the controller to run on adapters / producer.
enum PlaybackCommand: Equatable {
    case prepareDocument
    case enginePlay(from: Int)
    case enginePause
    case engineResume
    case engineStop
    case engineSeek(paragraph: Int)
}

/// Owns document, playhead, and phase. Engines are dumb; UI binds here only.
@MainActor
struct PlaybackSessionState: Equatable {
    var articleID: UUID?
    var document: ParagraphDocument = .empty
    var playhead: Int = 0
    var utf16Offset: Int = 0
    var phase: PlaybackPhase = .idle

    var isPrepared: Bool { articleID != nil && !document.isEmpty }
    var paragraphCount: Int { document.count }

    mutating func bind(articleID: UUID, document: ParagraphDocument, startingAt: Int) {
        self.articleID = articleID
        self.document = document
        let clamped = document.isEmpty ? 0 : max(0, min(startingAt, document.count - 1))
        playhead = clamped
        utf16Offset = document.isEmpty ? 0 : document.startUTF16Offset(forParagraph: clamped)
        phase = document.isEmpty ? .idle : .prepared
    }

    mutating func clear() {
        articleID = nil
        document = .empty
        playhead = 0
        utf16Offset = 0
        phase = .idle
    }

    /// Intent → commands. Phase updates that need engine confirmation stay tentative only where noted.
    mutating func handle(
        _ intent: PlaybackIntent,
        engine: PlaybackEngineSnapshot
    ) -> [PlaybackCommand] {
        switch intent {
        case .prepare(let startingAt):
            guard isPrepared else { return [.prepareDocument] }
            let clamped = document.isEmpty ? 0 : max(0, min(startingAt, document.count - 1))
            playhead = clamped
            utf16Offset = document.startUTF16Offset(forParagraph: clamped)
            if phase == .idle { phase = .prepared }
            return []

        case .play(let from):
            let clamped = document.isEmpty ? 0 : max(0, min(from, document.count - 1))
            // Play from the playhead keeps a sub-paragraph spot (scrubbed while prepared, Nav I).
            let keepsOffset = clamped == playhead && !document.isEmpty
                && document.index(containingUTF16Offset: utf16Offset) == clamped
            playhead = clamped
            if !keepsOffset {
                utf16Offset = document.isEmpty ? 0 : document.startUTF16Offset(forParagraph: clamped)
            }
            // Tentative playing; engine `becameAudible` confirms. Allows UI to show pause affordance
            // while first local unit prepares — reconcile snaps back if engine never starts.
            phase = .playing
            return [.enginePlay(from: clamped)]

        case .pause:
            // Always tell the engine to pause if anything is audible OR we think we're playing.
            if engine.isAudible || engine.isPaused || phase == .playing || phase == .paused {
                // Optimistic pause only when already paused in engine; otherwise wait for event,
                // but set paused immediately after issuing pause so toggle does not bounce.
                phase = .paused
                return engine.isPaused ? [] : [.enginePause]
            }
            return []

        case .resume:
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
            return [.enginePlay(from: playhead)]

        case .toggle:
            // Audible wins over stale phase (fixes Apple: audio playing, UI paused).
            if engine.isAudible || phase == .playing {
                phase = .paused
                return engine.isPaused ? [] : [.enginePause]
            }
            if engine.isPaused || phase == .paused {
                phase = .playing
                return [.engineResume]
            }
            if isPrepared {
                phase = .playing
                return [.enginePlay(from: playhead)]
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
                return [.engineSeek(paragraph: next)]
            }
            return []

        case .seek(let paragraph):
            guard isPrepared else { return [] }
            let next = max(0, min(document.count - 1, paragraph))
            return seek(toParagraph: next, utf16: document.startUTF16Offset(forParagraph: next), engine: engine)

        case .seekOffset(let utf16):
            guard isPrepared else { return [] }
            let length = (document.joinedText as NSString).length
            let clamped = max(0, min(utf16, max(0, length - 1)))
            return seek(toParagraph: document.index(containingUTF16Offset: clamped), utf16: clamped, engine: engine)
        }
    }

    /// Scrubber commit. Playing keeps playing from the new spot; paused stays paused there (the
    /// engine re-queues at the new spot without sounding, so Play resumes from it); prepared /
    /// finished just move the playhead (and offset) that Play starts from.
    private mutating func seek(toParagraph next: Int, utf16: Int, engine: PlaybackEngineSnapshot) -> [PlaybackCommand] {
        playhead = next
        utf16Offset = utf16
        if phase == .playing || engine.isAudible {
            phase = .playing
            return [.engineSeek(paragraph: next)]
        }
        if phase == .paused || engine.isPaused {
            phase = .paused
            return [.engineSeek(paragraph: next)]
        }
        if phase == .finished { phase = .prepared }
        return []
    }

    mutating func handle(_ event: PlaybackEngineEvent) {
        switch event {
        case .becameAudible:
            if phase != .paused { phase = .playing }
            // If we had optimistically paused but audio is audible, trust the engine.
            if phase == .paused {
                // Keep paused only if we intentionally paused; audible after pause request
                // means pause has not taken yet — stay paused (UI shows pause icon via audible).
            }

        case .becamePaused:
            phase = .paused

        case .playheadAdvanced(let paragraph, let utf16):
            playhead = paragraph
            if let utf16 { utf16Offset = utf16 }

        case .queueStarved:
            break // stay playing/paused; producer will feed more

        case .finished:
            phase = .finished

        case .failed:
            phase = articleID == nil ? .idle : .prepared
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
