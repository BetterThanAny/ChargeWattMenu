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
        #expect(actions.repairDaemonRegistrationCallCount == 0)
        #expect(actions.approveTimeouts.isEmpty)
    }

    @Test func prepareForActionRepairsUnregisteredDaemonBeforeFailing() async throws {
        let actions = FakeChargeControlActions(
            startStatuses: [.notRegistered, .enabled]
        )
        let client = ChargeControlClient(actions: actions)

        try await client.prepareForAction(approvalTimeout: 3)

        #expect(actions.startDaemonCallCount == 1)
        #expect(actions.repairDaemonRegistrationCallCount == 1)
        #expect(actions.callOrder == ["startDaemon", "repairDaemonRegistration"])
    }

    @Test func prepareForActionApprovesDaemonThatRequiresApproval() async throws {
        let actions = FakeChargeControlActions(startStatuses: [.requiresApproval])
        let client = ChargeControlClient(actions: actions)

        try await client.prepareForAction(approvalTimeout: 7)

        #expect(actions.startDaemonCallCount == 1)
        #expect(actions.repairDaemonRegistrationCallCount == 0)
        #expect(actions.approveTimeouts == [7])
    }

    @Test func prepareForActionMapsApprovalFailureToRequiresApproval() async {
        let actions = FakeChargeControlActions(
            startStatuses: [.requiresApproval],
            approveError: FakeChargeControlError.approvalFailed
        )
        let client = ChargeControlClient(actions: actions)

        await #expect(throws: ChargeControlError.daemonRequiresApproval) {
            try await client.prepareForAction(approvalTimeout: 7)
        }
        #expect(actions.approveTimeouts == [7])
    }

    @Test func prepareForActionRejectsUnregisteredDaemonAfterRepairAttempt() async {
        let actions = FakeChargeControlActions(
            startStatuses: [.notRegistered, .notRegistered]
        )
        let client = ChargeControlClient(actions: actions)

        await #expect(throws: ChargeControlError.daemonNotRegistered) {
            try await client.prepareForAction(approvalTimeout: 3)
        }
        #expect(actions.startDaemonCallCount == 1)
        #expect(actions.repairDaemonRegistrationCallCount == 1)
        #expect(actions.setLimitsCallCount == 0)
    }

    @Test func restoreChargingBeforeExitFailsOpenBeforeDisconnecting() async {
        let actions = FakeChargeControlActions(startStatuses: [.enabled])
        let client = ChargeControlClient(actions: actions)

        await client.restoreChargingBeforeExit()

        #expect(actions.prepareRequestConnectionCallCount == 1)
        #expect(actions.enablePowerAdapterCallCount == 1)
        #expect(actions.chargeToFullCallCount == 1)
        #expect(actions.stopCallCount == 1)
        #expect(
            actions.callOrder == [
                "prepareRequestConnection",
                "enablePowerAdapter",
                "chargeToFull",
                "stop"
            ]
        )
    }

    @Test func currentLimitsPreparesRequestConnectionBeforeReadingSettings() async throws {
        let actions = FakeChargeControlActions(startStatuses: [.enabled])
        let client = ChargeControlClient(actions: actions)

        _ = try await client.currentLimits()

        #expect(actions.prepareRequestConnectionCallCount == 1)
        #expect(actions.callOrder == ["prepareRequestConnection", "currentLimits"])
    }

    @Test func setLimitsAndApplyOnlyPersistsLimits() async throws {
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

        #expect(result == .updated)
        #expect(actions.prepareRequestConnectionCallCount == 1)
        #expect(actions.setLimitsCallCount == 1)
        #expect(actions.disableChargingCallCount == 0)
        #expect(actions.chargeToLimitCallCount == 0)
        #expect(actions.callOrder == ["prepareRequestConnection", "setLimits"])
    }

    @Test func setLimitsDoesNotChargeWhenBatteryIsBelowLowerLimit() async throws {
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

        #expect(result == .updated)
        #expect(actions.setLimitsCallCount == 1)
        #expect(actions.disableChargingCallCount == 0)
        #expect(actions.chargeToLimitCallCount == 0)
        #expect(actions.disablePowerAdapterCallCount == 0)
    }
}

private enum FakeChargeControlError: Error {
    case approvalFailed
}

private final class FakeChargeControlActions: ChargeControlActions, @unchecked Sendable {
    private let lock = NSLock()
    private var startStatuses: [ChargeControlClient.DaemonStatus]
    private let currentState: ChargeControlState
    private let approveError: (any Error)?

    private(set) var startDaemonCallCount = 0
    private(set) var repairDaemonRegistrationCallCount = 0
    private(set) var prepareRequestConnectionCallCount = 0
    private(set) var approveTimeouts: [UInt8] = []
    private(set) var setLimitsCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var disableChargingCallCount = 0
    private(set) var chargeToLimitCallCount = 0
    private(set) var chargeToFullCallCount = 0
    private(set) var disablePowerAdapterCallCount = 0
    private(set) var enablePowerAdapterCallCount = 0
    private(set) var callOrder: [String] = []

    init(
        startStatuses: [ChargeControlClient.DaemonStatus],
        currentState: ChargeControlState = ChargeControlState(
            batteryPercent: nil,
            isCharging: nil,
            isACConnected: nil,
            chargingDisabled: nil,
            maxCharge: nil
        ),
        approveError: (any Error)? = nil
    ) {
        self.startStatuses = startStatuses
        self.currentState = currentState
        self.approveError = approveError
    }

    func startDaemon() async -> ChargeControlClient.DaemonStatus {
        lock.withLock {
            startDaemonCallCount += 1
            callOrder.append("startDaemon")
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
        if let approveError {
            throw approveError
        }
    }

    func stop() async {
        lock.withLock {
            stopCallCount += 1
            callOrder.append("stop")
        }
    }

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

    func chargeToFull() async throws {
        lock.withLock {
            chargeToFullCallCount += 1
            callOrder.append("chargeToFull")
        }
    }

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

    func enablePowerAdapter() async throws {
        lock.withLock {
            enablePowerAdapterCallCount += 1
            callOrder.append("enablePowerAdapter")
        }
    }

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
