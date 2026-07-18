#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIGNING_MODE="${SIGNING_MODE:-adhoc}"
OUTPUT_DIR="${OUTPUT_DIR:-${ROOT_DIR}/dist}"
WORK_DIR="${OUTPUT_DIR}/.work"
DERIVED_DATA="${WORK_DIR}/DerivedData"
ENTITLEMENTS="${ROOT_DIR}/OpenVibeBoard/OpenVibeBoard.entitlements"
EXPECTED_BUNDLE_ID="com.ethereal49.OpenVibeBoard"

fail() {
    echo "error: $*" >&2
    exit 1
}

require_env() {
    local name="$1"
    [[ -n "${!name:-}" ]] || fail "${name} is required for SIGNING_MODE=developer-id"
}

case "${SIGNING_MODE}" in
    adhoc)
        SIGN_IDENTITY="-"
        ARTIFACT_SUFFIX="adhoc-unnotarized"
        ;;
    developer-id)
        require_env DEVELOPER_ID_APPLICATION
        require_env NOTARYTOOL_PROFILE
        SIGN_IDENTITY="${DEVELOPER_ID_APPLICATION}"
        ARTIFACT_SUFFIX="signed-notarized"
        security find-identity -v -p codesigning | grep -F "${SIGN_IDENTITY}" >/dev/null \
            || fail "Developer ID identity is not available in the current keychain"
        ;;
    *)
        fail "SIGNING_MODE must be 'adhoc' or 'developer-id'"
        ;;
esac

command -v xcodegen >/dev/null || fail "xcodegen is required"
command -v xcodebuild >/dev/null || fail "xcodebuild is required"

mkdir -p "${OUTPUT_DIR}"
rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}"

cd "${ROOT_DIR}"
xcodegen generate
xcodebuild \
    -project OpenVibeBoard.xcodeproj \
    -scheme OpenVibeBoard \
    -configuration Release \
    -destination "platform=macOS" \
    -derivedDataPath "${DERIVED_DATA}" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    build

APP_PATH="${DERIVED_DATA}/Build/Products/Release/OpenVibeBoard.app"
[[ -d "${APP_PATH}/Contents/MacOS" ]] || fail "Release app bundle was not produced"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP_PATH}/Contents/Info.plist")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${APP_PATH}/Contents/Info.plist")"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${APP_PATH}/Contents/Info.plist")"
[[ "${BUNDLE_ID}" == "${EXPECTED_BUNDLE_ID}" ]] || fail "unexpected bundle identifier: ${BUNDLE_ID}"
[[ -x "${APP_PATH}/Contents/MacOS/OpenVibeBoard" ]] || fail "main executable is missing"

if [[ "${SIGNING_MODE}" == "developer-id" ]]; then
    while IFS= read -r nested; do
        codesign --force --options runtime --timestamp --sign "${SIGN_IDENTITY}" "${nested}"
    done < <(find "${APP_PATH}/Contents" -type f -perm -111 ! -path "*/MacOS/OpenVibeBoard" -print)

    codesign \
        --force \
        --options runtime \
        --timestamp \
        --entitlements "${ENTITLEMENTS}" \
        --sign "${SIGN_IDENTITY}" \
        "${APP_PATH}"
else
    codesign \
        --force \
        --entitlements "${ENTITLEMENTS}" \
        --sign - \
        "${APP_PATH}"
fi

codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
codesign -dvvv --entitlements - "${APP_PATH}"

ARCHIVE_NAME="OpenVibeBoard-${VERSION}-macos-${ARTIFACT_SUFFIX}.zip"
ARCHIVE_PATH="${OUTPUT_DIR}/${ARCHIVE_NAME}"
CHECKSUM_PATH="${ARCHIVE_PATH}.sha256"
rm -f "${ARCHIVE_PATH}" "${CHECKSUM_PATH}"
ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ARCHIVE_PATH}"

if [[ "${SIGNING_MODE}" == "developer-id" ]]; then
    xcrun notarytool submit "${ARCHIVE_PATH}" --keychain-profile "${NOTARYTOOL_PROFILE}" --wait
    xcrun stapler staple "${APP_PATH}"
    xcrun stapler validate "${APP_PATH}"
    spctl --assess --type execute --verbose=4 "${APP_PATH}"

    rm -f "${ARCHIVE_PATH}"
    ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ARCHIVE_PATH}"
    TRUST_STATUS="Developer ID signed, notarized, stapled, Gatekeeper accepted"
else
    if spctl --assess --type execute --verbose=4 "${APP_PATH}"; then
        fail "ad-hoc test artifact was unexpectedly accepted by Gatekeeper"
    fi
    TRUST_STATUS="ad-hoc signed, unnotarized, Gatekeeper rejected (expected)"
fi

cd "${OUTPUT_DIR}"
shasum -a 256 "${ARCHIVE_NAME}" > "$(basename "${CHECKSUM_PATH}")"
shasum -a 256 -c "$(basename "${CHECKSUM_PATH}")"

echo "version=${VERSION} (${BUILD_NUMBER})"
echo "commit=$(git -C "${ROOT_DIR}" rev-parse HEAD)"
echo "trust=${TRUST_STATUS}"
echo "artifact=${ARCHIVE_PATH}"
echo "checksum=${CHECKSUM_PATH}"
