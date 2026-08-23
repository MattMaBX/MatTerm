#!/bin/zsh
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
app_path="${1:-$project_root/Build/MatTerm.app}"
binary_path="$app_path/Contents/MacOS/MatTerm"
plist_path="$app_path/Contents/Info.plist"
icon_path="$app_path/Contents/Resources/AppIcon.icns"

[[ -d "$app_path" ]] || { print -u2 "missing app: $app_path"; exit 1; }
[[ -x "$binary_path" ]] || { print -u2 "missing executable: $binary_path"; exit 1; }
[[ -f "$plist_path" ]] || { print -u2 "missing Info.plist"; exit 1; }
[[ -f "$icon_path" ]] || { print -u2 "missing AppIcon.icns"; exit 1; }

[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist_path")" == "com.matterm.app" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist_path")" == "MatTerm" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$plist_path")" == "26.0" ]]

architectures="$(lipo -archs "$binary_path")"
[[ "$architectures" == *arm64* ]] || { print -u2 "arm64 slice missing: $architectures"; exit 1; }
[[ "$architectures" == *x86_64* ]] || { print -u2 "x86_64 slice missing: $architectures"; exit 1; }
codesign --verify --deep --strict "$app_path"

print "app-validation: ok architectures=$architectures bundle_id=com.matterm.app minimum_macos=26.0"
