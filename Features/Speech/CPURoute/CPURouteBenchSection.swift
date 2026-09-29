import SwiftUI

/// "CPU route benchmark" section of the Listen debug panel (debug-only; see `CPURouteBench`).
struct CPURouteBenchSection: View {
    @Bindable var speech: SpeechController
    @Bindable private var bench = CPURouteBench.shared
    private var store: CPURouteModelStore { CPURouteModelStore.shared }

    var body: some View {
        Section {
            LabeledContent("Background GPU", value: CPURouteProbes.backgroundGPULabel)
                .accessibilityIdentifier("cpuBenchGPUProbe")
            modelRows
            Button(bench.isRunning ? "Benchmark running…" : "Run CPU benchmark") {
                Task { await bench.runBenchmark(coordinator: speech.localTTS) }
            }
            .disabled(!store.isInstalled || bench.isRunning || bench.soakRunning)
            .accessibilityIdentifier("cpuBenchRun")
            Text(bench.status)
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(bench.rows) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.label).font(.caption.weight(.semibold))
                    if let err = row.error {
                        Text(err).font(.caption2).foregroundStyle(.red)
                    } else {
                        Text(String(format: "501: %.2f×  190: %.2f×  load %d ms  cold %d ms", row.x501, row.x190, row.loadMs, row.coldMs))
                            .font(.system(.caption2, design: .monospaced))
                        Text(String(format: "CPU %.2f s/audio-s  peak %.0f MB  %@", row.cpuPerAudio501, row.peakMB, row.thermal))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if bench.sampleExists {
                Button(bench.isPlayingSample ? "Stop sample" : "Play ONNX sample (501 tokens, −3 dB)") {
                    bench.toggleSample()
                }
                .accessibilityIdentifier("cpuBenchPlaySample")
            }
            Toggle("Soak: render continuously for \(bench.soakMinutes) minutes", isOn: Binding(
                get: { bench.soakRunning },
                set: { $0 ? bench.startSoak(speech: speech) : bench.stopSoak() }
            ))
            .disabled(!store.isInstalled || bench.isRunning)
            .accessibilityIdentifier("cpuBenchSoak")
            Stepper("Soak length: \(bench.soakMinutes) min", value: $bench.soakMinutes, in: 1...120)
                .disabled(bench.soakRunning)
            Text(bench.soakStatus)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
        } header: {
            Text("CPU route benchmark")
        } footer: {
            Text("ONNX Runtime on CPU (Kokoro fp16) with FluidAudio's phonemes + af_heart. Benchmark ≈2–3 min; pauses the bake queue. Soak: start it, lock the phone, come back. Results: Application Support/ListenTiming/cpubench.jsonl.")
        }
    }

    @ViewBuilder
    private var modelRows: some View {
        switch store.state {
        case .notDownloaded:
            Button("Download CPU model (163 MB)") { store.download() }
                .accessibilityIdentifier("cpuBenchDownload")
        case let .downloading(fraction, written, total):
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: fraction)
                Text("\(FileSizes.label(written)) / \(FileSizes.label(total))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Button("Cancel download", role: .destructive) { store.cancel() }
                .accessibilityIdentifier("cpuBenchCancelDownload")
        case .verifying:
            HStack { ProgressView(); Text("Verifying SHA-256…").foregroundStyle(.secondary) }
        case let .installed(bytes):
            LabeledContent("CPU model", value: "installed · \(FileSizes.label(bytes))")
            Button("Delete CPU model", role: .destructive) { store.delete() }
                .disabled(bench.isRunning || bench.soakRunning)
                .accessibilityIdentifier("cpuBenchDeleteModel")
        case let .failed(message):
            Text(message).font(.caption).foregroundStyle(.red)
            Button("Retry download (163 MB)") { store.download() }
                .accessibilityIdentifier("cpuBenchDownload")
        }
    }
}
