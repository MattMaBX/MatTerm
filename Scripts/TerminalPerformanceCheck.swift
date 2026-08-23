import Foundation

@main
enum TerminalPerformanceCheck {
    static func main() {
        var buffer = TerminalTextBuffer(columns: 120)
        let line = String(repeating: "matterm-output ", count: 5) + "\n"
        let output = String(repeating: line, count: 8_000)

        let consumeStart = DispatchTime.now().uptimeNanoseconds
        buffer.consume(output)
        buffer.trimToCharacterLimit(240_000)
        let consumeMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - consumeStart) / 1_000_000

        let text = buffer.text
        precondition(text.count <= 240_000, "scrollback exceeded the configured character limit")
        precondition(text.contains("matterm-output"), "scrollback lost retained output")

        let renderStart = DispatchTime.now().uptimeNanoseconds
        let runs = buffer.runs
        let renderMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - renderStart) / 1_000_000
        precondition(!runs.isEmpty, "scrollback produced no render runs")

        print(
            "terminal-performance-check: ok "
                + "characters=\(text.count) runs=\(runs.count) "
                + "consume_ms=\(String(format: "%.1f", consumeMilliseconds)) "
                + "render_ms=\(String(format: "%.1f", renderMilliseconds))"
        )
    }
}
