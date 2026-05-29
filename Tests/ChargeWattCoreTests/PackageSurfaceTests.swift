import Foundation
import Testing

@Suite
struct PackageSurfaceTests {
    @Test func packageDoesNotShipChargeControlTargetsOrBatteryToolkitDependency() throws {
        let manifest = try readPackageFile("Package.swift")

        #expect(!manifest.contains("ChargeWattControl"))
        #expect(!manifest.contains("ChargeWattMenuDaemon"))
        #expect(!manifest.contains("Battery-Toolkit-SP"))
        #expect(!manifest.contains("BatteryToolkit"))
    }

    @Test func packagingScriptBuildsDisplayOnlyAppBundle() throws {
        let script = try readPackageFile("scripts/package-app.sh")

        #expect(!script.contains("ChargeWattMenuDaemon"))
        #expect(!script.contains("LaunchDaemons"))
        #expect(!script.contains("BT_ALLOW_ADHOC_CHARGE_CONTROL"))
        #expect(!script.contains("BT_DAEMON"))
    }

    private func readPackageFile(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appending(path: relativePath),
            encoding: .utf8
        )
    }
}
