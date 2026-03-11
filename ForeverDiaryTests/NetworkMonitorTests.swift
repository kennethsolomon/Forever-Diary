import XCTest
import Network
@testable import ForeverDiary

final class NetworkMonitorTests: XCTestCase {

    // MARK: - Initial state

    func testInitialIsConnectedIsTrue() {
        let monitor = NetworkMonitor()
        XCTAssertTrue(monitor.isConnected, "NetworkMonitor should default to connected before any path update")
    }

    // MARK: - Lifecycle: start

    func testStartDoesNotCrash() {
        let monitor = NetworkMonitor()
        monitor.start()
        monitor.stop()
    }

    func testStartIsIdempotent() {
        // Calling start() twice must not crash or create a second monitor
        let monitor = NetworkMonitor()
        monitor.start()
        monitor.start() // second call should be a no-op
        monitor.stop()
    }

    func testStartAfterStopDoesNotCrash() {
        let monitor = NetworkMonitor()
        monitor.start()
        monitor.stop()
        monitor.start() // should create a fresh NWPathMonitor
        monitor.stop()
    }

    // MARK: - Lifecycle: stop

    func testStopBeforeStartIsIdempotent() {
        // Calling stop() when monitor was never started must not crash
        let monitor = NetworkMonitor()
        monitor.stop()
    }

    func testStopIsIdempotent() {
        let monitor = NetworkMonitor()
        monitor.start()
        monitor.stop()
        monitor.stop() // second stop should be safe
    }

    func testFullStartStopCycleRepeated() {
        let monitor = NetworkMonitor()
        for _ in 0..<3 {
            monitor.start()
            monitor.stop()
        }
    }

    // MARK: - isConnected state preservation

    func testIsConnectedRemainsAfterStopWithoutNetworkEvent() {
        // Stopping without receiving a path update should leave isConnected unchanged
        let monitor = NetworkMonitor()
        let initialValue = monitor.isConnected
        monitor.start()
        monitor.stop()
        XCTAssertEqual(monitor.isConnected, initialValue)
    }

    func testIsConnectedDefaultTrueAfterMultipleCycles() {
        let monitor = NetworkMonitor()
        monitor.start()
        monitor.stop()
        monitor.start()
        monitor.stop()
        // No path events fired in tests — isConnected should still be the default
        XCTAssertTrue(monitor.isConnected)
    }
}
