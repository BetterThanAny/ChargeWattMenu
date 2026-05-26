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

        #expect(actions.repairDaemonRegistrationCallCount == 1)
        #expect(actions.approveTimeouts.isEmpty)
    }

    @Test func prepareForActionApprovesDaemonThatRequiresApproval() async throws {
        let actions = FakeChargeControlActions(startStatuses: [.requiresApproval])
        let client = ChargeControlClient(actions: actions)

        try await client.prepareForAction(approvalTimeout: 7)

        #expect(actions.repairDaemonRegistrationCallCount == 1)
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

    @Test func currentLimitsPreparesRequestConnectionBeforeReadingSettings() async throws {
        let actions = FakeChargeControlActions(startStatuses: [.enabled])
        let client = ChargeControlClient(actions: actions)

        _ = try await client.currentLimits()

        #expect(actions.prepareRequestConnectionCallCount == 1)
        #expect(actions.callOrder == ["prepareRequestConnection", "currentLimits"])
    }

    @Test func setLimitsAndApplyPreparesRequestConnectionOnceBeforeXPCRequests() async throws {
        let actions = FakeChargeControlActions(
            startStatuses: [.enabled],
            currentState: ChargeControlState(
                batteryPercent: 96,
                isCharging: false,
                isACConnected: true,
                chargingDisabled: false,
                maxCharge: 80
            )
        )
        let client = ChargeControlClient(actions: actions)

        _ = try await client.setLimitsAndApply(
            try ChargeLimitSettings(minCharge: 75, maxCharge: 80)
        )

        #expect(actions.prepareRequestConnectionCallCount == 1)
        #expect(
            actions.callOrder == [
                "prepareRequestConnection",
                "setLimits",
                "currentState",
                "disableCharging"
            ]
        )
    }

    @Test func setLimitsStopsChargingWhenBatteryIsAtOrAboveUpperLimit() async throws {
        let actions = FakeChargeControlActions(
            startStatuses: [.enabled],
            currentState: ChargeControlState(
                batteryPercent: 96,
                isCharging: false,
                isACConnected: true,
                chargingDisabled: false,
                maxCharge: 80
            )
        )
        let client = ChargeControlClient(actions: actions)

        let result = try await client.setLimitsAndApply(
            try ChargeLimitSettings(minCharge: 75, maxCharge: 80)
        )

        #expect(result == .stoppedCharging)
        #expect(actions.setLimitsCallCount == 1)
        #expect(actions.disableChargingCallCount == 1)
        #expect(actions.chargeToLimitCallCount == 0)
        #expect(actions.disablePowerAdapterCallCount == 0)
    }

    @Test func setLimitsChargesToLimitWhenBatteryIsBelowLowerLimit() async throws {
        let actions = FakeChargeControlActions(
            startStatuses: [.enabled],
            currentState: ChargeControlState(
                batteryPercent: 40,
                isCharging: false,
                isACConnected: true,
                chargingDisabled: true,
                maxCharge: 80
            )
        )
        let client = ChargeControlClient(actions: actions)

        let result = try await client.setLimitsAndApply(
            try ChargeLimitSettings(minCharge: 75, maxCharge: 80)
        )

        #expect(result == .chargingToLimit)
        #expect(actions.setLimitsCallCount == 1)
        #expect(actions.disableChargingCallCount == 0)
        #expect(actions.chargeToLimitCallCount == 1)
        #expect(actions.disablePowerAdapterCallCount == 0)
    }

    @Test func setLimitsLeavesChargingStateAloneInsideChargeWindow() async throws {
        let actions = FakeChargeControlActions(
            startStatuses: [.enabled],
            currentState: ChargeControlState(
                batteryPercent: 78,
                isCharging: false,
                isACConnected: true,
                chargingDisabled: true,
                maxCharge: 80
            )
        )
        let client = ChargeControlClient(actions: actions)

        let result = try await client.setLimitsAndApply(
            try ChargeLimitSettings(minCharge: 75, maxCharge: 80)
        )

        #expect(result == .waitingToDropBelowLowerLimit)
        #expect(actions.setLimitsCallCount == 1)
        #expect(actions.disableChargingCallCount == 0)
        #expect(actions.chargeToLimitCallCount == 0)
        #expect(actions.disablePowerAdapterCallCount == 0)
    }
}

private final class FakeChargeControlActions: ChargeControlActions, @unchecked Sendable {
    private let lock = NSLock()
    private var startStatuses: [ChargeControlClient.DaemonStatus]
    private let currentState: ChargeControlState

    private(set) var startDaemonCallCount = 0
    private(set) var repairDaemonRegistrationCallCount = 0
    private(set) var prepareRequestConnectionCallCount = 0
    private(set) var approveTimeouts: [UInt8] = []
    private(set) var setLimitsCallCount = 0
    private(set) var disableChargingCallCount = 0
    private(set) var chargeToLimitCallCount = 0
    private(set) var disablePowerAdapterCallCount = 0
    private(set) var callOrder: [String] = []

    init(
        startStatuses: [ChargeControlClient.DaemonStatus],
        currentState: ChargeControlState = ChargeControlState(
            batteryPercent: nil,
            isCharging: nil,
            isACConnected: nil,
            chargingDisabled: nil,
            maxCharge: nil
        )
    ) {
        self.startStatuses = startStatuses
        self.currentState = currentState
    }

    func startDaemon() async -> ChargeControlClient.DaemonStatus {
        lock.withLock {
            startDaemonCallCount += 1
            return startStatuses.isEmpty ? .enabled : startStatuses.removeFirst()
        }
    }

    func repairDaemonRegistration() async -> ChargeControlClient.DaemonStatus {
        lock.withLock {
            repairDaemonRegistrationCallCount += 1
            callOrder.append("repairDaemonRegistration")
            return startStatuses.isEmpty ? .enabled : startStatuses.removeFirst()
        }
    }

    func prepareRequestConnection() async {
        lock.withLock {
            prepareRequestConnectionCallCount += 1
            callOrder.append("prepareRequestConnection")
        }
    }

    func approveDaemon(timeout: UInt8) async throws {
        lock.withLock {
            approveTimeouts.append(timeout)
            callOrder.append("approveDaemon")
        }
    }

    func stop() async {}

    func currentLimits() async throws -> ChargeLimitSettings {
        lock.withLock {
            callOrder.append("currentLimits")
        }
        return try ChargeLimitSettings(minCharge: 75, maxCharge: 80)
    }

    func currentState() async throws -> ChargeControlState {
        lock.withLock {
            callOrder.append("currentState")
        }
        return currentState
    }

    func setLimits(_ limits: ChargeLimitSettings) async throws {
        lock.withLock {
            setLimitsCallCount += 1
            callOrder.append("setLimits")
        }
    }

    func chargeToLimit() async throws {
        lock.withLock {
            chargeToLimitCallCount += 1
            callOrder.append("chargeToLimit")
        }
    }

    func chargeToFull() async throws {}

    func disableCharging() async throws {
        lock.withLock {
            disableChargingCallCount += 1
            callOrder.append("disableCharging")
        }
    }

    func disablePowerAdapter() async throws {
        lock.withLock {
            disablePowerAdapterCallCount += 1
            callOrder.append("disablePowerAdapter")
        }
    }

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
