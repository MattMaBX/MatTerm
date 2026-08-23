import Darwin
import Foundation

@main
enum PTYPipelineCheck {
    static func main() throws {
        var master: Int32 = -1
        var size = winsize(ws_row: 24, ws_col: 100, ws_xpixel: 0, ws_ypixel: 0)
        let child = forkpty(&master, nil, nil, &size)
        guard child >= 0 else {
            throw NSError(domain: "PTYPipelineCheck", code: Int(errno), userInfo: [
                NSLocalizedDescriptionKey: String(cString: strerror(errno))
            ])
        }

        if child == 0 {
            setenv("TERM", "xterm-256color", 1)
            setenv("COLORTERM", "truecolor", 1)
            setenv("LC_ALL", "en_US.UTF-8", 1)
            var arguments: [UnsafeMutablePointer<CChar>?] = [
                strdup("zsh"),
                strdup("-f"),
                nil
            ]
            arguments.withUnsafeMutableBufferPointer { buffer in
                _ = execv("/bin/zsh", buffer.baseAddress!)
            }
            _exit(127)
        }

        defer {
            close(master)
            kill(child, SIGHUP)
            var status: Int32 = 0
            waitpid(child, &status, 0)
        }

        _ = fcntl(master, F_SETFL, O_NONBLOCK)
        let initialTranscript = readFor(milliseconds: 700, from: master)
        let command = Data("echo ".utf8) + Data([0xE4, 0xBD, 0xA0, 0xE5, 0xA5, 0xBD, 0x0D])
        try write(command, to: master)
        let transcript = readFor(milliseconds: 900, from: master)

        try write(Data("stty size\r".utf8), to: master)
        let initialSizeTranscript = readFor(milliseconds: 700, from: master)

        var resized = winsize(ws_row: 41, ws_col: 77, ws_xpixel: 0, ws_ypixel: 0)
        guard ioctl(master, TIOCSWINSZ, &resized) == 0 else {
            throw NSError(domain: "PTYPipelineCheck", code: Int(errno), userInfo: [
                NSLocalizedDescriptionKey: "Unable to resize PTY: \(String(cString: strerror(errno)))"
            ])
        }
        try write(Data("stty size\r".utf8), to: master)
        let resizedTranscript = readFor(milliseconds: 700, from: master)
        try write(Data("exit\r".utf8), to: master)

        var processor = ANSIProcessor()
        var buffer = TerminalTextBuffer(columns: 100)
        let result = processor.consume(initialTranscript + transcript + initialSizeTranscript + resizedTranscript)
        for segment in result.segments {
            switch segment {
            case .text(let text):
                buffer.consume(text)
            case .action(let action):
                buffer.apply(action)
            }
        }

        let rendered = buffer.text
        guard rendered.contains("echo ") else {
            throw NSError(domain: "PTYPipelineCheck", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "zsh command echo was not rendered: \(rendered)"
            ])
        }
        guard rendered.contains(String(decoding: [0xE4, 0xBD, 0xA0, 0xE5, 0xA5, 0xBD], as: UTF8.self)) else {
            throw NSError(domain: "PTYPipelineCheck", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "UTF-8 command output was not rendered: \(rendered)"
            ])
        }
        guard rendered.contains("24 100") else {
            throw NSError(domain: "PTYPipelineCheck", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Initial PTY size was not reported: \(rendered)"
            ])
        }
        guard rendered.contains("41 77") else {
            throw NSError(domain: "PTYPipelineCheck", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "Resized PTY size was not reported: \(rendered)"
            ])
        }

        print("pty-pipeline-check: ok")
    }

    private static func write(_ data: Data, to fileDescriptor: Int32) throws {
        try data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            var pointer = baseAddress
            var remaining = bytes.count
            while remaining > 0 {
                let count = Darwin.write(fileDescriptor, pointer, remaining)
                if count > 0 {
                    remaining -= count
                    pointer = pointer.advanced(by: count)
                } else if errno != EINTR {
                    throw NSError(domain: "PTYPipelineCheck", code: Int(errno), userInfo: [
                        NSLocalizedDescriptionKey: String(cString: strerror(errno))
                    ])
                }
            }
        }
    }

    private static func readFor(milliseconds: Int, from fileDescriptor: Int32) -> Data {
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(milliseconds) * 1_000_000
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)

        while DispatchTime.now().uptimeNanoseconds < deadline {
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(fileDescriptor, bytes.baseAddress, bytes.count)
            }
            if count > 0 {
                result.append(contentsOf: buffer[0..<count])
            } else if count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) {
                usleep(10_000)
            } else {
                break
            }
        }
        return result
    }
}
