import Foundation
import Network

@Observable
@MainActor
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var isOnline: Bool = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Swift.Task { @MainActor [weak self] in
                self?.isOnline = online
            }
        }
        monitor.start(queue: queue)
    }
}
