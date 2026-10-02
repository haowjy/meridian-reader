import Foundation

/// Device conditions that hold bake-ahead in `GlobalSynthQueue` (chunks someone is listening to
/// still render). Rendering whole articles ahead is optional work: on a hot device or in Low
/// Power Mode it waits, and the queue re-kicks when the thermal or power state changes.
struct BakeConditions: Equatable, Sendable {
    var thermalState: ProcessInfo.ThermalState
    var isLowPowerModeEnabled: Bool

    static var current: BakeConditions {
        let info = ProcessInfo.processInfo
        return BakeConditions(thermalState: info.thermalState, isLowPowerModeEnabled: info.isLowPowerModeEnabled)
    }

    enum Hold: Equatable, Sendable {
        case thermal(ProcessInfo.ThermalState)
        case lowPowerMode

        /// Debug overlay / timing-log wording.
        var label: String {
            switch self {
            case .thermal(let state): return state == .critical ? "device critically hot" : "device hot"
            case .lowPowerMode: return "Low Power Mode"
            }
        }
    }

    /// Why bake-ahead waits right now; nil = it may render. Thermal state `.serious` or worse.
    var bakeAheadHold: Hold? {
        if thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue { return .thermal(thermalState) }
        if isLowPowerModeEnabled { return .lowPowerMode }
        return nil
    }
}
