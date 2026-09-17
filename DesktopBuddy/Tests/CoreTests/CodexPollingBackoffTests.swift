import XCTest
@testable import DesktopBuddy

final class CodexPollingBackoffTests: XCTestCase {
    func testRepeatedFailuresBackOffAndSuccessRestoresNormalCadence() {
        var backoff = CodexPollingBackoff()

        XCTAssertEqual(backoff.nextDelay(after: .available), .seconds(5 * 60))
        XCTAssertEqual(backoff.nextDelay(after: .unavailable), .seconds(5 * 60))
        XCTAssertEqual(backoff.nextDelay(after: .unavailable), .seconds(15 * 60))
        XCTAssertEqual(backoff.nextDelay(after: .executableMissing), .seconds(30 * 60))
        XCTAssertEqual(backoff.nextDelay(after: .unavailable), .seconds(30 * 60))
        XCTAssertEqual(backoff.consecutiveFailures, 3)

        XCTAssertEqual(backoff.nextDelay(after: .available), .seconds(5 * 60))
        XCTAssertEqual(backoff.consecutiveFailures, 0)
    }

    func testLoadingDoesNotCountAsACompletedSuccessfulRead() {
        var backoff = CodexPollingBackoff()
        XCTAssertEqual(backoff.nextDelay(after: .loading), .seconds(5 * 60))
        XCTAssertEqual(backoff.consecutiveFailures, 1)
    }
}
