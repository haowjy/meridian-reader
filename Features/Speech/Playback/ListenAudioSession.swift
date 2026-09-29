import AVFoundation
import Foundation

/// System audio events Listen reacts to (parsed from `AVAudioSession` notifications).
enum ListenAudioEvent: Equatable {
    /// Phone call, Siri, alarm…
    case interruptionBegan
    case interruptionEnded(shouldResume: Bool)
    /// Headphones unplugged / Bluetooth route lost.
    case oldDeviceUnavailable
    case mediaServicesReset
}

enum ListenAudioAction: Equatable {
    case none, pause, resume
}

/// Pure interruption / route-change rules (unit-tested). Pause goes through the Session like any
/// other pause; resume only when iOS says `shouldResume` AND we were the ones playing.
struct ListenInterruptionPolicy: Equatable {
    private(set) var resumeAfterInterruption = false

    mutating func handle(_ event: ListenAudioEvent, isPlaying: Bool) -> ListenAudioAction {
        switch event {
        case .interruptionBegan:
            if isPlaying {
                resumeAfterInterruption = true
            }
            return isPlaying ? .pause : .none
        case .interruptionEnded(let shouldResume):
            defer { resumeAfterInterruption = false }
            return shouldResume && resumeAfterInterruption ? .resume : .none
        case .oldDeviceUnavailable, .mediaServicesReset:
            resumeAfterInterruption = false
            return isPlaying ? .pause : .none
        }
    }

    /// The user paused / stopped / picked something during an interruption: don't auto-resume.
    mutating func noteUserIntent() {
        resumeAfterInterruption = false
    }
}

/// Listen's `AVAudioSession`: `.playback` + `.spokenAudio`, **non-mixable** (a mixable session —
/// e.g. `.duckOthers` — never becomes the Now Playing app, so no lock-screen controls). With
/// `UIBackgroundModes: audio` this keeps playing after leaving the app. Activated when playback
/// starts or resumes, deactivated (notifying others, so music can resume) on stop / finish.
@MainActor
final class ListenAudioSession {
    /// false in unit tests: track state without touching the process-wide session.
    let managesSystemSession: Bool
    private(set) var isActive = false
    private(set) var activationCount = 0
    var onEvent: ((ListenAudioEvent) -> Void)?
    private var tokens: [NSObjectProtocol] = []

    init(managesSystemSession: Bool = true) {
        self.managesSystemSession = managesSystemSession
    }

    func configure() {
        guard managesSystemSession else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [])
        } catch {
            ListenTimingLog.log("audio_session_error", ["op": "category", "err": error.localizedDescription])
        }
    }

    func activate() {
        guard !isActive else { return }
        activationCount += 1
        guard managesSystemSession else { isActive = true; return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            isActive = true
            ListenTimingLog.log("audio_session", ["op": "activate"])
        } catch {
            ListenTimingLog.log("audio_session_error", ["op": "activate", "err": error.localizedDescription])
        }
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        guard managesSystemSession else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            ListenTimingLog.log("audio_session", ["op": "deactivate"])
        } catch {
            ListenTimingLog.log("audio_session_error", ["op": "deactivate", "err": error.localizedDescription])
        }
    }

    func startObserving() {
        guard managesSystemSession, tokens.isEmpty else { return }
        let nc = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        tokens.append(nc.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] note in
            let event = Self.interruptionEvent(note.userInfo)
            MainActor.assumeIsolated { self?.receive(event) }
        })
        tokens.append(nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { [weak self] note in
            let event = Self.routeEvent(note.userInfo)
            MainActor.assumeIsolated { self?.receive(event) }
        })
        tokens.append(nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.configure()
                self?.receive(.mediaServicesReset)
            }
        })
    }

    private func receive(_ event: ListenAudioEvent?) {
        guard let event else { return }
        switch event {
        case .interruptionBegan, .mediaServicesReset:
            isActive = false // iOS deactivated us
        default:
            break
        }
        onEvent?(event)
    }

    nonisolated static func interruptionEvent(_ info: [AnyHashable: Any]?) -> ListenAudioEvent? {
        guard let raw = info?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return nil }
        switch type {
        case .began:
            return .interruptionBegan
        case .ended:
            let opts = AVAudioSession.InterruptionOptions(rawValue: info?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            return .interruptionEnded(shouldResume: opts.contains(.shouldResume))
        @unknown default:
            return nil
        }
    }

    nonisolated static func routeEvent(_ info: [AnyHashable: Any]?) -> ListenAudioEvent? {
        guard let raw = info?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return nil }
        return .oldDeviceUnavailable
    }
}
