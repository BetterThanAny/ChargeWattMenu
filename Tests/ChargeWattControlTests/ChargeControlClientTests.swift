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

    @Test func restoreChargingBeforeExitSkipsDaemonConnectionWhenSessionDidNotControlCharging() async {
        let actions = FakeChargeControlActions(
            startStatuses: [.enabled],
            currentState: ChargeControlState(
                batteryPercent: 79,
                isCharging: false,
                isACConnected: true,
                chargingDisabled: true,
                maxCharge: 80,
                daemonEnabled: true
            )
        )
        let client = ChargeControlClient(actions: actions)

        let completed = await client.restoreChargingBeforeExit()

        #expect(completed)
        #expect(actions.callOrder.isEmpty)
        #expect(actions.prepareRequestConnectionCallCount == 0)
        #expect(actions.currentStateCallCount == 0)
        #expect(actions.stopCallCount == 0)
    }

    @Test func restoreChargingBeforeExitResumesLimitControlBeforeDisconnecting() async throws {
        let actions = FakeChargeControlActions(
            startStatuses: [.enabled],
            currentState: ChargeControlState(
                batteryPercent: 79,
                isCharging: false,
                isACConnected: true,
                chargingDisabled: true,
                maxCharge: 80,
                daemonEnabled: true
            )
        )
        let client = ChargeControlClient(actions: actions)
        try await client.disableCharging()
        actions.resetTracking()

        let completed = await client.restoreChargingBeforeExit()

        #expect(completed)
        #expect(actions.prepareRequestConnectionCallCount == 1)
        #expect(actions.currentStateCallCount == 1)
        #expect(actions.resumeActivityCallCount == 0)
        #expect(actions.enablePowerAdapterCallCount == 0)
        #expect(actions.chargeToLimitCallCount == 1)
        #expect(actions.chargeToFullCallCount == 0)
        #expect(actions.stopCallCount == 1)
        #expect(
            actions.callOrder == [
                "prepareRequestConnection",
                "currentState",
                "chargeToLimit",
                "stop"
            ]
        )
    }

    @Test func restoreChargingBeforeExitRestoresPowerAdapterIntervention() async throws {
        let actions = FakeChargeControlActions(
            startStatuses: [.enabled],
            currentState: ChargeControlState(
                batteryPercent: 79,
                isCharging: false,
                isACConnected: false,
                chargingDisabled: false,
                maxCharge: 80,
                daemonEnabled: true
            )
        )
        let client = ChargeControlClient(actions: actions)
        try await client.disablePowerAdapter()
        actions.resetTracking()

        let completed = await client.restoreChargingBeforeExit()

        #expect(completed)
        #expect(actions.enablePowerAdapterCallCount == 1)
        #expect(actions.chargeToLimitCallCount == 1)
        #expect(actions.callOrder == [
            "prepareRequestConnection",
            "currentState",
            "enablePowerAdapter",
            "chargeToLimit",
            "stop"
        ])
    }

    @Test func restoreChargingBeforeExitSkipsAfterSavingOnlyLimits() async throws {
        let actions = FakeChargeControlActions(
            startStatuses: [.enabled],
            currentState: ChargeControlState(
                batteryPercent: 79,
                isCharging: true,
                isACConnected: true,
                chargingDisabled: false,
                maxCharge: 80,
                daemonEnabled: true
            )
        )
        let client = ChargeControlClient(actions: actions)
        try await client.setLimits(ChargeLimitSettings.defaults)
        actions.resetTracking()

        let completed = await client.restoreChargingBeforeExit()

        #expect(completed)
        #expect(actions.callOrder.isEmpty)
    }

    @Test func restoreChargingBeforeExitSkipsAfterLimitsAlreadyMatchSteadyState() async throws {
        let actions = FakeChargeControlActions(
            startStatuses: [.enabled],
            currentState: ChargeControlState(
                batteryPercent: 78,
                isCharging: true,
                isACConnected: true,
                chargingDisabled: false,
                maxCharge: 80,
                daemonEnabled: true
            )
        )
        let client = ChargeControlClient(actions: actions)
        let result = try await client.setLimitsAndApply(ChargeLimitSettings.defaults)
        actions.resetTracking()

        let completed = await client.restoreChargingBeforeExit()

        #expect(result == .updated)
        #expect(completed)
        #expect(actions.callOrder.isEmpty)
    }

    @Test func restoreChargingBeforeExitSkipsAfterManualActivityPause() async throws {
        let actions = FakeChargeControlActions(
            startStatuses: [.enabled],
            currentState: ChargeControlState(
                batteryPercent: 79,
                isCharging: true,
                isACConnected: true,
                chargingDisabled: false,
                maxCharge: 80,
                daemonEnabled: true
            )
        )
        let client = ChargeControlClient(actions: actions)
        try await client.pauseActivity()
        actions.resetTracking()

        let completed = await client.restoreChargingBeforeExit()

        #expect(completed)
        #expect(actions.callOrder.isEmpty)
    }

    @Test func restoreChargingBeforeExitSkipsAfterPowerAdapterWasReenabled() async throws {
        let actions = FakeChargeControlActions(
            startStatuses: [.enabled],
            currentState: ChargeControlState(
                batteryPercent: 79,
                isCharging: false,
                isACConnected: true,
                chargingDisabled: false,
                maxCharge: 80,
                daemonEnabled: true
            )
        )
        let client = ChargeControlClient(actions: actions)
        try await client.disablePowerAdapter()
        try await client.enablePowerAdapter()
        actions.resetTracking()

        let completed = await client.restoreChargingBeforeExit()

        #expect(completed)
        #expect(actions.callOrder.isEmpty)
    }

    @Test func restoreChargingBeforeExitSkipsAfterChargeToFullReturnedToLimitMode() async throws {
        let actions = FakeChargeControlActions(
            startStatuses: [.enabled],
            currentState: ChargeControlState(
                batteryPercent: 79,
                isCharging: true,
                isACConnected: true,
                chargingDisabled: false,
                maxCharge: 80,
                daemonEnabled: true
            )
        )
        let client = ChargeControlClient(actions: actions)
        try await client.chargeToFull()
        try await client.chargeToLimit()
        actions.resetTracking()

        let completed = await client.restoreChargingBeforeExit()

        #expect(completed)
        #expect(actions.callOrder.isEmpty)
    }

    @Test func restoreChargingBeforeExitSkipsChargingChangesWhenDaemonIsDisabled() async throws {
        let actions = FakeChargeControlActions(
            startStatuses: [.enabled],
            currentState: ChargeControlState(
                batteryPercent: 79,
                isCharging: false,
                isACConnected: true,
                chargingDisabled: true,
                maxCharge: 80,
                daemonEnabled: false
            )
        )
        let client = ChargeControlClient(actions: actions)
        try await client.disableCharging()
        actions.resetTracking()

        let completed = await client.restoreChargingBeforeExit()

        #expect(completed)
        #expect(actions.enablePowerAdapterCallCount == 0)
        #expect(actions.chargeToLimitCallCount == 0)
        #expect(actions.chargeToFullCallCount == 0)
        #expect(actions.stopCallCount == 1)
    }

    @Test func restoreChargingBeforeExitTimesOutWhenDaemonDoesNotRespond() async throws {
        let actions = FakeChargeControlActions(startStatuses: [.enabled])
        let client = ChargeControlClient(actions: actions)
        try await client.disableCharging()
        actions.resetTracking()
        actions.hangPreparingRequestConnection()

        let completed = await client.restoreChargingBeforeExit(
            timeoutNanoseconds: 10_000_000
        )

        #expect(completed == false)
        #expect(actions.prepareRequestConnectionCallCount == 1)
    }

    @Test func currentLimitsReadsSettingsWithoutStartingEventStream() async throws {
        let actions = FakeChargeControlActions(startStatuses: [.enabled])
        let client = ChargeControlClient(actions: actions)

        _ = try await client.currentLimits()

        #expect(actions.prepareRequestConnectionCallCount == 0)
        #expect(actions.callOrder == ["currentLimits", "stop"])
    }

    @Test func currentStateReadsDaemonStateWithoutStartingEventStream() async throws {
        let actions = FakeChargeControlActions(startStatuses: [.enabled])
        let client = ChargeControlClient(actions: actions)

        _ = try await client.currentState()

        #expect(actions.prepareRequestConnectionCallCount == 0)
        #expect(actions.callOrder == ["currentState", "stop"])
    }

    @Test func setLimitsAndApplyStopsChargingAtOrAboveUpperLimit() async throws {
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
        #expect(actions.prepareRequestConnectionCallCount == 0)
        #expect(actions.setLimitsCallCount == 1)
        #expect(actions.currentStateCallCount == 1)
        #expect(actions.disableChargingCallCount == 1)
        #expect(actions.chargeToLimitCallCount == 0)
        #expect(actions.callOrder == ["setLimits", "currentState", "disableCharging", "stop"])
    }

    @Test func setLimitsAndApplyChargesToLimitBelowLowerLimit() async throws {
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

    @Test func setLimitsAndApplyWaitsWhenBatteryIsBetweenLimitsAndChargingIsDisabled() async throws {
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
        #expect(actions.disableChargingCallCount == 0)
        #expect(actions.chargeToLimitCallCount == 0)
    }

    @Test func setLimitsAndApplyReportsUnavailableState() async throws {
        let actions = FakeChargeControlActions(
            startStatuses: [.enabled],
            currentStateError: FakeChargeControlError.stateUnavailable
        )
        let client = ChargeControlClient(actions: actions)

        let result = try await client.setLimitsAndApply(
            try ChargeLimitSettings(minCharge: 75, maxCharge: 80)
        )

        #expect(result == .stateUnavailable)
        #expect(actions.setLimitsCallCount == 1)
        #expect(actions.disableChargingCallCount == 0)
        #expect(actions.chargeToLimitCallCount == 0)
    }

    @Test func chargeToLimitStopsEventStreamAfterSendingCommand() async throws {
        let actions = FakeChargeControlActions(startStatuses: [.enabled])
        let client = ChargeControlClient(actions: actions)

        try await client.chargeToLimit()

        #expect(actions.prepareRequestConnectionCallCount == 1)
        #expect(actions.chargeToLimitCallCount == 1)
        #expect(actions.stopCallCount == 1)
        #expect(actions.callOrder == [
            "prepareRequestConnection",
            "chargeToLimit",
            "stop"
        ])
    }

    @Test func chargeControlStateRequiresExplicitDaemonEnabledFlag() {
        let unknown = ChargeControlState(
            batteryPercent: nil,
            isCharging: nil,
            isACConnected: nil,
            chargingDisabled: nil,
            maxCharge: nil,
            daemonEnabled: nil
        )
        let disabled = ChargeControlState(
            batteryPercent: nil,
            isCharging: nil,
            isACConnected: nil,
            chargingDisabled: nil,
            maxCharge: nil,
            daemonEnabled: false
        )
        let enabled = ChargeControlState(
            batteryPercent: nil,
            isCharging: nil,
            isACConnected: nil,
            chargingDisabled: nil,
            maxCharge: nil,
            daemonEnabled: true
        )

        #expect(unknown.supportStatus == .unknown)
        #expect(disabled.supportStatus == .paused)
        #expect(enabled.supportStatus == .enabled)
    }

    @Test func terminationWaitsForActiveActionBeforeRestoring() async {
        let events = OrderedEvents()
        let activeAction = Task<Void, Never> {
            await events.append("active-start")
            try? await Task.sleep(nanoseconds: 20_000_000)
            await events.append("active-end")
        }

        let restored = await ChargeControlTermination.waitForActiveActionBeforeRestore(
            activeAction
        ) {
            await events.append("restore")
            return true
        }

        #expect(restored)
        #expect(await events.values == ["active-start", "active-end", "restore"])
    }
}

private actor OrderedEvents {
    private var entries: [String] = []

    var values: [String] {
        entries
    }

    func append(_ value: String) {
        entries.append(value)
    }
}

private enum FakeChargeControlError: Error {
    case approvalFailed
    case stateUnavailable
}

private final class FakeChargeControlActions: ChargeControlActions, @unchecked Sendable {
    private let lock = NSLock()
    private var startStatuses: [ChargeControlClient.DaemonStatus]
    private let currentState: ChargeControlState
    private let approveError: (any Error)?
    private let currentStateError: (any Error)?
    private var hangsPreparingRequestConnection: Bool

    private(set) var startDaemonCallCount = 0
    private(set) var repairDaemonRegistrationCallCount = 0
    private(set) var prepareRequestConnectionCallCount = 0
    private(set) var currentStateCallCount = 0
    private(set) var approveTimeouts: [UInt8] = []
    private(set) var setLimitsCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var disableChargingCallCount = 0
    private(set) var chargeToLimitCallCount = 0
    private(set) var chargeToFullCallCount = 0
    private(set) var disablePowerAdapterCallCount = 0
    private(set) var enablePowerAdapterCallCount = 0
    private(set) var resumeActivityCallCount = 0
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
        approveError: (any Error)? = nil,
        currentStateError: (any Error)? = nil,
        hangsPreparingRequestConnection: Bool = false
    ) {
        self.startStatuses = startStatuses
        self.currentState = currentState
        self.approveError = approveError
        self.currentStateError = currentStateError
        self.hangsPreparingRequestConnection = hangsPreparingRequestConnection
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
        let shouldHang = lock.withLock {
            prepareRequestConnectionCallCount += 1
            callOrder.append("prepareRequestConnection")
            return hangsPreparingRequestConnection
        }
        if shouldHang {
            try? await Task.sleep(nanoseconds: 60_000_000_000)
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
            currentStateCallCount += 1
            callOrder.append("currentState")
        }
        if let currentStateError {
            throw currentStateError
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

    func resumeActivity() async throws {
        lock.withLock {
            resumeActivityCallCount += 1
            callOrder.append("resumeActivity")
        }
    }

    func removeDaemon() async throws {}

    func hangPreparingRequestConnection() {
        lock.withLock {
            hangsPreparingRequestConnection = true
        }
    }

    func resetTracking() {
        lock.withLock {
            startDaemonCallCount = 0
            repairDaemonRegistrationCallCount = 0
            prepareRequestConnectionCallCount = 0
            currentStateCallCount = 0
            approveTimeouts = []
            setLimitsCallCount = 0
            stopCallCount = 0
            disableChargingCallCount = 0
            chargeToLimitCallCount = 0
            chargeToFullCallCount = 0
            disablePowerAdapterCallCount = 0
            enablePowerAdapterCallCount = 0
            resumeActivityCallCount = 0
            callOrder = []
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
