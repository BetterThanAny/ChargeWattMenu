public struct ChargeLimitSettings: Equatable, Sendable {
    public enum ValidationError: Error, Equatable {
        case minChargeBelowMinimum
        case maxChargeBelowMinimum
        case maxChargeAboveMaximum
        case minChargeNotBelowMaxCharge
        case minChargeAboveMaxCharge
    }

    public enum Bounds {
        public static let minChargeMinimum = 20
        public static let maxChargeMinimum = 50
        public static let maxChargeMaximum = 100
    }

    public static let defaults = try! ChargeLimitSettings(
        minCharge: 75,
        maxCharge: 80
    )

    public let minCharge: Int
    public let maxCharge: Int

    public init(minCharge: Int, maxCharge: Int) throws {
        if minCharge < Bounds.minChargeMinimum {
            throw ValidationError.minChargeBelowMinimum
        }

        if maxCharge < Bounds.maxChargeMinimum {
            throw ValidationError.maxChargeBelowMinimum
        }

        if maxCharge > Bounds.maxChargeMaximum {
            throw ValidationError.maxChargeAboveMaximum
        }

        if minCharge == maxCharge {
            throw ValidationError.minChargeNotBelowMaxCharge
        }

        if minCharge > maxCharge {
            throw ValidationError.minChargeAboveMaxCharge
        }

        self.minCharge = minCharge
        self.maxCharge = maxCharge
    }
}
