import Testing
@testable import ChargeWattCore

@Suite
struct ChargeLimitSettingsTests {
    @Test func acceptsValidBatteryToolkitChargeWindow() throws {
        let settings = try ChargeLimitSettings(minCharge: 75, maxCharge: 80)

        #expect(settings.minCharge == 75)
        #expect(settings.maxCharge == 80)
    }

    @Test func rejectsLowerLimitBelowBatteryToolkitMinimum() {
        #expect(throws: ChargeLimitSettings.ValidationError.minChargeBelowMinimum) {
            try ChargeLimitSettings(minCharge: 19, maxCharge: 80)
        }
    }

    @Test func rejectsUpperLimitBelowBatteryToolkitMinimum() {
        #expect(throws: ChargeLimitSettings.ValidationError.maxChargeBelowMinimum) {
            try ChargeLimitSettings(minCharge: 20, maxCharge: 49)
        }
    }

    @Test func rejectsUpperLimitAboveOneHundredPercent() {
        #expect(throws: ChargeLimitSettings.ValidationError.maxChargeAboveMaximum) {
            try ChargeLimitSettings(minCharge: 20, maxCharge: 101)
        }
    }

    @Test func rejectsLowerLimitAboveUpperLimit() {
        #expect(throws: ChargeLimitSettings.ValidationError.minChargeAboveMaxCharge) {
            try ChargeLimitSettings(minCharge: 81, maxCharge: 80)
        }
    }
}
