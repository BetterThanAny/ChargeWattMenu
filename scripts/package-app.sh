#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ChargeWattMenu"
DAEMON_NAME="ChargeWattMenuDaemon"
APP_ID="top.xsdev.ChargeWattMenu"
DAEMON_ID="${APP_ID}.daemon"
DAEMON_CONN="${DAEMON_ID}"
APP_DISPLAY_NAME="充电功率"
BUILD_CONFIGURATION="${BT_BUILD_CONFIGURATION:-}"

detect_signing_identity() {
    if [[ -n "${BT_SIGN_IDENTITY:-}" ]]; then
        printf '%s\n' "${BT_SIGN_IDENTITY}"
        return
    fi

    security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p; s/.*"\(Apple Development:.*\)"/\1/p' \
        | head -n 1
}

SIGN_IDENTITY="$(detect_signing_identity)"
if [[ -z "${SIGN_IDENTITY}" ]]; then
    SIGN_IDENTITY="-"
    BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-debug}"
    CODESIGN_CN="${BT_CODESIGN_CN:--}"
    echo "No Apple signing identity found; building a debug app with ad-hoc signing." >&2
    echo "Battery control is intended for local testing in this mode." >&2
else
    BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-release}"
    CODESIGN_CN="${BT_CODESIGN_CN:-${SIGN_IDENTITY}}"
fi

BUILD_DIR="${ROOT_DIR}/.build/${BUILD_CONFIGURATION}"
DEFAULT_OUTPUT_DIR="${TMPDIR:-/tmp}/ChargeWattMenu-build/${BUILD_CONFIGURATION}"
APP_OUTPUT_DIR="${BT_APP_OUTPUT_DIR:-${DEFAULT_OUTPUT_DIR}}"
APP_DIR="${APP_OUTPUT_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
LAUNCH_DAEMONS_DIR="${CONTENTS_DIR}/Library/LaunchDaemons"

cd "${ROOT_DIR}"
swift build -c "${BUILD_CONFIGURATION}" --product "${APP_NAME}"
swift build -c "${BUILD_CONFIGURATION}" --product "${DAEMON_NAME}"

rm -rf "${APP_DIR}"
mkdir -p "${APP_OUTPUT_DIR}"
mkdir -p "${MACOS_DIR}" "${LAUNCH_DAEMONS_DIR}"
cp "${BUILD_DIR}/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"
cp "${BUILD_DIR}/${DAEMON_NAME}" "${MACOS_DIR}/${DAEMON_NAME}"

plutil -create xml1 "${CONTENTS_DIR}/Info.plist"
plutil -insert CFBundleExecutable -string "${APP_NAME}" "${CONTENTS_DIR}/Info.plist"
plutil -insert CFBundleIdentifier -string "${APP_ID}" "${CONTENTS_DIR}/Info.plist"
plutil -insert CFBundleName -string "${APP_NAME}" "${CONTENTS_DIR}/Info.plist"
plutil -insert CFBundleDisplayName -string "${APP_DISPLAY_NAME}" "${CONTENTS_DIR}/Info.plist"
plutil -insert CFBundlePackageType -string APPL "${CONTENTS_DIR}/Info.plist"
plutil -insert CFBundleShortVersionString -string 0.2.0 "${CONTENTS_DIR}/Info.plist"
plutil -insert CFBundleVersion -string 2 "${CONTENTS_DIR}/Info.plist"
plutil -insert LSMinimumSystemVersion -string 13.0 "${CONTENTS_DIR}/Info.plist"
plutil -insert LSUIElement -bool YES "${CONTENTS_DIR}/Info.plist"
plutil -insert NSHighResolutionCapable -bool YES "${CONTENTS_DIR}/Info.plist"
plutil -insert BT_APP_ID -string "${APP_ID}" "${CONTENTS_DIR}/Info.plist"
plutil -insert BT_DAEMON_ID -string "${DAEMON_ID}" "${CONTENTS_DIR}/Info.plist"
plutil -insert BT_DAEMON_CONN -string "${DAEMON_CONN}" "${CONTENTS_DIR}/Info.plist"
plutil -insert BT_CODESIGN_CN -string "${CODESIGN_CN}" "${CONTENTS_DIR}/Info.plist"

PLIST_PATH="${LAUNCH_DAEMONS_DIR}/${DAEMON_ID}.plist"
plutil -create xml1 "${PLIST_PATH}"
plutil -insert Label -string "${DAEMON_ID}" "${PLIST_PATH}"
plutil -insert BundleProgram -string "Contents/MacOS/${DAEMON_NAME}" "${PLIST_PATH}"
plutil -insert AssociatedBundleIdentifiers -xml "<array><string>${APP_ID}</string></array>" "${PLIST_PATH}"
plutil -insert MachServices -xml "<dict><key>${DAEMON_CONN}</key><true/></dict>" "${PLIST_PATH}"
plutil -insert RunAtLoad -bool YES "${PLIST_PATH}"
plutil -insert KeepAlive -bool NO "${PLIST_PATH}"

codesign_args=(
    --force
    --sign "${SIGN_IDENTITY}"
)
if [[ "${SIGN_IDENTITY}" != "-" ]]; then
    codesign_args+=(--options runtime)
fi

xattr -cr "${APP_DIR}"
codesign "${codesign_args[@]}" --identifier "${DAEMON_ID}" "${MACOS_DIR}/${DAEMON_NAME}" >/dev/null
xattr -cr "${APP_DIR}"
codesign "${codesign_args[@]}" --identifier "${APP_ID}" "${MACOS_DIR}/${APP_NAME}" >/dev/null
xattr -cr "${APP_DIR}"
codesign "${codesign_args[@]}" "${APP_DIR}" >/dev/null
xattr -d com.apple.FinderInfo "${APP_DIR}" 2>/dev/null || true
xattr -d 'com.apple.fileprovider.fpfs#P' "${APP_DIR}" 2>/dev/null || true
codesign --verify --deep --strict --verbose=2 "${APP_DIR}" >/dev/null

echo "Built ${APP_DIR}"
echo "Configuration: ${BUILD_CONFIGURATION}"
echo "Signer: ${SIGN_IDENTITY}"
echo "App ID: ${APP_ID}"
echo "Daemon ID: ${DAEMON_ID}"
