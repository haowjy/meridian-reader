import Foundation

#if canImport(UIKit)
import UIKit
#endif

/// Coarse Apple silicon generation for gating on-device models (`HardwareRequirement.minimumChip`).
///
/// There is no public Apple API that returns “A15”. The standard approach is mapping
/// `uname` machine identifiers (`iPhone14,2`, …) to a chip floor.
enum DeviceChipGeneration: Int, Comparable, Sendable {
    case belowA15 = 0
    case a15 = 15
    case a16 = 16
    case a17OrNewer = 17

    static func < (lhs: DeviceChipGeneration, rhs: DeviceChipGeneration) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum DeviceChipGate {
    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    static var chipGeneration: DeviceChipGeneration {
        generation(forMachineID: machineIdentifier)
    }

    // MARK: - Engine requirements

    /// Does this device meet an engine's `HardwareRequirement` (from its `EngineDescriptor`)?
    static func meets(_ requirement: HardwareRequirement) -> Bool {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        guard os.majorVersion >= requirement.minimumOSMajor else { return false }
        guard let chip = requirement.minimumChip else { return true }
        if isSimulator { return requirement.allowsSimulator }
        return chipGeneration >= chip
    }

    // MARK: - Internals

    /// Raw `uname` machine id (e.g. `iPhone16,2`). Simulator uses a synthetic id.
    static var machineIdentifier: String {
        #if targetEnvironment(simulator)
        // Sims report "arm64" / "x86_64", not a product id — treat as below the A15 floor.
        #if arch(arm64)
        return "SimulatorArm64"
        #else
        return "SimulatorX86"
        #endif
        #else
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
        #endif
    }

    static func generation(forMachineID id: String) -> DeviceChipGeneration {
        // Simulator is not a real A15+ product — same floor failure as older phones.
        if id.hasPrefix("Simulator") { return .belowA15 }

        // iPhone: product major maps cleanly enough for an A15 floor.
        // iPhone13,* = A14 (iPhone 12) → below
        // iPhone14,* = A15 (13 / 14 / SE 3) → a15
        // iPhone15,* = A16 → a16
        // iPhone16,* / 17,* = A17 / A18+ → a17OrNewer
        if id.hasPrefix("iPhone") {
            let major = productMajor(id, prefix: "iPhone")
            switch major {
            case ...13: return .belowA15
            case 14: return .a15
            case 15: return .a16
            default: return .a17OrNewer
            }
        }

        // iPad: only known A15+ / Apple silicon that we care about for on-device models.
        // iPad14,1 / 14,2 = mini (6th gen) A15
        // iPad14,3–14,6 = Air / Pro — treat as a15+ floor
        // iPad13,* Air 5 is M1 (OK) but iPad13,* also includes A14 Air 4 —
        // be conservative: require iPad14+ or explicit M-series iPad13 ids.
        if id.hasPrefix("iPad") {
            let major = productMajor(id, prefix: "iPad")
            if major >= 14 { return .a15 }
            // iPad13,4–13,7 Pro 11" 3rd / 12.9" 5th = M1
            // iPad13,8–13,11 Air 5 = M1
            // iPad13,1–13,2 Air 4 = A14 → below
            if let minor = productMinor(id, prefix: "iPad"), major == 13, minor >= 4 {
                return .a15
            }
            return .belowA15
        }

        // Unknown product (Apple Vision, future): don't claim A15+.
        return .belowA15
    }

    private static func productMajor(_ id: String, prefix: String) -> Int {
        let rest = id.dropFirst(prefix.count) // "14,2"
        return Int(rest.split(separator: ",").first ?? "0") ?? 0
    }

    private static func productMinor(_ id: String, prefix: String) -> Int? {
        let parts = id.dropFirst(prefix.count).split(separator: ",")
        guard parts.count >= 2 else { return nil }
        return Int(parts[1])
    }
}
