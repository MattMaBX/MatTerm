import Foundation
import GhosttyVt

@main
enum GhosttyVTCheck {
    static func main() {
        let engine = GhosttyTerminalEngine(columns: 32, rows: 8)
        precondition(engine.isReady, "Ghostty terminal resources were not created")
        precondition(engine.configureScrollback(maxLines: 123), "Ghostty scrollback limit was not configured")
        precondition(engine.scrollbackMaximumLines == 123, "Ghostty scrollback limit was not retained")
        precondition(engine.scrollbackMaximumBytes == nil, "Ghostty byte limit was not removed")

        let longHistoryEngine = GhosttyTerminalEngine(columns: 32, rows: 8)
        precondition(longHistoryEngine.configureScrollback(maxLines: 2_000), "Long-history limit was not configured")
        let longHistory = (0..<1_000).map { "history-\($0)\n" }.joined()
        longHistoryEngine.write(Data(longHistory.utf8))
        precondition(
            longHistoryEngine.snapshot().totalRows >= 1_000,
            "Configured row limit was preempted by a byte limit"
        )

        var wheelAccumulator = TerminalMouseWheelAccumulator()
        precondition(
            wheelAccumulator.consume(delta: 24, isPrecise: true, lineHeight: 16) == 0,
            "Precise wheel deltas were not accumulated"
        )
        precondition(
            wheelAccumulator.consume(delta: 56, isPrecise: true, lineHeight: 16) == 1,
            "Precise wheel distance did not map to one tmux wheel event"
        )
        precondition(
            wheelAccumulator.consume(delta: -80, isPrecise: true, lineHeight: 16) == -1,
            "Reverse precise wheel distance did not preserve direction"
        )
        precondition(
            wheelAccumulator.consume(delta: 1, isPrecise: false, lineHeight: 16) == 1,
            "Physical mouse wheel ticks were incorrectly throttled"
        )

        var palette = Array(repeating: GhosttyColorRgb(r: 0, g: 0, b: 0), count: 256)
        palette[1] = GhosttyColorRgb(r: 255, g: 16, b: 32)
        engine.configureColors(TerminalColorConfiguration(
            id: "check",
            foreground: GhosttyColorRgb(r: 220, g: 223, b: 228),
            background: GhosttyColorRgb(r: 40, g: 44, b: 52),
            cursor: GhosttyColorRgb(r: 163, g: 179, b: 204),
            palette: palette
        ))

        engine.write(Data("matterm-你好".utf8))
        var snapshot = engine.snapshot()
        precondition(snapshot.line(at: 0).map(\.character).contains("m"), "Ghostty text was not rendered")
        precondition(engine.visibleText.contains("matterm-你好"), "UTF-8 text was not preserved")

        engine.write(Data("\u{1B}[31mred\u{1B}[0m\u{1B}[1m bold".utf8))
        snapshot = engine.snapshot()
        precondition(snapshot.lines.flatMap { $0 }.contains { $0.character == "r" }, "SGR text was not rendered")
        precondition(
            snapshot.lines.flatMap { $0 }.contains {
                $0.character == "r" && $0.style.foreground == .ansi(1)
            },
            "Configured terminal palette index was not preserved"
        )
        precondition(
            snapshot.palette.indices.contains(1)
                && snapshot.palette[1] == .rgb(red: 255, green: 16, blue: 32),
            "Configured terminal palette RGB value was not applied"
        )

        engine.write(Data("\u{1B}[0m\u{1B}[38;2;1;2;3mtruecolor\u{1B}[38;5;1mindexed\u{1B}[1;31mbold-red".utf8))
        snapshot = engine.snapshot()
        precondition(
            snapshot.lines.flatMap { $0 }.contains {
                $0.character == "t" && $0.style.foreground == .rgb(red: 1, green: 2, blue: 3)
            },
            "Truecolor SGR was not preserved"
        )
        let indexedForegrounds: [TerminalColor] = [
            .ansi(1), .rgb(red: 255, green: 16, blue: 32)
        ]
        precondition(
            snapshot.lines.flatMap { $0 }.contains {
                $0.character == "i" && indexedForegrounds.contains($0.style.foreground)
            },
            "256-color SGR value was not rendered"
        )
        precondition(
            snapshot.lines.flatMap { $0 }.contains {
                $0.character == "b" && $0.style.foreground == .ansi(9)
            },
            "Bold ANSI brightening was not applied"
        )

        precondition(!engine.visibleText.contains("\u{1B}"), "VT control bytes leaked into the screen")

        engine.write(Data("\u{1B}[?1h\u{1B}[?2004h\u{1B}[?1000h\u{1B}[?1006h".utf8))
        precondition(engine.applicationCursorKeys, "DEC application cursor mode was not tracked")
        precondition(engine.bracketedPasteEnabled, "Bracketed paste mode was not tracked")
        precondition(engine.mouseTracking == .normal, "Mouse tracking mode was not tracked")
        precondition(engine.mouseEncoding == .sgr, "SGR mouse encoding was not tracked")

        precondition(engine.encodeFocusEvent(focused: true) == Data("\u{1B}[I".utf8), "Ghostty focus encoder did not emit focus-in")
        precondition(engine.encodeFocusEvent(focused: false) == Data("\u{1B}[O".utf8), "Ghostty focus encoder did not emit focus-out")
        let paste = engine.encodePaste("one\ntwo")
        precondition(paste == Data("\u{1B}[200~one\ntwo\u{1B}[201~".utf8), "Ghostty paste encoder did not honor bracketed paste")

        let key = engine.encodeKey(keyCode: 123, modifiers: 0, optionAsAlt: true)
        precondition(key?.first == 0x1B, "Ghostty key encoder did not emit an escape sequence")
        let functionKey = engine.encodeKey(keyCode: 122, modifiers: 0, optionAsAlt: true)
        precondition(functionKey == Data("\u{1B}OP".utf8), "Function-key encoding is incorrect")
        engine.write(Data("\u{1B}[?1002h".utf8))
        let mouse = engine.encodeMouse(
            kind: .press, button: 0, column: 4, row: 2, modifiers: 0,
            anyButtonPressed: true
        )
        let drag = engine.encodeMouse(
            kind: .motion, button: 0, column: 5, row: 2, modifiers: 0,
            anyButtonPressed: true
        )
        let release = engine.encodeMouse(
            kind: .release, button: 0, column: 5, row: 2, modifiers: 0,
            anyButtonPressed: false
        )
        precondition(mouse == Data("\u{1B}[<0;4;2M".utf8), "Ghostty mouse press encoding is incorrect")
        precondition(drag == Data("\u{1B}[<32;5;2M".utf8), "Ghostty mouse drag encoding is incorrect")
        precondition(release == Data("\u{1B}[<0;5;2m".utf8), "Ghostty mouse release encoding is incorrect")

        engine.write(Data("\u{1B}[5n".utf8))
        precondition(engine.drainPTYOutput() == Data("\u{1B}[0n".utf8), "Ghostty status response was not emitted")

        engine.write(Data("\u{1B}[?1049h\u{1B}[2J\u{1B}[Halternate".utf8))
        precondition(engine.isAlternateScreen, "Ghostty alternate screen was not entered")
        precondition(engine.visibleText.contains("alternate"), "Alternate-screen content was not rendered")
        engine.write(Data("\u{1B}[?1049l".utf8))
        precondition(!engine.isAlternateScreen, "Ghostty alternate screen was not restored")

        engine.reset()
        let rows = (0..<24).map { "scroll-\($0)\n" }.joined()
        engine.write(Data(rows.utf8))
        let bottom = engine.snapshot()
        precondition(bottom.totalRows > bottom.rows, "Ghostty scrollback did not grow")
        engine.scrollViewport(delta: -3)
        let scrolled = engine.snapshot()
        precondition(scrolled.screenTopIndex < bottom.screenTopIndex, "Ghostty viewport did not scroll into history")
        precondition(scrolled.line(at: scrolled.screenTopIndex).contains { $0.character == "s" }, "Ghostty scrollback rows were not rendered")
        engine.scrollViewport(row: 0)
        let top = engine.snapshot()
        precondition(top.screenTopIndex == 0, "Ghostty absolute viewport did not reach the top")
        let topText = top.lines.map { line in
            line.filter { !$0.isContinuation }.map(\.character).reduce(into: "") { result, character in
                result.append(character)
            }
        }.joined(separator: "\n")
        precondition(topText.contains("scroll-0"), "Ghostty top scrollback rows were not rendered")

        engine.reset()
        engine.write(Data("selection one\nselection two".utf8))
        precondition(
            engine.setSelection(startColumn: 0, startRow: 0, endColumn: 8, endRow: 0),
            "Ghostty selection could not be installed"
        )
        let selectedSnapshot = engine.snapshot()
        precondition(
            selectedSnapshot.line(at: 0).prefix(9).allSatisfy(\.isSelected),
            "Selected cells were not exposed by the render state"
        )
        precondition(engine.selectedText() == "selection", "Selected text was not formatted")
        engine.clearSelection()

        print("ghostty-vt-check: ok")
    }
}
