import SwiftUI

/// Listen debug panel: Kokoro route knobs. The ONNX CPU route is the default; the Core ML route is
/// an opt-in that can crash in libBNNS on iOS 26.4+ and hands over to ONNX once the app is in the
/// background.
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
                        await tts.setKokoroCPUThreads(n)
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
                 + "The fast GPU route uses Core ML in the foreground only; from the first render in the background until the app quits it uses ONNX. Any Kokoro crash turns it off.")
        }
    }

    private var liveRoute: String {
        guard let r = tts.liveKokoroRoute else { return "not loaded (\(tts.kokoroRouteSettings.route.label) next)" }
        return "\(r.label) · \(tts.synth.hostRoutingLabel ?? "")"
    }

    private var paceLabel: String {
        let p = RenderPace.shared.snapshot
        guard let s = p.speed else { return "— (\(p.samples) calls)" }
        return String(format: "%.1f× real time (%d calls)", s, p.samples)
    }
}
