import SwiftUI

/// Listen debug panel: Kokoro route knobs. The ONNX CPU route is the default; the Core ML route is
/// an opt-in that crashed in libBNNS on iOS 26.4+ and never renders in the background.
struct KokoroRouteDebugSection: View {
    @Bindable var speech: SpeechController
    @State private var fastGPU = KokoroRouteSettings().fastGPURouteEnabled
    @State private var threads = KokoroRouteSettings().cpuThreads
    @State private var busy = false

    private var tts: LocalTTSCoordinator { speech.localTTS }

    var body: some View {
        Section {
            Toggle("Kokoro fast GPU route (may crash on iOS 26.4+)", isOn: $fastGPU)
                .disabled(busy)
                .onChange(of: fastGPU) { _, on in
                    busy = true
                    Task {
                        await tts.setKokoroFastGPURoute(on)
                        speech.applyEngineSelectionChange()
                        busy = false
                    }
                }
                .accessibilityIdentifier("kokoroFastGPURouteToggle")
            Stepper("ONNX threads: \(threads)\(threads == KokoroRouteSettings.defaultThreads ? " (default)" : "")",
                    value: $threads, in: KokoroRouteSettings.threadRange)
                .disabled(busy || fastGPU)
                .onChange(of: threads) { _, n in
                    busy = true
                    Task {
                        await tts.setKokoroCPUThreads(n)
                        speech.applyEngineSelectionChange()
                        busy = false
                    }
                }
            LabeledContent("Live route", value: liveRoute)
            LabeledContent("Render speed", value: paceLabel)
            LabeledContent("ONNX crashes (→ Apple at 2)", value: "\(tts.kokoroRouteSettings.onnxCrashCount)")
        } header: {
            Text("Kokoro route")
        } footer: {
            Text("Default: ONNX Runtime on the CPU (no Core ML, keeps rendering in the background). "
                 + "The fast GPU route uses Core ML in the foreground only; in the background it falls back to Apple for unrendered paragraphs.")
        }
    }

    private var liveRoute: String {
        guard let r = tts.liveKokoroRoute else { return "not loaded (\(tts.kokoroRouteSettings.route.label) next)" }
        return "\(r.label) · \(tts.localEngineInstance.hostRoutingLabel ?? "")"
    }

    private var paceLabel: String {
        let p = RenderPace.shared.snapshot
        guard let s = p.speed else { return "— (\(p.samples) calls)" }
        return String(format: "%.1f× real time (%d calls)", s, p.samples)
    }
}
