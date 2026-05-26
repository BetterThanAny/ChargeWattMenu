import Foundation
import Testing
@testable import ChargeWattCore

@Suite
struct BatterySnapshotTests {
    @Test func computesBatteryPowerFromVoltageAndInstantAmperage() {
        let snapshot = BatterySnapshot(properties: [
            "BatteryInstalled": true,
            "ExternalConnected": true,
            "ExternalChargeCapable": true,
            "IsCharging": true,
            "FullyCharged": false,
            "Voltage": 12_071,
            "InstantAmperage": 2_990,
            "CurrentCapacity": 51,
            "MaxCapacity": 100,
            "CycleCount": 39,
            "TimeRemaining": 37,
            "AvgTimeToFull": 37,
            "AvgTimeToEmpty": 65_535,
            "AppleRawMaxCapacity": 4_626,
            "DesignCapacity": 4_629,
            "AdapterDetails": [
                "Watts": 45,
                "AdapterVoltage": 20_000,
                "Current": 2_250
            ]
        ], date: Date(timeIntervalSince1970: 1_779_781_128))

        #expect(abs(snapshot.batteryPowerWatts! - 36.1) < 0.05)
        #expect(snapshot.stateOfChargePercent == 51)
        #expect(snapshot.adapterWatts == 45)
        #expect(abs(snapshot.adapterVoltageVolts! - 20.0) < 0.001)
        #expect(abs(snapshot.adapterCurrentAmps! - 2.25) < 0.001)
        #expect(snapshot.timeToFullMinutes == 37)
        #expect(snapshot.timeToEmptyMinutes == nil)
        #expect(abs(snapshot.batteryHealthPercent! - 99.9) < 0.05)
    }

    @Test func fallsBackToAmperageWhenInstantAmperageIsMissing() {
        let snapshot = BatterySnapshot(properties: [
            "BatteryInstalled": true,
            "ExternalConnected": false,
            "IsCharging": false,
            "Voltage": 11_500,
            "Amperage": -1_200
        ], date: Date(timeIntervalSince1970: 0))

        #expect(abs(snapshot.batteryPowerWatts! - -13.8) < 0.05)
    }

    @Test func convertsBatteryTemperatureFromDeciKelvinToCelsius() {
        let snapshot = BatterySnapshot(properties: [
            "BatteryInstalled": true,
            "Temperature": 3_024
        ], date: Date(timeIntervalSince1970: 0))

        #expect(abs(snapshot.temperatureCelsius! - 29.25) < 0.05)
    }

    @Test func usesTimeRemainingAsFallbackForChargingEstimate() {
        let snapshot = BatterySnapshot(properties: [
            "BatteryInstalled": true,
            "IsCharging": true,
            "TimeRemaining": 42,
            "AvgTimeToFull": 65_535
        ], date: Date(timeIntervalSince1970: 0))

        #expect(snapshot.timeToFullMinutes == 42)
    }

    @Test func usesAverageTimeToEmptyForDischargeEstimate() {
        let snapshot = BatterySnapshot(properties: [
            "BatteryInstalled": true,
            "IsCharging": false,
            "ExternalConnected": false,
            "TimeRemaining": 65_535,
            "AvgTimeToEmpty": 93
        ], date: Date(timeIntervalSince1970: 0))

        #expect(snapshot.timeToEmptyMinutes == 93)
        #expect(snapshot.timeToFullMinutes == nil)
    }

    @Test func ignoresUnavailableTimeSentinelAndInvalidHealthCapacity() {
        let snapshot = BatterySnapshot(properties: [
            "BatteryInstalled": true,
            "TimeRemaining": 65_535,
            "AvgTimeToFull": -1,
            "AvgTimeToEmpty": 65_535,
            "AppleRawMaxCapacity": 4_000,
            "DesignCapacity": 0
        ], date: Date(timeIntervalSince1970: 0))

        #expect(snapshot.timeToFullMinutes == nil)
        #expect(snapshot.timeToEmptyMinutes == nil)
        #expect(snapshot.batteryHealthPercent == nil)
    }

    @Test func unavailableSnapshotWhenBatteryIsNotInstalled() {
        let snapshot = BatterySnapshot(properties: [
            "BatteryInstalled": false
        ], date: Date(timeIntervalSince1970: 0))

        #expect(!snapshot.batteryInstalled)
        #expect(snapshot.batteryPowerWatts == nil)
        #expect(snapshot.stateOfChargePercent == nil)
        #expect(snapshot.timeToFullMinutes == nil)
        #expect(snapshot.batteryHealthPercent == nil)
    }
}
