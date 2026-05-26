import BatteryToolkit
import ChargeWattCore
import Foundation

struct ChargeControlClient: Sendable {
    enum DaemonStatus: Sendable {
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

    func startDaemon() async -> DaemonStatus {
        await DaemonStatus(BTActions.startDaemon())
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
