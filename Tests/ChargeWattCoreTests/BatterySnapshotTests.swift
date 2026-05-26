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

    @Test func unavailableSnapshotWhenBatteryIsNotInstalled() {
        let snapshot = BatterySnapshot(properties: [
            "BatteryInstalled": false
        ], date: Date(timeIntervalSince1970: 0))

        #expect(!snapshot.batteryInstalled)
        #expect(snapshot.batteryPowerWatts == nil)
        #expect(snapshot.stateOfChargePercent == nil)
    }
}
