import SwiftUI

/// What a prepare still to finish says about itself, the one wording a folder header and the
/// Prepared Audio list share (C91): where it is and how long its rendering has left.
///
/// ```
/// Preparing 5 of 17   ~2 h 45 min left
/// ```
enum PrepareStatusText {
    /// A prepare's line: ["Preparing 5 of 17", "~2 h 45 min left"], ["Waiting 5 of 17",
    /// "starts in ~3 h"], ["Paused 5 of 17"]. `count`: show "5 of 17" (a folder's); a page's
    /// prepare shows only its state and time.
    @MainActor
    static func parts(_ record: PrepareRecord, preparedAudio: PrepareCenter, count: Bool) -> [String] {
        let of = count ? " \(record.finishedCount) of \(record.entries.count)" : ""
        if record.isPaused { return [String(localized: "Paused\(of)")] }
        let left = preparedAudio.renderSecondsLeft(record).map { String(localized: "\(PrepareCenter.estimate($0)) left") }
        if preparedAudio.isActive(record.id) {
            return [String(localized: "Preparing\(of)"), left].compactMap { $0 }
        }
        let before = preparedAudio.renderSecondsBefore(record)
        return [String(localized: "Waiting\(of)"),
                before > 0 ? String(localized: "starts in \(PrepareCenter.estimate(before))") : left].compactMap { $0 }
    }
}
