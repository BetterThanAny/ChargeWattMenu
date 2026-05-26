import BatteryToolkit
import ChargeWattCore
import Foundation

public enum ChargeControlError: Error, Equatable {
    case daemonNotRegistered
    case daemonRequiresApproval
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
        try await actions.currentLimits()
    }

    public func setLimits(_ limits: ChargeLimitSettings) async throws {
        try await actions.setLimits(limits)
    }

    public func chargeToLimit() async throws {
        try await actions.chargeToLimit()
    }

    public func chargeToFull() async throws {
        try await actions.chargeToFull()
    }

    public func disableCharging() async throws {
        try await actions.disableCharging()
    }

    public func disablePowerAdapter() async throws {
        try await actions.disablePowerAdapter()
    }

    public func enablePowerAdapter() async throws {
        try await actions.enablePowerAdapter()
    }

    public func pauseActivity() async throws {
        try await actions.pauseActivity()
    }

    public func resumeActivity() async throws {
        try await actions.resumeActivity()
    }

    public func removeDaemon() async throws {
        try await actions.removeDaemon()
    }
}

protocol ChargeControlActions: Sendable {
    func startDaemon() async -> ChargeControlClient.DaemonStatus
    func approveDaemon(timeout: UInt8) async throws
    func stop() async
    func currentLimits() async throws -> ChargeLimitSettings
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

    func approveDaemon(timeout: UInt8) async throws {
        try await BTActions.approveDaemon(timeout: timeout)
    }

    func stop() async {
        await BTActions.stop()
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
        guard let number = value as? NSNumber else {
            return defaultValue
        }

        return number.intValue
    }
}
