import XCTest
@testable import Reader

/// ONNX-main Kokoro: route selection, crash auto-recover, resume target, crash-marker parsing,
/// Core ML breadcrumb attribution, first-chunk sizing and the head-start rule.
@MainActor
final class KokoroRouteTests: XCTestCase {
    private var cleanups: [() -> Void] = []

    override func tearDown() async throws {
        cleanups.reversed().forEach { $0() }
        cleanups = []
    }

    private func suiteDefaults() -> UserDefaults {
        let suite = "KokoroRoute-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        cleanups.append { d.removePersistentDomain(forName: suite) }
        return d
    }

    private func tempDir() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("KokoroRoute-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        cleanups.append { try? FileManager.default.removeItem(at: u) }
        return u
    }

    // MARK: Route selection

    func testDefaultRouteIsONNXAndToggleSelectsCoreML() {
        let d = suiteDefaults()
        let s = KokoroRouteSettings(defaults: d)
        XCTAssertEqual(s.route, .onnxCPU)
        XCTAssertEqual(s.cpuThreads, KokoroRouteSettings.defaultThreads)
        XCTAssertTrue(KokoroRoute.onnxCPU.rendersInBackground)
        XCTAssertFalse(KokoroRoute.coreMLGPU.rendersInBackground)
        let t = s
        t.fastGPURouteEnabled = true
        XCTAssertEqual(KokoroRouteSettings(defaults: d).route, .coreMLGPU)
        XCTAssertEqual(KokoroRoutePolicy.route(fastGPURouteEnabled: false), .onnxCPU)
        t.cpuThreads = 5
        XCTAssertEqual(KokoroRouteSettings(defaults: d).cpuThreads, 5)
        t.cpuThreads = 99 // out of range → default
        XCTAssertEqual(KokoroRouteSettings(defaults: d).cpuThreads, KokoroRouteSettings.defaultThreads)
    }

    func testProviderMakesCPUHostByDefaultAndCoreMLHostWithToggle() {
        let d = suiteDefaults()
        let provider = FluidAudioProvider(routeSettings: KokoroRouteSettings(defaults: d))
        let cpu = provider.makeHost(for: .kokoro, voice: nil)
        XCTAssertTrue(cpu is KokoroCPUHost)
        XCTAssertEqual(cpu?.routeTag, "onnx")
        XCTAssertEqual(cpu?.rendersInBackground, true)
        let s = KokoroRouteSettings(defaults: d)
        s.fastGPURouteEnabled = true
        let gpu = provider.makeHost(for: .kokoro, voice: nil)
        XCTAssertTrue(gpu is KokoroHost)
        XCTAssertEqual(gpu?.routeTag, "coreml")
        XCTAssertEqual(gpu?.rendersInBackground, false)
        XCTAssertEqual(provider.descriptors.first?.limits, TextChunker.Limits.kokoroCPU)
    }

    // MARK: Auto-recover state machine

    func testCrashRecoveryStateMachine() {
        var n = 0
        XCTAssertEqual(KokoroCrashRecovery.onCrash(route: .coreMLGPU, onnxCrashCount: &n), .resumeOnONNX(disableFastRoute: true))
        XCTAssertEqual(n, 0)
        XCTAssertEqual(KokoroCrashRecovery.onCrash(route: nil, onnxCrashCount: &n), .resumeOnONNX(disableFastRoute: true),
                       "legacy markers were Core ML")
        XCTAssertEqual(KokoroCrashRecovery.onCrash(route: .onnxCPU, onnxCrashCount: &n), .resumeOnONNX(disableFastRoute: false))
        XCTAssertEqual(n, 1)
        XCTAssertEqual(KokoroCrashRecovery.onCrash(route: .onnxCPU, onnxCrashCount: &n), .fallBackToApple)
        XCTAssertEqual(n, 0, "manual retry starts fresh")
        XCTAssertEqual(KokoroCrashRecovery.notice(for: .fallBackToApple), KokoroCrashRecovery.appleNotice)
    }

    func testResumeTargetPrefersRecentPlayingPoint() {
        let crash = Date(timeIntervalSince1970: 1_000_000)
        let playingID = UUID()
        let point = ListenResumeTarget(articleKey: playingID.uuidString, paragraph: 12, at: crash.addingTimeInterval(-30))
        let recent = ListenResumeTarget.forCrash(article: "BA7D7639", paragraph: 14, crashAt: crash, playing: point,
                                                 now: crash.addingTimeInterval(5))
        XCTAssertEqual(recent?.paragraph, 12)
        XCTAssertEqual(recent?.autoPlay, true)
        XCTAssertTrue(recent!.matches(playingID))

        let late = ListenResumeTarget.forCrash(article: "BA7D7639", paragraph: 14, crashAt: crash, playing: point,
                                               now: crash.addingTimeInterval(3600))
        XCTAssertEqual(late?.autoPlay, false, "old crash: open paused")

        let stale = ListenResumeTarget(articleKey: playingID.uuidString, paragraph: 3, at: crash.addingTimeInterval(-7200))
        let marker = ListenResumeTarget.forCrash(article: "BA7D7639", paragraph: 14, crashAt: crash, playing: stale, now: crash)
        XCTAssertEqual(marker?.articleKey, "BA7D7639")
        XCTAssertEqual(marker?.paragraph, 14)
        XCTAssertEqual(marker?.autoPlay, false)
        XCTAssertTrue(marker!.matches(UUID(uuidString: "BA7D7639-0000-0000-0000-000000000000")!))
        XCTAssertNil(ListenResumeTarget.forCrash(article: nil, paragraph: nil, crashAt: crash, playing: nil, now: crash))
    }

    // MARK: Crash marker + breadcrumb

    func testCrashInfoParsesLegacyCtx() {
        let info = EngineCrashGuard.crashInfo(from: ["engine": "local.kokoro", "ctx": "BA7D7639/p14", "t": 1790307929.97],
                                              engine: .kokoro)
        XCTAssertEqual(info.articleKey, "BA7D7639")
        XCTAssertEqual(info.paragraph, 14)
        XCTAssertNil(info.route)
    }

    func testCrashGuardAttributesCoreMLBreadcrumb() {
        let dir = tempDir()
        let guardian = EngineCrashGuard(directory: dir)
        let crumbs = CoreMLBreadcrumbFile(url: dir.appendingPathComponent("coreml_breadcrumb.json"))
        crumbs.write(model: "kokoro", stage: "albert.done", detail: nil, now: Date().addingTimeInterval(-60)) // stale
        guardian.beginCall(engine: .kokoro, chars: 174, context: "BA7D7639/p14", route: "coreml",
                           article: UUID().uuidString, paragraph: 14, phase: "foreground")
        crumbs.write(model: "g2p.bart", stage: "decoder", detail: "Adric")
        let info = guardian.consumeCrashInfo(legacyEngine: nil)
        XCTAssertEqual(info?.coreMLStage, "g2p.bart/decoder")
        XCTAssertEqual(info?.route, "coreml")
        XCTAssertNil(crumbs.read(), "breadcrumb consumed")

        // ONNX route: no Core ML breadcrumb newer than the marker → nil.
        crumbs.write(model: "kokoro", stage: "vocoder", detail: nil, now: Date().addingTimeInterval(-60))
        guardian.beginCall(engine: .kokoro, chars: 80, context: "x/p1", route: "onnx")
        XCTAssertNil(guardian.consumeCrashInfo(legacyEngine: nil)?.coreMLStage)
    }

    // MARK: Coordinator auto-recover

    private func makeCoordinator(defaults: UserDefaults, guardDir: URL) -> LocalTTSCoordinator {
        let registry = EngineRegistry(providers: [AppleSpeechProvider(), KokoroStubProvider()], gate: { _ in true })
        let root = tempDir()
        return LocalTTSCoordinator(engines: registry, defaults: defaults, audioCache: ArticleAudioCache(root: root),
                                   crashGuard: EngineCrashGuard(directory: guardDir))
    }

    func testCoordinatorResumesOnONNXAfterCrashThenFallsBackAfterTwoONNXCrashes() {
        ListenResumePointStore.shared.clear()
        let d = suiteDefaults()
        let guardDir = tempDir()
        d.set(SpeechEngineID.kokoro.rawValue, forKey: LocalTTSCoordinator.engineIDKey)
        let s = KokoroRouteSettings(defaults: d)
        s.fastGPURouteEnabled = true
        let article = UUID()

        // Core ML crash → Kokoro kept, fast route off, resume at the marker's paragraph.
        EngineCrashGuard(directory: guardDir).beginCall(engine: .kokoro, chars: 174, context: "BA7D7639/p14",
                                                       route: "coreml", article: article.uuidString, paragraph: 14)
        let c1 = makeCoordinator(defaults: d, guardDir: guardDir)
        XCTAssertEqual(c1.selectedEngineID, .kokoro)
        XCTAssertEqual(c1.engineCrashNotice, KokoroCrashRecovery.resumedNotice)
        XCTAssertFalse(KokoroRouteSettings(defaults: d).fastGPURouteEnabled)
        let r = c1.takePendingResume()
        XCTAssertEqual(r?.paragraph, 14)
        XCTAssertTrue(r?.matches(article) ?? false)

        // First ONNX crash → still Kokoro.
        EngineCrashGuard(directory: guardDir).beginCall(engine: .kokoro, chars: 90, context: "x/p2", route: "onnx")
        let c2 = makeCoordinator(defaults: d, guardDir: guardDir)
        XCTAssertEqual(c2.selectedEngineID, .kokoro)
        XCTAssertEqual(KokoroRouteSettings(defaults: d).onnxCrashCount, 1)

        // Second ONNX crash → Apple, with the explicit notice.
        EngineCrashGuard(directory: guardDir).beginCall(engine: .kokoro, chars: 90, context: "x/p3", route: "onnx")
        let c3 = makeCoordinator(defaults: d, guardDir: guardDir)
        XCTAssertEqual(c3.selectedEngineID, .apple)
        XCTAssertEqual(c3.engineCrashNotice, KokoroCrashRecovery.appleNotice)
    }

    func testOneTimeMigrationBringsAppleUserBackToKokoroPaused() {
        ListenResumePointStore.shared.clear()
        let d = suiteDefaults()
        let guardDir = tempDir()
        // Old build: Core ML crash already consumed → Apple selected, engine_crashes.json remains.
        let g = EngineCrashGuard(directory: guardDir)
        g.beginCall(engine: .kokoro, chars: 174, context: "BA7D7639/p14")
        _ = g.consumeCrashInfo(legacyEngine: .kokoro)
        d.set(SpeechEngineID.apple.rawValue, forKey: LocalTTSCoordinator.engineIDKey)

        let c = makeCoordinator(defaults: d, guardDir: guardDir)
        XCTAssertEqual(c.selectedEngineID, .kokoro)
        let r = c.takePendingResume()
        XCTAssertEqual(r?.articleKey, "BA7D7639")
        XCTAssertEqual(r?.paragraph, 14)
        XCTAssertEqual(r?.autoPlay, false)

        // Only once.
        d.set(SpeechEngineID.apple.rawValue, forKey: LocalTTSCoordinator.engineIDKey)
        let again = makeCoordinator(defaults: d, guardDir: guardDir)
        XCTAssertEqual(again.selectedEngineID, .apple)
    }

    // MARK: First chunk + head start

    func testKokoroCPUFirstChunkIsShort() {
        let para = "Adric ruffled Keo’s thick, black hair, which was harder to reach now that he was so tall. "
            + "“Maybe next cycle when you get Chosen. Then I’ll give you whatever weapon you want.”"
        let chunks = TextChunker.chunks(for: para, limits: .kokoroCPU)
        XCTAssertGreaterThanOrEqual(chunks.count, 2, "174-char paragraph splits so first audio comes fast")
        XCTAssertLessThanOrEqual(chunks[0].count, TextChunker.Limits.kokoroCPU.firstTarget + 24)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= TextChunker.Limits.kokoroCPU.hardMax })
        XCTAssertEqual(chunks.joined(separator: " ").filter { !$0.isWhitespace }, para.filter { !$0.isWhitespace })
        // Short paragraphs stay whole.
        XCTAssertEqual(TextChunker.chunks(for: "“No, you do not,” said Annaliese.", limits: .kokoroCPU).count, 1)
    }

    func testHeadStartMath() {
        XCTAssertEqual(HeadStart.requiredBuffer(remainingAudio: 60, speed: 2, rate: 1, firstPieceAudio: 5), 2.5, accuracy: 1e-9)
        XCTAssertEqual(HeadStart.requiredBuffer(remainingAudio: 60, speed: 0.5, rate: 1, firstPieceAudio: 5), 40, accuracy: 1e-9)
        let slow = RenderPace.Snapshot(speed: 0.5, chunkWall: 10, samples: 3)
        let fast = RenderPace.Snapshot(speed: 3, chunkWall: 1, samples: 3)
        XCTAssertTrue(HeadStart.projectsUnderrun(remainingChars: 600, firstChunkChars: 180, bufferedAudio: 5,
                                                 pace: slow, rate: 1, workerBusyOther: false))
        XCTAssertFalse(HeadStart.projectsUnderrun(remainingChars: 600, firstChunkChars: 180, bufferedAudio: 5,
                                                  pace: fast, rate: 1, workerBusyOther: false))
        XCTAssertFalse(HeadStart.projectsUnderrun(remainingChars: 600, firstChunkChars: 180, bufferedAudio: 0,
                                                  pace: .init(speed: nil, chunkWall: nil, samples: 1), rate: 1,
                                                  workerBusyOther: true), "unknown pace: wait, don't switch voice")
        let pace = RenderPace()
        pace.record(audioSeconds: 10, wallSeconds: 5)
        XCTAssertNil(pace.snapshot.speed)
        pace.record(audioSeconds: 10, wallSeconds: 5)
        XCTAssertEqual(pace.snapshot.speed ?? 0, 2, accuracy: 1e-9)
    }
}

/// Kokoro-id engine backed by the fake tone host (coordinator tests without FluidAudio/downloads).
@MainActor
final class KokoroStubProvider: SpeechEngineProvider {
    let name = "KokoroStub"
    var descriptors: [EngineDescriptor] {
        [EngineDescriptor(
            id: .kokoro, providerName: name, kind: .onDevice,
            displayName: "Kokoro (stub)", shortName: "Kokoro", subtitle: "Test",
            isRecommended: true, sortOrder: 1,
            voices: [], defaultVoiceID: nil, voiceDefaultsKey: nil, cacheVoiceKey: .prefixed("kstub"),
            streaming: .wholeCall, limits: .kokoroCPU, limitNotes: "",
            assets: [], approxDownloadBytes: 0, hardware: .none,
            computeRouting: nil, quirks: [], supportsBakeCache: true,
            crashGuarded: true, crashNoticeDetail: "test", supportedLanguages: [])]
    }
    func makeHost(for id: SpeechEngineID, voice: String?) -> LocalSynthHost? {
        id == .kokoro ? FakeSynthHost(engineID: id, config: .init(rendersInBackground: true)) : nil
    }
    func isInstalled(_ id: SpeechEngineID) -> Bool { true }
    func deleteModels(_ id: SpeechEngineID) throws {}
}
