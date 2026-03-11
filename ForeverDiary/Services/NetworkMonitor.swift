import Network
import Foundation

@Observable
final class NetworkMonitor {
    private(set) var isConnected: Bool = true

    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "com.foreverdiary.networkmonitor")

    func start() {
        guard monitor == nil else { return }
        let m = NWPathMonitor()
        m.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
            }
        }
        m.start(queue: queue)
        monitor = m
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
    }
}
