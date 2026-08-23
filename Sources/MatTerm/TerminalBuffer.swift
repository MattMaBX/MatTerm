import Foundation

enum TerminalColor: Equatable {
    case `default`
    case ansi(Int)
    case rgb(red: UInt8, green: UInt8, blue: UInt8)
}

struct TerminalTextStyle: Equatable {
    var foreground: TerminalColor = .default
    var background: TerminalColor = .default
    var bold = false
    var dim = false
    var underline = false
    var inverse = false
}

struct TerminalCell: Equatable {
    var character: Character
    var style: TerminalTextStyle
    var isContinuation = false
}

struct TerminalTextRun: Equatable {
    var text: String
    var style: TerminalTextStyle
    var isCursor = false
}

enum TerminalControlAction {
    case clearScreen
    case eraseScreen(Int)
    case clearLine(Int)
    case setCursor(row: Int, column: Int)
    case moveCursor(row: Int, column: Int)
    case moveCursorToStartOfLine(Int)
    case setColumn(Int)
    case setRow(Int)
    case insertCharacters(Int)
    case deleteCharacters(Int)
    case eraseCharacters(Int)
    case insertLines(Int)
    case deleteLines(Int)
    case setStyle(TerminalTextStyle)
    case setTitle(String)
    case setWorkingDirectory(String)
    case setBracketedPaste(Bool)
    case saveCursor
    case restoreCursor
    case setCursorVisible(Bool)
    case enterAlternateScreen
    case exitAlternateScreen
    case requestCursorPosition
    case requestDeviceAttributes
    case requestStatus(Int)
}

struct TerminalTextBuffer {
    private struct Snapshot {
        var lines: [[TerminalCell]]
        var cursorRow: Int
        var cursorColumn: Int
        var currentStyle: TerminalTextStyle
        var cursorVisible: Bool
    }

    private struct CursorSnapshot {
        var cursorRow: Int
        var cursorColumn: Int
        var currentStyle: TerminalTextStyle
    }

    private(set) var columns: Int
    private var lines: [[TerminalCell]] = [[]]
    private var cursorRow = 0
    private var cursorColumn = 0
    private var currentStyle = TerminalTextStyle()
    private var savedCursor: CursorSnapshot?
    private var primaryScreen: Snapshot?
    private var isAlternateScreen = false
    private var cursorVisible = true

    init(columns: Int = 120) {
        self.columns = max(2, columns)
    }

    var text: String {
        lines.map(lineText).joined(separator: "\n")
    }

    var cursorPosition: (row: Int, column: Int) {
        (cursorRow + 1, cursorColumn + 1)
    }

    var hasVisibleCharacters: Bool {
        lines.contains { line in
            line.contains { cell in
                !cell.isContinuation && cell.character != " "
            }
        }
    }

    var runs: [TerminalTextRun] {
        var result: [TerminalTextRun] = []
        for (lineIndex, line) in lines.enumerated() {
            var activeStyle: TerminalTextStyle?
            var activeIsCursor = false
            var currentText = ""

            func flush() {
                guard let activeStyle, !currentText.isEmpty else { return }
                result.append(TerminalTextRun(
                    text: currentText,
                    style: activeStyle,
                    isCursor: activeIsCursor
                ))
                currentText = ""
            }

            func append(_ character: Character, style: TerminalTextStyle, isCursor: Bool) {
                if activeStyle != style || activeIsCursor != isCursor {
                    flush()
                    activeStyle = style
                    activeIsCursor = isCursor
                }
                currentText.append(character)
            }

            for (column, cell) in line.enumerated() {
                guard !cell.isContinuation else { continue }
                let wideCursorCell = displayWidth(of: cell.character) == 2
                    && cursorColumn == column + 1
                append(
                    cell.character,
                    style: cell.style,
                    isCursor: cursorVisible && lineIndex == cursorRow
                        && (column == cursorColumn || wideCursorCell)
                )
            }

            if cursorVisible && lineIndex == cursorRow && cursorColumn >= line.count {
                for _ in line.count..<cursorColumn {
                    append(" ", style: currentStyle, isCursor: false)
                }
                append(" ", style: currentStyle, isCursor: true)
            }
            flush()
            if lineIndex < lines.count - 1 {
                result.append(TerminalTextRun(text: "\n", style: TerminalTextStyle()))
            }
        }
        return result
    }

    mutating func resize(columns: Int) {
        self.columns = max(2, columns)
    }

    mutating func clear() {
        lines = [[]]
        cursorRow = 0
        cursorColumn = 0
    }

    mutating func removeLeadingBlankLines() {
        while lines.count > 1 && lines[0].allSatisfy({ $0.character == " " }) {
            lines.removeFirst()
            cursorRow = max(0, cursorRow - 1)
        }
    }

    mutating func apply(_ action: TerminalControlAction) {
        switch action {
        case .clearScreen:
            clear()
        case .eraseScreen(let mode):
            eraseScreen(mode)
        case .clearLine(let mode):
            ensureLine(cursorRow)
            switch mode {
            case 1:
                let end = min(cursorColumn, lines[cursorRow].count - 1)
                if end >= 0 {
                    for index in 0...end {
                        lines[cursorRow][index] = TerminalCell(character: " ", style: currentStyle)
                    }
                }
            case 2:
                lines[cursorRow].removeAll(keepingCapacity: true)
            default:
                if cursorColumn < lines[cursorRow].count {
                    lines[cursorRow].removeSubrange(cursorColumn...)
                }
            }
        case .setCursor(let row, let column):
            cursorRow = max(0, row)
            cursorColumn = min(max(0, column), columns)
            ensureLine(cursorRow)
        case .moveCursor(let row, let column):
            cursorRow = max(0, cursorRow + row)
            cursorColumn = min(max(0, cursorColumn + column), columns)
            ensureLine(cursorRow)
        case .moveCursorToStartOfLine(let row):
            cursorRow = max(0, cursorRow + row)
            cursorColumn = 0
            ensureLine(cursorRow)
        case .setColumn(let column):
            cursorColumn = min(max(0, column), columns)
            ensureLine(cursorRow)
        case .setRow(let row):
            cursorRow = max(0, row)
            ensureLine(cursorRow)
        case .insertCharacters(let count):
            insertCharacters(count)
        case .deleteCharacters(let count):
            deleteCharacters(count)
        case .eraseCharacters(let count):
            eraseCharacters(count)
        case .insertLines(let count):
            insertLines(count)
        case .deleteLines(let count):
            deleteLines(count)
        case .setStyle(let style):
            currentStyle = style
        case .setTitle, .setWorkingDirectory:
            break
        case .setBracketedPaste:
            break
        case .saveCursor:
            savedCursor = CursorSnapshot(
                cursorRow: cursorRow,
                cursorColumn: cursorColumn,
                currentStyle: currentStyle
            )
        case .restoreCursor:
            if let savedCursor {
                cursorRow = savedCursor.cursorRow
                cursorColumn = savedCursor.cursorColumn
                currentStyle = savedCursor.currentStyle
                ensureLine(cursorRow)
            }
        case .setCursorVisible(let visible):
            cursorVisible = visible
        case .enterAlternateScreen:
            enterAlternateScreen()
        case .exitAlternateScreen:
            exitAlternateScreen()
        case .requestCursorPosition, .requestDeviceAttributes, .requestStatus:
            break
        }
    }

    mutating func trimToCharacterLimit(_ limit: Int) {
        guard limit > 0 else {
            clear()
            return
        }

        // Trim whole terminal lines first. This avoids creating a large String
        // and preserves the style of the retained cells.
        let totalCharacters = lines.reduce(0) { partialResult, line in
            partialResult + visibleCharacterCount(in: line)
        } + max(0, lines.count - 1)
        guard totalCharacters > limit else { return }

        var excess = totalCharacters - limit
        var linesToRemove = 0
        while linesToRemove < max(0, lines.count - 1) && excess > 0 {
            let lineCost = visibleCharacterCount(in: lines[linesToRemove]) + 1
            guard excess >= lineCost else { break }
            excess -= lineCost
            linesToRemove += 1
        }

        if linesToRemove > 0 {
            lines.removeSubrange(0..<linesToRemove)
            cursorRow = max(0, cursorRow - linesToRemove)
        }

        if excess > 0, !lines.isEmpty {
            var removedCharacters = 0
            var cellsToRemove = 0
            while cellsToRemove < lines[0].count, removedCharacters < excess {
                let cell = lines[0][cellsToRemove]
                cellsToRemove += 1
                guard !cell.isContinuation else { continue }
                removedCharacters += 1
                if cellsToRemove < lines[0].count, lines[0][cellsToRemove].isContinuation {
                    cellsToRemove += 1
                }
            }
            if cellsToRemove > 0 {
                lines[0].removeFirst(cellsToRemove)
                if cursorRow == 0 {
                    cursorColumn = max(0, cursorColumn - cellsToRemove)
                }
            }
        }

        if lines.isEmpty {
            lines = [[]]
            cursorRow = 0
            cursorColumn = 0
        }
    }

    mutating func consume(_ text: String) {
        var printable = ""
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x08:
                writePrintable(printable)
                printable.removeAll(keepingCapacity: true)
                cursorColumn = max(0, cursorColumn - 1)
            case 0x09:
                writePrintable(printable)
                printable.removeAll(keepingCapacity: true)
                let nextTabStop = ((cursorColumn / 8) + 1) * 8
                for _ in cursorColumn..<nextTabStop {
                    write(" ")
                }
            case 0x0A:
                writePrintable(printable)
                printable.removeAll(keepingCapacity: true)
                cursorRow += 1
                cursorColumn = 0
                ensureLine(cursorRow)
            case 0x0D:
                writePrintable(printable)
                printable.removeAll(keepingCapacity: true)
                cursorColumn = 0
            default:
                if scalar.value >= 0x20 {
                    printable.unicodeScalars.append(scalar)
                }
            }
        }
        writePrintable(printable)
    }

    private mutating func writePrintable(_ text: String) {
        for character in text {
            if isCombining(character) {
                appendCombining(character)
            } else {
                write(character)
            }
        }
    }

    private mutating func write(_ value: Character) {
        ensureLine(cursorRow)
        let width = displayWidth(of: value)
        guard width > 0 else {
            appendCombining(value)
            return
        }
        if cursorColumn + width > columns {
            cursorRow += 1
            cursorColumn = 0
            ensureLine(cursorRow)
        }

        while lines[cursorRow].count < cursorColumn {
            lines[cursorRow].append(TerminalCell(character: " ", style: currentStyle))
        }

        clearWideCellIfNeeded(at: cursorColumn)
        let cell = TerminalCell(character: value, style: currentStyle)
        if cursorColumn < lines[cursorRow].count {
            lines[cursorRow][cursorColumn] = cell
        } else {
            lines[cursorRow].append(cell)
        }
        if width == 2 {
            let continuation = TerminalCell(
                character: " ",
                style: currentStyle,
                isContinuation: true
            )
            if cursorColumn + 1 < lines[cursorRow].count {
                lines[cursorRow][cursorColumn + 1] = continuation
            } else {
                lines[cursorRow].append(continuation)
            }
        }
        cursorColumn += width
    }

    private mutating func appendCombining(_ character: Character) {
        ensureLine(cursorRow)
        let index = max(0, min(cursorColumn - 1, lines[cursorRow].count - 1))
        guard !lines[cursorRow].isEmpty,
              index < lines[cursorRow].count,
              !lines[cursorRow][index].isContinuation else { return }
        lines[cursorRow][index].character = Character(String(lines[cursorRow][index].character) + String(character))
    }

    private mutating func clearWideCellIfNeeded(at column: Int) {
        guard lines[cursorRow].indices.contains(column) else { return }
        if lines[cursorRow][column].isContinuation, column > 0 {
            lines[cursorRow][column - 1] = TerminalCell(character: " ", style: currentStyle)
        }
        if column + 1 < lines[cursorRow].count, lines[cursorRow][column + 1].isContinuation {
            lines[cursorRow][column + 1] = TerminalCell(character: " ", style: currentStyle)
        }
    }

    private mutating func insertCharacters(_ count: Int) {
        ensureLine(cursorRow)
        let amount = max(1, count)
        let spaces = Array(repeating: TerminalCell(character: " ", style: currentStyle), count: amount)
        let index = min(cursorColumn, lines[cursorRow].count)
        lines[cursorRow].insert(contentsOf: spaces, at: index)
        if lines[cursorRow].count > columns {
            lines[cursorRow].removeLast(lines[cursorRow].count - columns)
        }
    }

    private mutating func deleteCharacters(_ count: Int) {
        ensureLine(cursorRow)
        guard cursorColumn < lines[cursorRow].count else { return }
        let amount = min(max(1, count), lines[cursorRow].count - cursorColumn)
        lines[cursorRow].removeSubrange(cursorColumn..<(cursorColumn + amount))
    }

    private mutating func eraseCharacters(_ count: Int) {
        ensureLine(cursorRow)
        guard cursorColumn < columns else { return }
        let end = min(columns, cursorColumn + max(1, count))
        while lines[cursorRow].count < end {
            lines[cursorRow].append(TerminalCell(character: " ", style: currentStyle))
        }
        for index in cursorColumn..<end {
            lines[cursorRow][index] = TerminalCell(character: " ", style: currentStyle)
        }
    }

    private mutating func insertLines(_ count: Int) {
        let amount = max(1, count)
        let insertionIndex = min(cursorRow, lines.count)
        lines.insert(contentsOf: Array(repeating: [], count: amount), at: insertionIndex)
    }

    private mutating func deleteLines(_ count: Int) {
        guard cursorRow < lines.count else { return }
        let amount = min(max(1, count), lines.count - cursorRow)
        lines.removeSubrange(cursorRow..<(cursorRow + amount))
        ensureLine(cursorRow)
    }

    private mutating func eraseScreen(_ mode: Int) {
        ensureLine(cursorRow)
        switch mode {
        case 1:
            for row in 0...min(cursorRow, lines.count - 1) {
                if row == cursorRow {
                    let end = min(cursorColumn, lines[row].count)
                    if end > 0 {
                        for index in 0..<end {
                            lines[row][index] = TerminalCell(character: " ", style: currentStyle)
                        }
                    }
                } else {
                    lines[row].removeAll(keepingCapacity: true)
                }
            }
        case 2:
            clear()
        default:
            if cursorRow < lines.count {
                if cursorColumn < lines[cursorRow].count {
                    lines[cursorRow].removeSubrange(cursorColumn...)
                }
                if cursorRow + 1 < lines.count {
                    lines.removeSubrange((cursorRow + 1)...)
                }
            }
        }
    }

    private mutating func enterAlternateScreen() {
        guard !isAlternateScreen else { return }
        primaryScreen = Snapshot(
            lines: lines,
            cursorRow: cursorRow,
            cursorColumn: cursorColumn,
            currentStyle: currentStyle,
            cursorVisible: cursorVisible
        )
        isAlternateScreen = true
        lines = [[]]
        cursorRow = 0
        cursorColumn = 0
    }

    private mutating func exitAlternateScreen() {
        guard isAlternateScreen else { return }
        if let primaryScreen {
            lines = primaryScreen.lines
            cursorRow = primaryScreen.cursorRow
            cursorColumn = primaryScreen.cursorColumn
            currentStyle = primaryScreen.currentStyle
            cursorVisible = primaryScreen.cursorVisible
        }
        self.primaryScreen = nil
        isAlternateScreen = false
        ensureLine(cursorRow)
    }

    private func lineText(_ line: [TerminalCell]) -> String {
        line.filter { !$0.isContinuation }.map(\.character).reduce(into: "") { result, character in
            result.append(character)
        }
    }

    private func visibleCharacterCount(in line: [TerminalCell]) -> Int {
        line.reduce(0) { count, cell in
            count + (cell.isContinuation ? 0 : 1)
        }
    }

    private func isCombining(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 0x200C, 0x200D, 0xFE00...0xFE0F, 0xE0100...0xE01EF:
                return true
            default:
                return [.nonspacingMark, .spacingMark, .enclosingMark].contains(scalar.properties.generalCategory)
            }
        }
    }

    private func displayWidth(of character: Character) -> Int {
        if isCombining(character) { return 0 }
        if character.unicodeScalars.contains(where: isWideScalar) { return 2 }
        return 1
    }

    private func isWideScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x1100...0x115F, 0x2329...0x232A,
             0x2E80...0x303E, 0x3040...0xA4CF,
             0xAC00...0xD7A3, 0xF900...0xFAFF,
             0xFE10...0xFE19, 0xFE30...0xFE6F,
             0xFF00...0xFF60, 0xFFE0...0xFFE6,
             0x1F300...0x1FAFF:
            return true
        default:
            return false
        }
    }

    private mutating func ensureLine(_ row: Int) {
        while lines.count <= row {
            lines.append([])
        }
    }
}
