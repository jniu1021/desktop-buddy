import XCTest
@testable import DesktopBuddy

final class SystemFanSensorTests: XCTestCase {
    func testSMCNumericTypesAndMissingValues() {
        XCTAssertEqual(SMCNumericDecoder.decode(type: "ui8 ", bytes: [2]), 2)
        XCTAssertEqual(SMCNumericDecoder.decode(type: "flt ", bytes: [0, 0, 0xA8, 0x44]), 1344)
        XCTAssertEqual(SMCNumericDecoder.decode(type: "fpe2", bytes: [0x15, 0x18]), 1350)
        XCTAssertNil(SMCNumericDecoder.decode(type: "flt ", bytes: [0]))
        XCTAssertNil(SMCNumericDecoder.decode(type: "????", bytes: [0]))
        XCTAssertNil(SMCNumericDecoder.decode(type: "flt ", bytes: [0, 0, 0x80, 0x7F]))
    }

    func testReadsCurrentMacFansWithoutWriting() async throws {
        let state = await SystemFanSensor().currentState()
        guard state.availability == .available else {
            throw XCTSkip("This Mac has no readable fan state")
        }
        XCTAssertEqual(state.availability, .available)
        XCTAssertFalse(state.fans.isEmpty)
        XCTAssertEqual(state.fans.map(\.index), Array(state.fans.indices))
        XCTAssertTrue(state.fans.allSatisfy(\.hasValidRange))
        XCTAssertTrue(state.fans.allSatisfy { $0.currentRPM != nil })
    }
}
