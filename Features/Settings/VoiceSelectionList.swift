import SwiftUI

/// C138a: the one voice switcher, Settings › Voice (the default for new articles) and an
/// article's or a book's *Voice* picker (`VoicePickerSheet`). One card: each registered engine, in
/// the registry's order, is a row that opens its section in place (`DisclosureRow`), as iOS's
/// Settings groups do, its voices following (with samples and downloads, `VoiceChoiceRows`), or
/// why it can't run on this device. Picking a voice picks its engine.
///
/// ```
/// Phonon                          ⌄
/// ( ▶ )  Zoey                     ✓
///        0.3 MB
/// ( ▶ )  Jude
///        0.3 MB
///        More Voices              ›      an engine's further voices, closed until opened
/// Kokoro                Heart  ◔  ›      closed: the voice in use, a download running in it
/// New articles and books use this voice. …
/// ```
///
/// Open at first: the engine holding the voice in use and any engine with a download running;
/// several can be open, and what is open lasts as long as the screen (nothing stored). A closed
/// engine's row names the voice in use when it holds it, and rings while one of its voices
/// downloads.
struct VoiceSelectionList: View {
    @Bindable var speech: SpeechController
    /// The selection with the checkmark.
    let current: VoiceSelection?
    var footer: String
    /// Why the last pick didn't change anything (a save that failed), under the list.
    var error: String?
    let preview: VoicePreviewPlayer
    /// Removes a downloaded voice (Settings › Voice); nil: this picker removes nothing.
    var onRemove: ((VoiceSelection) -> Void)?
    let onPick: (VoiceSelection) -> Void

    /// The open engines' sections, and the engines whose *More Voices* is open; nil until the
    /// screen first shows (then `startsOpen`).
    @State private var openEngines: Set<SpeechEngineID>?
    @State private var openMore: Set<SpeechEngineID>?
    #if DEBUG
    @Environment(\.voicePageProbe) private var probe
    #endif

    private var localTTS: LocalTTSCoordinator { speech.localTTS }
    private var downloads: VoiceDownloads { localTTS.voiceDownloads }

    private var engines: [EngineDescriptor] {
        localTTS.engines.descriptors.filter { !$0.voices.isEmpty }
    }

    var body: some View {
        Section {
            ForEach(engines, id: \.id) { descriptor in
                engineRows(descriptor)
            }
        } footer: {
            footerText.listFooter()
        }
        .listCard()
        .onAppear {
            if openEngines == nil { openEngines = startsOpen(more: false) }
            if openMore == nil { openMore = startsOpen(more: true) }
        }
    }

    @ViewBuilder
    private func engineRows(_ descriptor: EngineDescriptor) -> some View {
        let id = descriptor.id
        let open = (openEngines ?? startsOpen(more: false)).contains(id)
        let running = downloading(in: descriptor.allVoices, of: id)
        DisclosureRow(title: descriptor.displayName, isOpen: open,
                      value: inUseLabel(in: descriptor.allVoices, of: id),
                      downloading: running.any, fraction: running.fraction,
                      accessibilityID: "engineSection-\(descriptor.shortName.lowercased())") {
            openEngines = (openEngines ?? startsOpen(more: false)).symmetricDifference([id])
        }
        if open {
            if localTTS.engines.supports(id) {
                if case .failed(id, let message) = localTTS.synth.state(of: id) {
                    Text(message)
                        .typeStyle(.caption)
                        .foregroundStyle(Palette.destructive)
                        .padding(.leading, VoiceRow.nameInset)
                }
                voiceRows(descriptor)
                if !descriptor.moreVoices.isEmpty { moreVoicesRows(descriptor) }
            } else {
                Text(localTTS.engines.blockReason(id) ?? String(localized: "Not supported on this device"))
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
    }

    private func voiceRows(_ descriptor: EngineDescriptor) -> some View {
        let id = descriptor.id
        return VoiceChoiceRows(descriptor: descriptor, current: current?.engine == id ? current?.voice : nil,
                               preview: preview, speech: speech, onRemove: onRemove) { voice in
            onPick(VoiceSelection(engine: id, voice: voice.id))
        }
    }

    /// The engine's further voices behind their own row, so its curated ones stay a short list.
    @ViewBuilder
    private func moreVoicesRows(_ descriptor: EngineDescriptor) -> some View {
        let id = descriptor.id
        let open = (openMore ?? startsOpen(more: true)).contains(id)
        let running = downloading(in: descriptor.moreVoices, of: id)
        DisclosureRow(title: String(localized: "More Voices"), isOpen: open,
                      value: inUseLabel(in: descriptor.moreVoices, of: id),
                      downloading: running.any, fraction: running.fraction,
                      leadingInset: VoiceRow.nameInset,
                      accessibilityID: "moreVoices-\(descriptor.shortName.lowercased())") {
            openMore = (openMore ?? startsOpen(more: true)).symmetricDifference([id])
        }
        if open { voiceRows(Self.moreDescriptor(descriptor)) }
    }

    /// The same engine listing only its *More Voices* (`VoiceChoiceRows` lists `voices`).
    private static func moreDescriptor(_ descriptor: EngineDescriptor) -> EngineDescriptor {
        var more = descriptor
        more.voices = descriptor.moreVoices
        return more
    }

    /// What opens first: where the voice in use is and wherever a download runs (`more`: among
    /// the engines' *More Voices*).
    private func startsOpen(more: Bool) -> Set<SpeechEngineID> {
        var open = Set<SpeechEngineID>()
        for descriptor in engines {
            let id = descriptor.id
            let voices = more ? descriptor.moreVoices : descriptor.allVoices
            if inUseLabel(in: voices, of: id) != nil || downloading(in: voices, of: id).any { open.insert(id) }
        }
        if !more, current == nil { open.insert(localTTS.engines.defaultEngine.id) }
        #if DEBUG
        if !more, let name = probe.openSection?.lowercased(),
           let asked = engines.first(where: { $0.shortName.lowercased() == name || $0.id.rawValue == name }) {
            open.insert(asked.id)
        }
        #endif
        return open
    }

    /// The voice in use's name when it is one of `voices`.
    private func inUseLabel(in voices: [EngineVoice], of id: SpeechEngineID) -> String? {
        guard let current, current.engine == id else { return nil }
        return voices.first { $0.id == current.voice }?.label
    }

    /// Whether any of `voices` is downloading, and how far (nil while one hasn't a size yet).
    private func downloading(in voices: [EngineVoice], of id: SpeechEngineID) -> (any: Bool, fraction: Double?) {
        var fractions: [Double?] = []
        for voice in voices {
            if case .downloading(let fraction, _) = downloads.status(of: VoiceSelection(engine: id, voice: voice.id)) {
                fractions.append(fraction)
            }
        }
        guard !fractions.isEmpty else { return (false, nil) }
        let known = fractions.compactMap { $0 }
        return (true, known.count == fractions.count ? known.reduce(0, +) / Double(known.count) : nil)
    }

    /// What the picked voice is for (`footer`), or why the last pick changed nothing.
    @ViewBuilder
    private var footerText: some View {
        if let error {
            Text(error).foregroundStyle(Palette.destructive)
        } else {
            Text(footer)
        }
    }
}
