import Foundation
import Network

struct SystemNetworkAvailabilityMonitor: NetworkAvailabilityMonitoring {
    func availabilityUpdates() -> AsyncStream<NetworkAvailability> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "com.desktopbuddy.network-availability")

            monitor.pathUpdateHandler = { path in
                continuation.yield(path.status == .satisfied ? .available : .unavailable)
            }
            continuation.onTermination = { _ in
                monitor.cancel()
            }
            monitor.start(queue: queue)
        }
    }
}
