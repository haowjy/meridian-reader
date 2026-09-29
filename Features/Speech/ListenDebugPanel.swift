import SwiftUI

/// Developer overlay for local-engine listen gaps / bake queue.
/// Open: Settings → Listen → Listen debug (toggle + Open panel), Debug chip on the listen bar,
/// or long-press play/pause.
struct ListenDebugPanel: View {
    @Bindable var speech: SpeechController
    @Environment(\.dismiss) private var dismiss

    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    @State private var snapshot: ListenDebugSnapshot?

    var body: some View {
        NavigationStack {
            List {
                if let snapshot {
                    Section("Article / queue") {
                        row("Article", snapshot.articleIdentity)
                        row("Queue #1", snapshot.queuePrimary)
                        row("Demoted", "\(snapshot.demotedCount)")
                        row("Active bake", snapshot.activeBakeUnit)
                        row("Next missing", snapshot.nextMissingUnit)
                        row("Worker", snapshot.workerBusy ? "busy" : "idle")
                        row("Warming local engine", snapshot.warmingLocal ? "yes" : "no")
                        row("Plan", snapshot.bakePlan)
                        row("Cache ready", "\(snapshot.bakeReadyCount) / \(snapshot.bakeParagraphCount)")
                        row("Bake %", bakePercentLabel(snapshot))
                        row("Pending units", "\(snapshot.bakePendingJobs)")
                        row("Last bake", snapshot.lastBakeEvent)
                    }
                    Section("Session") {
                        row("Phase", snapshot.phaseLabel)
                        row("Engine", snapshot.engine)
                        row("Render mode", snapshot.renderMode)
                        row("Ready ahead", "\(snapshot.readyAhead) paragraphs")
                        row("Background", snapshot.background)
                        row("Audio session", snapshot.audioSession)
                        row("Language", snapshot.language)
                        row("Audible", snapshot.isAudible ? "yes" : "no")
                        row("isSpeaking", snapshot.isSpeaking ? "yes" : "no")
                        row("isPaused", snapshot.isPaused ? "yes" : "no")
                        row("Playhead", "\(snapshot.playhead + 1) / \(max(snapshot.paragraphCount, 0))")
                    }
                    Section("Local synth queue") {
                        row("Buffered", "\(snapshot.bufferedCount)")
                        row("awaitingMore", snapshot.awaitingMore ? "yes" : "no")
                        row("producerActive", snapshot.producerActive ? "yes" : "no")
                        row("epoch", "\(snapshot.epoch)")
                        row("CAF", snapshot.currentCAF)
                        row(
                            "Since enqueue",
                            snapshot.secondsSinceEnqueue.map { String(format: "%.2fs", $0) } ?? "—"
                        )
                        row(
                            "Last handoff",
                            String(
                                format: "%.0fms %@",
                                snapshot.lastHandoffGapMs,
                                snapshot.lastHandoffWasPrimed ? "(primed)" : "(cold)"
                            )
                        )
                        row("Starve events", "\(snapshot.starveEventCount)")
                    }
                } else {
                    Text("No snapshot yet").foregroundStyle(.secondary)
                }

                Section {
                    Button(EngineLatencyProbe.isRunning ? "Engine probe running…" : "Run engine probe (on-device engines)") {
                        Task { await EngineLatencyProbe.run(coordinator: speech.localTTS) }
                    }
                    .disabled(EngineLatencyProbe.isRunning)
                    .accessibilityIdentifier("runEngineProbe")
                } footer: {
                    Text("Writes Documents/engine_probe.txt. Takes ~1–2 min; don't listen meanwhile.")
                }

                KokoroRouteDebugSection(speech: speech)

                CPURouteBenchSection(speech: speech)

                Section("Log (last \(ListenDebugLog.shared.lines.count))") {
                    if ListenDebugLog.shared.lines.isEmpty {
                        Text("Empty").foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(ListenDebugLog.shared.lines.enumerated().reversed()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.caption2, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .navigationTitle("Listen debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear log") { ListenDebugLog.shared.clear() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        speech.showListenDebug = false
                        dismiss()
                    }
                }
            }
            .onAppear { snapshot = speech.listenDebugSnapshot() }
            .onReceive(timer) { _ in snapshot = speech.listenDebugSnapshot() }
        }
    }

    private func bakePercentLabel(_ s: ListenDebugSnapshot) -> String {
        let total = max(s.bakeParagraphCount, 0)
        guard total > 0 else { return "—" }
        let pct = Int((100.0 * Double(s.bakeReadyCount) / Double(total)).rounded())
        return "\(pct)%  (\(s.bakeReadyCount)/\(total))"
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Compact live bake / queue strip above the listen controls. Does not block play/pause.
struct BakeDebugOverlay: View {
    @Bindable var speech: SpeechController
    var onOpenFull: () -> Void = {}

    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    @State private var snapshot: ListenDebugSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("Bake debug")
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                Button("Full") { onOpenFull() }
                    .font(.caption2.weight(.semibold))
                    .accessibilityIdentifier("bakeDebugOpenFull")
                Button {
                    speech.showBakeDebugOverlay = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss bake debug")
                .accessibilityIdentifier("bakeDebugDismiss")
            }

            ScrollView {
                Text(overlayText)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 140)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
        )
        .padding(.horizontal, 8)
        .accessibilityIdentifier("bakeDebugOverlay")
        .onAppear { snapshot = speech.listenDebugSnapshot() }
        .onReceive(timer) { _ in snapshot = speech.listenDebugSnapshot() }
    }

    private var overlayText: String {
        guard let s = snapshot else { return "…" }
        let recent = ListenDebugLog.shared.lines.suffix(3).joined(separator: "\n")
        return """
        article  \(s.articleIdentity)
        queue#1  \(s.queuePrimary)  demoted=\(s.demotedCount)
        active   \(s.activeBakeUnit)  next=\(s.nextMissingUnit)
        worker   \(s.workerBusy ? "busy" : "idle")  localWarm=\(s.warmingLocal ? "yes" : "no")
        bake     \(bakePercent(s))  \(s.bakeReadyCount)/\(s.bakeParagraphCount)  pending=\(s.bakePendingJobs)
        lang     \(s.language)
        render   \(s.renderMode)  ahead=\(s.readyAhead)
        bg       \(s.background)
        phase    \(s.phaseLabel)  playhead=\(s.playhead + 1)/\(max(s.paragraphCount, 0))
        plan     \(s.bakePlan)
        last     \(s.lastBakeEvent)
        \(recent.isEmpty ? "" : "log\n\(recent)")
        """.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func bakePercent(_ s: ListenDebugSnapshot) -> String {
        let total = max(s.bakeParagraphCount, 0)
        guard total > 0 else { return "—%" }
        let pct = Int((100.0 * Double(s.bakeReadyCount) / Double(total)).rounded())
        return "\(pct)%"
    }
}
