import Foundation

public struct BatterySnapshot: Equatable, Sendable {
    public let date: Date
    public let batteryInstalled: Bool
    public let externalConnected: Bool
    public let externalChargeCapable: Bool
    public let isCharging: Bool
    public let fullyCharged: Bool
    public let voltageMillivolts: Double?
    public let currentMilliamps: Double?
    public let stateOfChargePercent: Int?
    public let cycleCount: Int?
    public let temperatureCelsius: Double?
    public let timeRemainingMinutes: Int?
    public let avgTimeToFullMinutes: Int?
    public let avgTimeToEmptyMinutes: Int?
    public let rawMaxCapacityMilliampHours: Double?
    public let designCapacityMilliampHours: Double?
    public let adapterWatts: Int?
    public let adapterVoltageMillivolts: Double?
    public let adapterCurrentMilliamps: Double?

    public init(properties: [String: Any], date: Date = Date()) {
        self.date = date
        self.batteryInstalled = BatteryProperty.bool(properties["BatteryInstalled"]) ?? true
        self.externalConnected = BatteryProperty.bool(properties["ExternalConnected"]) ?? false
        self.externalChargeCapable = BatteryProperty.bool(properties["ExternalChargeCapable"]) ?? false
        self.isCharging = BatteryProperty.bool(properties["IsCharging"]) ?? false
        self.fullyCharged = BatteryProperty.bool(properties["FullyCharged"]) ?? false

        if batteryInstalled {
            self.voltageMillivolts = BatteryProperty.double(properties["Voltage"])
            self.currentMilliamps = BatteryProperty.double(properties["InstantAmperage"])
                ?? BatteryProperty.double(properties["Amperage"])
            self.stateOfChargePercent = BatterySnapshot.percent(
                current: BatteryProperty.double(properties["CurrentCapacity"]),
                max: BatteryProperty.double(properties["MaxCapacity"])
            )
            self.cycleCount = BatteryProperty.int(properties["CycleCount"])
            self.temperatureCelsius = BatterySnapshot.celsiusFromDeciKelvin(
                BatteryProperty.double(properties["Temperature"])
            )
            self.timeRemainingMinutes = BatterySnapshot.validMinutes(
                BatteryProperty.int(properties["TimeRemaining"])
            )
            self.avgTimeToFullMinutes = BatterySnapshot.validMinutes(
                BatteryProperty.int(properties["AvgTimeToFull"])
            )
            self.avgTimeToEmptyMinutes = BatterySnapshot.validMinutes(
                BatteryProperty.int(properties["AvgTimeToEmpty"])
            )
            self.rawMaxCapacityMilliampHours = BatteryProperty.double(properties["AppleRawMaxCapacity"])
            self.designCapacityMilliampHours = BatteryProperty.double(properties["DesignCapacity"])
        } else {
            self.voltageMillivolts = nil
            self.currentMilliamps = nil
            self.stateOfChargePercent = nil
            self.cycleCount = nil
            self.temperatureCelsius = nil
            self.timeRemainingMinutes = nil
            self.avgTimeToFullMinutes = nil
            self.avgTimeToEmptyMinutes = nil
            self.rawMaxCapacityMilliampHours = nil
            self.designCapacityMilliampHours = nil
        }

        let adapterDetails = BatteryProperty.dictionary(properties["AdapterDetails"])
        self.adapterWatts = BatteryProperty.int(adapterDetails?["Watts"])
        self.adapterVoltageMillivolts = BatteryProperty.double(adapterDetails?["AdapterVoltage"])
        self.adapterCurrentMilliamps = BatteryProperty.double(adapterDetails?["Current"])
    }

    public static func unavailable(date: Date = Date()) -> BatterySnapshot {
        BatterySnapshot(properties: ["BatteryInstalled": false], date: date)
    }

    public var batteryPowerWatts: Double? {
        guard batteryInstalled,
              let voltageMillivolts,
              let currentMilliamps else {
            return nil
        }
        return voltageMillivolts * currentMilliamps / 1_000_000
    }

    public var batteryVoltageVolts: Double? {
        voltageMillivolts.map { $0 / 1_000 }
    }

    public var batteryCurrentAmps: Double? {
        currentMilliamps.map { $0 / 1_000 }
    }

    public var adapterVoltageVolts: Double? {
        adapterVoltageMillivolts.map { $0 / 1_000 }
    }

    public var adapterCurrentAmps: Double? {
        adapterCurrentMilliamps.map { $0 / 1_000 }
    }

    public var timeToFullMinutes: Int? {
        guard isCharging else {
            return nil
        }
        return avgTimeToFullMinutes ?? timeRemainingMinutes
    }

    public var timeToEmptyMinutes: Int? {
        guard !isCharging, !externalConnected else {
            return nil
        }
        return avgTimeToEmptyMinutes ?? timeRemainingMinutes
    }

    public var batteryHealthPercent: Double? {
        guard let rawMaxCapacityMilliampHours,
              let designCapacityMilliampHours,
              designCapacityMilliampHours > 0 else {
            return nil
        }
        return rawMaxCapacityMilliampHours / designCapacityMilliampHours * 100
    }

    public var stateDescription: String {
        if !batteryInstalled {
            return "not installed"
        }
        if fullyCharged {
            return "full"
        }
        if isCharging {
            return "charging"
        }
        if externalConnected {
            return "on AC"
        }
        return "discharging"
    }

    private static func percent(current: Double?, max: Double?) -> Int? {
        guard let current else {
            return nil
        }
        guard let max, max > 0 else {
            return Int(current.rounded())
        }
        return Int((current / max * 100).rounded())
    }

    private static func celsiusFromDeciKelvin(_ value: Double?) -> Double? {
        guard let value else {
            return nil
        }
        let celsius = value / 10 - 273.15
        guard celsius >= -40, celsius <= 125 else {
            return nil
        }
        return celsius
    }

    private static func validMinutes(_ value: Int?) -> Int? {
        guard let value, value > 0, value < 65_535 else {
            return nil
        }
        return value
    }
}

private enum BatteryProperty {
    static func bool(_ value: Any?) -> Bool? {
        if let value = value as? Bool {
            return value
        }
        if let value = value as? NSNumber {
            return value.boolValue
        }
        return nil
    }

    static func int(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        if let value = value as? String {
            return Int(value)
        }
        return nil
    }

    static func double(_ value: Any?) -> Double? {
        if let value = value as? Double {
            return value
        }
        if let value = value as? Int {
            return Double(value)
        }
        if let value = value as? NSNumber {
            return value.doubleValue
        }
        if let value = value as? String {
            return Double(value)
        }
        return nil
    }

    static func dictionary(_ value: Any?) -> [String: Any]? {
        if let value = value as? [String: Any] {
            return value
        }
        if let value = value as? NSDictionary {
            var dictionary: [String: Any] = [:]
            for (key, entry) in value {
                if let key = key as? String {
                    dictionary[key] = entry
                } else if let key = key as? NSString {
                    dictionary[key as String] = entry
                }
            }
            return dictionary.isEmpty ? nil : dictionary
        }
        return nil
    }
}
