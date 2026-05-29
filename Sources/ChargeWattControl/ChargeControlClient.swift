import BatteryToolkit
import ChargeWattCore
import Foundation
import ServiceManagement

public enum ChargeControlError: Error, Equatable {
    case daemonNotRegistered
    case daemonRequiresApproval
}

public struct ChargeControlState: Equatable, Sendable {
    public enum SupportStatus: Equatable, Sendable {
        case enabled
        case paused
        case unsupported
        case unknown
    }

    public let batteryPercent: Int?
    public let isCharging: Bool?
    public let isACConnected: Bool?
    public let chargingDisabled: Bool?
    public let maxCharge: Int?
    public let daemonEnabled: Bool?

    public init(
        batteryPercent: Int?,
        isCharging: Bool?,
        isACConnected: Bool?,
        chargingDisabled: Bool?,
        maxCharge: Int?,
        daemonEnabled: Bool? = nil
    ) {
        self.batteryPercent = batteryPercent
        self.isCharging = isCharging
        self.isACConnected = isACConnected
        self.chargingDisabled = chargingDisabled
        self.maxCharge = maxCharge
        self.daemonEnabled = daemonEnabled
    }

    public var supportStatus: SupportStatus {
        switch daemonEnabled {
        case .some(true):
            return .enabled
        case .some(false):
            return .paused
        case .none:
            return .unknown
        }
    }
}

public enum ChargeLimitApplicationResult: Equatable, Sendable {
    case updated
    case stoppedCharging
    case chargingToLimit
    case waitingToDropBelowLowerLimit
    case stateUnavailable
}

extension ChargeControlError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .daemonNotRegistered:
            return "后台 daemon 未能注册。请保持 ChargeWattMenu 位于“应用程序”目录，重新打开应用，并在系统设置中允许后台项目。"
        case .daemonRequiresApproval:
            return "后台 daemon 还没有被系统允许。请在“系统设置 > 通用 > 登录项与扩展”中允许 ChargeWattMenu，然后重试。"
        }
    }
}

public struct ChargeControlClient: Sendable {
    public enum DaemonStatus: Sendable {
        case enabled
        case requiresApproval
        case notRegistered

        init(_ status: BTDaemonManagementStatus) {
            switch status {
            case .enabled:
                self = .enabled
            case .requiresApproval:
                self = .requiresApproval
            case .notRegistered:
                self = .notRegistered
            }
        }

        @available(macOS 13.0, *)
        init(_ status: SMAppService.Status) {
            switch status {
            case .enabled:
                self = .enabled
            case .requiresApproval:
                self = .requiresApproval
            default:
                self = .notRegistered
            }
        }
    }

    private let actions: any ChargeControlActions
    private let sessionState: ChargeControlSessionState

    public init() {
        self.actions = BatteryToolkitChargeControlActions()
        self.sessionState = ChargeControlSessionState()
    }

    init(actions: any ChargeControlActions) {
        self.actions = actions
        self.sessionState = ChargeControlSessionState()
    }

    public func startDaemon() async -> DaemonStatus {
        await actions.startDaemon()
    }

    public func repairDaemonRegistration() async -> DaemonStatus {
        await actions.repairDaemonRegistration()
    }

    public func approveDaemon(timeout: UInt8) async throws {
        try await actions.approveDaemon(timeout: timeout)
    }

    public func prepareForAction(approvalTimeout: UInt8 = 6) async throws {
        var status = await actions.startDaemon()
        if status == .notRegistered {
            status = await actions.repairDaemonRegistration()
        }

        switch status {
        case .enabled:
            return
        case .requiresApproval:
            do {
                try await actions.approveDaemon(timeout: approvalTimeout)
            } catch {
                throw ChargeControlError.daemonRequiresApproval
            }
        case .notRegistered:
            throw ChargeControlError.daemonNotRegistered
        }
    }

    public func stop() async {
        await actions.stop()
    }

    @discardableResult
    public func restoreChargingBeforeExit(
        timeoutNanoseconds: UInt64 = 3_000_000_000
    ) async -> Bool {
        guard sessionState.hasPerformedChargingControl else {
            return true
        }

        let completed = await Self.runWithTimeout(timeoutNanoseconds: timeoutNanoseconds) {
            await actions.prepareRequestConnection()

            if let state = try? await actions.currentState(),
               state.daemonEnabled == true {
                let interventions = sessionState.currentInterventions
                if interventions.contains(.powerAdapter) {
                    try? await actions.enablePowerAdapter()
                }
                if interventions.requiresLimitModeRestore {
                    try? await actions.chargeToLimit()
                }
            }

            await actions.stop()
        }
        if completed {
            sessionState.clearChargingControl()
        }
        return completed
    }

    public func currentLimits() async throws -> ChargeLimitSettings {
        do {
            let limits = try await actions.currentLimits()
            await actions.stop()
            return limits
        } catch {
            await actions.stop()
            throw error
        }
    }

    public func currentState() async throws -> ChargeControlState {
        do {
            let state = try await actions.currentState()
            await actions.stop()
            return state
        } catch {
            await actions.stop()
            throw error
        }
    }

    public func setLimits(_ limits: ChargeLimitSettings) async throws {
        do {
            try await actions.setLimits(limits)
            await actions.stop()
        } catch {
            await actions.stop()
            throw error
        }
    }

    public func setLimitsAndApply(
        _ limits: ChargeLimitSettings
    ) async throws -> ChargeLimitApplicationResult {
        do {
            try await actions.setLimits(limits)
            guard let state = try? await actions.currentState(),
                  let batteryPercent = state.batteryPercent else {
                await actions.stop()
                return .stateUnavailable
            }

            if batteryPercent >= limits.maxCharge {
                try await actions.disableCharging()
                await actions.stop()
                return .stoppedCharging
            }

            if batteryPercent < limits.minCharge {
                try await actions.chargeToLimit()
                await actions.stop()
                return .chargingToLimit
            }

            await actions.stop()
            if state.chargingDisabled == true {
                return .waitingToDropBelowLowerLimit
            }

            return .updated
        } catch {
            await actions.stop()
            throw error
        }
    }

    public func chargeToLimit() async throws {
        try await runPreparedControlAction(
            restoresOnExit: [],
            clearsOnSuccess: [.charging, .chargeModeOverride]
        ) {
            try await actions.chargeToLimit()
        }
    }

    public func chargeToFull() async throws {
        try await runPreparedControlAction(restoresOnExit: .chargeModeOverride) {
            try await actions.chargeToFull()
        }
    }

    public func disableCharging() async throws {
        try await runPreparedControlAction(restoresOnExit: .charging) {
            try await actions.disableCharging()
        }
    }

    public func disablePowerAdapter() async throws {
        try await runPreparedControlAction(restoresOnExit: .powerAdapter) {
            try await actions.disablePowerAdapter()
        }
    }

    public func enablePowerAdapter() async throws {
        try await runPreparedControlAction(
            restoresOnExit: [],
            clearsOnSuccess: .powerAdapter
        ) {
            try await actions.enablePowerAdapter()
        }
    }

    public func pauseActivity() async throws {
        try await runPreparedControlAction(restoresOnExit: []) {
            try await actions.pauseActivity()
        }
    }

    public func resumeActivity() async throws {
        try await runPreparedControlAction(restoresOnExit: []) {
            try await actions.resumeActivity()
        }
    }

    public func removeDaemon() async throws {
        try await actions.removeDaemon()
    }

    private func runPreparedControlAction(
        restoresOnExit interventions: ChargeControlInterventions,
        clearsOnSuccess clearedInterventions: ChargeControlInterventions = [],
        _ operation: @escaping @Sendable () async throws -> Void
    ) async throws {
        await actions.prepareRequestConnection()
        do {
            try await operation()
            if !clearedInterventions.isEmpty {
                sessionState.clearChargingControl(clearedInterventions)
            }
            if !interventions.isEmpty {
                sessionState.markChargingControl(interventions)
            }
            await actions.stop()
        } catch {
            await actions.stop()
            throw error
        }
    }

    private static func runWithTimeout(
        timeoutNanoseconds: UInt64,
        operation: @escaping @Sendable () async -> Void
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            let gate = OneShotContinuation(continuation)
            let operationTask = Task {
                await operation()
                gate.resume(returning: true)
            }

            Task {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                if gate.resume(returning: false) {
                    operationTask.cancel()
                }
            }
        }
    }
}

public enum ChargeControlTermination {
    @discardableResult
    public static func waitForActiveActionBeforeRestore(
        _ activeAction: Task<Void, Never>?,
        activeActionTimeoutNanoseconds: UInt64 = 3_000_000_000,
        restore: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        if let activeAction {
            await waitForActiveAction(
                activeAction,
                timeoutNanoseconds: activeActionTimeoutNanoseconds
            )
        }
        return await restore()
    }

    private static func waitForActiveAction(
        _ activeAction: Task<Void, Never>,
        timeoutNanoseconds: UInt64
    ) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let gate = OneShotContinuation(continuation)
            Task {
                await activeAction.value
                gate.resume(returning: ())
            }
            Task {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                if gate.resume(returning: ()) {
                    activeAction.cancel()
                }
            }
        }
    }
}

private struct ChargeControlInterventions: OptionSet, Sendable {
    let rawValue: UInt8

    static let charging = ChargeControlInterventions(rawValue: 1 << 0)
    static let powerAdapter = ChargeControlInterventions(rawValue: 1 << 1)
    static let chargeModeOverride = ChargeControlInterventions(rawValue: 1 << 2)

    var requiresLimitModeRestore: Bool {
        !intersection([.charging, .powerAdapter, .chargeModeOverride]).isEmpty
    }
}

private final class ChargeControlSessionState: @unchecked Sendable {
    private let lock = NSLock()
    private var interventions: ChargeControlInterventions = []

    var hasPerformedChargingControl: Bool {
        lock.withLock {
            !interventions.isEmpty
        }
    }

    var currentInterventions: ChargeControlInterventions {
        lock.withLock {
            interventions
        }
    }

    func markChargingControl(_ interventions: ChargeControlInterventions) {
        lock.withLock {
            self.interventions.formUnion(interventions)
        }
    }

    func clearChargingControl() {
        lock.withLock {
            interventions = []
        }
    }

    func clearChargingControl(_ clearedInterventions: ChargeControlInterventions) {
        lock.withLock {
            interventions.subtract(clearedInterventions)
        }
    }
}

private final class OneShotContinuation<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?

    init(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = continuation
    }

    @discardableResult
    func resume(returning value: Value) -> Bool {
        let continuation = lock.withLock {
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
        guard let continuation else {
            return false
        }
        continuation.resume(returning: value)
        return true
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

protocol ChargeControlActions: Sendable {
    func startDaemon() async -> ChargeControlClient.DaemonStatus
    func repairDaemonRegistration() async -> ChargeControlClient.DaemonStatus
    func prepareRequestConnection() async
    func approveDaemon(timeout: UInt8) async throws
    func stop() async
    func currentLimits() async throws -> ChargeLimitSettings
    func currentState() async throws -> ChargeControlState
    func setLimits(_ limits: ChargeLimitSettings) async throws
    func chargeToLimit() async throws
    func chargeToFull() async throws
    func disableCharging() async throws
    func disablePowerAdapter() async throws
    func enablePowerAdapter() async throws
    func pauseActivity() async throws
    func resumeActivity() async throws
    func removeDaemon() async throws
}

private struct BatteryToolkitChargeControlActions: ChargeControlActions {
    func startDaemon() async -> ChargeControlClient.DaemonStatus {
        await ChargeControlClient.DaemonStatus(BTActions.startDaemon())
    }

    func repairDaemonRegistration() async -> ChargeControlClient.DaemonStatus {
        let updateAwareStatus = await startDaemon()
        guard updateAwareStatus == .notRegistered else {
            return updateAwareStatus
        }

        guard #available(macOS 13.0, *) else {
            return updateAwareStatus
        }

        let daemonId = Bundle.main.object(
            forInfoDictionaryKey: "BT_DAEMON_ID"
        ) as? String ?? "top.xsdev.ChargeWattMenu.control-daemon"
        let plistName = "\(daemonId).plist"

        let currentStatus = ChargeControlClient.DaemonStatus(
            SMAppService.daemon(plistName: plistName).status
        )
        if currentStatus != .notRegistered {
            return currentStatus
        }

        for _ in 0 ... 5 {
            let appService = SMAppService.daemon(plistName: plistName)
            do {
                try appService.register()
            } catch {
                // Re-check status after failed registration; an already registered
                // service can still be enabled or waiting for user approval.
            }

            let status = ChargeControlClient.DaemonStatus(appService.status)
            if status != .notRegistered {
                return status
            }

            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        return .notRegistered
    }

    func approveDaemon(timeout: UInt8) async throws {
        try await BTActions.approveDaemon(timeout: timeout)
    }

    func stop() async {
        await BTDaemonXPCClient.stopEventStream()
        await BTActions.stop()
    }

    func prepareRequestConnection() async {
        await BTDaemonXPCClient.startEventStream { _ in }
    }

    func currentLimits() async throws -> ChargeLimitSettings {
        let settings = try await BTActions.getSettings()
        let minCharge = Self.intValue(
            settings[BTSettingsInfo.Keys.minCharge],
            default: Int(BTSettingsInfo.Defaults.minCharge)
        )
        let maxCharge = Self.intValue(
            settings[BTSettingsInfo.Keys.maxCharge],
            default: Int(BTSettingsInfo.Defaults.maxCharge)
        )

        return try ChargeLimitSettings(
            minCharge: minCharge,
            maxCharge: maxCharge
        )
    }

    func currentState() async throws -> ChargeControlState {
        let state = try await BTActions.getState()
        return ChargeControlState(
            batteryPercent: Self.intValue(state[BTStateInfo.Keys.batteryPercent]),
            isCharging: Self.boolValue(state[BTStateInfo.Keys.isCharging]),
            isACConnected: Self.boolValue(state[BTStateInfo.Keys.isACConnected]),
            chargingDisabled: Self.boolValue(state[BTStateInfo.Keys.chargingDisabled]),
            maxCharge: Self.intValue(state[BTStateInfo.Keys.maxCharge]),
            daemonEnabled: Self.boolValue(state[BTStateInfo.Keys.enabled])
        )
    }

    func setLimits(_ limits: ChargeLimitSettings) async throws {
        var settings = try await BTActions.getSettings()
        settings[BTSettingsInfo.Keys.minCharge] = NSNumber(value: limits.minCharge)
        settings[BTSettingsInfo.Keys.maxCharge] = NSNumber(value: limits.maxCharge)
        try await BTActions.setSettings(settings: settings)
    }

    func chargeToLimit() async throws {
        try await BTActions.chargeToLimit()
    }

    func chargeToFull() async throws {
        try await BTActions.chargeToFull()
    }

    func disableCharging() async throws {
        try await BTActions.disableCharging()
    }

    func disablePowerAdapter() async throws {
        try await BTActions.disablePowerAdapter()
    }

    func enablePowerAdapter() async throws {
        try await BTActions.enablePowerAdapter()
    }

    func pauseActivity() async throws {
        try await BTActions.pauseActivity()
    }

    func resumeActivity() async throws {
        try await BTActions.resumeActivity()
    }

    func removeDaemon() async throws {
        try await BTActions.removeDaemon()
    }

    private static func intValue(
        _ value: (NSObject & Sendable)?,
        default defaultValue: Int
    ) -> Int {
        intValue(value) ?? defaultValue
    }

    private static func intValue(_ value: (NSObject & Sendable)?) -> Int? {
        guard let number = value as? NSNumber else {
            return nil
        }

        return number.intValue
    }

    private static func boolValue(_ value: (NSObject & Sendable)?) -> Bool? {
        guard let number = value as? NSNumber else {
            return nil
        }

        return number.boolValue
    }
}
