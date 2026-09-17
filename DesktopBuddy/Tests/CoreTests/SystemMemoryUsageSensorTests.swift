import XCTest
@testable import DesktopBuddy

final class SystemMemoryUsageSensorTests: XCTestCase {
    func testNonCacheEstimatorMatchesDocumentedPageFormula() {
        let pageSize: UInt64 = 4_096

        let usedBytes = NonCacheMemoryEstimator.usedBytes(
            totalBytes: 100 * pageSize,
            pageSize: pageSize,
            freePages: 10,
            speculativePages: 2,
            purgeablePages: 5,
            externalPages: 20
        )

        XCTAssertEqual(usedBytes, 67 * pageSize)
    }

    func testNonCacheEstimatorMakesExternalPageDivergenceExplicit() {
        let pageSize: UInt64 = 4_096
        let withoutExternalPages = NonCacheMemoryEstimator.usedBytes(
            totalBytes: 100 * pageSize,
            pageSize: pageSize,
            freePages: 10,
            speculativePages: 2,
            purgeablePages: 5,
            externalPages: 0
        )
        let withExternalPages = NonCacheMemoryEstimator.usedBytes(
            totalBytes: 100 * pageSize,
            pageSize: pageSize,
            freePages: 10,
            speculativePages: 2,
            purgeablePages: 5,
            externalPages: 20
        )

        XCTAssertEqual(withoutExternalPages - withExternalPages, 20 * pageSize)
    }

    func testNonCacheEstimatorClampsInvalidOrOversizedReclaimableCounts() {
        let pageSize: UInt64 = 4_096

        XCTAssertEqual(NonCacheMemoryEstimator.usedBytes(
            totalBytes: 4 * pageSize,
            pageSize: pageSize,
            freePages: 2,
            speculativePages: 5,
            purgeablePages: 3,
            externalPages: 3
        ), 0)
        XCTAssertEqual(NonCacheMemoryEstimator.usedBytes(
            totalBytes: 4 * pageSize,
            pageSize: 0,
            freePages: 0,
            speculativePages: 0,
            purgeablePages: 0,
            externalPages: 0
        ), 0)
    }

    func testSamplingIntervalCanBeThrottledAndClampsInvalidValues() {
        let sensor = SystemMemoryUsageSensor()

        XCTAssertEqual(sensor.configuredSamplingIntervalSeconds, 10)
        sensor.setSamplingInterval(seconds: 30)
        XCTAssertEqual(sensor.configuredSamplingIntervalSeconds, 30)
        sensor.setSamplingInterval(seconds: 0)
        XCTAssertEqual(sensor.configuredSamplingIntervalSeconds, 10)
    }

    func testProvidesCurrentMacMemoryUsage() async throws {
        let sensor = SystemMemoryUsageSensor()
        var iterator = sensor.stateUpdates().makeAsyncIterator()
        var state = await iterator.next()

        if state?.isAvailable == false {
            state = await iterator.next()
        }

        let availableState = try XCTUnwrap(state)
        XCTAssertTrue(availableState.isAvailable)
        XCTAssertGreaterThan(availableState.usedBytes, 0)
        XCTAssertLessThanOrEqual(availableState.usedBytes, availableState.totalBytes)
        XCTAssertTrue((0...100).contains(availableState.usagePercent))
    }
}
