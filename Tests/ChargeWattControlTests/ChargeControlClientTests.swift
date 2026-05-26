import ChargeWattCore
import Foundation
import Testing
@testable import ChargeWattControl

@Suite
struct ChargeControlClientTests {
    @Test func prepareForActionReturnsWhenDaemonIsEnabled() async throws {
        let actions = FakeChargeControlActions(startStatuses: [.enabled])
        let client = ChargeControlClient(actions: actions)

        try await client.prepareForAction(approvalTimeout: 3)

        #expect(actions.startDaemonCallCount == 1)
        #expect(actions.approveTimeouts.isEmpty)
    }

    @Test func prepareForActionApprovesDaemonThatRequiresApproval() async throws {
        let actions = FakeChargeControlActions(startStatuses: [.requiresApproval])
        let client = ChargeControlClient(actions: actions)

        try await client.prepareForAction(approvalTimeout: 7)

        #expect(actions.startDaemonCallCount == 1)
        #expect(actions.approveTimeouts == [7])
    }

    @Test func prepareForActionRejectsUnregisteredDaemon() async {
        let actions = FakeChargeControlActions(startStatuses: [.notRegistered])
        let client = ChargeControlClient(actions: actions)

        await #expect(throws: ChargeControlError.daemonNotRegistered) {
            try await client.prepareForAction(approvalTimeout: 3)
        }
        #expect(actions.setLimitsCallCount == 0)
    }
}

private final class FakeChargeControlActions: ChargeControlActions, @unchecked Sendable {
    private let lock = NSLock()
    private var startStatuses: [ChargeControlClient.DaemonStatus]

    private(set) var startDaemonCallCount = 0
    private(set) var approveTimeouts: [UInt8] = []
    private(set) var setLimitsCallCount = 0

    init(startStatuses: [ChargeControlClient.DaemonStatus]) {
        self.startStatuses = startStatuses
    }

    func startDaemon() async -> ChargeControlClient.DaemonStatus {
        lock.withLock {
            startDaemonCallCount += 1
            return startStatuses.isEmpty ? .enabled : startStatuses.removeFirst()
        }
    }

    func approveDaemon(timeout: UInt8) async throws {
        lock.withLock {
            approveTimeouts.append(timeout)
        }
    }

    func stop() async {}

    func currentLimits() async throws -> ChargeLimitSettings {
        try ChargeLimitSettings(minCharge: 75, maxCharge: 80)
    }

    func setLimits(_ limits: ChargeLimitSettings) async throws {
        lock.withLock {
            setLimitsCallCount += 1
        }
    }

    func chargeToLimit() async throws {}

    func chargeToFull() async throws {}

    func disableCharging() async throws {}

    func disablePowerAdapter() async throws {}

    func enablePowerAdapter() async throws {}

    func pauseActivity() async throws {}

    func resumeActivity() async throws {}

    func removeDaemon() async throws {}
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
