import Foundation

struct Scheme {
    let name: String
    let foreground: String
    let background: String
    let cursor: String
    let colors: [String]
}

guard CommandLine.arguments.count == 3 else {
    fputs("usage: generate-tabby-themes <scheme-directory> <output-file>\n", stderr)
    exit(2)
}

let fileManager = FileManager.default
let directoryURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

func swiftString(_ value: String) -> String {
    "\"" + value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n") + "\""
}

func parseScheme(at url: URL) throws -> Scheme? {
    let source = try String(contentsOf: url, encoding: .utf8)
    var variables: [String: String] = [:]
    var values: [String: String] = [:]

    for rawLine in source.split(whereSeparator: \.isNewline) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, !line.hasPrefix("!") else { continue }

        if line.hasPrefix("#define") {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if fields.count >= 3 {
                variables[String(fields[1])] = String(fields.dropFirst(2).joined(separator: " "))
            }
            continue
        }

        guard line.hasPrefix("*."), let colon = line.firstIndex(of: ":") else { continue }
        let key = String(line[line.index(line.startIndex, offsetBy: 2)..<colon])
        let rawValue = line[line.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
        let value = variables[rawValue] ?? rawValue
        values[key] = value
    }

    var colors: [String] = []
    var index = 0
    while let color = values["color\(index)"] {
        colors.append(color)
        index += 1
    }

    guard let foreground = values["foreground"],
          let background = values["background"],
          let cursor = values["cursorColor"],
          colors.count >= 16 else {
        return nil
    }

    return Scheme(
        name: url.lastPathComponent,
        foreground: foreground,
        background: background,
        cursor: cursor,
        colors: Array(colors.prefix(16))
    )
}

let schemes = try fileManager
    .contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
    .filter { !$0.hasDirectoryPath }
    .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    .compactMap { try? parseScheme(at: $0) }

func themeID(_ name: String) -> String {
    let scalars = name.lowercased().unicodeScalars.map { scalar -> Character in
        if CharacterSet.alphanumerics.contains(scalar) { return Character(String(scalar)) }
        return "-"
    }
    let collapsed = String(scalars).split(separator: "-").joined(separator: "-")
    return collapsed.isEmpty ? "theme" : collapsed
}

var output = """
// Generated from Eugeny/tabby tabby-community-color-schemes.
// Do not edit individual entries by hand; refresh with Scripts/generate-tabby-themes.swift.
import Foundation

enum TabbyBuiltInThemes {
    static let all: [TerminalTheme] = [
        TerminalTheme(
            id: "tabby-default",
            title: "Tabby Default",
            foregroundHex: "#cacaca",
            backgroundHex: "#171717",
            cursorHex: "#bbbbbb",
            ansiHexColors: ["#000000", "#ff615a", "#b1e969", "#ebd99c", "#5da9f6", "#e86aff", "#82fff7", "#dedacf", "#313131", "#f58c80", "#ddf88f", "#eee5b2", "#a5c7ff", "#ddaaff", "#b7fff9", "#ffffff"]
        ),
        TerminalTheme(
            id: "tabby-default-light",
            title: "Tabby Default Light",
            foregroundHex: "#4d4d4c",
            backgroundHex: "#ffffff",
            cursorHex: "#4d4d4c",
            ansiHexColors: ["#000000", "#c82829", "#718c00", "#eab700", "#4271ae", "#8959a8", "#3e999f", "#ffffff", "#000000", "#c82829", "#718c00", "#eab700", "#4271ae", "#8959a8", "#3e999f", "#ffffff"]
        ),
"""

var usedIDs: Set<String> = ["tabby-default", "tabby-default-light"]
for scheme in schemes {
    var id = themeID(scheme.name)
    var suffix = 2
    while usedIDs.contains(id) {
        id = "\(themeID(scheme.name))-\(suffix)"
        suffix += 1
    }
    usedIDs.insert(id)

    output += """
        TerminalTheme(
            id: \(swiftString(id)),
            title: \(swiftString(scheme.name)),
            foregroundHex: \(swiftString(scheme.foreground)),
            backgroundHex: \(swiftString(scheme.background)),
            cursorHex: \(swiftString(scheme.cursor)),
            ansiHexColors: [\(scheme.colors.map(swiftString).joined(separator: ", "))]
        ),
"""
}

output += "    ]\n}\n"
try output.write(to: outputURL, atomically: true, encoding: .utf8)
print("Generated \(schemes.count + 2) Tabby themes at \(outputURL.path)")
