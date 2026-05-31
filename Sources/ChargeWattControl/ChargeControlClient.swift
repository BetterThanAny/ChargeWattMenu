import BatteryToolkit
import ChargeWattCore
import Foundation
import Security
import ServiceManagement

public enum ChargeControlError: Error, Equatable {
    case daemonNotRegistered
    case daemonRequiresApproval
    case daemonTimedOut
    case daemonRequiresSignedBuild
    case authorizationSetupFailed
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
        case .daemonTimedOut:
            return "后台 daemon 没有响应。请稍后重试，或重启 ChargeWattMenu。"
        case .daemonRequiresSignedBuild:
            return "当前安装包没有 Apple 代码签名身份，macOS 会拒绝启动后台 daemon。请使用 Apple Development 或 Developer ID 签名后重新安装。"
        case .authorizationSetupFailed:
            return "充电控制授权配置失败。请重新打开 ChargeWattMenu 后再试。"
        }
    }
}

public struct ChargeControlClient: Sendable {
    public enum DaemonStatus: Sendable {
        case enabled
        case requiresApproval
        case notRegistered
        case notResponding
        case requiresSignedBuild

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
    private static let defaultDaemonResponseTimeoutNanoseconds: UInt64 = 8_000_000_000

    public init() {
        self.actions = BatteryToolkitChargeControlActions()
        self.sessionState = ChargeControlSessionState()
    }

    init(actions: any ChargeControlActions) {
        self.actions = actions
        self.sessionState = ChargeControlSessionState()
    }

    public func startDaemon(
        timeoutNanoseconds: UInt64 = 8_000_000_000
    ) async -> DaemonStatus {
        do {
            try await prepareRequestConnection(timeoutNanoseconds: timeoutNanoseconds)
            return try await Self.runThrowingWithTimeout(
                timeoutNanoseconds: timeoutNanoseconds
            ) {
                await actions.startDaemon()
            }
        } catch {
            return .notResponding
        }
    }

    public func repairDaemonRegistration() async -> DaemonStatus {
        await actions.repairDaemonRegistration()
    }

    public func approveDaemon(timeout: UInt8) async throws {
        try await actions.approveDaemon(timeout: timeout)
    }

    public func prepareForAction(
        approvalTimeout: UInt8 = 6,
        daemonResponseTimeoutNanoseconds: UInt64 = 8_000_000_000
    ) async throws {
        try await prepareRequestConnection(
            timeoutNanoseconds: daemonResponseTimeoutNanoseconds
        )

        var status: DaemonStatus
        do {
            status = try await Self.runThrowingWithTimeout(
                timeoutNanoseconds: daemonResponseTimeoutNanoseconds
            ) {
                await actions.startDaemon()
            }
        } catch ChargeControlError.daemonTimedOut {
            throw ChargeControlError.daemonTimedOut
        }
        if status == .notRegistered {
            status = try await repairDaemonRegistration(
                timeoutNanoseconds: daemonResponseTimeoutNanoseconds
            )
        }

        switch status {
        case .enabled:
            try await prepareManageAuthorizationRight(
                timeoutNanoseconds: daemonResponseTimeoutNanoseconds
            )
            return
        case .requiresApproval:
            do {
                try await actions.approveDaemon(timeout: approvalTimeout)
            } catch {
                throw ChargeControlError.daemonRequiresApproval
            }
            try await prepareManageAuthorizationRight(
                timeoutNanoseconds: daemonResponseTimeoutNanoseconds
            )
        case .notRegistered:
            throw ChargeControlError.daemonNotRegistered
        case .notResponding:
            throw ChargeControlError.daemonTimedOut
        case .requiresSignedBuild:
            throw ChargeControlError.daemonRequiresSignedBuild
        }
    }

    private func repairDaemonRegistration(timeoutNanoseconds: UInt64) async throws -> DaemonStatus {
        try await Self.runThrowingWithTimeout(timeoutNanoseconds: timeoutNanoseconds) {
            await actions.repairDaemonRegistration()
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

    public func currentLimits(
        timeoutNanoseconds: UInt64 = 8_000_000_000
    ) async throws -> ChargeLimitSettings {
        do {
            try await prepareRequestConnection(timeoutNanoseconds: timeoutNanoseconds)
            let limits = try await Self.runThrowingWithTimeout(
                timeoutNanoseconds: timeoutNanoseconds
            ) {
                try await actions.currentLimits()
            }
            await actions.stop()
            return limits
        } catch {
            await actions.stop()
            throw error
        }
    }

    public func currentState(
        timeoutNanoseconds: UInt64 = 8_000_000_000
    ) async throws -> ChargeControlState {
        do {
            try await prepareRequestConnection(timeoutNanoseconds: timeoutNanoseconds)
            let state = try await Self.runThrowingWithTimeout(
                timeoutNanoseconds: timeoutNanoseconds
            ) {
                try await actions.currentState()
            }
            await actions.stop()
            return state
        } catch {
            await actions.stop()
            throw error
        }
    }

    public func setLimits(
        _ limits: ChargeLimitSettings,
        timeoutNanoseconds: UInt64 = 8_000_000_000
    ) async throws {
        do {
            try await prepareRequestConnection(timeoutNanoseconds: timeoutNanoseconds)
            try await prepareManageAuthorizationRight(timeoutNanoseconds: timeoutNanoseconds)
            try await Self.runThrowingWithTimeout(timeoutNanoseconds: timeoutNanoseconds) {
                try await actions.setLimits(limits)
            }
            await actions.stop()
        } catch {
            await actions.stop()
            throw error
        }
    }

    public func setLimitsAndApply(
        _ limits: ChargeLimitSettings,
        timeoutNanoseconds: UInt64 = 8_000_000_000
    ) async throws -> ChargeLimitApplicationResult {
        do {
            try await prepareRequestConnection(timeoutNanoseconds: timeoutNanoseconds)
            try await prepareManageAuthorizationRight(timeoutNanoseconds: timeoutNanoseconds)
            let result: ChargeLimitApplicationResult = try await Self.runThrowingWithTimeout(
                timeoutNanoseconds: timeoutNanoseconds
            ) {
                try await actions.setLimits(limits)
                guard let state = try? await actions.currentState(),
                      let batteryPercent = state.batteryPercent else {
                    return .stateUnavailable
                }

                if batteryPercent >= limits.maxCharge {
                    try await actions.disableCharging()
                    return .stoppedCharging
                }

                if batteryPercent < limits.minCharge {
                    try await actions.chargeToLimit()
                    return .chargingToLimit
                }

                if state.chargingDisabled == true {
                    return .waitingToDropBelowLowerLimit
                }

                return .updated
            }
            await actions.stop()
            return result
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
        try await runPreparedControlAction(
            restoresOnExit: .charging,
            requiresAuthorization: true
        ) {
            try await actions.disableCharging()
        }
    }

    public func disablePowerAdapter() async throws {
        try await runPreparedControlAction(
            restoresOnExit: .powerAdapter,
            requiresAuthorization: true
        ) {
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
        try await runPreparedControlAction(
            restoresOnExit: [],
            requiresAuthorization: true
        ) {
            try await actions.pauseActivity()
        }
    }

    public func resumeActivity() async throws {
        try await runPreparedControlAction(
            restoresOnExit: [],
            requiresAuthorization: true
        ) {
            try await actions.resumeActivity()
        }
    }

    public func removeDaemon() async throws {
        try await actions.removeDaemon()
    }

    private func runPreparedControlAction(
        restoresOnExit interventions: ChargeControlInterventions,
        clearsOnSuccess clearedInterventions: ChargeControlInterventions = [],
        requiresAuthorization: Bool = false,
        timeoutNanoseconds: UInt64 = Self.defaultDaemonResponseTimeoutNanoseconds,
        _ operation: @escaping @Sendable () async throws -> Void
    ) async throws {
        do {
            try await prepareRequestConnection(timeoutNanoseconds: timeoutNanoseconds)
            if requiresAuthorization {
                try await prepareManageAuthorizationRight(timeoutNanoseconds: timeoutNanoseconds)
            }
            try await Self.runThrowingWithTimeout(timeoutNanoseconds: timeoutNanoseconds) {
                try await operation()
            }
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

    private func prepareRequestConnection(timeoutNanoseconds: UInt64) async throws {
        try await Self.runThrowingWithTimeout(timeoutNanoseconds: timeoutNanoseconds) {
            await actions.prepareRequestConnection()
        }
    }

    private func prepareManageAuthorizationRight(timeoutNanoseconds: UInt64) async throws {
        try await Self.runThrowingWithTimeout(timeoutNanoseconds: timeoutNanoseconds) {
            try await actions.prepareManageAuthorizationRight()
        }
    }

    private static func runThrowingWithTimeout<Value: Sendable>(
        timeoutNanoseconds: UInt64,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            let gate = OneShotThrowingContinuation(continuation)
            let operationTask = Task {
                do {
                    let value = try await operation()
                    gate.resume(returning: value)
                } catch {
                    gate.resume(throwing: error)
                }
            }

            Task {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                if gate.resume(throwing: ChargeControlError.daemonTimedOut) {
                    operationTask.cancel()
                }
            }
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

private final class OneShotThrowingContinuation<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, any Error>?

    init(_ continuation: CheckedContinuation<Value, any Error>) {
        self.continuation = continuation
    }

    @discardableResult
    func resume(returning value: Value) -> Bool {
        let continuation = takeContinuation()
        guard let continuation else {
            return false
        }
        continuation.resume(returning: value)
        return true
    }

    @discardableResult
    func resume(throwing error: any Error) -> Bool {
        let continuation = takeContinuation()
        guard let continuation else {
            return false
        }
        continuation.resume(throwing: error)
        return true
    }

    private func takeContinuation() -> CheckedContinuation<Value, any Error>? {
        lock.withLock {
            let continuation = self.continuation
            self.continuation = nil
            return continuation
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
    func prepareManageAuthorizationRight() async throws
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
        guard Self.supportsPrivilegedDaemonLaunch else {
            return .requiresSignedBuild
        }

        return await ChargeControlClient.DaemonStatus(BTActions.startDaemon())
    }

    func repairDaemonRegistration() async -> ChargeControlClient.DaemonStatus {
        guard #available(macOS 13.0, *) else {
            return .notRegistered
        }
        guard Self.supportsPrivilegedDaemonLaunch else {
            return .requiresSignedBuild
        }

        let appId = Bundle.main.bundleIdentifier ?? "top.xsdev.ChargeWattMenu"
        let daemonId = Bundle.main.object(
            forInfoDictionaryKey: "BT_DAEMON_ID"
        ) as? String ?? "\(appId).daemon"
        let plistName = "\(daemonId).plist"
        let appService = SMAppService.daemon(plistName: plistName)

        let currentStatus = ChargeControlClient.DaemonStatus(
            appService.status
        )
        if currentStatus != .notRegistered {
            return currentStatus
        }

        for _ in 0 ... 5 {
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

    func prepareManageAuthorizationRight() async throws {
        try Self.ensurePrivilegedDaemonLaunchSupported()
        let status = SimpleAuth.duplicateRight(
            rightName: BTAuthorizationRights.manage,
            templateName: kAuthorizationRuleAuthenticateAsAdmin,
            comment: "Used by \(BTPreprocessor.daemonId) to allow access to its privileged functions",
            timeout: 300
        )
        guard status == errSecSuccess else {
            throw ChargeControlError.authorizationSetupFailed
        }
    }

    func currentLimits() async throws -> ChargeLimitSettings {
        try Self.ensurePrivilegedDaemonLaunchSupported()
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
        try Self.ensurePrivilegedDaemonLaunchSupported()
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
        try Self.ensurePrivilegedDaemonLaunchSupported()
        var settings = try await BTActions.getSettings()
        settings[BTSettingsInfo.Keys.minCharge] = NSNumber(value: limits.minCharge)
        settings[BTSettingsInfo.Keys.maxCharge] = NSNumber(value: limits.maxCharge)
        try await BTActions.setSettings(settings: settings)
    }

    func chargeToLimit() async throws {
        try Self.ensurePrivilegedDaemonLaunchSupported()
        try await BTActions.chargeToLimit()
    }

    func chargeToFull() async throws {
        try Self.ensurePrivilegedDaemonLaunchSupported()
        try await BTActions.chargeToFull()
    }

    func disableCharging() async throws {
        try Self.ensurePrivilegedDaemonLaunchSupported()
        try await BTActions.disableCharging()
    }

    func disablePowerAdapter() async throws {
        try Self.ensurePrivilegedDaemonLaunchSupported()
        try await BTActions.disablePowerAdapter()
    }

    func enablePowerAdapter() async throws {
        try Self.ensurePrivilegedDaemonLaunchSupported()
        try await BTActions.enablePowerAdapter()
    }

    func pauseActivity() async throws {
        try Self.ensurePrivilegedDaemonLaunchSupported()
        try await BTActions.pauseActivity()
    }

    func resumeActivity() async throws {
        try Self.ensurePrivilegedDaemonLaunchSupported()
        try await BTActions.resumeActivity()
    }

    func removeDaemon() async throws {
        try await BTActions.removeDaemon()
    }

    private static var supportsPrivilegedDaemonLaunch: Bool {
        let codesignCN = Bundle.main.object(
            forInfoDictionaryKey: "BT_CODESIGN_CN"
        ) as? String
        return codesignCN != "-"
    }

    private static func ensurePrivilegedDaemonLaunchSupported() throws {
        guard supportsPrivilegedDaemonLaunch else {
            throw ChargeControlError.daemonRequiresSignedBuild
        }
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
