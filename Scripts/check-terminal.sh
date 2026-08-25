#!/bin/zsh
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
phase="${MATTERM_TERMINAL_PHASE:-all}"
ghostty_headers="$project_root/Vendor/GhosttyVT/ghostty-vt.xcframework/macos-arm64_x86_64/Headers"
ghostty_library="$project_root/Vendor/GhosttyVT/ghostty-vt.xcframework/macos-arm64_x86_64/libghostty-vt.a"

ghostty_swift_flags=(
    -I "$ghostty_headers"
    -L "$project_root/Vendor/GhosttyVT/ghostty-vt.xcframework/macos-arm64_x86_64"
    -Xlinker -force_load
    -Xlinker "$ghostty_library"
)

should_run() {
    [[ "$phase" == "all" || "$phase" == "$1" ]]
}

if should_run ghostty; then
    ghostty_binary="$(mktemp -t matterm-ghostty-vt-check)"
    trap 'rm -f "$ghostty_binary"' EXIT

    swiftc \
        -O \
        "${ghostty_swift_flags[@]}" \
        "$project_root/Sources/MatTerm/GhosttyTerminalTypes.swift" \
        "$project_root/Sources/MatTerm/GhosttyTerminalEngine.swift" \
        "$project_root/Scripts/GhosttyVTCheck.swift" \
        -o "$ghostty_binary"

    "$ghostty_binary"
fi

if should_run app-pty; then
    app_pty_binary="$(mktemp -t matterm-app-pty-check)"
    trap 'rm -f "$app_pty_binary"' EXIT

    swiftc \
        -O \
        "${ghostty_swift_flags[@]}" \
        "$project_root/Sources/MatTerm/GhosttyTerminalTypes.swift" \
        "$project_root/Sources/MatTerm/Models.swift" \
        "$project_root/Sources/MatTerm/GhosttyTerminalEngine.swift" \
        "$project_root/Sources/MatTerm/PTYSession.swift" \
        "$project_root/Scripts/AppPTYCheck.swift" \
        -o "$app_pty_binary"

    "$app_pty_binary"
fi

if should_run multiplexer; then
    multiplexer_binary="$(mktemp -t matterm-multiplexer-check)"
    trap 'rm -f "$multiplexer_binary"' EXIT

    swiftc \
        -O \
        "${ghostty_swift_flags[@]}" \
        "$project_root/Sources/MatTerm/GhosttyTerminalTypes.swift" \
        "$project_root/Sources/MatTerm/Models.swift" \
        "$project_root/Sources/MatTerm/GhosttyTerminalEngine.swift" \
        "$project_root/Sources/MatTerm/PTYSession.swift" \
        "$project_root/Scripts/MultiplexerPTYCheck.swift" \
        -o "$multiplexer_binary"

    "$multiplexer_binary"
fi
