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
enum AppPTYCheck {
    @MainActor
    static func main() async {
        do {
            try await run()
        } catch {
            let message = "app-pty-check failed: \(error.localizedDescription)"
            print("::error::\(message)")
            fputs(message + "\n", stderr)
            exit(1)
        }
    }

    @MainActor
    private static func run() async throws {
        let session = TerminalSession(kind: .local)
        session.resize(columns: 100, rows: 24)
        session.start()

        try await waitUntil(timeoutMilliseconds: 5_000) {
            session.status == .running
        }
        session.send("pwd\r")
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
        try await waitUntil(timeoutMilliseconds: 5_000) {
            session.displayText.contains(homeDirectory)
        }
        session.send("cd /tmp\r")
        try await waitUntil(timeoutMilliseconds: 5_000) {
            session.workingDirectory == "/private/tmp" || session.workingDirectory == "/tmp"
        }
        guard session.title == session.workingDirectory else {
            throw failure("Local tab title did not follow working directory: \(session.title) / \(session.workingDirectory)")
        }
        guard !session.displayText.hasPrefix("\n") else {
            throw failure("Local terminal transcript starts with an unexpected empty line: \(session.displayText)")
        }

        session.send("printf 'matterm-input-你好\\n'\r")
        try await waitUntil(timeoutMilliseconds: 5_000) {
            session.displayText.contains("matterm-input-你好")
        }

        // Mouse protocols can overlap while tmux/screen switch modes. Turning
        // off 1002 must not disable 1000 while it is still active.
        session.send("printf '\\033[?1000h\\033[?1002h\\033[?1002l'\r")
        try await waitUntil(timeoutMilliseconds: 5_000) {
            session.mouseTracking == .normal
        }
        session.send("printf '\\033[?1000l'\r")
        try await waitUntil(timeoutMilliseconds: 5_000) {
            session.mouseTracking == .off
        }

        // Mouse encodings are independent DEC modes. Disabling SGR must
        // restore an active UTF-8 encoding instead of silently falling back
        // to legacy X10 bytes.
        session.send("printf '\\033[?1005h\\033[?1006h'\r")
        try await waitUntil(timeoutMilliseconds: 5_000) {
            session.mouseEncoding == .sgr
        }
        session.send("printf '\\033[?1006l'\r")
        try await waitUntil(timeoutMilliseconds: 5_000) {
            session.mouseEncoding == .utf8
        }
        session.send("printf '\\033[?1005l'\r")
        try await waitUntil(timeoutMilliseconds: 5_000) {
            session.mouseEncoding == .x10
        }

        session.resize(columns: 77, rows: 41)
        session.send("stty size\r")
        try await waitUntil(timeoutMilliseconds: 5_000) {
            session.displayText.contains("41 77")
        }

        session.send("sleep 5\r")
        try await wait(milliseconds: 250)
        session.send("\u{03}")
        session.send("printf 'matterm-control-c-ok\\n'\r")
        try await waitUntil(timeoutMilliseconds: 5_000) {
            session.displayText.contains("matterm-control-c-ok")
        }

        session.stop()
        print("app-pty-check: ok")
    }

    private static func wait(milliseconds: UInt64) async throws {
        try await Task.sleep(nanoseconds: milliseconds * 1_000_000)
    }

    @MainActor
    private static func waitUntil(
        timeoutMilliseconds: UInt64,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds
            + timeoutMilliseconds * 1_000_000
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if condition() { return }
            try await wait(milliseconds: 50)
        }
        guard condition() else {
            throw failure("Timed out waiting for terminal output: \(condition())")
        }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "AppPTYCheck", code: 1, userInfo: [
            NSLocalizedDescriptionKey: message
        ])
    }
}
