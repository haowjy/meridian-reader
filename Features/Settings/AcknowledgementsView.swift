import SwiftUI

/// Settings › About › Acknowledgements: open-source TTS and extraction stack used by Meridian.
/// Dense list (same card style as the rest of Settings); licenses match `docs/RELEASE.md`.
struct AcknowledgementsView: View {
    private static let entries: [Entry] = [
        .init(name: "FluidAudio", license: "Apache-2.0",
              detail: "Runs Kokoro’s voices"),
        .init(name: "Kokoro", license: "Apache-2.0",
              detail: "Voices, downloaded when chosen"),
        .init(name: "Phonon / Gradium", license: "Apache-2.0 / MIT",
              detail: "Voices built into the app"),
        .init(name: "ONNX Runtime", license: "MIT",
              detail: "Runs Kokoro’s model"),
        .init(name: "ZIPFoundation", license: "MIT",
              detail: "Opens EPUB books and Phonon’s voices"),
        .init(name: "Mozilla Readability", license: "Apache-2.0",
              detail: "Finds the article on a web page"),
    ]

    var body: some View {
        List {
            Section {
                ForEach(Self.entries) { entry in
                    SymbolRow(entry.name, details: [DetailPart(entry.license), DetailPart(entry.detail)],
                              symbol: nil) { EmptyView() }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("ack-\(entry.id)")
                }
            } footer: {
                Text("Every voice runs on this device. What you read and listen to is never uploaded.")
                    .listFooter()
            }
            .listCard()
        }
        .cardListStyle(startsWithCard: true)
        .navigationTitle(String(localized: "Acknowledgements"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("acknowledgementsList")
    }

    private struct Entry: Identifiable {
        var id: String { name }
        let name: String
        let license: String
        let detail: String
    }
}
