import Foundation
import GhosttyVt

struct TerminalColorConfiguration {
    let id: String
    let foreground: GhosttyColorRgb
    let background: GhosttyColorRgb
    let cursor: GhosttyColorRgb
    let palette: [GhosttyColorRgb]

    init(
        id: String,
        foreground: GhosttyColorRgb,
        background: GhosttyColorRgb,
        cursor: GhosttyColorRgb,
        palette: [GhosttyColorRgb]
    ) {
        self.id = id
        self.foreground = foreground
        self.background = background
        self.cursor = cursor
        self.palette = palette
    }
}

enum TerminalColor: Hashable {
    case `default`
    case ansi(Int)
    case rgb(red: UInt8, green: UInt8, blue: UInt8)
}

enum TerminalMouseTracking: Equatable {
    case off
    case x10
    case normal
    case buttonMotion
    case anyMotion
}

enum TerminalMouseEncoding: Equatable {
    case x10
    case utf8
    case sgr
    case urxvt
}

enum TerminalMouseEventKind: Equatable {
    case press
    case release
    case motion
    case scrollUp
    case scrollDown
}

struct TerminalTextStyle: Hashable {
    var foreground: TerminalColor = .default
    var background: TerminalColor = .default
    var bold = false
    var dim = false
    var italic = false
    var underline = false
    var strikethrough = false
    var blink = false
    var invisible = false
    var inverse = false
}

struct TerminalCell: Equatable {
    var character: Character
    var style: TerminalTextStyle
    var isContinuation = false
    var isSelected = false
}

/// A renderer-facing view of the cells currently visible through Ghostty's
/// viewport. `lines` contains exactly `rows` viewport rows; `screenTopIndex`
/// maps them into the complete primary-screen scrollback coordinate space.
struct TerminalGridSnapshot {
    let columns: Int
    let rows: Int
    let lines: [[TerminalCell]]
    let screenTopIndex: Int
    let totalRows: Int
    let cursorRow: Int
    let cursorColumn: Int
    let cursorVisible: Bool
    let isAlternateScreen: Bool
    /// These are the colors resolved by Ghostty for the current terminal
    /// state. They can change at runtime through OSC 4/10/11/12, so the
    /// renderer must not fall back to the original SwiftUI theme for them.
    let defaultForeground: TerminalColor
    let defaultBackground: TerminalColor
    let cursorColor: TerminalColor
    let palette: [TerminalColor]

    var contentRowCount: Int { max(rows, totalRows) }

    var screenCursorRow: Int { cursorRow - screenTopIndex }

    var documentCursorRow: Int { cursorRow }

    func line(at row: Int) -> [TerminalCell] {
        let viewportRow = row - screenTopIndex
        guard lines.indices.contains(viewportRow) else { return [] }
        return lines[viewportRow]
    }
}
