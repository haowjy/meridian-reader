import XCTest
@testable import MeridianReader

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
        let t = s
        t.fastGPURouteEnabled = true
        XCTAssertEqual(KokoroRouteSettings(defaults: d).route, .coreMLGPU)
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
        XCTAssertTrue(gpu is KokoroSplitHost)
        XCTAssertEqual(gpu?.routeTag, "coreml")
        XCTAssertEqual(gpu?.routingLabel, "aneTailGpu")
        XCTAssertEqual(gpu?.rendersInBackground, true, "ONNX takes over in the background")
        XCTAssertEqual(provider.descriptors.first?.onDevice?.limits, TextChunker.Limits.kokoroCPU)
    }

    func testCoreMLRouteNamesONNXForACallInTheBackground() {
        let runState = AppRunState(phase: .active)
        let host = KokoroSplitHost(coreML: KokoroHost(), onnx: KokoroCPUHost(), runState: runState)
        XCTAssertEqual(host.routeTag, "coreml")
        XCTAssertEqual(host.routingLabel, "aneTailGpu")
        runState.set(.inactive)
        XCTAssertEqual(host.routeTag, "coreml", "Control Center or a banner keeps Core ML")
        runState.set(.background)
        XCTAssertEqual(host.routeTag, "onnx", "the crash guard names the route that runs")
        XCTAssertFalse(host.isPrepared)
    }

    // MARK: Auto-recover state machine

    func testCrashRecoveryStateMachine() {
        var n = 0
        XCTAssertEqual(KokoroCrashRecovery.onCrash(route: .coreMLGPU, onnxCrashCount: &n), .resumeOnONNX)
        XCTAssertEqual(n, 0)
        XCTAssertEqual(KokoroCrashRecovery.onCrash(route: nil, onnxCrashCount: &n), .resumeOnONNX,
                       "legacy markers were Core ML")
        XCTAssertEqual(KokoroCrashRecovery.onCrash(route: .onnxCPU, onnxCrashCount: &n), .resumeOnONNX)
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
        guardian.beginCall(engine: .kokoro, chars: 174, route: "coreml", article: UUID(), paragraph: 14)
        crumbs.write(model: "g2p.bart", stage: "decoder", detail: "Adric")
        let info = guardian.consumeCrashInfo()
        XCTAssertEqual(info?.coreMLStage, "g2p.bart/decoder")
        XCTAssertEqual(info?.route, "coreml")
        XCTAssertNil(crumbs.read(), "breadcrumb consumed")

        // ONNX route: no Core ML breadcrumb newer than the marker → nil.
        crumbs.write(model: "kokoro", stage: "vocoder", detail: nil, now: Date().addingTimeInterval(-60))
        guardian.beginCall(engine: .kokoro, chars: 80, route: "onnx")
        XCTAssertNil(guardian.consumeCrashInfo()?.coreMLStage)
    }

    // MARK: Coordinator auto-recover

    /// Kokoro (the stub, with its crash policy over `defaults`) beside Apple, launched afresh by
    /// each `launch`.
    private func kokoroStack(defaults: UserDefaults) -> TestSpeech {
        let stack = TestSpeech(providers: [KokoroStubProvider(routeSettings: KokoroRouteSettings(defaults: defaults))],
                               defaults: defaults)
        cleanups.append { stack.tearDown() }
        return stack
    }

    private func launch(_ stack: TestSpeech) -> LocalTTSCoordinator {
        stack.relaunch()
        return stack.tts
    }

    func testCoordinatorResumesOnONNXAfterCrashThenFallsBackAfterTwoONNXCrashes() {
        let d = suiteDefaults()
        let stack = kokoroStack(defaults: d)
        let guardDir = stack.guardDirectory
        d.set(SpeechEngineID.kokoro.rawValue, forKey: LocalTTSCoordinator.engineIDKey)
        let s = KokoroRouteSettings(defaults: d)
        s.fastGPURouteEnabled = true
        let article = UUID()

        // Core ML crash → Kokoro kept, fast route off, resume at the marker's paragraph.
        EngineCrashGuard(directory: guardDir).beginCall(engine: .kokoro, chars: 174, route: "coreml",
                                                       article: article, paragraph: 14)
        let c1 = launch(stack)
        XCTAssertEqual(c1.selectedEngineID, .kokoro)
        XCTAssertEqual(c1.engineCrashNotice, KokoroCrashRecovery.resumedNotice)
        XCTAssertFalse(KokoroRouteSettings(defaults: d).fastGPURouteEnabled)
        let r = c1.takePendingResume()
        XCTAssertEqual(r?.paragraph, 14)
        XCTAssertTrue(r?.matches(article) ?? false)

        // First ONNX crash → still Kokoro. A crash on the Core ML route's ONNX half turns the route off too.
        s.fastGPURouteEnabled = true
        EngineCrashGuard(directory: guardDir).beginCall(engine: .kokoro, chars: 90, route: "onnx")
        let c2 = launch(stack)
        XCTAssertEqual(c2.selectedEngineID, .kokoro)
        XCTAssertEqual(KokoroRouteSettings(defaults: d).onnxCrashCount, 1)
        XCTAssertFalse(KokoroRouteSettings(defaults: d).fastGPURouteEnabled)

        // Second ONNX crash → Apple, with the explicit notice.
        EngineCrashGuard(directory: guardDir).beginCall(engine: .kokoro, chars: 90, route: "onnx")
        let c3 = launch(stack)
        XCTAssertEqual(c3.selectedEngineID, .apple)
        XCTAssertEqual(c3.engineCrashNotice, KokoroCrashRecovery.appleNotice)
    }

    /// The libBNNS containment: a death inside the call while listening reopens the page and
    /// plays on.
    func testAFreshMarkerStillResumesAndAutoPlays() {
        let d = suiteDefaults()
        let stack = kokoroStack(defaults: d)
        d.set(SpeechEngineID.kokoro.rawValue, forKey: LocalTTSCoordinator.engineIDKey)
        let article = UUID()
        stack.resumePoints.save(article: article, paragraph: 4, at: Date().addingTimeInterval(-5))
        EngineCrashGuard(directory: stack.guardDirectory).beginCall(engine: .kokoro, chars: 90, route: "onnx",
                                                                   article: article, paragraph: 6)
        let c = launch(stack)
        XCTAssertEqual(c.engineCrashNotice, KokoroCrashRecovery.resumedNotice)
        XCTAssertEqual(KokoroRouteSettings(defaults: d).onnxCrashCount, 1)
        let resume = c.takePendingResume()
        XCTAssertEqual(resume?.paragraph, 4, "the paragraph that was playing")
        XCTAssertEqual(resume?.autoPlay, true)
    }

    /// The process played on two minutes after the call began: it outlived that call, so the
    /// marker is no crash (no notice, no count, no resume).
    func testAStaleMarkerNeitherResumesNorCounts() {
        let d = suiteDefaults()
        let stack = kokoroStack(defaults: d)
        d.set(SpeechEngineID.kokoro.rawValue, forKey: LocalTTSCoordinator.engineIDKey)
        let article = UUID()
        EngineCrashGuard(directory: stack.guardDirectory).beginCall(engine: .kokoro, chars: 90, route: "onnx",
                                                                   article: article, paragraph: 6)
        stack.resumePoints.save(article: article, paragraph: 9, at: Date().addingTimeInterval(120))
        let c = launch(stack)
        XCTAssertEqual(c.selectedEngineID, .kokoro)
        XCTAssertNil(c.engineCrashNotice)
        XCTAssertNil(c.takePendingResume(), "nothing plays at launch")
        XCTAssertEqual(KokoroRouteSettings(defaults: d).onnxCrashCount, 0)
        XCTAssertNil(c.launchCrash)
    }

    /// iOS reclaimed a backgrounded app mid-call with a large footprint: that isn't the engine,
    /// so a second one doesn't switch the voice to Apple.
    func testABackgroundMemoryKillKeepsTheVoice() throws {
        let d = suiteDefaults()
        let stack = kokoroStack(defaults: d)
        let guardDir = stack.guardDirectory
        d.set(SpeechEngineID.kokoro.rawValue, forKey: LocalTTSCoordinator.engineIDKey)
        KokoroRouteSettings(defaults: d).onnxCrashCount = 1
        try FileManager.default.createDirectory(at: guardDir, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: [
            "t": Date().timeIntervalSince1970, "engine": "local.kokoro", "chars": 120, "route": "onnx",
            "article": UUID().uuidString, "p": 3, "phase": "background",
            "mem_mb": EngineCrashGuard.memoryKillFootprintMB + 200,
        ]).write(to: guardDir.appendingPathComponent("engine_inflight.json"))
        let c = launch(stack)
        XCTAssertEqual(c.selectedEngineID, .kokoro)
        XCTAssertNil(c.engineCrashNotice)
        XCTAssertEqual(KokoroRouteSettings(defaults: d).onnxCrashCount, 1)
    }

    func testAnEngineWithoutARecoveryHookSwitchesAwayOnlyWhenItWasSelected() async {
        let stack = TestSpeech(providers: [FakeEngineProvider()], selected: FakeEngineProvider.fakeID)
        cleanups.append { stack.tearDown() }
        let d = stack.defaults
        let guardDir = stack.guardDirectory
        EngineCrashGuard(directory: guardDir).beginCall(engine: FakeEngineProvider.fakeID, chars: 10)
        let c = launch(stack)
        XCTAssertEqual(c.selectedEngineID, .apple)
        XCTAssertEqual(c.engineCrashNotice?.hasPrefix("Fake crashed last session"), true)
        XCTAssertNil(c.takePendingResume())
        await c.selectEngine(FakeEngineProvider.fakeID)
        XCTAssertNil(c.engineCrashNotice, "picking it again is a fresh try")

        // A crash inside an engine that wasn't the selection changes nothing.
        d.set(SpeechEngineID.apple.rawValue, forKey: LocalTTSCoordinator.engineIDKey)
        EngineCrashGuard(directory: guardDir).beginCall(engine: FakeEngineProvider.fakeID, chars: 10)
        let quiet = launch(stack)
        XCTAssertEqual(quiet.selectedEngineID, .apple)
        XCTAssertNil(quiet.engineCrashNotice)
    }

    func testOneTimeMigrationBringsAppleUserBackToKokoroPaused() throws {
        let d = suiteDefaults()
        let stack = kokoroStack(defaults: d)
        let guardDir = stack.guardDirectory
        // Old build: Core ML crash already consumed → Apple selected, engine_crashes.json remains.
        // Its marker named the article and paragraph in one "ctx" string, and no route.
        let g = EngineCrashGuard(directory: guardDir)
        try FileManager.default.createDirectory(at: guardDir, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: [
            "t": Date().timeIntervalSince1970, "engine": "local.kokoro", "chars": 174, "ctx": "BA7D7639/p14",
        ]).write(to: guardDir.appendingPathComponent("engine_inflight.json"))
        _ = g.consumeCrashInfo()
        d.set(SpeechEngineID.apple.rawValue, forKey: LocalTTSCoordinator.engineIDKey)

        let c = launch(stack)
        XCTAssertEqual(c.selectedEngineID, .apple, "the launch migration hasn't run yet")
        KokoroONNXMainMigration().runIfNeeded(c)
        XCTAssertEqual(c.selectedEngineID, .kokoro)
        XCTAssertEqual(d.string(forKey: LocalTTSCoordinator.engineIDKey), SpeechEngineID.kokoro.rawValue)
        XCTAssertEqual(c.engineCrashNotice, KokoroCrashRecovery.resumedNotice)
        let r = c.takePendingResume()
        XCTAssertEqual(r?.articleKey, "BA7D7639")
        XCTAssertEqual(r?.paragraph, 14)
        XCTAssertEqual(r?.autoPlay, false)

        // Only once.
        d.set(SpeechEngineID.apple.rawValue, forKey: LocalTTSCoordinator.engineIDKey)
        let again = launch(stack)
        KokoroONNXMainMigration().runIfNeeded(again)
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

/// Kokoro-id engine backed by the fake tone host (coordinator tests without FluidAudio/downloads),
/// with Kokoro's crash policy over a test suite's route settings.
@MainActor
final class KokoroStubProvider: SpeechEngineProvider {
    let name = "KokoroStub"
    let routeSettings: KokoroRouteSettings

    init(routeSettings: KokoroRouteSettings = KokoroRouteSettings(defaults: UserDefaults(suiteName: "KokoroStub")!)) {
        self.routeSettings = routeSettings
    }

    func recover(from crash: EngineCrashGuard.CrashInfo, playing: ListenResumeTarget?) -> CrashRecovery? {
        crash.engine == .kokoro ? KokoroCrashRecovery.recover(from: crash, playing: playing, settings: routeSettings) : nil
    }

    var descriptors: [EngineDescriptor] {
        [EngineDescriptor(
            id: .kokoro,
            displayName: "Kokoro (stub)", shortName: "Kokoro", subtitle: "Test",
            isRecommended: true, sortOrder: 1,
            onDevice: OnDeviceTraits(cacheVoicePrefix: "kstub", limits: .kokoroCPU, crashNotice: "test"))]
    }
    func makeHost(for id: SpeechEngineID, voice: String?) -> LocalSynthHost? {
        id == .kokoro ? FakeSynthHost(engineID: id, config: .init(rendersInBackground: true)) : nil
    }
    func isInstalled(_ id: SpeechEngineID) -> Bool { true }
    func deleteModels(_ id: SpeechEngineID) throws {}
}
