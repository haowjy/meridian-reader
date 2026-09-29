import AVFoundation
import Observation

/// Plays the bundled voice preview clips (`Resources/VoicePreviews/<resource>.m4a`, ~5 s,
/// rendered offline with the same engine) from Settings → Listen → Voice.
@MainActor
@Observable
final class VoicePreviewPlayer: NSObject, AVAudioPlayerDelegate {
    private(set) var playingID: String?
    @ObservationIgnored private var player: AVAudioPlayer?

    static func url(forResource name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "m4a", subdirectory: "VoicePreviews")
            ?? Bundle.main.url(forResource: name, withExtension: "m4a")
    }

    static func hasPreview(_ voice: EngineVoice) -> Bool {
        voice.previewResource.flatMap(url(forResource:)) != nil
    }

    func toggle(_ voice: EngineVoice) {
        if playingID == voice.id {
            stop()
            return
        }
        stop()
        guard let name = voice.previewResource, let url = Self.url(forResource: name),
              let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.delegate = self
        self.player = player
        playingID = voice.id
        player.play()
    }

    func stop() {
        player?.stop()
        player = nil
        playingID = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            if self.player === player { self.stop() }
        }
    }
}
