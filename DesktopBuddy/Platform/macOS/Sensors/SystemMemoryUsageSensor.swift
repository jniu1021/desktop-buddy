import Darwin
import Dispatch
import Foundation

final class SystemMemoryUsageSensor: MemoryUsageSensing, @unchecked Sendable {
    private let lock = NSLock()
    private let queue: DispatchQueue
    private var latestState: MemoryUsageState = .unavailable
    private var systemPressure: SystemMemoryPressure = .normal
    private var previousSwapOutBytes: UInt64?
    private var previousSampleDate: Date?
    private var samplingIntervalSeconds = 10
    private var continuations: [UUID: AsyncStream<MemoryUsageState>.Continuation] = [:]
    private let timer: DispatchSourceTimer
    private let pressureSource: DispatchSourceMemoryPressure

    init(queue: DispatchQueue = DispatchQueue(label: "com.desktopbuddy.memory-usage")) {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        let pressureSource = DispatchSource.makeMemoryPressureSource(
            eventMask: [.normal, .warning, .critical],
            queue: queue
        )
        self.queue = queue
        self.timer = timer
        self.pressureSource = pressureSource

        timer.schedule(deadline: .now(), repeating: .seconds(10), leeway: .seconds(1))
        timer.setEventHandler { [weak self] in
            self?.sampleAndPublish()
        }

        pressureSource.setEventHandler { [weak self, weak pressureSource] in
            guard let self, let pressureSource else { return }
            self.recordPressure(event: pressureSource.data)
            self.sampleAndPublish()
        }

        pressureSource.activate()
        timer.activate()
    }

    deinit {
        timer.cancel()
        pressureSource.cancel()

        let activeContinuations = lock.withLock {
            let values = Array(continuations.values)
            continuations.removeAll()
            return values
        }
        activeContinuations.forEach { $0.finish() }
    }

    func currentState() async -> MemoryUsageState {
        lock.withLock { latestState }
    }

    func stateUpdates() -> AsyncStream<MemoryUsageState> {
        let identifier = UUID()

        return AsyncStream { continuation in
            let initialState = lock.withLock {
                continuations[identifier] = continuation
                return latestState
            }

            continuation.yield(initialState)
            continuation.onTermination = { [weak self] _ in
                self?.removeContinuation(identifier)
            }
        }
    }

    func setSamplingInterval(seconds: Int) {
        let interval = max(10, seconds)
        let shouldReschedule = lock.withLock {
            guard samplingIntervalSeconds != interval else { return false }
            samplingIntervalSeconds = interval
            return true
        }
        guard shouldReschedule else { return }

        queue.async { [weak self] in
            self?.timer.schedule(
                deadline: .now() + .seconds(interval),
                repeating: .seconds(interval),
                leeway: .seconds(max(1, interval / 10))
            )
        }
    }

    var configuredSamplingIntervalSeconds: Int {
        lock.withLock { samplingIntervalSeconds }
    }

    private func sampleAndPublish(now: Date = Date()) {
        guard let rawSample = Self.readRawSample() else { return }

        let result = lock.withLock { () -> (MemoryUsageState, [AsyncStream<MemoryUsageState>.Continuation]) in
            let elapsed = previousSampleDate.map { now.timeIntervalSince($0) } ?? 0
            let swapDelta = rawSample.swapOutBytes >= (previousSwapOutBytes ?? rawSample.swapOutBytes)
                ? rawSample.swapOutBytes - (previousSwapOutBytes ?? rawSample.swapOutBytes)
                : 0
            let swapOutRate = elapsed > 0 ? UInt64(Double(swapDelta) / elapsed) : 0

            let state = MemoryUsageState(
                usedBytes: rawSample.usedBytes,
                totalBytes: rawSample.totalBytes,
                compressedBytes: rawSample.compressedBytes,
                swapUsedBytes: rawSample.swapUsedBytes,
                swapOutBytesPerSecond: swapOutRate,
                systemPressure: systemPressure
            )

            previousSwapOutBytes = rawSample.swapOutBytes
            previousSampleDate = now
            latestState = state
            return (state, Array(continuations.values))
        }

        result.1.forEach { $0.yield(result.0) }
    }

    private func recordPressure(event: DispatchSource.MemoryPressureEvent) {
        let pressure: SystemMemoryPressure
        if event.contains(.critical) {
            pressure = .high
        } else if event.contains(.warning) {
            pressure = .elevated
        } else {
            pressure = .normal
        }

        lock.withLock {
            systemPressure = pressure
        }
    }

    private func removeContinuation(_ identifier: UUID) {
        _ = lock.withLock {
            continuations.removeValue(forKey: identifier)
        }
    }

    private static func readRawSample() -> RawSample? {
        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else {
            return nil
        }

        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let status = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(
                    mach_host_self(),
                    HOST_VM_INFO64,
                    reboundPointer,
                    &count
                )
            }
        }
        guard status == KERN_SUCCESS else { return nil }

        let totalBytes = ProcessInfo.processInfo.physicalMemory
        let usedBytes = NonCacheMemoryEstimator.usedBytes(
            totalBytes: totalBytes,
            pageSize: UInt64(pageSize),
            freePages: UInt64(statistics.free_count),
            speculativePages: UInt64(statistics.speculative_count),
            purgeablePages: UInt64(statistics.purgeable_count),
            externalPages: UInt64(statistics.external_page_count)
        )
        let compressedBytes = UInt64(statistics.compressor_page_count) * UInt64(pageSize)
        let swapOutBytes = UInt64(statistics.swapouts) * UInt64(pageSize)

        var swapUsage = xsw_usage()
        var swapUsageSize = MemoryLayout<xsw_usage>.size
        let swapStatus = sysctlbyname("vm.swapusage", &swapUsage, &swapUsageSize, nil, 0)
        let swapUsedBytes = swapStatus == 0 ? swapUsage.xsu_used : 0

        return RawSample(
            usedBytes: usedBytes,
            totalBytes: totalBytes,
            compressedBytes: compressedBytes,
            swapUsedBytes: swapUsedBytes,
            swapOutBytes: swapOutBytes
        )
    }

    private struct RawSample {
        let usedBytes: UInt64
        let totalBytes: UInt64
        let compressedBytes: UInt64
        let swapUsedBytes: UInt64
        let swapOutBytes: UInt64
    }
}

/// Product metric from PRODUCT_DESIGN §6. This is intentionally non-cache physical-memory
/// occupancy, not a claim of byte-for-byte parity with Activity Monitor's private formula.
enum NonCacheMemoryEstimator {
    static func usedBytes(
        totalBytes: UInt64,
        pageSize: UInt64,
        freePages: UInt64,
        speculativePages: UInt64,
        purgeablePages: UInt64,
        externalPages: UInt64
    ) -> UInt64 {
        guard totalBytes > 0, pageSize > 0 else { return 0 }

        let adjustedFreePages = freePages > speculativePages
            ? freePages - speculativePages
            : 0
        let reclaimablePages = saturatingSum([
            adjustedFreePages,
            purgeablePages,
            externalPages
        ])
        let (reclaimableBytes, overflowed) = reclaimablePages.multipliedReportingOverflow(
            by: pageSize
        )
        guard !overflowed, reclaimableBytes < totalBytes else { return 0 }
        return totalBytes - reclaimableBytes
    }

    private static func saturatingSum(_ values: [UInt64]) -> UInt64 {
        values.reduce(0) { result, value in
            let (sum, overflowed) = result.addingReportingOverflow(value)
            return overflowed ? .max : sum
        }
    }
}
