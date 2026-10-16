import SwiftUI

/// Listen debug panel: Kokoro route knobs. The ONNX CPU route is the default; the Core ML route is
/// an opt-in that can crash in libBNNS on iOS 26.4+ and hands over to ONNX once the app is in the
/// background. The settings belong to `FluidAudioProvider`.
struct KokoroRouteDebugSection: View {
    @Bindable var speech: SpeechController
    @State private var fastGPU: Bool
    @State private var threads: Int
    @State private var busy = false

    init(speech: SpeechController) {
        self.speech = speech
        let settings = speech.localTTS.engines.provider(FluidAudioProvider.self)?.routeSettings
        _fastGPU = State(initialValue: settings?.fastGPURouteEnabled ?? false)
        _threads = State(initialValue: settings?.cpuThreads ?? KokoroRouteSettings.defaultThreads)
    }

    private var tts: LocalTTSCoordinator { speech.localTTS }
    private var kokoro: FluidAudioProvider? { tts.engines.provider(FluidAudioProvider.self) }

    var body: some View {
        Section {
            Toggle("Kokoro fast GPU route (may crash on iOS 26.4+)", isOn: $fastGPU)
                .disabled(busy)
                .onChange(of: fastGPU) { _, on in
                    busy = true
                    Task {
                        if kokoro?.setFastGPURoute(on) == true { await tts.reloadEngine(.kokoro) }
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
                        if kokoro?.setCPUThreads(n) == true { await tts.reloadEngine(.kokoro) }
                        busy = false
                    }
                }
            LabeledContent("Live route", value: liveRoute)
            LabeledContent("Render speed", value: paceLabel)
            LabeledContent("ONNX crashes (→ Apple at 2)", value: "\(kokoro?.routeSettings.onnxCrashCount ?? 0)")
        } header: {
            Text("Kokoro route")
        } footer: {
            Text("Default: ONNX Runtime on the CPU (no Core ML, keeps rendering in the background). "
                 + "The fast GPU route uses Core ML in the foreground only; from the first render in the background until the app quits it uses ONNX. Any Kokoro crash turns it off.")
        }
    }

    private var liveRoute: String {
        guard tts.activeLocalEngineID == .kokoro, let r = tts.synth.hostRouteTag.flatMap(KokoroRoute.init(rawValue:)) else {
            return "not loaded (\(kokoro?.routeSettings.route.label ?? "—") next)"
        }
        return "\(r.label) · \(tts.synth.hostRoutingLabel ?? "")"
    }

    private var paceLabel: String {
        let p = RenderPace.shared.snapshot
        guard let s = p.speed else { return "— (\(p.samples) calls)" }
        return String(format: "%.1f× real time (%d calls)", s, p.samples)
    }
}
