import Foundation
import Testing
@testable import ChargeWattCore

@Suite
struct PowerFormatterTests {
    private let formatter = PowerFormatter()

    @Test func statusTitleShowsChargingWatts() {
        let snapshot = BatterySnapshot(properties: [
            "BatteryInstalled": true,
            "ExternalConnected": true,
            "IsCharging": true,
            "Voltage": 12_071,
            "InstantAmperage": 2_990
        ], date: Date(timeIntervalSince1970: 0))

        #expect(formatter.statusTitle(for: snapshot) == "36.1W")
    }

    @Test func statusTitleShowsDischargingWattsWithMinusSign() {
        let snapshot = BatterySnapshot(properties: [
            "BatteryInstalled": true,
            "ExternalConnected": false,
            "IsCharging": false,
            "Voltage": 11_500,
            "Amperage": -1_200
        ], date: Date(timeIntervalSince1970: 0))

        #expect(formatter.statusTitle(for: snapshot) == "-13.8W")
    }

    @Test func statusTitleShowsAdapterInChineseWhenConnectedButNoCurrentIsAvailable() {
        let snapshot = BatterySnapshot(properties: [
            "BatteryInstalled": true,
            "ExternalConnected": true,
            "IsCharging": false,
            "AdapterDetails": [
                "Watts": 45
            ]
        ], date: Date(timeIntervalSince1970: 0))

        #expect(formatter.statusTitle(for: snapshot) == "接电45W")
    }

    @Test func menuLinesContainReadableChineseDetails() {
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
            "Temperature": 3_024,
            "AdapterDetails": [
                "Watts": 45,
                "AdapterVoltage": 20_000,
                "Current": 2_250
            ]
        ], date: Date(timeIntervalSince1970: 0))

        #expect(formatter.menuLines(for: snapshot) == [
            "电池侧功率：36.1 W",
            "适配器档位：45 W（20.0 V / 2.25 A）",
            "电池：51%，正在充电",
            "电池电压/电流：12.07 V / 2.99 A",
            "温度：29.3°C",
            "循环次数：39"
        ])
    }
}
