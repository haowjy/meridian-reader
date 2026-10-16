import XCTest
@testable import MeridianReader

/// Pending bake jobs live in a small JSON file; jobs older builds left in UserDefaults move there
/// on the first load. Files with fields jobs no longer keep still decode.
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

        let store = PendingBakeJobStore(storeURL: url, defaults: defaults)
        let jobs = store.pendingJobs()
        XCTAssertEqual(jobs.map(\.articleID), [key])
        XCTAssertEqual(jobs.first?.paragraphs, ["One.", "Two."])
        XCTAssertEqual(jobs.first?.priorityStart, 1)
        XCTAssertNil(defaults.object(forKey: "reader.tts.pendingBakeJobs"), "moved out of UserDefaults")
        let written = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(written.contains("voiceID"), "a job renders in the voice selected when it runs")
        XCTAssertFalse(written.contains("fillGapsFromTopAfterPriority"), "the plan is rebuilt from priorityStart")

        // Another instance reads the file.
        XCTAssertEqual(PendingBakeJobStore(storeURL: url, defaults: defaults).pendingJobs(), jobs)

        store.enqueuePending(articleID: UUID(), paragraphs: ["Three."], priorityStart: 0)
        XCTAssertEqual(store.pendingJobs().count, 2)
        for job in store.pendingJobs() { store.removePending(articleID: job.articleID) }
        XCTAssertTrue(store.pendingJobs().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "no jobs → no file")
    }
}
