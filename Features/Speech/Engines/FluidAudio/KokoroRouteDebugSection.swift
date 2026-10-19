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

/// Listen debug panel: Kokoro route knobs. The ONNX CPU route is the default; the Core ML route is
/// an opt-in that can crash in libBNNS on iOS 26.4+ and hands over to ONNX once the app is in the
/// background. The settings belong to `FluidAudioProvider`.
struct KokoroRouteDebugSection: View {
    let kokoro: FluidAudioProvider
    let tts: LocalTTSCoordinator
    @State private var fastGPU: Bool
    @State private var threads: Int
    @State private var busy = false

    init(kokoro: FluidAudioProvider, tts: LocalTTSCoordinator) {
        self.kokoro = kokoro
        self.tts = tts
        _fastGPU = State(initialValue: kokoro.routeSettings.fastGPURouteEnabled)
        _threads = State(initialValue: kokoro.routeSettings.cpuThreads)
    }

    var body: some View {
        Section {
            Toggle("Kokoro fast GPU route (may crash on iOS 26.4+)", isOn: $fastGPU)
                .disabled(busy)
                .onChange(of: fastGPU) { _, on in
                    busy = true
                    Task {
                        if kokoro.setFastGPURoute(on) { await tts.reloadEngine(.kokoro) }
                        busy = false
                    }
                }
                .accessibilityIdentifier("kokoroFastGPURouteToggle")
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
            LabeledContent("ONNX crashes (→ Apple at 2)", value: "\(kokoro.routeSettings.onnxCrashCount)")
        } header: {
            SectionHeader(title: "Kokoro Route").listHeader()
        } footer: {
            Text("Default: ONNX Runtime on the CPU (no Core ML, keeps rendering in the background). "
                 + "The fast GPU route uses Core ML in the foreground only; from the first render in the background until the app quits it uses ONNX. Any Kokoro crash turns it off.")
                .listFooter()
        }
        .listCard()
    }

    private var liveRoute: String {
        guard tts.activeLocalEngineID == .kokoro, let r = tts.synth.hostRouteTag.flatMap(KokoroRoute.init(rawValue:)) else {
            return "not loaded (\(kokoro.routeSettings.route.label) next)"
        }
        return "\(r.label), \(tts.synth.hostRoutingLabel ?? "")"
    }

    private var paceLabel: String {
        let p = RenderPace.shared.snapshot
        guard let s = p.speed else { return "— (\(p.samples) calls)" }
        return String(format: "%.1f× real time (%d calls)", s, p.samples)
    }
}
