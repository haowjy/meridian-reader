import Foundation

/// The Kokoro voices Reader offers (Settings → Listen → Voice). THE place to swap voices:
/// edit one line. Each id must be a FluidAudio English pack (`KokoroAneConstants.englishVoices`;
/// non-default packs download ~0.5 MB on select) and should have a bundled preview clip
/// `Resources/VoicePreviews/voice-preview-kokoro-<id>.m4a` (see docs/LISTEN_PLAYBACK.md for how
/// the clips were rendered).
enum KokoroVoiceCatalog {
    static let defaultVoice = "af_heart"

    static let curated: [EngineVoice] = [
        voice("af_heart", "Heart", "Warm · American"),
        voice("af_bella", "Bella", "Bright · American"),
        voice("bf_emma", "Emma", "British"),
        voice("am_puck", "Puck", "American male"),
        voice("bm_fable", "Fable", "British male"),
    ]

    private static func voice(_ id: String, _ label: String, _ detail: String) -> EngineVoice {
        EngineVoice(id: id, label: label, detail: detail, previewResource: "voice-preview-kokoro-\(id)")
    }
}
