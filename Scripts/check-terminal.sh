#!/bin/zsh
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
phase="${MATTERM_TERMINAL_PHASE:-all}"

should_run() {
    [[ "$phase" == "all" || "$phase" == "$1" ]]
}

if should_run parser; then
    temporary_binary="$(mktemp -t matterm-terminal-check)"
    trap 'rm -f "$temporary_binary"' EXIT

    swiftc \
        -O \
        "$project_root/Sources/MatTerm/TerminalBuffer.swift" \
        "$project_root/Sources/MatTerm/ANSIProcessor.swift" \
        "$project_root/Scripts/TerminalParserCheck.swift" \
        -o "$temporary_binary"

    "$temporary_binary"
fi

if should_run pty; then
    pty_binary="$(mktemp -t matterm-pty-check)"
    trap 'rm -f "$pty_binary"' EXIT

    swiftc \
        "$project_root/Sources/MatTerm/TerminalBuffer.swift" \
        "$project_root/Sources/MatTerm/ANSIProcessor.swift" \
        "$project_root/Scripts/PTYPipelineCheck.swift" \
        -o "$pty_binary"

    "$pty_binary"
fi

if should_run performance; then
    performance_binary="$(mktemp -t matterm-terminal-performance-check)"
    trap 'rm -f "$performance_binary"' EXIT

    swiftc \
        -O \
        "$project_root/Sources/MatTerm/TerminalBuffer.swift" \
        "$project_root/Scripts/TerminalPerformanceCheck.swift" \
        -o "$performance_binary"

    "$performance_binary"
fi

if should_run app-pty; then
    app_pty_binary="$(mktemp -t matterm-app-pty-check)"
    trap 'rm -f "$app_pty_binary"' EXIT

    swiftc \
        -O \
        "$project_root/Sources/MatTerm/TerminalBuffer.swift" \
        "$project_root/Sources/MatTerm/ANSIProcessor.swift" \
        "$project_root/Sources/MatTerm/Models.swift" \
        "$project_root/Sources/MatTerm/PTYSession.swift" \
        "$project_root/Scripts/AppPTYCheck.swift" \
        -o "$app_pty_binary"

    "$app_pty_binary"
fi
