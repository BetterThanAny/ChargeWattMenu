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
        ], date: Date(timeIntervalSince1970: 0))

        #expect(formatter.menuLines(for: snapshot) == [
            "电池侧功率：36.1 W",
            "剩余时间：37 分钟后充满",
            "电池：51%，正在充电",
            "健康度：99.9%（4626 / 4629 mAh）",
            "循环次数：39",
            "电池电压/电流：12.07 V / 2.99 A",
            "适配器档位：45 W（20.0 V / 2.25 A）",
            "温度：29.3°C"
        ])
    }

    @Test func menuLinesShowDischargingTimeToEmpty() {
        let snapshot = BatterySnapshot(properties: [
            "BatteryInstalled": true,
            "ExternalConnected": false,
            "IsCharging": false,
            "Voltage": 11_500,
            "Amperage": -1_200,
            "CurrentCapacity": 66,
            "MaxCapacity": 100,
            "AvgTimeToEmpty": 93
        ], date: Date(timeIntervalSince1970: 0))

        #expect(formatter.menuLines(for: snapshot).contains("剩余时间：1 小时 33 分钟后耗尽"))
    }

    @Test func menuLinesShowUnavailableTimeAndHealthWhenMissing() {
        let snapshot = BatterySnapshot(properties: [
            "BatteryInstalled": true,
            "ExternalConnected": true,
            "IsCharging": false,
            "AdapterDetails": [
                "Watts": 45
            ]
        ], date: Date(timeIntervalSince1970: 0))

        let lines = formatter.menuLines(for: snapshot)
        #expect(lines.contains("剩余时间：不可用"))
        #expect(lines.contains("健康度：不可用"))
    }
}
