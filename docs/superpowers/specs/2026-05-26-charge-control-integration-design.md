# Charge Control Integration Design

Date: 2026-05-26

## Scope

Integrate Battery-Toolkit-SP into ChargeWattMenu for the first control surface only:

- Set lower and upper charge limits.
- Charge to configured limit.
- Charge to full.
- Stop charging immediately.
- Disable and enable the power adapter.
- Pause, resume, and remove the background control daemon.

Out of scope for this pass: fan control, MagSafe indicator control, pmset power-mode tuning, caffeinate sessions, calibration scheduling, and AppIntents.

## Architecture

ChargeWattCore stays independent of Battery-Toolkit-SP and only gains a small ChargeLimitSettings model for validation and tests. ChargeWattMenu depends on BatteryToolkit for UI-triggered daemon actions. A new ChargeWattMenuDaemon executable target depends on BatteryToolkit and starts the privileged daemon with BTDaemon.run().

The packaged app owns both executables. scripts/package-app.sh builds ChargeWattMenu and ChargeWattMenuDaemon, writes BT_* values into the app Info.plist, embeds a LaunchDaemons plist, signs both binaries and the app bundle, and uses debug/ad-hoc signing when no Apple signing identity is available.

## UI Flow

On launch, the menu starts or registers the daemon asynchronously and shows a disabled status line. If macOS requires approval, ChargeWattMenu opens Login Items settings through Battery-Toolkit-SP. Menu commands run in Task blocks and report errors with alerts.

The charge range command opens a two-field modal alert. Values must satisfy Battery Toolkit bounds: lower limit >= 20, upper limit >= 50, upper limit <= 100, and lower limit <= upper limit.

## Verification

Run swift test for validation logic, swift build for compilation, and scripts/package-app.sh for bundle assembly. Runtime daemon approval still requires user interaction in macOS System Settings.
