import Foundation

struct ANSIProcessor {
    enum Segment {
        case text(String)
        case action(TerminalControlAction)
    }

    struct Result {
        var segments: [Segment]

        var didClearScreen: Bool {
            segments.contains { segment in
                guard case .action(let action) = segment else { return false }
                if case .clearScreen = action { return true }
                return false
            }
        }
    }

    private enum EscapeState {
        case normal
        case afterEscape
        case csi
        case osc
        case oscAfterEscape
    }

    private var state: EscapeState = .normal
    private var sequence = ""
    private var currentStyle = TerminalTextStyle()
    private var pendingUTF8 = Data()

    mutating func reset() {
        state = .normal
        sequence.removeAll(keepingCapacity: true)
        currentStyle = TerminalTextStyle()
        pendingUTF8.removeAll(keepingCapacity: true)
    }

    mutating func consume(_ data: Data) -> Result {
        var bytes = Array(pendingUTF8)
        bytes.append(contentsOf: data)
        let splitIndex = incompleteUTF8Start(in: bytes)
        let completeBytes = bytes[..<splitIndex]
        pendingUTF8 = Data(bytes[splitIndex...])
        guard !completeBytes.isEmpty else {
            return Result(segments: [])
        }
        let string = String(decoding: completeBytes, as: UTF8.self)

        var output = ""
        var segments: [Segment] = []

        func flushOutput() {
            guard !output.isEmpty else { return }
            segments.append(.text(output))
            output.removeAll(keepingCapacity: true)
        }

        for scalar in string.unicodeScalars {
            let value = scalar.value

            switch state {
            case .normal:
                if value == 0x1B {
                    state = .afterEscape
                    sequence.removeAll(keepingCapacity: true)
                } else {
                    appendPrintable(scalar, to: &output)
                }

            case .afterEscape:
                sequence.unicodeScalars.append(scalar)
                switch value {
                case 0x5B:
                    state = .csi
                case 0x5D:
                    state = .osc
                default:
                    state = .normal
                    sequence.removeAll(keepingCapacity: true)
                }

            case .csi:
                sequence.unicodeScalars.append(scalar)
                if (0x40...0x7E).contains(value) {
                    if let action = parseCSI(sequence) {
                        flushOutput()
                        segments.append(.action(action))
                    }
                    state = .normal
                    sequence.removeAll(keepingCapacity: true)
                }

            case .osc:
                if value == 0x07 {
                    if let action = parseOSC(sequence) {
                        flushOutput()
                        segments.append(.action(action))
                    }
                    state = .normal
                    sequence.removeAll(keepingCapacity: true)
                } else if value == 0x1B {
                    state = .oscAfterEscape
                } else {
                    sequence.unicodeScalars.append(scalar)
                }

            case .oscAfterEscape:
                if value == 0x5C {
                    if let action = parseOSC(sequence) {
                        flushOutput()
                        segments.append(.action(action))
                    }
                    state = .normal
                    sequence.removeAll(keepingCapacity: true)
                } else if value == 0x07 {
                    if let action = parseOSC(sequence) {
                        flushOutput()
                        segments.append(.action(action))
                    }
                    state = .normal
                    sequence.removeAll(keepingCapacity: true)
                } else {
                    sequence.unicodeScalars.append("\u{1B}")
                    sequence.unicodeScalars.append(scalar)
                    state = .osc
                }
            }
        }

        flushOutput()
        return Result(segments: segments)
    }

    private mutating func parseCSI(_ sequence: String) -> TerminalControlAction? {
        guard sequence.first == "[", let final = sequence.last else { return nil }
        let parameterText = String(sequence.dropFirst().dropLast())
        let isPrivate = parameterText.contains("?")
        let parameters = parameterText
            .trimmingCharacters(in: CharacterSet(charactersIn: "? >"))
            .split(separator: ";", omittingEmptySubsequences: false)
            .map { Int($0) ?? 0 }

        func parameter(_ index: Int, default defaultValue: Int) -> Int {
            guard parameters.indices.contains(index), parameters[index] != 0 else { return defaultValue }
            return parameters[index]
        }

        switch final {
        case "m":
            currentStyle = parseStyle(parameters)
            return .setStyle(currentStyle)
        case "J" where parameter(0, default: 0) >= 2:
            return .clearScreen
        case "J":
            return .eraseScreen(parameter(0, default: 0))
        case "K":
            return .clearLine(parameter(0, default: 0))
        case "H", "f":
            return .setCursor(
                row: parameter(0, default: 1) - 1,
                column: parameter(1, default: 1) - 1
            )
        case "A":
            return .moveCursor(row: -parameter(0, default: 1), column: 0)
        case "B":
            return .moveCursor(row: parameter(0, default: 1), column: 0)
        case "C":
            return .moveCursor(row: 0, column: parameter(0, default: 1))
        case "D":
            return .moveCursor(row: 0, column: -parameter(0, default: 1))
        case "G", "`":
            return .setColumn(parameter(0, default: 1) - 1)
        case "d":
            return .setRow(parameter(0, default: 1) - 1)
        case "e":
            return .moveCursor(row: parameter(0, default: 1), column: 0)
        case "E":
            return .moveCursorToStartOfLine(parameter(0, default: 1))
        case "F":
            return .moveCursorToStartOfLine(-parameter(0, default: 1))
        case "@":
            return .insertCharacters(parameter(0, default: 1))
        case "P":
            return .deleteCharacters(parameter(0, default: 1))
        case "X":
            return .eraseCharacters(parameter(0, default: 1))
        case "L":
            return .insertLines(parameter(0, default: 1))
        case "M":
            return .deleteLines(parameter(0, default: 1))
        case "s":
            return .saveCursor
        case "u":
            return .restoreCursor
        case "h" where isPrivate && parameters.contains(25):
            return .setCursorVisible(true)
        case "l" where isPrivate && parameters.contains(25):
            return .setCursorVisible(false)
        case "h" where isPrivate && parameters.contains(2004):
            return .setBracketedPaste(true)
        case "l" where isPrivate && parameters.contains(2004):
            return .setBracketedPaste(false)
        case "h" where parameters.contains(1049) || parameters.contains(47):
            return .enterAlternateScreen
        case "l" where parameters.contains(1049) || parameters.contains(47):
            return .exitAlternateScreen
        case "n" where parameter(0, default: 0) == 6:
            return .requestCursorPosition
        case "n" where parameter(0, default: 0) == 5:
            return .requestStatus(5)
        case "c":
            return .requestDeviceAttributes
        default:
            return nil
        }
    }

    private func parseOSC(_ sequence: String) -> TerminalControlAction? {
        guard sequence.first == "]" else { return nil }
        let payload = String(sequence.dropFirst())
        guard let separator = payload.firstIndex(of: ";"),
              let code = Int(payload[..<separator]) else { return nil }
        let value = String(payload[payload.index(after: separator)...])
        switch code {
        case 0, 1, 2:
            return .setTitle(value)
        case 7:
            return workingDirectoryAction(from: value)
        default:
            return nil
        }
    }

    private func workingDirectoryAction(from value: String) -> TerminalControlAction? {
        if let url = URL(string: value), url.scheme == "file" {
            let path = url.path.removingPercentEncoding ?? url.path
            return path.isEmpty ? nil : .setWorkingDirectory(path)
        }
        let path = value.removingPercentEncoding ?? value
        return path.hasPrefix("/") ? .setWorkingDirectory(path) : nil
    }

    private func incompleteUTF8Start(in bytes: [UInt8]) -> Int {
        guard let last = bytes.last else { return bytes.count }

        func expectedLength(for byte: UInt8) -> Int {
            switch byte {
            case 0xC2...0xDF: return 2
            case 0xE0...0xEF: return 3
            case 0xF0...0xF4: return 4
            default: return 1
            }
        }

        if (last & 0xC0) != 0x80 {
            let expected = expectedLength(for: last)
            return expected > 1 ? bytes.count - 1 : bytes.count
        }

        var leadIndex = bytes.count - 1
        while leadIndex >= 0 && (bytes[leadIndex] & 0xC0) == 0x80 {
            leadIndex -= 1
        }
        guard leadIndex >= 0 else { return bytes.count }

        let expected = expectedLength(for: bytes[leadIndex])
        let actual = bytes.count - leadIndex
        return expected > actual ? leadIndex : bytes.count
    }

    private func parseStyle(_ parameters: [Int]) -> TerminalTextStyle {
        let codes = parameters.isEmpty ? [0] : parameters
        var style = currentStyle
        var index = 0

        while index < codes.count {
            let code = codes[index]
            switch code {
            case 0:
                style = TerminalTextStyle()
            case 1:
                style.bold = true
            case 2:
                style.dim = true
            case 4:
                style.underline = true
            case 7:
                style.inverse = true
            case 22:
                style.bold = false
                style.dim = false
            case 24:
                style.underline = false
            case 27:
                style.inverse = false
            case 30...37:
                style.foreground = .ansi(code - 30)
            case 39:
                style.foreground = .default
            case 40...47:
                style.background = .ansi(code - 40)
            case 49:
                style.background = .default
            case 90...97:
                style.foreground = .ansi(code - 90 + 8)
            case 100...107:
                style.background = .ansi(code - 100 + 8)
            case 38, 48:
                let isForeground = code == 38
                if index + 2 < codes.count, codes[index + 1] == 5 {
                    let color = TerminalColor.ansi(codes[index + 2])
                    if isForeground { style.foreground = color } else { style.background = color }
                    index += 2
                } else if index + 4 < codes.count, codes[index + 1] == 2 {
                    let color = TerminalColor.rgb(
                        red: UInt8(clamping: codes[index + 2]),
                        green: UInt8(clamping: codes[index + 3]),
                        blue: UInt8(clamping: codes[index + 4])
                    )
                    if isForeground { style.foreground = color } else { style.background = color }
                    index += 4
                }
            default:
                break
            }
            index += 1
        }
        return style
    }

    private func appendPrintable(_ scalar: Unicode.Scalar, to output: inout String) {
        switch scalar.value {
        case 0x08, 0x09, 0x0A, 0x0D:
            output.unicodeScalars.append(scalar)
        case 0x20...0x7E, 0x80...0x10FFFF:
            output.unicodeScalars.append(scalar)
        default:
            break
        }
    }
}
