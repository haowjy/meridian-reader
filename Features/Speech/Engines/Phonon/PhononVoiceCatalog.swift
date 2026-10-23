import Foundation

/// Phonon 31m English voices shipped in `phonon-31m-en-coreml.zip` (Gradium release v0.4.0).
/// Ids match the `.safetensors` file names (no extension). THE place to trim the Settings list.
/// `curated` is the top of the picker (natural long-form reading voices, Zoey first and default);
/// `more` is everything else in the bundle, shown under *More voices*.
enum PhononVoiceCatalog {
    static let defaultVoice = "Zoey"

    static let curated: [EngineVoice] = [
        "Zoey", "Freya", "Harper", "Maeve", "Imogen", "Miles", "Preston", "Easton",
    ].map { EngineVoice(id: $0, label: $0) }

    static let more: [EngineVoice] = [
        "Alfie", "Bryony", "Delia", "Edwin", "Elodie-Rose", "Everly", "Hadley", "Hugh", "Juniper",
        "Lottie", "Micah", "Pippa", "Russell", "Spencer", "Teddy", "Toby", "Trevor",
        // Character voices.
        "Azgorath", "Captain Silas Blackwater", "Fairy Godmother", "Fennick the Young Elf",
        "Grub the Ogre", "Master Aldric", "Morwenna of the Deep", "Old Mortlake", "Sir Bramwell",
        "The Snow Queen", "The Thing Under the Stairs", "Vyrmathrax the Ancient",
        "default",
    ].map { EngineVoice(id: $0, label: $0 == "default" ? "Gradium default" : $0) }

    static let all: [EngineVoice] = curated + more
}
