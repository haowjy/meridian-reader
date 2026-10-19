import Foundation

/// The lock screen and Control Center: what they show (`NowPlayingController`, built from
/// `nowPlaying` like the bar) and the commands they, headphones and CarPlay send. See
/// docs/LISTEN_PLAYBACK.md, "Background listening".
extension SpeechController {
    // MARK: - Remote commands (lock screen / Control Center / headphones)

    /// Every remote command becomes a Session intent — the same path as the on-screen buttons.
    @discardableResult
    func handleRemoteCommand(_ command: RemoteCommand) -> RemoteCommandOutcome {
        guard playback.isPrepared else { return .noActionableNowPlayingItem }
        ListenTimingLog.log("remote_command", [
            "cmd": String(describing: command), "phase": String(describing: playback.phase), "p": playback.playhead,
        ])
        switch command {
        case .changePlaybackRate(let rate):
            noteUserIntent()
            setRateMultiplier(rate)
            return .success
        case .nextTrack where !canSkipToNextParagraph, .previousTrack where !canSkipToPreviousParagraph:
            return .commandFailed
        default:
            guard let intent = command.intent else { return .commandFailed }
            userPerform(intent)
            return .success
        }
    }

    // MARK: - Now Playing

    /// The lock screen shows what the bar shows (`nowPlaying`), while it plays or is paused; its
    /// ⏮ ⏭ follow the on-screen ones. An untitled web page's title is already its site, so its
    /// subtitle leaves the site's byline out, as the bar does (a chapter's byline is the book's
    /// author, which its title doesn't name).
    func refreshNowPlaying() {
        guard let now = nowPlaying, now.phase == .playing || now.phase == .paused else {
            lockScreen.update(nil)
            return
        }
        var album = now.byline
        if case .folder(_, let name) = now.playingFrom { album = name }
        let info = NowPlayingInfo(
            title: now.lineOne, site: now.title == nil && !now.isChapter ? nil : now.byline, album: album,
            paragraph: currentParagraphIndex + 1, paragraphCount: document.count,
            isPlaying: now.phase == .playing, rate: rateMultiplier, artwork: now.artwork)
        lockScreen.update(info, canNext: canSkipToNextParagraph, canPrevious: canSkipToPreviousParagraph)
    }
}
