import Foundation

@main
enum TerminalParserCheck {
    static func main() {
        var buffer = TerminalTextBuffer(columns: 12)
        buffer.consume("prompt\rready")
        precondition(buffer.text == "readyt", "carriage return handling failed: \(buffer.text)")

        buffer.clear()
        buffer.consume("abc\u{08}\u{08}OK")
        precondition(buffer.text == "aOK", "backspace handling failed: \(buffer.text)")

        var processor = ANSIProcessor()
        let result = processor.consume(Data("\u{1B}[31mred\u{1B}[0mplain".utf8))
        let hasRedStyle = result.segments.contains { segment in
            guard case .action(.setStyle(let style)) = segment else { return false }
            return style.foreground == .ansi(1)
        }
        let textSegments = result.segments.compactMap { segment -> String? in
            guard case .text(let text) = segment else { return nil }
            return text
        }
        precondition(hasRedStyle, "ANSI foreground style was not parsed")
        precondition(textSegments == ["red", "plain"], "ANSI segment ordering failed: \(textSegments)")

        processor.reset()
        let firstUTF8Chunk = processor.consume(Data([0xE4, 0xBD]))
        precondition(firstUTF8Chunk.segments.isEmpty, "incomplete UTF-8 was emitted too early")
        let secondUTF8Chunk = processor.consume(Data([0xA0, 0xE5, 0xA5, 0xBD, 0x21]))
        let decodedText = secondUTF8Chunk.segments.compactMap { segment -> String? in
            guard case .text(let text) = segment else { return nil }
            return text
        }.joined()
        let expectedText = String(decoding: [0xE4, 0xBD, 0xA0, 0xE5, 0xA5, 0xBD, 0x21], as: UTF8.self)
        precondition(decodedText == expectedText, "split UTF-8 decoding failed")

        let screenActions = processor.consume(Data("\u{1B}[?1049h\u{1B}[?25l\u{1B}[?2004h\u{1B}[s".utf8)).segments
        precondition(screenActions.contains { segment in
            if case .action(.enterAlternateScreen) = segment { return true }
            return false
        }, "alternate screen enter was not parsed")
        precondition(screenActions.contains { segment in
            if case .action(.setCursorVisible(false)) = segment { return true }
            return false
        }, "cursor visibility was not parsed")
        precondition(screenActions.contains { segment in
            if case .action(.setBracketedPaste(true)) = segment { return true }
            return false
        }, "bracketed paste mode was not parsed")
        precondition(screenActions.contains { segment in
            if case .action(.saveCursor) = segment { return true }
            return false
        }, "cursor save was not parsed")

        let queryActions = processor.consume(Data("\u{1B}[6n\u{1B}[c\u{1B}[5n".utf8)).segments
        precondition(queryActions.contains { segment in
            if case .action(.requestCursorPosition) = segment { return true }
            return false
        }, "cursor position query was not parsed")
        precondition(queryActions.contains { segment in
            if case .action(.requestDeviceAttributes) = segment { return true }
            return false
        }, "device attributes query was not parsed")
        precondition(queryActions.contains { segment in
            if case .action(.requestStatus(5)) = segment { return true }
            return false
        }, "terminal status query was not parsed")

        buffer.clear()
        buffer.consume("primary")
        buffer.apply(.enterAlternateScreen)
        buffer.consume("alternate")
        precondition(buffer.text == "alternate", "alternate screen content failed")
        buffer.apply(.exitAlternateScreen)
        precondition(buffer.text == "primary", "primary screen was not restored")
        precondition(buffer.runs.contains(where: \.isCursor), "cursor run was not rendered")
        buffer.apply(.setCursorVisible(false))
        precondition(!buffer.runs.contains(where: \.isCursor), "hidden cursor still rendered")

        buffer.clear()
        buffer.resize(columns: 8)
        buffer.consume("A你B")
        precondition(buffer.text == "A你B", "wide character text was duplicated: \(buffer.text)")
        precondition(buffer.cursorPosition == (1, 5), "wide character cursor width failed: \(buffer.cursorPosition)")

        buffer.clear()
        buffer.consume("1234567你")
        precondition(buffer.text == "1234567\n你", "wide character did not wrap at the terminal edge: \(buffer.text)")

        buffer.clear()
        buffer.consume("e\u{301}")
        precondition(buffer.text == "e\u{301}", "combining character was rendered as a new cell: \(buffer.text)")

        processor.reset()
        let titleActions = processor.consume(Data("\u{1B}]2;MatTerm\u{07}".utf8)).segments
        precondition(titleActions.contains { segment in
            if case .action(.setTitle("MatTerm")) = segment { return true }
            return false
        }, "OSC title was not parsed")

        processor.reset()
        let workingDirectoryActions = processor.consume(Data("\u{1B}]7;file://localhost/Users/test%20folder\u{07}".utf8)).segments
        precondition(workingDirectoryActions.contains { segment in
            if case .action(.setWorkingDirectory("/Users/test folder")) = segment { return true }
            return false
        }, "OSC 7 working directory was not parsed")

        buffer.clear()
        buffer.consume("abc")
        buffer.apply(.setColumn(1))
        buffer.apply(.insertCharacters(2))
        precondition(buffer.text == "a  bc", "character insertion failed: \(buffer.text)")
        buffer.apply(.setColumn(1))
        buffer.apply(.deleteCharacters(2))
        precondition(buffer.text == "abc", "character deletion failed: \(buffer.text)")

        buffer.clear()
        buffer.apply(.setCursorVisible(false))
        buffer.apply(.enterAlternateScreen)
        buffer.apply(.setCursorVisible(true))
        buffer.apply(.exitAlternateScreen)
        precondition(!buffer.runs.contains(where: \.isCursor), "primary cursor visibility was not restored")

        print("terminal-parser-check: ok")
    }
}
