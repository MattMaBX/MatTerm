#!/bin/zsh
set -euo pipefail

swift -e '
import AppKit

let families = NSFontManager.shared.availableFontFamilies
    .filter { family in
        guard let font = NSFont(name: family, size: 13) else { return false }
        return NSFontManager.shared.traits(of: font).contains(.fixedPitchFontMask)
    }

guard !families.isEmpty else {
    fatalError("No monospaced font family is available")
}

let preferred = ["Maple Mono NF CN", "SF Mono", "Menlo", "Monaco", "PT Mono"]
let availablePreferred = preferred.filter { family in
    guard let font = NSFont(name: family, size: 13) else { return false }
    return NSFontManager.shared.traits(of: font).contains(.fixedPitchFontMask)
}
let fallback = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
print("appearance-check: monospaced=\(families.count) preferred=\(availablePreferred.joined(separator: ",")) fallback=\(fallback.fontName)")
'
