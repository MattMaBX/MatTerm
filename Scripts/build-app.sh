#!/bin/zsh
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
phase="${MATTERM_BUILD_PHASE:-all}"

if [[ "${MATTERM_SKIP_CHECKS:-0}" != "1" ]]; then
    ./Scripts/check-terminal.sh
    ./Scripts/check-appearance.sh
fi

arm64_scratch="$project_root/.build/arm64-release"
x86_64_scratch="$project_root/.build/x86_64-release"
if [[ "$phase" == "all" || "$phase" == "arm64" ]]; then
    print "build-app: arm64"
    swift build -c release --triple arm64-apple-macosx26.0 --scratch-path "$arm64_scratch"
fi
if [[ "$phase" == "all" || "$phase" == "x86_64" ]]; then
    print "build-app: x86_64"
    swift build -c release --triple x86_64-apple-macosx26.0 --scratch-path "$x86_64_scratch"
fi
if [[ "$phase" == "arm64" || "$phase" == "x86_64" ]]; then
    exit 0
fi

arm64_binary="$arm64_scratch/out/Products/Release/MatTerm"
x86_64_binary="$x86_64_scratch/out/Products/Release/MatTerm"
[[ -x "$arm64_binary" ]] || { print -u2 "missing arm64 build: $arm64_binary"; exit 1; }
[[ -x "$x86_64_binary" ]] || { print -u2 "missing x86_64 build: $x86_64_binary"; exit 1; }
app_path="$project_root/Build/MatTerm.app"

rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
lipo -create "$arm64_binary" "$x86_64_binary" -output "$app_path/Contents/MacOS/MatTerm"
cp "$project_root/Resources/Info.plist" "$app_path/Contents/Info.plist"
swift "$project_root/Scripts/generate-app-icon.swift" "$project_root/Resources/AppIcon.iconset"
iconutil -c icns "$project_root/Resources/AppIcon.iconset" -o "$app_path/Contents/Resources/AppIcon.icns"

codesign --force --deep --sign - "$app_path" >/dev/null
echo "$app_path"
