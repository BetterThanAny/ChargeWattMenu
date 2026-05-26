import BatteryToolkit
import ChargeWattCore
import Foundation
import ServiceManagement

public enum ChargeControlError: Error, Equatable {
    case daemonNotRegistered
    case daemonRequiresApproval
}

public struct ChargeControlState: Equatable, Sendable {
    public let batteryPercent: Int?
    public let isCharging: Bool?
    public let isACConnected: Bool?
    public let chargingDisabled: Bool?
    public let maxCharge: Int?

    public init(
        batteryPercent: Int?,
        isCharging: Bool?,
        isACConnected: Bool?,
        chargingDisabled: Bool?,
        maxCharge: Int?
    ) {
        self.batteryPercent = batteryPercent
        self.isCharging = isCharging
        self.isACConnected = isACConnected
        self.chargingDisabled = chargingDisabled
        self.maxCharge = maxCharge
    }
}

public enum ChargeLimitApplicationResult: Equatable, Sendable {
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

    public init() {
        self.actions = BatteryToolkitChargeControlActions()
    }

    init(actions: any ChargeControlActions) {
        self.actions = actions
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
        switch await actions.startDaemon() {
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

    public func currentLimits() async throws -> ChargeLimitSettings {
        await actions.prepareRequestConnection()
        return try await actions.currentLimits()
    }

    public func currentState() async throws -> ChargeControlState {
        await actions.prepareRequestConnection()
        return try await actions.currentState()
    }

    public func setLimits(_ limits: ChargeLimitSettings) async throws {
        await actions.prepareRequestConnection()
        try await actions.setLimits(limits)
    }

    public func setLimitsAndApply(
        _ limits: ChargeLimitSettings
    ) async throws -> ChargeLimitApplicationResult {
        await actions.prepareRequestConnection()
        try await actions.setLimits(limits)

        let state = try await actions.currentState()
        guard let batteryPercent = state.batteryPercent else {
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

        return .waitingToDropBelowLowerLimit
    }

    public func chargeToLimit() async throws {
        await actions.prepareRequestConnection()
        try await actions.chargeToLimit()
    }

    public func chargeToFull() async throws {
        await actions.prepareRequestConnection()
        try await actions.chargeToFull()
    }

    public func disableCharging() async throws {
        await actions.prepareRequestConnection()
        try await actions.disableCharging()
    }

    public func disablePowerAdapter() async throws {
        await actions.prepareRequestConnection()
        try await actions.disablePowerAdapter()
    }

    public func enablePowerAdapter() async throws {
        await actions.prepareRequestConnection()
        try await actions.enablePowerAdapter()
    }

    public func pauseActivity() async throws {
        await actions.prepareRequestConnection()
        try await actions.pauseActivity()
    }

    public func resumeActivity() async throws {
        await actions.prepareRequestConnection()
        try await actions.resumeActivity()
    }

    public func removeDaemon() async throws {
        try await actions.removeDaemon()
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
            maxCharge: Self.intValue(state[BTStateInfo.Keys.maxCharge])
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
