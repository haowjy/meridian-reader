import Foundation
import os

/// Where row and menu work goes (C98): an `os_signpost` interval per measured block (Instruments'
/// Points of Interest, subsystem `com.jimmyyao.Reader`, category `RenderTiming`) and running
/// totals that the log gets every 5 s while something is measured:
/// `render_timing pageRow=412 0.9ms folderRow=3 0.1ms menuBuild=0 0.0ms`. Main actor only; cheap
/// enough to leave on (a clock read and an add per block).
@MainActor
enum RenderTiming {
    enum Block: String, CaseIterable { case pageRow, folderRow, menuBuild }

    private static let signposter = OSSignposter(subsystem: "com.jimmyyao.Reader", category: "RenderTiming")
    private static let log = Logger(subsystem: "com.jimmyyao.Reader", category: "RenderTiming")
    private static var counts: [Block: Int] = [:]
    private static var nanos: [Block: UInt64] = [:]
    private static var windowStart = DispatchTime.now().uptimeNanoseconds

    static func measure<T>(_ block: Block, _ work: () -> T) -> T {
        let state = signposter.beginInterval("block", "\(block.rawValue, privacy: .public)")
        let start = DispatchTime.now().uptimeNanoseconds
        let result = work()
        let end = DispatchTime.now().uptimeNanoseconds
        signposter.endInterval("block", state)
        counts[block, default: 0] += 1
        nanos[block, default: 0] &+= end &- start
        if end > windowStart && end - windowStart > 5_000_000_000 { flush(now: end) }
        return result
    }

    private static func flush(now: UInt64) {
        let line = Block.allCases.map { b in
            String(format: "%@=%d %.1fms", b.rawValue, counts[b] ?? 0, Double(nanos[b] ?? 0) / 1e6)
        }.joined(separator: " ")
        log.notice("render_timing \(line, privacy: .public)")
        counts = [:]
        nanos = [:]
        windowStart = now
    }
}
