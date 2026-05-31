#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ChargeWattMenu"
DAEMON_NAME="ChargeWattMenuDaemon"
APP_ID="${BT_APP_ID:-top.xsdev.ChargeWattMenu}"
DAEMON_ID="${BT_DAEMON_ID:-${APP_ID}.daemon}"
DAEMON_CONN="${BT_DAEMON_CONN:-${DAEMON_ID}}"
APP_DISPLAY_NAME="${BT_APP_DISPLAY_NAME:-充电功率}"
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

resolve_codesign_cn() {
    local identity="$1"
    local resolved_cn

    if [[ -n "${BT_CODESIGN_CN:-}" ]]; then
        printf '%s\n' "${BT_CODESIGN_CN}"
        return
    fi

    resolved_cn="$(
        security find-identity -v -p codesigning 2>/dev/null \
            | sed -nE 's/^[[:space:]]*[0-9]+\) ([0-9A-F]{40}) "(Developer ID Application:.*|Apple Development:.*)"$/\1|\2/p' \
            | awk -F'|' -v id="${identity}" '$1 == id || $2 == id { print $2; exit }'
    )"
    if [[ -n "${resolved_cn}" ]]; then
        printf '%s\n' "${resolved_cn}"
        return
    fi

    case "${identity}" in
        "Developer ID Application:"*|"Apple Development:"*)
            printf '%s\n' "${identity}"
            ;;
    esac
}

SIGN_IDENTITY="$(detect_signing_identity)"
if [[ -z "${SIGN_IDENTITY}" || "${SIGN_IDENTITY}" == "-" ]]; then
    if [[ "${BT_ALLOW_ADHOC_CHARGE_CONTROL:-0}" != "1" ]]; then
        echo "No Apple signing identity found." >&2
        echo "Refusing to build charge-control daemon with ad-hoc signing by default." >&2
        echo "For local-only testing, rerun with BT_ALLOW_ADHOC_CHARGE_CONTROL=1." >&2
        exit 2
    fi
    SIGN_IDENTITY="-"
    if [[ -n "${BUILD_CONFIGURATION}" && "${BUILD_CONFIGURATION}" != "debug" ]]; then
        echo "Ad-hoc charge-control builds require debug; using debug instead of ${BUILD_CONFIGURATION}." >&2
    fi
    BUILD_CONFIGURATION="debug"
    CODESIGN_CN="${BT_CODESIGN_CN:--}"
    DAEMON_AUTH_REQUIREMENT="identifier \"${APP_ID}\""
    echo "No Apple signing identity found; building a local-only debug app with ad-hoc signing." >&2
    echo "Do not distribute or install this build for production use." >&2
else
    BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-release}"
    CODESIGN_CN="$(resolve_codesign_cn "${SIGN_IDENTITY}")"
    if [[ -z "${CODESIGN_CN}" ]]; then
        echo "Could not resolve signing certificate common name." >&2
        echo "Set BT_CODESIGN_CN to the exact certificate name shown by:" >&2
        echo "  security find-identity -v -p codesigning" >&2
        exit 2
    fi
    DAEMON_AUTH_REQUIREMENT="identifier \"${APP_ID}\" and anchor apple generic and certificate leaf[subject.CN] = \"${CODESIGN_CN}\" and certificate 1[field.1.2.840.113635.100.6.2.1] /* exists */"
fi

BUILD_DIR="${ROOT_DIR}/.build/${BUILD_CONFIGURATION}"
DEFAULT_OUTPUT_DIR="${TMPDIR:-/tmp}/ChargeWattMenu-build/${BUILD_CONFIGURATION}"
APP_OUTPUT_DIR="${BT_APP_OUTPUT_DIR:-${DEFAULT_OUTPUT_DIR}}"
APP_DIR="${APP_OUTPUT_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
LAUNCH_SERVICES_DIR="${CONTENTS_DIR}/Library/LaunchServices"
LAUNCH_DAEMONS_DIR="${CONTENTS_DIR}/Library/LaunchDaemons"
DAEMON_INFO_PLIST="${APP_OUTPUT_DIR}/${DAEMON_NAME}-Info.plist"

cd "${ROOT_DIR}"
mkdir -p "${APP_OUTPUT_DIR}"

plutil -create xml1 "${DAEMON_INFO_PLIST}"
plutil -insert CFBundleIdentifier -string "${DAEMON_ID}" "${DAEMON_INFO_PLIST}"
plutil -insert CFBundleExecutable -string "${DAEMON_NAME}" "${DAEMON_INFO_PLIST}"
plutil -insert CFBundleName -string "${DAEMON_NAME}" "${DAEMON_INFO_PLIST}"
plutil -insert CFBundlePackageType -string XPC! "${DAEMON_INFO_PLIST}"
plutil -insert BT_APP_ID -string "${APP_ID}" "${DAEMON_INFO_PLIST}"
plutil -insert BT_DAEMON_ID -string "${DAEMON_ID}" "${DAEMON_INFO_PLIST}"
plutil -insert BT_DAEMON_CONN -string "${DAEMON_CONN}" "${DAEMON_INFO_PLIST}"
plutil -insert BT_CODESIGN_CN -string "${CODESIGN_CN}" "${DAEMON_INFO_PLIST}"
plutil -insert LSMachServices -xml "<dict><key>${DAEMON_CONN}</key><true/></dict>" "${DAEMON_INFO_PLIST}"
plutil -insert SMAuthorizedClients -array "${DAEMON_INFO_PLIST}"
plutil -insert SMAuthorizedClients.0 -string "${DAEMON_AUTH_REQUIREMENT}" "${DAEMON_INFO_PLIST}"
plutil -insert SMAssociatedBundleIdentifiers -array "${DAEMON_INFO_PLIST}"
plutil -insert SMAssociatedBundleIdentifiers.0 -string "${APP_ID}" "${DAEMON_INFO_PLIST}"

swift build -c "${BUILD_CONFIGURATION}" --product "${APP_NAME}"
rm -f "${BUILD_DIR}/${DAEMON_NAME}"
swift build -c "${BUILD_CONFIGURATION}" --product "${DAEMON_NAME}" \
    -Xlinker -sectcreate \
    -Xlinker __TEXT \
    -Xlinker __info_plist \
    -Xlinker "${DAEMON_INFO_PLIST}"

rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${LAUNCH_SERVICES_DIR}" "${LAUNCH_DAEMONS_DIR}"
cp "${BUILD_DIR}/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"
cp "${BUILD_DIR}/${DAEMON_NAME}" "${LAUNCH_SERVICES_DIR}/${DAEMON_NAME}"

plutil -create xml1 "${CONTENTS_DIR}/Info.plist"
plutil -insert CFBundleExecutable -string "${APP_NAME}" "${CONTENTS_DIR}/Info.plist"
plutil -insert CFBundleIdentifier -string "${APP_ID}" "${CONTENTS_DIR}/Info.plist"
plutil -insert CFBundleName -string "${APP_NAME}" "${CONTENTS_DIR}/Info.plist"
plutil -insert CFBundleDisplayName -string "${APP_DISPLAY_NAME}" "${CONTENTS_DIR}/Info.plist"
plutil -insert CFBundlePackageType -string APPL "${CONTENTS_DIR}/Info.plist"
plutil -insert CFBundleShortVersionString -string 0.2.2 "${CONTENTS_DIR}/Info.plist"
plutil -insert CFBundleVersion -string 5 "${CONTENTS_DIR}/Info.plist"
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
plutil -insert BundleProgram -string "Contents/Library/LaunchServices/${DAEMON_NAME}" "${PLIST_PATH}"
plutil -insert AssociatedBundleIdentifiers -xml "<array><string>${APP_ID}</string></array>" "${PLIST_PATH}"
plutil -insert EnvironmentVariables -xml "<dict><key>BT_APP_ID</key><string>${APP_ID}</string><key>BT_DAEMON_ID</key><string>${DAEMON_ID}</string><key>BT_DAEMON_CONN</key><string>${DAEMON_CONN}</string><key>BT_CODESIGN_CN</key><string>${CODESIGN_CN}</string></dict>" "${PLIST_PATH}"
plutil -insert MachServices -xml "<dict><key>${DAEMON_CONN}</key><true/></dict>" "${PLIST_PATH}"
plutil -insert RunAtLoad -bool YES "${PLIST_PATH}"
plutil -insert KeepAlive -xml "<dict><key>SuccessfulExit</key><false/></dict>" "${PLIST_PATH}"

codesign_args=(
    --force
    --sign "${SIGN_IDENTITY}"
)
if [[ "${SIGN_IDENTITY}" != "-" ]]; then
    codesign_args+=(--options runtime,hard,kill,restrict,enforcement,library)
fi

xattr -cr "${APP_DIR}"
codesign "${codesign_args[@]}" --identifier "${DAEMON_ID}" "${LAUNCH_SERVICES_DIR}/${DAEMON_NAME}" >/dev/null
codesign "${codesign_args[@]}" --identifier "${APP_ID}" "${MACOS_DIR}/${APP_NAME}" >/dev/null
codesign "${codesign_args[@]}" "${APP_DIR}" >/dev/null
xattr -d com.apple.FinderInfo "${APP_DIR}" 2>/dev/null || true
xattr -d 'com.apple.fileprovider.fpfs#P' "${APP_DIR}" 2>/dev/null || true
codesign --verify --deep --strict --verbose=2 "${APP_DIR}" >/dev/null

echo "Built ${APP_DIR}"
echo "Configuration: ${BUILD_CONFIGURATION}"
echo "Signer: ${SIGN_IDENTITY}"
echo "App ID: ${APP_ID}"
echo "Daemon ID: ${DAEMON_ID}"
