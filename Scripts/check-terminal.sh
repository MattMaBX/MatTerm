#!/bin/zsh
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
temporary_binary="$(mktemp -t matterm-terminal-check)"
trap 'rm -f "$temporary_binary"' EXIT

swiftc \
    -O \
    "$project_root/Sources/MatTerm/TerminalBuffer.swift" \
    "$project_root/Sources/MatTerm/ANSIProcessor.swift" \
    "$project_root/Scripts/TerminalParserCheck.swift" \
    -o "$temporary_binary"

"$temporary_binary"

pty_binary="$(mktemp -t matterm-pty-check)"
trap 'rm -f "$temporary_binary" "$pty_binary"' EXIT

swiftc \
    "$project_root/Sources/MatTerm/TerminalBuffer.swift" \
    "$project_root/Sources/MatTerm/ANSIProcessor.swift" \
    "$project_root/Scripts/PTYPipelineCheck.swift" \
    -o "$pty_binary"

"$pty_binary"

performance_binary="$(mktemp -t matterm-terminal-performance-check)"
trap 'rm -f "$temporary_binary" "$pty_binary" "$performance_binary"' EXIT

swiftc \
    -O \
    "$project_root/Sources/MatTerm/TerminalBuffer.swift" \
    "$project_root/Scripts/TerminalPerformanceCheck.swift" \
    -o "$performance_binary"

"$performance_binary"

app_pty_binary="$(mktemp -t matterm-app-pty-check)"
trap 'rm -f "$temporary_binary" "$pty_binary" "$performance_binary" "$app_pty_binary"' EXIT

swiftc \
    -O \
    "$project_root/Sources/MatTerm/TerminalBuffer.swift" \
    "$project_root/Sources/MatTerm/ANSIProcessor.swift" \
    "$project_root/Sources/MatTerm/Models.swift" \
    "$project_root/Sources/MatTerm/PTYSession.swift" \
    "$project_root/Scripts/AppPTYCheck.swift" \
    -o "$app_pty_binary"

"$app_pty_binary"
