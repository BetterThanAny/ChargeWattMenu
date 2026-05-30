import Foundation
import Testing

@Suite
struct PersonalControlBuildSurfaceTests {
    @Test func packagingScriptAllowsUserOwnedBundleIdentifiers() throws {
        let script = try readPackageFile("scripts/package-app.sh")

        #expect(script.contains("APP_ID=\"${BT_APP_ID:-top.xsdev.ChargeWattMenu}\""))
        #expect(script.contains("DAEMON_ID=\"${BT_DAEMON_ID:-${APP_ID}.daemon}\""))
        #expect(script.contains("DAEMON_CONN=\"${BT_DAEMON_CONN:-${DAEMON_ID}}\""))
        #expect(script.contains("APP_DISPLAY_NAME=\"${BT_APP_DISPLAY_NAME:-充电功率}\""))
    }

    @Test func packagingScriptResolvesCertificateCommonNameForDaemonAuthorization() throws {
        let script = try readPackageFile("scripts/package-app.sh")

        #expect(script.contains("resolve_codesign_cn()"))
        #expect(script.contains("BT_CODESIGN_CN"))
        #expect(script.contains("Could not resolve signing certificate common name."))
        #expect(script.contains("security find-identity -v -p codesigning"))
    }

    @Test func runtimeDaemonFallbackFollowsBundleIdentifier() throws {
        let source = try readPackageFile(
            "Sources/ChargeWattControl/ChargeControlClient.swift"
        )

        #expect(source.contains("Bundle.main.bundleIdentifier"))
        #expect(source.contains("\"\\(appId).daemon\""))
    }

    @Test func readmeDocumentsSelfSignedChargeControlBuilds() throws {
        let readme = try readPackageFile("README.md")

        #expect(readme.contains("charge-control-local"))
        #expect(readme.contains("BT_APP_ID=\"com.example.ChargeWattMenu\""))
        #expect(readme.contains("BT_SIGN_IDENTITY"))
        #expect(readme.contains("BT_CODESIGN_CN"))
        #expect(readme.contains("只运行自己从源码构建并用自己证书签名的版本"))
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
