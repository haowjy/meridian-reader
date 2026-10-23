import SwiftUI

/// Settings › About › Acknowledgements: open-source TTS and extraction stack used by Meridian.
/// Dense list (same card style as the rest of Settings); licenses match `docs/RELEASE.md`.
struct AcknowledgementsView: View {
    private static let entries: [Entry] = [
        .init(name: "FluidAudio", license: "Apache-2.0",
              detail: "On-device Kokoro TTS (vendored with local patches)"),
        .init(name: "Kokoro", license: "Apache-2.0",
              detail: "82M English voice model (downloaded on device)"),
        .init(name: "Phonon / Gradium", license: "Apache-2.0 / MIT",
              detail: "Phonon 31m English Core ML (ptts)"),
        .init(name: "ONNX Runtime", license: "MIT",
              detail: "Kokoro CPU inference"),
        .init(name: "ZIPFoundation", license: "MIT",
              detail: "EPUB and Phonon model unzip"),
        .init(name: "Mozilla Readability", license: "Apache-2.0",
              detail: "Article extraction from web pages"),
    ]

    var body: some View {
        List {
            Section {
                ForEach(Self.entries) { entry in
                    SymbolRow(entry.name, subtitle: DetailPart("\(entry.license) · \(entry.detail)"),
                              symbol: nil)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("ack-\(entry.id)")
                }
            } footer: {
                Text("All of these licenses are permissive and compatible with App Store distribution. Model weights download to this iPhone when you pick that voice; nothing is uploaded to Meridian.")
                    .listFooter()
            }
            .listCard()
        }
        .cardListStyle()
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
