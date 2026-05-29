#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ChargeWattMenu"
APP_ID="top.xsdev.ChargeWattMenu"
APP_DISPLAY_NAME="充电功率"
BUILD_CONFIGURATION="${BT_BUILD_CONFIGURATION:-release}"

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
    SIGNER_LABEL="ad-hoc"
    echo "No Apple signing identity found; using ad-hoc signing." >&2
else
    SIGNER_LABEL="Apple signing identity"
fi

BUILD_DIR="${ROOT_DIR}/.build/${BUILD_CONFIGURATION}"
DEFAULT_OUTPUT_DIR="${TMPDIR:-/tmp}/ChargeWattMenu-build/${BUILD_CONFIGURATION}"
APP_OUTPUT_DIR="${BT_APP_OUTPUT_DIR:-${DEFAULT_OUTPUT_DIR}}"
APP_DIR="${APP_OUTPUT_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"

cd "${ROOT_DIR}"
mkdir -p "${APP_OUTPUT_DIR}"

swift build -c "${BUILD_CONFIGURATION}" --product "${APP_NAME}"

rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}"
cp "${BUILD_DIR}/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"

plutil -create xml1 "${CONTENTS_DIR}/Info.plist"
plutil -insert CFBundleExecutable -string "${APP_NAME}" "${CONTENTS_DIR}/Info.plist"
plutil -insert CFBundleIdentifier -string "${APP_ID}" "${CONTENTS_DIR}/Info.plist"
plutil -insert CFBundleName -string "${APP_NAME}" "${CONTENTS_DIR}/Info.plist"
plutil -insert CFBundleDisplayName -string "${APP_DISPLAY_NAME}" "${CONTENTS_DIR}/Info.plist"
plutil -insert CFBundlePackageType -string APPL "${CONTENTS_DIR}/Info.plist"
plutil -insert CFBundleShortVersionString -string 0.3.0 "${CONTENTS_DIR}/Info.plist"
plutil -insert CFBundleVersion -string 6 "${CONTENTS_DIR}/Info.plist"
plutil -insert LSMinimumSystemVersion -string 13.0 "${CONTENTS_DIR}/Info.plist"
plutil -insert LSUIElement -bool YES "${CONTENTS_DIR}/Info.plist"
plutil -insert NSHighResolutionCapable -bool YES "${CONTENTS_DIR}/Info.plist"

codesign_args=(
    --force
    --sign "${SIGN_IDENTITY}"
)
if [[ "${SIGN_IDENTITY}" != "-" ]]; then
    codesign_args+=(--options runtime)
fi

xattr -cr "${APP_DIR}"
codesign "${codesign_args[@]}" --identifier "${APP_ID}" "${MACOS_DIR}/${APP_NAME}" >/dev/null
codesign "${codesign_args[@]}" "${APP_DIR}" >/dev/null
xattr -d com.apple.FinderInfo "${APP_DIR}" 2>/dev/null || true
xattr -d 'com.apple.fileprovider.fpfs#P' "${APP_DIR}" 2>/dev/null || true
codesign --verify --deep --strict --verbose=2 "${APP_DIR}" >/dev/null

echo "Built ${APP_DIR}"
echo "Configuration: ${BUILD_CONFIGURATION}"
echo "Signer: ${SIGNER_LABEL}"
echo "App ID: ${APP_ID}"
