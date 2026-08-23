#!/bin/zsh
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
app_path="${1:-$project_root/Build/MatTerm.app}"
output_directory="${2:-$project_root/Artifacts}"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")"
archive_path="$output_directory/MatTerm-$version-macos26-universal.zip"

mkdir -p "$output_directory"
rm -f "$archive_path"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$archive_path"
print "$archive_path"
