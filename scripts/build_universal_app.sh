#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_ROOT="${CLEAR_OUTPUT_DIR:-${PROJECT_ROOT}/dist}"
VERSION="${CLEAR_VERSION:-0.1.0}"
BUILD_NUMBER="${CLEAR_BUILD_NUMBER:-1}"
APP_PATH="${OUTPUT_ROOT}/Clear.app"
ARM_BUILD="${PROJECT_ROOT}/.build/clear-arm64"
INTEL_BUILD="${PROJECT_ROOT}/.build/clear-x86_64"

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Universal macOS builds must run on macOS." >&2
    exit 1
fi

mkdir -p "${OUTPUT_ROOT}"
rm -rf "${APP_PATH}"

swift build \
    --package-path "${PROJECT_ROOT}" \
    --scratch-path "${ARM_BUILD}" \
    --configuration release \
    --arch arm64 \
    --product Clear

swift build \
    --package-path "${PROJECT_ROOT}" \
    --scratch-path "${INTEL_BUILD}" \
    --configuration release \
    --arch x86_64 \
    --product Clear

ARM_BIN_DIR="$(swift build \
    --package-path "${PROJECT_ROOT}" \
    --scratch-path "${ARM_BUILD}" \
    --configuration release \
    --arch arm64 \
    --show-bin-path)"

INTEL_BIN_DIR="$(swift build \
    --package-path "${PROJECT_ROOT}" \
    --scratch-path "${INTEL_BUILD}" \
    --configuration release \
    --arch x86_64 \
    --show-bin-path)"

mkdir -p "${APP_PATH}/Contents/MacOS" "${APP_PATH}/Contents/Resources"
cp "${PROJECT_ROOT}/Support/Info.plist" "${APP_PATH}/Contents/Info.plist"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${APP_PATH}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "${APP_PATH}/Contents/Info.plist"

lipo -create \
    "${ARM_BIN_DIR}/Clear" \
    "${INTEL_BIN_DIR}/Clear" \
    -output "${APP_PATH}/Contents/MacOS/Clear"

chmod 755 "${APP_PATH}/Contents/MacOS/Clear"

# This is an ad-hoc integrity signature. It does not identify the developer and
# does not bypass Gatekeeper.
codesign --force --sign - --options runtime --timestamp=none "${APP_PATH}"
codesign --verify --strict --deep --verbose=2 "${APP_PATH}"

ARCHITECTURES="$(lipo -archs "${APP_PATH}/Contents/MacOS/Clear")"
if [[ "${ARCHITECTURES}" != *"arm64"* || "${ARCHITECTURES}" != *"x86_64"* ]]; then
    echo "Expected arm64 and x86_64, found: ${ARCHITECTURES}" >&2
    exit 1
fi

echo "Built ${APP_PATH} (${ARCHITECTURES})"
