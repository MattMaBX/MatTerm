import Foundation

enum SessionKind: Hashable {
    case local
    case ssh(SSHProfile)

    var title: String {
        switch self {
        case .local: return "Local Shell"
        case .ssh(let profile): return profile.name
        }
    }

    var iconName: String {
        switch self {
        case .local: return "terminal"
        case .ssh: return "network"
        }
    }
}

enum SessionStatus: Equatable {
    case connecting
    case running
    case exited(Int32)
    case failed(String)
}

@main
enum MultiplexerPTYCheck {
    private struct TmuxPane {
        let id: String
        let left: Int
        let top: Int
        let width: Int
        let height: Int

        func contains(column: Int, row: Int) -> Bool {
            let x = column - 1
            let y = row - 1
            return x >= left && x < left + width && y >= top && y < top + height
        }
    }

    @MainActor
    static func main() async {
        do {
            try await checkTmux()
            try await checkVim()
            try await checkScreen()
            print("multiplexer-pty-check: ok")
        } catch {
            print("::error::multiplexer-pty-check failed: \(error.localizedDescription)")
            exit(1)
        }
    }

    @MainActor
    private static func checkTmux() async throws {
        guard commandExists("tmux") else {
            print("multiplexer-pty-check: tmux unavailable, skipped")
            return
        }

        print("multiplexer-pty-check: tmux startup")
        _ = try? runTmux(["kill-server"])
        let session = TerminalSession(kind: .local)
        defer {
            session.stop()
            _ = try? runTmux(["kill-server"])
        }
        session.resize(columns: 100, rows: 24)
        session.start()
        try await waitUntil(timeoutMilliseconds: 5_000) { session.status == .running }

        session.send("tmux -L matterm-check kill-server >/dev/null 2>&1; tmux -L matterm-check -f /dev/null new-session -A -s matterm-check\r")
        try await waitUntil(timeoutMilliseconds: 10_000) { (try? tmuxPanes().isEmpty) == false }

        print("multiplexer-pty-check: tmux mouse mode")
        _ = try runTmux(["set-option", "-g", "mouse", "on"])
        try await waitUntil(timeoutMilliseconds: 5_000) { session.mouseTracking != .off }
        precondition(session.mouseEncoding == .sgr, "tmux did not negotiate SGR mouse encoding")

        let markerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("matterm-tmux-wheel-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: markerURL) }
        _ = try runTmux([
            "bind-key", "-n", "WheelUpPane", "run-shell",
            "printf '%s' matterm-wheel > \(shellQuote(markerURL.path))"
        ])
        session.sendMouse(kind: .scrollUp, column: 8, row: 5)
        try await waitUntil(timeoutMilliseconds: 5_000) {
            (try? String(contentsOf: markerURL, encoding: .utf8)) == "matterm-wheel"
        }

        session.send("printf 'matterm-tmux-input\\n'\r")
        print("multiplexer-pty-check: tmux input")
        try await waitUntil(timeoutMilliseconds: 5_000) { session.displayText.contains("matterm-tmux-input") }
        assertNoControlResidue(in: session.displayText, context: "tmux startup and input")

        print("multiplexer-pty-check: tmux split")
        _ = try runTmux(["split-window", "-h", "-t", "matterm-check:0"])
        try await waitUntil(timeoutMilliseconds: 5_000) { (try? tmuxPanes().count) == 2 }
        let panes = try tmuxPanes()
        let wheelColumn = 75
        let wheelRow = 5
        guard let expectedPane = panes.first(where: { $0.contains(column: wheelColumn, row: wheelRow) }) else {
            throw NSError(
                domain: "MultiplexerPTYCheck",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "No tmux pane covers the split-wheel test coordinates"]
            )
        }

        try? FileManager.default.removeItem(at: markerURL)
        _ = try runTmux([
            "bind-key", "-n", "WheelUpPane", "run-shell",
            "printf '%s' '#{mouse_pane}:#{mouse_x}:#{mouse_y}' > \(shellQuote(markerURL.path))"
        ])
        session.sendMouse(kind: .scrollUp, column: 75, row: 5)
        print("multiplexer-pty-check: tmux split mouse")
        try await waitUntil(timeoutMilliseconds: 5_000) {
            FileManager.default.fileExists(atPath: markerURL.path)
        }
        let routedPane = try String(contentsOf: markerURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        precondition(
            routedPane.hasPrefix(expectedPane.id + ":"),
            "tmux routed split-wheel to \(routedPane), expected \(expectedPane.id)"
        )

        // Exercise the same clear, home, cursor movement and alternate-screen
        // sequences emitted by full-screen tools inside tmux.
        session.clearDisplay()
        session.send("printf '\\033[2J\\033[Hmatterm-tmux-redraw'; printf '\\033[2Cmatterm-tmux-cursor\\n'\r")
        print("multiplexer-pty-check: tmux redraw")
        try await waitUntil(timeoutMilliseconds: 5_000) { session.displayText.contains("matterm-tmux-cursor") }
        assertNoControlResidue(in: session.displayText, context: "tmux redraw")

        session.clearDisplay()
        session.send("printf '\\033[?1049h\\033[2J\\033[Hmatterm-tmux-alt\\033[?1049l'\r")
        print("multiplexer-pty-check: tmux alternate screen")
        try await waitUntil(timeoutMilliseconds: 5_000) { session.displayText.contains("matterm-tmux-alt") }
        assertNoControlResidue(in: session.displayText, context: "tmux alternate screen")

    }

    @MainActor
    private static func checkScreen() async throws {
        guard commandExists("screen") else {
            print("multiplexer-pty-check: screen unavailable, skipped")
            return
        }

        killScreenSessions()
        let session = TerminalSession(kind: .local)
        defer {
            session.stop()
            killScreenSessions()
        }
        session.resize(columns: 100, rows: 24)
        session.start()
        try await waitUntil(timeoutMilliseconds: 5_000) { session.status == .running }

        _ = try runScreen(["-dmS", "matterm-check", "/bin/zsh", "-l"])
        try await waitUntil(timeoutMilliseconds: 5_000) {
            screenSessionList()?.contains("matterm-check") == true
        }
        session.clearDisplay()
        session.send("screen -D -r matterm-check\r")
        print("multiplexer-pty-check: screen startup")
        try await waitUntil(timeoutMilliseconds: 5_000) {
            screenSessionList()?.contains("matterm-check") == true
        }
        try await waitUntil(timeoutMilliseconds: 10_000) {
            screenSessionList()?.contains("(Attached)") == true
        }
        session.send("printf 'matterm-screen-input\\n'\r")
        try await waitUntil(timeoutMilliseconds: 5_000) { session.displayText.contains("matterm-screen-input") }
        assertNoControlResidue(in: session.displayText, context: "screen input")
    }

    @MainActor
    private static func checkVim() async throws {
        guard commandExists("vim") else {
            print("multiplexer-pty-check: vim unavailable, skipped")
            return
        }

        let session = TerminalSession(kind: .local)
        session.resize(columns: 100, rows: 24)
        session.start()
        defer { session.stop() }
        try await waitUntil(timeoutMilliseconds: 5_000) { session.status == .running }

        let upMapping = shellQuote(
            "nnoremap <ScrollWheelUp> :call setline(1, 'matterm-vim-wheel')<CR>"
        )
        let downMapping = shellQuote(
            "nnoremap <ScrollWheelDown> :call setline(1, 'matterm-vim-wheel')<CR>"
        )
        let vimCommand = "vim -Nu NONE -n -i NONE "
            + "-c " + shellQuote("set mouse=a") + " "
            + "-c " + upMapping + " "
            + "-c " + downMapping + "\r"
        session.send(vimCommand)
        print("multiplexer-pty-check: vim mouse mode")
        try await waitUntil(timeoutMilliseconds: 10_000) {
            session.mouseTracking != .off
        }
        session.sendMouse(kind: .scrollUp, column: 8, row: 5)
        try await waitUntil(timeoutMilliseconds: 5_000) {
            session.displayText.contains("matterm-vim-wheel")
        }
        session.send(":qa!\r")
    }

    private static func commandExists(_ command: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: "/usr/bin/\(command)")
            || FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/\(command)")
            || FileManager.default.isExecutableFile(atPath: "/usr/local/bin/\(command)")
    }

    private static func assertNoControlResidue(in text: String, context: String) {
        let forbidden = [
            "1;2C",
            "2cprintf",
            "\u{1B}",
            "\u{FFFD}"
        ]
        for value in forbidden {
            precondition(!text.contains(value), "\(context) contains visible control residue: \(value)")
        }
    }

    private static func tmuxPanes() throws -> [TmuxPane] {
        let output = try runTmux([
            "list-panes", "-t", "matterm-check:0",
            "-F", "#{pane_id}\t#{pane_left}\t#{pane_top}\t#{pane_width}\t#{pane_height}"
        ])
        return output.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 5,
                  let left = Int(fields[1]),
                  let top = Int(fields[2]),
                  let width = Int(fields[3]),
                  let height = Int(fields[4]) else {
                return nil
            }
            return TmuxPane(id: String(fields[0]), left: left, top: top, width: width, height: height)
        }
    }

    private static func runTmux(_ arguments: [String]) throws -> String {
        try runProcess(executable: "tmux", arguments: ["-L", "matterm-check"] + arguments)
    }

    private static func runScreen(_ arguments: [String]) throws -> String {
        try runProcess(executable: "screen", arguments: arguments)
    }

    private static func screenSessionList() -> String? {
        try? runProcess(executable: "screen", arguments: ["-ls"], allowFailure: true)
    }

    private static func killScreenSessions() {
        guard let listing = screenSessionList() else { return }
        for line in listing.split(whereSeparator: \.isNewline) {
            guard let socket = line.split(whereSeparator: \.isWhitespace).first,
                  socket.hasSuffix(".matterm-check") else {
                continue
            }
            _ = try? runScreen(["-S", String(socket), "-X", "quit"])
        }
        // macOS screen can keep a detached helper alive after -X quit. The
        // session name is test-specific, so terminate only that helper.
        _ = try? runProcess(
            executable: "pkill",
            arguments: ["-f", "SCREEN.*matterm-check"],
            allowFailure: true
        )
    }

    private static func runProcess(
        executable: String,
        arguments: [String],
        allowFailure: Bool = false
    ) throws -> String {
        let candidates = ["/opt/homebrew/bin/\(executable)", "/usr/local/bin/\(executable)", "/usr/bin/\(executable)"]
        guard let executablePath = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) else {
            throw NSError(
                domain: "MultiplexerPTYCheck",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "\(executable) executable was not found"]
            )
        }

        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 || allowFailure else {
            let message = String(
                data: errors.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? "unknown tmux error"
            throw NSError(
                domain: "MultiplexerPTYCheck",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
        return String(
            data: output.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\\"'\\\"'") + "'"
    }

    private static func wait(milliseconds: UInt64) async throws {
        try await Task.sleep(nanoseconds: milliseconds * 1_000_000)
    }

    @MainActor
    private static func waitUntil(
        timeoutMilliseconds: UInt64,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutMilliseconds * 1_000_000
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if condition() { return }
            try await wait(milliseconds: 50)
        }
        guard condition() else {
            throw NSError(domain: "MultiplexerPTYCheck", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Timed out waiting for multiplexer output"
            ])
        }
    }
}
