import AppKit
import SwiftUI

struct TerminalView: View {
    @ObservedObject var session: TerminalSession
    let isFocusedPane: Bool
    let onFocus: () -> Void
    @EnvironmentObject private var terminalAppearance: TerminalAppearance

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                TerminalBackdropView(appearance: terminalAppearance)
                TerminalOutputView(
                    session: session,
                    appearance: terminalAppearance,
                    isFocusedPane: isFocusedPane,
                    onFocus: onFocus
                )
            }
            .clipped()
                .onAppear {
                    synchronizeSession(for: proxy.size)
                }
                .onChange(of: proxy.size) { _, size in
                    synchronizeSession(for: size)
                }
                .onChange(of: terminalAppearance.fontSize) { _, _ in
                    synchronizeSession(for: proxy.size)
                }
                .onChange(of: terminalAppearance.fontFamily) { _, _ in
                    synchronizeSession(for: proxy.size)
                }
                .onChange(of: terminalAppearance.lineSpacing) { _, _ in
                    synchronizeSession(for: proxy.size)
                }
        }
        .background(Color.clear)
    }

    private func synchronizeSession(for size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        let horizontalInset: CGFloat = 32
        let verticalInset: CGFloat = 32
        let columns = UInt16(max(2, min(512, Int((size.width - horizontalInset) / terminalAppearance.characterWidth))))
        let rows = UInt16(max(2, min(256, Int((size.height - verticalInset) / terminalAppearance.lineHeight))))
        session.resize(columns: columns, rows: rows)
        session.start()
    }
}

private struct TerminalBackdropView: NSViewRepresentable {
    @ObservedObject var appearance: TerminalAppearance

    func makeNSView(context: Context) -> TerminalBackdropNSView {
        let view = TerminalBackdropNSView()
        view.update(appearance: appearance)
        return view
    }

    func updateNSView(_ nsView: TerminalBackdropNSView, context: Context) {
        nsView.update(appearance: appearance)
    }
}

private final class TerminalBackdropNSView: NSView {
    private let visualEffectView = NSVisualEffectView()
    private let colorView = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        colorView.wantsLayer = true
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .inactive
        addSubview(visualEffectView)
        addSubview(colorView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        visualEffectView.frame = bounds
        colorView.frame = bounds
    }

    func update(appearance: TerminalAppearance) {
        let background = appearance.theme.appKitBackground
            .withAlphaComponent(CGFloat(appearance.backgroundOpacity))
        colorView.layer?.backgroundColor = background.cgColor

        if appearance.backgroundBlur <= 0.01 {
            visualEffectView.state = .inactive
            visualEffectView.alphaValue = 0
        } else {
            visualEffectView.state = .active
            // AppKit exposes blur as native materials rather than a raw radius.
            visualEffectView.material = material(for: appearance.backgroundBlur)
            visualEffectView.alphaValue = min(1, max(0.18, appearance.backgroundBlur / 18))
        }
    }

    private func material(for blur: Double) -> NSVisualEffectView.Material {
        switch blur {
        case 0..<6: return .underWindowBackground
        case 6..<12: return .hudWindow
        case 12..<18: return .popover
        default: return .sidebar
        }
    }
}

private struct TerminalOutputView: NSViewRepresentable {
    @ObservedObject var session: TerminalSession
    @ObservedObject var appearance: TerminalAppearance
    let isFocusedPane: Bool
    let onFocus: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.scrollerStyle = .overlay
        scrollView.backgroundColor = .clear

        let textView = TerminalTextView()
        textView.wantsLayer = true
        textView.layer?.backgroundColor = NSColor.clear.cgColor
        textView.session = session
        textView.terminalAppearance = appearance
        textView.isFocusedPane = isFocusedPane
        textView.onFocus = onFocus
        textView.configure()
        scrollView.documentView = textView

        if isFocusedPane {
            DispatchQueue.main.async {
                textView.focus()
            }
        }
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? TerminalTextView else { return }
        textView.session = session
        textView.terminalAppearance = appearance
        textView.onFocus = onFocus
        textView.updateFocusState(isFocusedPane)
        textView.updateAppearance()
        textView.updateContent()

        if isFocusedPane,
           nsView.window?.firstResponder !== textView,
           nsView.window?.firstResponder == nsView.window?.contentView {
            DispatchQueue.main.async {
                textView.focus()
            }
        }

        if isFocusedPane, context.coordinator.lastFocusRevision != session.focusRevision {
            context.coordinator.lastFocusRevision = session.focusRevision
            DispatchQueue.main.async {
                textView.focus()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var lastFocusRevision = -1
    }
}

@MainActor
private final class TerminalTextView: NSTextView {
    weak var session: TerminalSession?
    weak var terminalAppearance: TerminalAppearance?
    var onFocus: (() -> Void)?
    private var lastDisplayRevision: UInt64 = 0
    private var lastFontFamily = ""
    private var lastFontSize: Double = 0
    private var lastLineSpacing: Double = 0
    private var lastTheme: TerminalTheme?
    private var lastCursorBlinkOn: Bool?
    private var lastCursorBlinkEnabled: Bool?
    private var lastFocusState: Bool?
    private var lastTerminalColumns: UInt16?
    private var lastTerminalRows: UInt16?
    private var cachedANSIColors: [NSColor] = []
    private var cursorBlinkTimer: Timer?
    private var windowKeyObserver: NSObjectProtocol?
    private var cursorBlinkOn = true
    private var cursorRanges: [CursorRange] = []

    private struct CursorRange {
        let range: NSRange
        let baseAttributes: [NSAttributedString.Key: Any]
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        // The terminal buffer owns cursor rendering and blinking.
    }

    func configure() {
        isEditable = false
        isSelectable = true
        isRichText = true
        allowsUndo = false
        usesFontPanel = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        insertionPointColor = .clear
        drawsBackground = false
        backgroundColor = .clear
        textContainerInset = NSSize(width: 14, height: 14)
        textContainer?.lineFragmentPadding = 0
        textContainer?.lineBreakMode = .byCharWrapping
        textContainer?.widthTracksTextView = false
        isVerticallyResizable = true
        isHorizontallyResizable = false
        minSize = NSSize(width: 0, height: 0)
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        autoresizingMask = [.width]
        updateAppearance()
        updateContent()
    }

    func focus() {
        guard let window, window.isVisible else { return }
        if window.firstResponder !== self {
            _ = window.makeFirstResponder(self)
        }
    }

    func updateAppearance() {
        guard let terminalAppearance else { return }
        let familyChanged = lastFontFamily != terminalAppearance.fontFamily
        let sizeChanged = lastFontSize != terminalAppearance.fontSize
        let lineSpacingChanged = lastLineSpacing != terminalAppearance.lineSpacing
        let themeChanged = lastTheme != terminalAppearance.theme
        guard familyChanged || sizeChanged || lineSpacingChanged || themeChanged else { return }

        lastFontFamily = terminalAppearance.fontFamily
        lastFontSize = terminalAppearance.fontSize
        lastLineSpacing = terminalAppearance.lineSpacing
        lastTheme = terminalAppearance.theme
        cachedANSIColors = terminalAppearance.theme.appKitANSIColors
        typingAttributes = [.font: terminalAppearance.font(ofSize: CGFloat(terminalAppearance.fontSize))]
        lastDisplayRevision = 0
        cursorRanges = []
        lastCursorBlinkOn = nil
        lastCursorBlinkEnabled = nil
        updateContent()
    }

    func updateContent() {
        guard let session, let terminalAppearance else { return }
        let contentChanged = lastDisplayRevision != session.displayRevision
        let fontChanged = lastFontSize != terminalAppearance.fontSize
            || lastFontFamily != terminalAppearance.fontFamily
            || lastLineSpacing != terminalAppearance.lineSpacing
        let blinkSettingChanged = lastCursorBlinkEnabled != terminalAppearance.cursorBlinkEnabled
        let blinkChanged = lastCursorBlinkOn != cursorBlinkOn
        let focusChanged = lastFocusState != isFocusedPane
        guard contentChanged || fontChanged || blinkSettingChanged || blinkChanged || focusChanged else { return }

        if contentChanged || fontChanged || blinkSettingChanged || focusChanged {
            cursorBlinkOn = true
        }

        if contentChanged || fontChanged {
            let shouldFollowOutput = isNearBottom
            let rendered = NSMutableAttributedString()
            var updatedCursorRanges: [CursorRange] = []

            for run in session.displayRuns {
                var attributes: [NSAttributedString.Key: Any] = [
                    .font: terminalAppearance.font(
                        ofSize: CGFloat(terminalAppearance.fontSize),
                        bold: run.style.bold
                    ),
                    .foregroundColor: nsColor(
                        for: run.style.inverse ? run.style.background : run.style.foreground,
                        fallback: terminalAppearance.theme.appKitForeground
                    ),
                    .backgroundColor: nsColor(
                        for: run.style.inverse ? run.style.foreground : run.style.background,
                        fallback: run.style.inverse ? terminalAppearance.theme.appKitForeground : .clear
                    )
                ]
                let paragraphStyle = NSMutableParagraphStyle()
                // Keep glyph line boxes at the font's native height. The
                // preference adds space after terminal rows instead of
                // stretching the current row.
                paragraphStyle.lineSpacing = 0
                paragraphStyle.paragraphSpacing = CGFloat(terminalAppearance.lineSpacing)
                paragraphStyle.minimumLineHeight = terminalAppearance.fontLineHeight
                paragraphStyle.maximumLineHeight = terminalAppearance.fontLineHeight
                attributes[.paragraphStyle] = paragraphStyle
                if run.style.underline {
                    attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                }
                if run.style.dim {
                    let foreground = (attributes[.foregroundColor] as? NSColor) ?? terminalAppearance.theme.appKitForeground
                    attributes[.foregroundColor] = foreground.withAlphaComponent(0.62)
                }

                let range = NSRange(location: rendered.length, length: run.text.utf16.count)
                rendered.append(NSAttributedString(string: run.text, attributes: attributes))
                if run.isCursor, range.length > 0 {
                    updatedCursorRanges.append(CursorRange(range: range, baseAttributes: attributes))
                }
            }

            textStorage?.setAttributedString(rendered)
            cursorRanges = updatedCursorRanges
            updateCursorAttributes()
            updateDocumentFrame()
            if shouldFollowOutput {
                scrollToEndOfDocument(nil)
            }
        } else if blinkChanged || blinkSettingChanged {
            // Blinking only changes the cursor character. Avoid relaying out
            // the entire scrollback buffer for every blink tick.
            updateCursorAttributes()
        }

        lastDisplayRevision = session.displayRevision
        lastFontFamily = terminalAppearance.fontFamily
        lastFontSize = terminalAppearance.fontSize
        lastLineSpacing = terminalAppearance.lineSpacing
        lastCursorBlinkOn = cursorBlinkOn
        lastCursorBlinkEnabled = terminalAppearance.cursorBlinkEnabled
        lastFocusState = isFocusedPane
    }

    var isFocusedPane = true

    func updateFocusState(_ focused: Bool) {
        guard isFocusedPane != focused else {
            if lastFocusState == nil { updateContent() }
            return
        }
        isFocusedPane = focused
        cursorBlinkOn = true
        updateContent()
    }

    private func updateCursorAttributes() {
        guard let textStorage, let terminalAppearance else { return }
        let cursorVisible = isFocusedPane && (!terminalAppearance.cursorBlinkEnabled || cursorBlinkOn)
        textStorage.beginEditing()
        for cursor in cursorRanges {
            if cursorVisible {
                textStorage.addAttributes([
                    .foregroundColor: terminalAppearance.theme.appKitBackground,
                    .backgroundColor: terminalAppearance.theme.appKitCursor
                ], range: cursor.range)
            } else {
                textStorage.setAttributes(cursor.baseAttributes, range: cursor.range)
            }
        }
        textStorage.endEditing()
        lastCursorBlinkOn = cursorBlinkOn
        lastCursorBlinkEnabled = terminalAppearance.cursorBlinkEnabled
        setNeedsDisplay(bounds)
    }

    private var isNearBottom: Bool {
        guard let scrollView = enclosingScrollView else { return true }
        let visibleMaxY = NSMaxY(scrollView.contentView.bounds)
        let documentMaxY = NSMaxY(scrollView.documentView?.bounds ?? .zero)
        return documentMaxY - visibleMaxY < 24
    }

    private func updateDocumentFrame() {
        guard let scrollView = enclosingScrollView,
              let textContainer,
              let layoutManager else { return }

        let width = max(scrollView.contentView.bounds.width, 1)
        textContainer.containerSize = NSSize(
            width: max(width - textContainerInset.width * 2, 1),
            height: CGFloat.greatestFiniteMagnitude
        )
        textContainer.widthTracksTextView = false
        layoutManager.ensureLayout(for: textContainer)
        let usedHeight = layoutManager.usedRect(for: textContainer).height
        let height = max(scrollView.contentView.bounds.height, usedHeight + textContainerInset.height * 2)
        frame = NSRect(x: 0, y: 0, width: width, height: height)
        resizeSessionToViewport()
    }

    private func resizeSessionToViewport() {
        guard let session, let terminalAppearance, let scrollView = enclosingScrollView else { return }
        let viewport = scrollView.contentView.bounds.size
        guard viewport.width > 1, viewport.height > 1 else { return }

        let columns = UInt16(max(
            2,
            min(512, Int((viewport.width - textContainerInset.width * 2) / terminalAppearance.characterWidth))
        ))
        let rows = UInt16(max(
            2,
            min(256, Int((viewport.height - textContainerInset.height * 2) / terminalAppearance.lineHeight))
        ))
        guard columns != lastTerminalColumns || rows != lastTerminalRows else { return }
        lastTerminalColumns = columns
        lastTerminalRows = rows
        session.resize(columns: columns, rows: rows)
    }

    override func layout() {
        super.layout()
        resizeSessionToViewport()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        cursorBlinkTimer?.invalidate()
        cursorBlinkTimer = nil
        if let windowKeyObserver {
            NotificationCenter.default.removeObserver(windowKeyObserver)
            self.windowKeyObserver = nil
        }
        if window != nil {
            let timer = Timer(timeInterval: 0.55, target: self, selector: #selector(toggleCursorBlink), userInfo: nil, repeats: true)
            cursorBlinkTimer = timer
            RunLoop.main.add(timer, forMode: .common)

            windowKeyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    if self?.isFocusedPane == true {
                        self?.focus()
                    }
                }
            }
        }
        DispatchQueue.main.async { [weak self] in
            if self?.isFocusedPane == true {
                self?.focus()
            }
            self?.updateDocumentFrame()
        }
    }

    @objc private func toggleCursorBlink() {
        guard isFocusedPane else { return }
        guard terminalAppearance?.cursorBlinkEnabled == true else {
            if !cursorBlinkOn {
                cursorBlinkOn = true
                updateContent()
            }
            return
        }
        cursorBlinkOn.toggle()
        updateContent()
    }

    override func mouseDown(with event: NSEvent) {
        onFocus?()
        focus()
        super.mouseDown(with: event)
    }

    override func paste(_ sender: Any?) {
        pasteClipboardContents()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }

        switch event.keyCode {
        case 8 where selectedRange().length > 0: // Cmd-C
            copy(nil)
            return true
        case 9: // Cmd-V and Cmd-Shift-V
            pasteClipboardContents()
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        if let text = insertString as? String {
            session?.send(text)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard let session else {
            super.keyDown(with: event)
            return
        }

        if event.modifierFlags.contains(.command) {
            if event.keyCode == 9 {
                pasteClipboardContents()
            } else {
                super.keyDown(with: event)
            }
            return
        }

        if event.modifierFlags.contains(.control),
           let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first {
            let value = scalar.value
            if value == 0x20 {
                session.send("\0")
                return
            }
            if (0x40...0x7F).contains(value), let controlScalar = UnicodeScalar(value & 0x1F) {
                session.send(String(controlScalar))
                return
            }
        }

        if let sequence = escapeSequence(for: event) {
            session.send(sequence)
        } else if event.modifierFlags.contains(.option),
                  let characters = event.charactersIgnoringModifiers,
                  !characters.isEmpty {
            session.send("\u{1B}" + characters)
        } else {
            // Let AppKit's text system handle composed characters and IME input.
            interpretKeyEvents([event])
        }
    }

    private func pasteClipboardContents() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        session?.paste(text)
    }

    private func escapeSequence(for event: NSEvent) -> String? {
        let option = event.modifierFlags.contains(.option)
        switch event.keyCode {
        case 36, 76: return "\r"
        case 48: return event.modifierFlags.contains(.shift) ? "\u{1B}[Z" : "\t"
        case 51: return "\u{7F}"
        case 53: return "\u{1B}"
        case 114: return "\u{1B}[2~"
        case 117: return "\u{1B}[3~"
        case 123: return option ? "\u{1B}b" : "\u{1B}[D"
        case 124: return option ? "\u{1B}f" : "\u{1B}[C"
        case 125: return "\u{1B}[B"
        case 126: return "\u{1B}[A"
        case 115: return "\u{1B}[H"
        case 119: return "\u{1B}[F"
        case 116: return "\u{1B}[5~"
        case 121: return "\u{1B}[6~"
        default: return nil
        }
    }

    private func nsColor(for color: TerminalColor, fallback: NSColor) -> NSColor {
        switch color {
        case .default:
            return fallback
        case .rgb(let red, let green, let blue):
            return NSColor(
                calibratedRed: CGFloat(red) / 255,
                green: CGFloat(green) / 255,
                blue: CGFloat(blue) / 255,
                alpha: 1
            )
        case .ansi(let index):
            return ansiColor(index)
        }
    }

    private func ansiColor(_ index: Int) -> NSColor {
        if cachedANSIColors.indices.contains(index) {
            return cachedANSIColors[index]
        }
        let palette: [NSColor] = [
            NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.12, alpha: 1),
            NSColor(calibratedRed: 0.92, green: 0.28, blue: 0.28, alpha: 1),
            NSColor(calibratedRed: 0.34, green: 0.78, blue: 0.42, alpha: 1),
            NSColor(calibratedRed: 0.92, green: 0.72, blue: 0.28, alpha: 1),
            NSColor(calibratedRed: 0.36, green: 0.60, blue: 0.96, alpha: 1),
            NSColor(calibratedRed: 0.72, green: 0.46, blue: 0.86, alpha: 1),
            NSColor(calibratedRed: 0.28, green: 0.78, blue: 0.78, alpha: 1),
            NSColor(calibratedRed: 0.86, green: 0.86, blue: 0.86, alpha: 1),
            NSColor(calibratedRed: 0.40, green: 0.40, blue: 0.40, alpha: 1),
            NSColor(calibratedRed: 1.00, green: 0.40, blue: 0.40, alpha: 1),
            NSColor(calibratedRed: 0.46, green: 0.92, blue: 0.54, alpha: 1),
            NSColor(calibratedRed: 1.00, green: 0.82, blue: 0.38, alpha: 1),
            NSColor(calibratedRed: 0.52, green: 0.70, blue: 1.00, alpha: 1),
            NSColor(calibratedRed: 0.86, green: 0.58, blue: 1.00, alpha: 1),
            NSColor(calibratedRed: 0.38, green: 0.92, blue: 0.92, alpha: 1),
            NSColor.white
        ]
        if index < palette.count { return palette[max(index, 0)] }
        if index >= 232 && index <= 255 {
            let value = CGFloat(8 + (index - 232) * 10) / 255
            return NSColor(calibratedRed: value, green: value, blue: value, alpha: 1)
        }
        let colorIndex = max(0, min(215, index - 16))
        let red = colorIndex / 36
        let green = (colorIndex / 6) % 6
        let blue = colorIndex % 6
        func channel(_ value: Int) -> CGFloat {
            value == 0 ? 0 : CGFloat(55 + value * 40) / 255
        }
        return NSColor(calibratedRed: channel(red), green: channel(green), blue: channel(blue), alpha: 1)
    }
}
