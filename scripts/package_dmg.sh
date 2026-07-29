#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_ROOT="${CLEAR_OUTPUT_DIR:-${PROJECT_ROOT}/dist}"
VERSION="${CLEAR_VERSION:-0.1.0}"
DMG_PATH="${OUTPUT_ROOT}/Clear-${VERSION}-universal.dmg"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/clear-dmg.XXXXXX")"

cleanup() {
    rm -rf "${STAGING_DIR}"
}
trap cleanup EXIT

bash "${SCRIPT_DIR}/build_universal_app.sh"

cp -R "${OUTPUT_ROOT}/Clear.app" "${STAGING_DIR}/Clear.app"
ln -s /Applications "${STAGING_DIR}/Applications"

rm -f "${DMG_PATH}"
hdiutil create \
    -volname "Clear ${VERSION}" \
    -srcfolder "${STAGING_DIR}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}"

DMG_NAME="$(basename "${DMG_PATH}")"
(
    cd "${OUTPUT_ROOT}"
    shasum -a 256 "${DMG_NAME}" > "${DMG_NAME}.sha256"
)
echo "Created ${DMG_PATH}"
