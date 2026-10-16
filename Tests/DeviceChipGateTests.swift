import XCTest
@testable import MeridianReader

final class DeviceChipGateTests: XCTestCase {
    func testTheA15FloorByMachineID() {
        let table: [(id: String, chip: DeviceChipGeneration)] = [
            ("iPhone13,2", .belowA15),  // iPhone 12 (A14)
            ("iPhone14,5", .a15),       // iPhone 13 (A15)
            ("iPhone14,6", .a15),       // iPhone SE 3 (A15)
            ("iPhone15,2", .a15),       // iPhone 14 Pro (A16)
            ("iPhone18,1", .a15),       // a later iPhone
            ("iPhone9,1", .belowA15),   // a single-digit major
            ("iPad14,1", .belowA15),    // the app is iPhone-only
            ("Simulator", .belowA15),
            ("iPhone", .belowA15),      // no product number
        ]
        for row in table {
            XCTAssertEqual(DeviceChipGate.generation(forMachineID: row.id), row.chip, row.id)
        }
    }
}
