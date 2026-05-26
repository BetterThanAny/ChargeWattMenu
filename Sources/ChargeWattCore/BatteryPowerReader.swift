import Foundation
import IOKit

public final class BatteryPowerReader {
    public init() {}

    public func readSnapshot(date: Date = Date()) -> BatterySnapshot {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard service != 0 else {
            return .unavailable(date: date)
        }
        defer {
            IOObjectRelease(service)
        }

        var rawProperties: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(
            service,
            &rawProperties,
            kCFAllocatorDefault,
            0
        )
        guard result == KERN_SUCCESS,
              let properties = rawProperties?.takeRetainedValue() as? [String: Any] else {
            return .unavailable(date: date)
        }

        return BatterySnapshot(properties: properties, date: date)
    }
}
