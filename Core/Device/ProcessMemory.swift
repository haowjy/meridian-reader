import Darwin
import Foundation
import os

/// The process's memory as jetsam counts it.
enum ProcessMemory {
    /// `phys_footprint` and the process-lifetime peak, bytes (0 when unreadable).
    static func footprint() -> (current: UInt64, peak: UInt64) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return (0, 0) }
        return (info.phys_footprint, info.ledger_phys_footprint_peak > 0 ? UInt64(info.ledger_phys_footprint_peak) : 0)
    }

    /// `phys_footprint` in MB.
    static var footprintMB: Int { Int(footprint().current / 1_048_576) }

    /// Bytes the app can still allocate before hitting its jetsam limit (0 if unknown).
    static func availableMemory() -> UInt64 {
        #if os(iOS)
        return UInt64(os_proc_available_memory())
        #else
        return 0
        #endif
    }
}
