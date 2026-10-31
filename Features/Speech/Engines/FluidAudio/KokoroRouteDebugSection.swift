import SwiftUI

extension FluidAudioProvider {
    /// The Kokoro route knobs; a Debug build adds the CPU route benchmark.
    func debugSections(speech: SpeechController) -> AnyView {
        AnyView(Group {
            KokoroRouteDebugSection(kokoro: self, tts: speech.localTTS)
            #if DEBUG
            CPURouteBenchSection(speech: speech)
            #endif
        })
    }
}

/// Listen debug panel: Kokoro's ONNX CPU route knobs. The settings belong to `FluidAudioProvider`.
struct KokoroRouteDebugSection: View {
    let kokoro: FluidAudioProvider
    let tts: LocalTTSCoordinator
    @State private var threads: Int
    @State private var busy = false

    init(kokoro: FluidAudioProvider, tts: LocalTTSCoordinator) {
        self.kokoro = kokoro
        self.tts = tts
        _threads = State(initialValue: kokoro.routeSettings.cpuThreads)
    }

    var body: some View {
        Section {
            Stepper("ONNX threads: \(threads)\(threads == KokoroRouteSettings.defaultThreads ? " (default)" : "")",
                    value: $threads, in: KokoroRouteSettings.threadRange)
                .disabled(busy)
                .onChange(of: threads) { _, n in
                    busy = true
                    Task {
                        if kokoro.setCPUThreads(n) { await tts.reloadEngine(.kokoro) }
                        busy = false
                    }
                }
            LabeledContent("Live route", value: liveRoute)
            LabeledContent("Render speed", value: paceLabel)
            LabeledContent("ONNX crashes (pauses for Retry at 2)", value: "\(kokoro.routeSettings.onnxCrashCount)")
        } header: {
            SectionHeader(title: "Kokoro Route").listHeader()
        } footer: {
            Text("ONNX Runtime on the CPU (no Core ML, keeps rendering in the background), one thread in the background. "
                 + "A crash resumes on one thread fewer.")
                .listFooter()
        }
        .listCard()
    }

    private var liveRoute: String {
        guard tts.activeLocalEngineID == .kokoro, let label = tts.synth.hostRoutingLabel else { return "not loaded" }
        return label
    }

    private var paceLabel: String {
        let p = RenderPace.shared.snapshot
        guard let s = p.speed else { return "— (\(p.samples) calls)" }
        return String(format: "%.1f× real time (%d calls)", s, p.samples)
    }
}
