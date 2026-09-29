import Foundation
import MediaPlayer
import UIKit

/// Lock screen / Control Center / headphone commands, mapped 1:1 onto Session intents by
/// `SpeechController.handleRemoteCommand` (the Session owns playhead + play/pause state; this
/// type holds no playback state of its own).
enum RemoteCommand: Equatable {
    case play, pause, togglePlayPause
    /// Next / previous **paragraph**.
    case nextTrack, previousTrack
    case changePlaybackRate(Double)
}

extension RemoteCommand {
    /// The Session intent this command maps to (nil: not a playhead/phase intent — rate).
    var intent: PlaybackIntent? {
        switch self {
        case .play: return .resume // paused → resume; prepared / finished → play from the playhead
        case .pause: return .pause
        case .togglePlayPause: return .toggle
        case .nextTrack: return .skip(delta: 1)
        case .previousTrack: return .skip(delta: -1) // at paragraph 1: restarts it
        case .changePlaybackRate: return nil
        }
    }
}

enum RemoteCommandOutcome: Equatable {
    case success, noActionableNowPlayingItem, commandFailed

    var mpStatus: MPRemoteCommandHandlerStatus {
        switch self {
        case .success: return .success
        case .noActionableNowPlayingItem: return .noActionableNowPlayingItem
        case .commandFailed: return .commandFailed
        }
    }
}

/// What the lock screen shows. Paragraph progress is "N of M" (audio duration isn't known up
/// front for on-device synthesis, so no fake elapsed-time scrubber).
struct NowPlayingInfo: Equatable {
    var title: String
    var site: String?
    var paragraph: Int
    var paragraphCount: Int
    var isPlaying: Bool
    var rate: Double
    var artwork: Data?

    var progressLabel: String { "Paragraph \(paragraph) of \(paragraphCount)" }
    /// Subtitle line (MPMediaItemPropertyArtist): the lock screen shows title + this line.
    var subtitle: String { [site, progressLabel].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ") }

    var dictionary: [String: Any] {
        var d: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: subtitle,
            MPMediaItemPropertyAlbumTitle: site ?? "Reader",
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyChapterNumber: max(0, paragraph - 1),
            MPNowPlayingInfoPropertyChapterCount: paragraphCount,
            MPNowPlayingInfoPropertyPlaybackProgress: paragraphCount > 0 ? Float(paragraph - 1) / Float(paragraphCount) : 0,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? rate : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
        ]
        if let artwork, let image = UIImage(data: artwork) {
            d[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        return d
    }
}

@MainActor
final class NowPlayingController {
    /// nil in unit tests (no process-wide registration / publishing).
    private let commandCenter: MPRemoteCommandCenter?
    private let infoCenter: MPNowPlayingInfoCenter?
    private(set) var lastInfo: NowPlayingInfo?
    private var registered = false

    init(commandCenter: MPRemoteCommandCenter? = .shared(), infoCenter: MPNowPlayingInfoCenter? = .default()) {
        self.commandCenter = commandCenter
        self.infoCenter = infoCenter
    }

    /// Register handlers once. Every command is routed to `handler` (→ Session intents).
    func attach(rateOptions: [Double], handler: @escaping @MainActor (RemoteCommand) -> RemoteCommandOutcome) {
        guard let c = commandCenter, !registered else { return }
        registered = true
        func add(_ command: MPRemoteCommand, _ make: @escaping (MPRemoteCommandEvent) -> RemoteCommand?) {
            command.isEnabled = true
            command.addTarget { event in
                guard let remote = make(event) else { return .commandFailed }
                // MPRemoteCommandCenter calls targets on the main thread; be defensive anyway.
                guard Thread.isMainThread else {
                    DispatchQueue.main.async { _ = handler(remote) }
                    return .success
                }
                return MainActor.assumeIsolated { handler(remote).mpStatus }
            }
        }
        add(c.playCommand) { _ in .play }
        add(c.pauseCommand) { _ in .pause }
        add(c.togglePlayPauseCommand) { _ in .togglePlayPause }
        add(c.nextTrackCommand) { _ in .nextTrack }
        add(c.previousTrackCommand) { _ in .previousTrack }
        c.changePlaybackRateCommand.supportedPlaybackRates = rateOptions.map { NSNumber(value: $0) }
        add(c.changePlaybackRateCommand) { event in
            (event as? MPChangePlaybackRateCommandEvent).map { .changePlaybackRate(Double($0.playbackRate)) }
        }
        // Time-based commands don't fit paragraph playback.
        for cmd in [c.skipForwardCommand, c.skipBackwardCommand, c.seekForwardCommand,
                    c.seekBackwardCommand, c.changePlaybackPositionCommand] {
            cmd.isEnabled = false
        }
    }

    /// Publish (or clear with nil). Skips identical updates (the playhead ticks often).
    func update(_ info: NowPlayingInfo?, canNext: Bool = true, canPrevious: Bool = true) {
        guard info != lastInfo else { return }
        lastInfo = info
        if let c = commandCenter, registered {
            c.nextTrackCommand.isEnabled = info != nil && canNext
            c.previousTrackCommand.isEnabled = info != nil && canPrevious
        }
        guard let infoCenter else { return }
        infoCenter.nowPlayingInfo = info?.dictionary
    }
}
