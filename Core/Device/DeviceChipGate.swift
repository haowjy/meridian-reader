import Foundation

/// Apple silicon generation, as far as gating on-device models needs it: the A15 floor
/// (`HardwareRequirement.minimumChip`).
enum DeviceChipGeneration: Int, Comparable, Sendable {
    case belowA15 = 0
    /// A15 or newer.
    case a15 = 15

    static func < (lhs: DeviceChipGeneration, rhs: DeviceChipGeneration) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// No public API names the chip, so the floor comes from the `uname` machine id
/// (`iPhone14,2`, …). The app is iPhone-only: any other id is below the floor.
enum DeviceChipGate {
    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    /// Does this device meet an engine's `HardwareRequirement` (from its `EngineDescriptor`)?
    static func meets(_ requirement: HardwareRequirement) -> Bool {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        guard os.majorVersion >= requirement.minimumOSMajor else { return false }
        guard let chip = requirement.minimumChip else { return true }
        if isSimulator { return requirement.allowsSimulator }
        return generation(forMachineID: machineIdentifier) >= chip
    }

    /// Raw `uname` machine id (`iPhone16,2`); the Simulator reports a synthetic one (for logs).
    static var machineIdentifier: String {
        #if targetEnvironment(simulator)
        return "Simulator"
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

    /// iPhone14,* (iPhone 13, 14, SE 3) is the first A15 product id; later majors are newer chips.
    static func generation(forMachineID id: String) -> DeviceChipGeneration {
        guard id.hasPrefix("iPhone"),
              let major = Int(id.dropFirst("iPhone".count).split(separator: ",").first ?? "")
        else { return .belowA15 }
        return major >= 14 ? .a15 : .belowA15
    }
}
