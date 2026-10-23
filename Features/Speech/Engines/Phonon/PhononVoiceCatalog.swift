import Foundation

/// Phonon 31m English voices shipped in `phonon-31m-en-coreml.zip` (Gradium release v0.4.0).
/// Ids match the `.safetensors` file names (no extension). THE place to trim the Settings list.
/// `curated` is the top of the picker (natural long-form reading voices, Zoey first and default);
/// `more` is everything else in the bundle, shown under *More voices*.
/// Details follow Kokoro's short pattern (accent/region + one tone word), from Gradium's catalog.
enum PhononVoiceCatalog {
    static let defaultVoice = "Zoey"

    static let curated: [EngineVoice] = [
        voice("Zoey", "Playful, American"),
        voice("Freya", "Bright, British"),
        voice("Harper", "Confident, American"),
        voice("Maeve", "Sparky, British"),
        voice("Imogen", "Warm, British"),
        voice("Miles", "Resonant, American male"),
        voice("Preston", "Steady, American male"),
        voice("Easton", "Punchy, American male"),
    ]

    static let more: [EngineVoice] = [
        // Natural voices.
        voice("Alfie", "Punchy, British male"),
        voice("Bryony", "Rich, British"),
        voice("Delia", "Grounded, American"),
        voice("Edwin", "Firm, British male"),
        voice("Elodie-Rose", "Sparky, British"),
        voice("Everly", "Soft, American"),
        voice("Hadley", "Kind, American"),
        voice("Hugh", "Soft, British male"),
        voice("Juniper", "Cheerful, American"),
        voice("Lottie", "Sparky, British"),
        voice("Micah", "Buoyant, American male"),
        voice("Pippa", "Upbeat, British"),
        voice("Russell", "Energetic, American male"),
        voice("Spencer", "Patient, British male"),
        voice("Teddy", "Sparky, British male"),
        voice("Toby", "Attentive, British male"),
        voice("Trevor", "Buoyant, American male"),
        // Character voices.
        voice("Azgorath", "Demon"),
        voice("Captain Silas Blackwater", "Pirate"),
        voice("Fairy Godmother", "Fairy tale"),
        voice("Fennick the Young Elf", "Young elf"),
        voice("Grub the Ogre", "Ogre"),
        voice("Master Aldric", "Wizard"),
        voice("Morwenna of the Deep", "Seductive"),
        voice("Old Mortlake", "Gravedigger"),
        voice("Sir Bramwell", "Knight"),
        voice("The Snow Queen", "Ice queen"),
        voice("The Thing Under the Stairs", "Monster"),
        voice("Vyrmathrax the Ancient", "Dragon"),
        EngineVoice(id: "default", label: "Gradium default", detail: "Neutral default"),
    ]

    static let all: [EngineVoice] = curated + more

    private static func voice(_ id: String, _ detail: String) -> EngineVoice {
        EngineVoice(id: id, label: id, detail: detail)
    }
}
