import Foundation

/// Phonon 31m English voices shipped in `phonon-31m-en-coreml.zip` (Gradium release v0.4.0).
/// Ids match the `.safetensors` file names (no extension). THE place to trim the Settings list.
enum PhononVoiceCatalog {
    static let defaultVoice = "default"

    /// Full release set. Labels are the voice names as Gradium ships them.
    static let curated: [EngineVoice] = names.map { EngineVoice(id: $0, label: $0 == "default" ? "Default" : $0) }

    private static let names: [String] = [
        "default",
        "Alfie", "Azgorath", "Bryony", "Captain Silas Blackwater", "Delia", "Easton", "Edwin",
        "Elodie-Rose", "Everly", "Fairy Godmother", "Fennick the Young Elf", "Freya", "Grub the Ogre",
        "Hadley", "Harper", "Hugh", "Imogen", "Juniper", "Lottie", "Maeve", "Master Aldric", "Micah",
        "Miles", "Morwenna of the Deep", "Old Mortlake", "Pippa", "Preston", "Russell", "Sir Bramwell",
        "Spencer", "Teddy", "The Snow Queen", "The Thing Under the Stairs", "Toby", "Trevor",
        "Vyrmathrax the Ancient", "Zoey",
    ]
}
