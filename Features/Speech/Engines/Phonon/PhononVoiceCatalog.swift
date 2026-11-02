import Foundation

/// Phonon 31m English voices in the shipped model bundle (`PhononModelStore`).
/// Ids match the `.safetensors` file names (no extension). THE place to trim the Settings list.
/// `curated` is the top of the picker (natural long-form reading voices, Zoey first and default);
/// `more` is everything else in the bundle, shown under *More Voices*. Every voice has a sample.
enum PhononVoiceCatalog {
    static let defaultVoice = "Zoey"

    static let curated: [EngineVoice] = [
        voice("Zoey"),
        voice("Freya"),
        voice("Harper"),
        voice("Maeve"),
        voice("Imogen"),
        voice("Miles"),
        voice("Preston"),
        voice("Easton"),
    ]

    static let more: [EngineVoice] = [
        // Natural voices.
        voice("Alfie"),
        voice("Bryony"),
        voice("Delia"),
        voice("Edwin"),
        voice("Elodie-Rose"),
        voice("Everly"),
        voice("Hadley"),
        voice("Hugh"),
        voice("Juniper"),
        voice("Lottie"),
        voice("Micah"),
        voice("Pippa"),
        voice("Russell"),
        voice("Spencer"),
        voice("Teddy"),
        voice("Toby"),
        voice("Trevor"),
        // Character voices.
        voice("Azgorath"),
        voice("Captain Silas Blackwater"),
        voice("Fairy Godmother"),
        voice("Fennick the Young Elf"),
        voice("Grub the Ogre"),
        voice("Master Aldric"),
        voice("Morwenna of the Deep"),
        voice("Old Mortlake"),
        voice("Sir Bramwell"),
        voice("The Snow Queen"),
        voice("The Thing Under the Stairs"),
        voice("Vyrmathrax the Ancient"),
        voice("default", label: "Gradium default"),
    ]

    static let all: [EngineVoice] = curated + more

    /// Its sample is `Resources/VoicePreviews/voice-preview-phonon-<id, lowercased, spaces as
    /// hyphens>.m4a` (`docs/TTS_ENGINES.md`, "Phonon").
    private static func voice(_ id: String, label: String? = nil) -> EngineVoice {
        let slug = id.lowercased().replacingOccurrences(of: " ", with: "-")
        return EngineVoice(id: id, label: label ?? id, previewResource: "voice-preview-phonon-\(slug)")
    }
}
