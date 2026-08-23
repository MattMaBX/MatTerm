#!/bin/zsh
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
app_path="${1:-$project_root/Build/MatTerm.app}"
output_directory="${2:-$project_root/Artifacts}"

: "${APPLE_CERTIFICATE_P12_BASE64:?APPLE_CERTIFICATE_P12_BASE64 is required}"
: "${APPLE_CERTIFICATE_PASSWORD:?APPLE_CERTIFICATE_PASSWORD is required}"
: "${APPLE_SIGNING_IDENTITY:?APPLE_SIGNING_IDENTITY is required}"
: "${APPLE_ID:?APPLE_ID is required}"
: "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required}"
: "${APPLE_APP_PASSWORD:?APPLE_APP_PASSWORD is required}"

keychain_path="$RUNNER_TEMP/matterm-signing.keychain-db"
certificate_path="$RUNNER_TEMP/matterm-signing.p12"
keychain_password="$(uuidgen)"

printf '%s' "$APPLE_CERTIFICATE_P12_BASE64" | base64 -D > "$certificate_path"
security create-keychain -p "$keychain_password" "$keychain_path"
security set-keychain-settings -lut 21600 "$keychain_path"
security unlock-keychain -p "$keychain_password" "$keychain_path"
security import "$certificate_path" -k "$keychain_path" -P "$APPLE_CERTIFICATE_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
security list-keychains -d user -s "$keychain_path"
security default-keychain -s "$keychain_path"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain_path"

codesign --force --deep --options runtime --timestamp --sign "$APPLE_SIGNING_IDENTITY" "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"

archive_path="$("$project_root/Scripts/package-app.sh" "$app_path" "$output_directory")"
xcrun notarytool submit "$archive_path" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD" --wait
xcrun stapler staple "$app_path"

# Stapling changes the bundle, so replace the pre-staple archive.
archive_path="$("$project_root/Scripts/package-app.sh" "$app_path" "$output_directory")"
print "signed-release: ok archive=$archive_path"
