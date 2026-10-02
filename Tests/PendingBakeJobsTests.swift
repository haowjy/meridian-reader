import XCTest
@testable import Reader

/// Pending bake jobs live in a small JSON file; jobs older builds left in UserDefaults move there
/// on the first load.
@MainActor
final class PendingBakeJobsTests: XCTestCase {
    func testLegacyUserDefaultsJobsMoveToTheFileOnce() throws {
        let suite = "PendingBakeJobs-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PendingBakeJobs-\(UUID().uuidString).json")
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: url)
        }
        let key = UUID()
        let legacy = """
        [{"articleID":"\(key.uuidString)","paragraphs":["One.","Two."],"rate":0.5,"voiceID":"kokoro.af_heart",
          "priorityStart":1,"fillGapsFromTopAfterPriority":true}]
        """
        defaults.set(Data(legacy.utf8), forKey: "reader.tts.pendingBakeJobs")

        let scheduler = BackgroundAudioBakeScheduler(storeURL: url, defaults: defaults)
        let jobs = scheduler.pendingJobs()
        XCTAssertEqual(jobs.map(\.articleID), [key])
        XCTAssertEqual(jobs.first?.paragraphs, ["One.", "Two."])
        XCTAssertEqual(jobs.first?.priorityStart, 1)
        XCTAssertNil(defaults.object(forKey: "reader.tts.pendingBakeJobs"), "moved out of UserDefaults")

        // Another instance reads the file.
        XCTAssertEqual(BackgroundAudioBakeScheduler(storeURL: url, defaults: defaults).pendingJobs(), jobs)

        scheduler.enqueuePending(articleID: UUID(), paragraphs: ["Three."], voiceID: "v", plan: .topDown(paragraphCount: 1))
        XCTAssertEqual(scheduler.pendingJobs().count, 2)
        for job in scheduler.pendingJobs() { scheduler.removePending(articleID: job.articleID) }
        XCTAssertTrue(scheduler.pendingJobs().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "no jobs → no file")
    }
}
