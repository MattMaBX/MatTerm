import Foundation
import GhosttyVt

/// libghostty-vt owns the terminal parser, screen state, scrollback, modes and
/// input encoders. This adapter only translates its render snapshot into the
/// cell model consumed by MatTerm's existing AppKit view.
final class GhosttyTerminalEngine {
    private var terminal: GhosttyTerminal?
    private var renderState: GhosttyRenderState?
    private var rowIterator: GhosttyRenderStateRowIterator?
    private var rowCells: GhosttyRenderStateRowCells?
    private var keyEncoder: GhosttyKeyEncoder?
    private var keyEvent: GhosttyKeyEvent?
    private var mouseEncoder: GhosttyMouseEncoder?
    private var mouseEvent: GhosttyMouseEvent?
    private var pendingPTYOutput = Data()
    private var configuredColors: TerminalColorConfiguration?
    private var cachedSnapshot: TerminalGridSnapshot?
    private var viewportScrollPending = false

    private static let writePTYCallback: GhosttyTerminalWritePtyFn = {
        _, userdata, bytes, length in
        guard let userdata, let bytes, length > 0 else { return }
        let engine = Unmanaged<GhosttyTerminalEngine>
            .fromOpaque(userdata)
            .takeUnretainedValue()
        engine.pendingPTYOutput.append(bytes, count: length)
    }

    init(columns: UInt16, rows: UInt16) {
        var terminal: GhosttyTerminal?
        guard isSuccess(ghostty_terminal_new(nil, &terminal, columns, rows)),
              let terminal else {
            return
        }

        var renderState: GhosttyRenderState?
        var rowIterator: GhosttyRenderStateRowIterator?
        var rowCells: GhosttyRenderStateRowCells?
        var keyEncoder: GhosttyKeyEncoder?
        var keyEvent: GhosttyKeyEvent?
        var mouseEncoder: GhosttyMouseEncoder?
        var mouseEvent: GhosttyMouseEvent?
        guard isSuccess(ghostty_render_state_new(nil, &renderState)),
              isSuccess(ghostty_render_state_row_iterator_new(nil, &rowIterator)),
              isSuccess(ghostty_render_state_row_cells_new(nil, &rowCells)),
              isSuccess(ghostty_key_encoder_new(nil, &keyEncoder)),
              isSuccess(ghostty_key_event_new(nil, &keyEvent)),
              isSuccess(ghostty_mouse_encoder_new(nil, &mouseEncoder)),
              isSuccess(ghostty_mouse_event_new(nil, &mouseEvent)) else {
            ghostty_terminal_free(terminal)
            return
        }

        self.terminal = terminal
        self.renderState = renderState
        self.rowIterator = rowIterator
        self.rowCells = rowCells
        self.keyEncoder = keyEncoder
        self.keyEvent = keyEvent
        self.mouseEncoder = mouseEncoder
        self.mouseEvent = mouseEvent
        configureCallbacks()
    }

    deinit {
        if let mouseEvent { ghostty_mouse_event_free(mouseEvent) }
        if let mouseEncoder { ghostty_mouse_encoder_free(mouseEncoder) }
        if let keyEvent { ghostty_key_event_free(keyEvent) }
        if let keyEncoder { ghostty_key_encoder_free(keyEncoder) }
        if let rowCells { ghostty_render_state_row_cells_free(rowCells) }
        if let rowIterator { ghostty_render_state_row_iterator_free(rowIterator) }
        if let renderState { ghostty_render_state_free(renderState) }
        if let terminal { ghostty_terminal_free(terminal) }
    }

    var isReady: Bool { terminal != nil && renderState != nil && rowIterator != nil && rowCells != nil }

    func write(_ data: Data) {
        guard let terminal, !data.isEmpty else { return }
        viewportScrollPending = false
        data.withUnsafeBytes { rawBuffer in
            guard let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
            ghostty_terminal_vt_write(terminal, bytes, data.count)
        }
    }

    func drainPTYOutput() -> Data {
        guard !pendingPTYOutput.isEmpty else { return Data() }
        let result = pendingPTYOutput
        pendingPTYOutput.removeAll(keepingCapacity: true)
        return result
    }

    func encodeFocusEvent(focused: Bool) -> Data? {
        var buffer = [CChar](repeating: 0, count: 8)
        var written = 0
        let result = buffer.withUnsafeMutableBufferPointer { buffer in
            ghostty_focus_encode(
                focused ? GHOSTTY_FOCUS_GAINED : GHOSTTY_FOCUS_LOST,
                buffer.baseAddress,
                buffer.count,
                &written
            )
        }
        guard isSuccess(result), written > 0 else { return nil }
        return Data(buffer.prefix(written).map { UInt8(bitPattern: $0) })
    }

    func encodePaste(_ text: String) -> Data? {
        let inputBytes = Array(text.utf8)
        guard !inputBytes.isEmpty else { return Data() }

        var queryInput = inputBytes.map { CChar(bitPattern: $0) }
        var required = 0
        let queryResult = queryInput.withUnsafeMutableBufferPointer { input in
            ghostty_paste_encode(
                input.baseAddress,
                input.count,
                bracketedPasteEnabled,
                nil,
                0,
                &required
            )
        }
        guard queryResult.rawValue == GHOSTTY_OUT_OF_SPACE.rawValue, required > 0 else {
            return nil
        }

        var output = [CChar](repeating: 0, count: required)
        var encodeInput = inputBytes.map { CChar(bitPattern: $0) }
        var written = 0
        let result = encodeInput.withUnsafeMutableBufferPointer { input in
            output.withUnsafeMutableBufferPointer { output in
                ghostty_paste_encode(
                    input.baseAddress,
                    input.count,
                    bracketedPasteEnabled,
                    output.baseAddress,
                    output.count,
                    &written
                )
            }
        }
        guard isSuccess(result), written > 0 else { return nil }
        return Data(output.prefix(written).map { UInt8(bitPattern: $0) })
    }

    func resize(columns: UInt16, rows: UInt16, cellWidth: UInt32 = 0, cellHeight: UInt32 = 0) {
        guard let terminal else { return }
        viewportScrollPending = false
        _ = ghostty_terminal_resize(terminal, columns, rows, cellWidth, cellHeight)
        cachedSnapshot = nil
    }

    func reset() {
        if let terminal { ghostty_terminal_reset(terminal) }
        viewportScrollPending = false
        cachedSnapshot = nil
    }

    @discardableResult
    func configureScrollback(maxLines: Int) -> Bool {
        guard let terminal, maxLines >= 0 else { return false }
        // Ghostty applies the byte and line limits together. Its default byte
        // limit can be reached long before the user-configured row count, so
        // remove it and let the exposed row limit be the sole constraint.
        guard isSuccess(ghostty_terminal_set(
            terminal,
            GhosttyTerminalOption(rawValue: 27),
            nil
        )) else { return false }
        var lineLimit = UInt(maxLines)
        let result = withUnsafePointer(to: &lineLimit) { pointer in
            ghostty_terminal_set(
                terminal,
                GhosttyTerminalOption(rawValue: 28),
                UnsafeRawPointer(pointer)
            )
        }
        guard isSuccess(result) else { return false }
        // Lowering the limit can prune historical pages immediately.
        viewportScrollPending = false
        cachedSnapshot = nil
        return true
    }

    @discardableResult
    func setSelection(
        startColumn: Int,
        startRow: Int,
        endColumn: Int,
        endRow: Int,
        rectangle: Bool = false
    ) -> Bool {
        guard let terminal,
              let start = gridReference(column: startColumn, row: startRow),
              let end = gridReference(column: endColumn, row: endRow) else {
            return false
        }

        var selection = GhosttySelection()
        selection.size = MemoryLayout<GhosttySelection>.size
        selection.start = start
        selection.end = end
        selection.rectangle = rectangle
        let result = withUnsafePointer(to: &selection) { pointer in
            ghostty_terminal_set(
                terminal,
                GhosttyTerminalOption(rawValue: 21),
                UnsafeRawPointer(pointer)
            )
        }
        guard isSuccess(result) else { return false }
        cachedSnapshot = nil
        viewportScrollPending = false
        return true
    }

    func clearSelection() {
        guard let terminal else { return }
        _ = ghostty_terminal_set(terminal, GhosttyTerminalOption(rawValue: 21), nil)
        cachedSnapshot = nil
    }

    func selectedText() -> String? {
        guard let terminal else { return nil }

        var selection = GhosttySelection()
        selection.size = MemoryLayout<GhosttySelection>.size
        guard isSuccess(ghostty_terminal_get(
            terminal,
            GhosttyTerminalData(rawValue: 31),
            &selection
        )) else { return nil }

        var options = GhosttyTerminalSelectionFormatOptions()
        options.size = MemoryLayout<GhosttyTerminalSelectionFormatOptions>.size
        options.emit = GhosttyFormatterFormat(rawValue: 0)
        options.unwrap = true
        options.trim = true
        options.selection = nil

        var output: UnsafeMutablePointer<UInt8>?
        var length = 0
        let result = ghostty_terminal_selection_format_alloc(
            terminal,
            nil,
            options,
            &output,
            &length
        )
        guard isSuccess(result), let output, length > 0 else { return nil }
        let text = String(decoding: UnsafeBufferPointer(start: output, count: length), as: UTF8.self)
        ghostty_free(nil, output, length)
        return text
    }

    private func gridReference(column: Int, row: Int) -> GhosttyGridRef? {
        guard let terminal else { return nil }
        var point = GhosttyPoint(
            tag: GhosttyPointTag(rawValue: 2),
            value: .init()
        )
        point.value.coordinate = GhosttyPointCoordinate(
            x: UInt16(clamping: max(0, column)),
            y: UInt32(clamping: max(0, row))
        )
        var reference = GhosttyGridRef()
        reference.size = MemoryLayout<GhosttyGridRef>.size
        guard isSuccess(ghostty_terminal_grid_ref(terminal, point, &reference)) else {
            return nil
        }
        return reference
    }

    func encodeKey(
        keyCode: UInt16,
        modifiers: UInt16,
        optionAsAlt: Bool,
        repeatEvent: Bool = false
    ) -> Data? {
        guard let terminal, let keyEncoder, let keyEvent,
              let key = key(for: keyCode) else { return nil }

        ghostty_key_encoder_setopt_from_terminal(keyEncoder, terminal)
        var option = GhosttyOptionAsAlt(rawValue: optionAsAlt ? 1 : 0)
        withUnsafePointer(to: &option) { pointer in
            ghostty_key_encoder_setopt(
                keyEncoder,
                GhosttyKeyEncoderOption(rawValue: 6),
                UnsafeRawPointer(pointer)
            )
        }
        ghostty_key_event_set_action(
            keyEvent,
            GhosttyKeyAction(rawValue: repeatEvent ? 2 : 1)
        )
        ghostty_key_event_set_key(keyEvent, key)
        ghostty_key_event_set_mods(keyEvent, GhosttyMods(modifiers))

        var buffer = [CChar](repeating: 0, count: 256)
        var written = 0
        let result = buffer.withUnsafeMutableBufferPointer { buffer in
            ghostty_key_encoder_encode(
                keyEncoder,
                keyEvent,
                buffer.baseAddress,
                buffer.count,
                &written
            )
        }
        guard isSuccess(result), written > 0 else { return nil }
        return Data(buffer.prefix(written).map { UInt8(bitPattern: $0) })
    }

    func configureColors(_ configuration: TerminalColorConfiguration) {
        guard let terminal, configuration.palette.count == 256 else { return }
        configuredColors = configuration
        viewportScrollPending = false
        cachedSnapshot = nil

        var foreground = configuration.foreground
        var background = configuration.background
        var cursor = configuration.cursor
        withUnsafePointer(to: &foreground) { pointer in
            _ = ghostty_terminal_set(
                terminal,
                GhosttyTerminalOption(rawValue: 11),
                UnsafeRawPointer(pointer)
            )
        }
        withUnsafePointer(to: &background) { pointer in
            _ = ghostty_terminal_set(
                terminal,
                GhosttyTerminalOption(rawValue: 12),
                UnsafeRawPointer(pointer)
            )
        }
        withUnsafePointer(to: &cursor) { pointer in
            _ = ghostty_terminal_set(
                terminal,
                GhosttyTerminalOption(rawValue: 13),
                UnsafeRawPointer(pointer)
            )
        }
        configuration.palette.withUnsafeBufferPointer { palette in
            _ = ghostty_terminal_set(
                terminal,
                GhosttyTerminalOption(rawValue: 14),
                UnsafeRawPointer(palette.baseAddress!)
            )
        }
    }

    func encodeMouse(
        kind: TerminalMouseEventKind,
        button: Int,
        column: Int,
        row: Int,
        modifiers: UInt16,
        anyButtonPressed: Bool = false
    ) -> Data? {
        guard let terminal, let mouseEncoder, let mouseEvent else { return nil }
        ghostty_mouse_encoder_setopt_from_terminal(mouseEncoder, terminal)

        let width = max(2, Int(columns))
        let height = max(2, Int(rows))
        var size = GhosttyMouseEncoderSize(
            size: MemoryLayout<GhosttyMouseEncoderSize>.size,
            screen_width: UInt32(width),
            screen_height: UInt32(height),
            cell_width: 1,
            cell_height: 1,
            padding_top: 0,
            padding_bottom: 0,
            padding_right: 0,
            padding_left: 0
        )
        withUnsafePointer(to: &size) { pointer in
            ghostty_mouse_encoder_setopt(
                mouseEncoder,
                GhosttyMouseEncoderOption(rawValue: 2),
                UnsafeRawPointer(pointer)
            )
        }

        let isScroll = kind == .scrollUp || kind == .scrollDown
        let action: GhosttyMouseAction
        switch kind {
        case .press, .scrollUp, .scrollDown:
            action = GhosttyMouseAction(rawValue: 0)
        case .release:
            action = GhosttyMouseAction(rawValue: 1)
        case .motion:
            action = GhosttyMouseAction(rawValue: 2)
        }
        ghostty_mouse_event_set_action(mouseEvent, action)
        ghostty_mouse_event_set_mods(mouseEvent, GhosttyMods(modifiers))
        if !isScroll && kind == .motion && button < 0 {
            ghostty_mouse_event_clear_button(mouseEvent)
        } else {
            let rawButton: Int
            if isScroll {
                rawButton = kind == .scrollUp ? 4 : 5
            } else {
                rawButton = max(1, min(11, button + 1))
            }
            ghostty_mouse_event_set_button(mouseEvent, GhosttyMouseButton(rawValue: Int32(rawButton)))
        }
        var pressed = anyButtonPressed
        withUnsafePointer(to: &pressed) { pointer in
            ghostty_mouse_encoder_setopt(
                mouseEncoder,
                GhosttyMouseEncoderOption(rawValue: 3),
                UnsafeRawPointer(pointer)
            )
        }
        ghostty_mouse_event_set_position(
            mouseEvent,
            GhosttyMousePosition(
                x: Float(max(0, column - 1)) + 0.5,
                y: Float(max(0, row - 1)) + 0.5
            )
        )

        var buffer = [CChar](repeating: 0, count: 128)
        var written = 0
        let result = buffer.withUnsafeMutableBufferPointer { buffer in
            ghostty_mouse_encoder_encode(
                mouseEncoder,
                mouseEvent,
                buffer.baseAddress,
                buffer.count,
                &written
            )
        }
        guard isSuccess(result), written > 0 else { return nil }
        return Data(buffer.prefix(written).map { UInt8(bitPattern: $0) })
    }

    var columns: UInt16 { readTerminal(GhosttyTerminalData(rawValue: 1), defaultValue: 0) }
    var rows: UInt16 { readTerminal(GhosttyTerminalData(rawValue: 2), defaultValue: 0) }

    var applicationCursorKeys: Bool { mode(1) }
    var bracketedPasteEnabled: Bool { mode(2004) }
    var focusReporting: Bool { mode(1004) }
    var mouseTracking: TerminalMouseTracking {
        if mode(1003) { return .anyMotion }
        if mode(1002) { return .buttonMotion }
        if mode(1000) { return .normal }
        if mode(9) { return .x10 }
        return .off
    }
    var mouseEncoding: TerminalMouseEncoding {
        if mode(1006) { return .sgr }
        if mode(1005) { return .utf8 }
        if mode(1015) { return .urxvt }
        return .x10
    }
    var isAlternateScreen: Bool {
        guard let terminal else { return false }
        var screen = GhosttyTerminalScreen(rawValue: 0)
        let result = ghostty_terminal_get(terminal, GhosttyTerminalData(rawValue: 6), &screen)
        return isSuccess(result) && screen.rawValue == 1
    }

    var title: String? { readString(GhosttyTerminalData(rawValue: 12)) }
    var workingDirectory: String? { readString(GhosttyTerminalData(rawValue: 13)) }
    var scrollbackRows: Int {
        readTerminal(GhosttyTerminalData(rawValue: 15), defaultValue: 0)
    }
    var scrollbackMaximumLines: Int? {
        guard let terminal else { return nil }
        var value: UInt = 0
        guard isSuccess(ghostty_terminal_get(
            terminal,
            GhosttyTerminalData(rawValue: 35),
            &value
        )) else { return nil }
        return Int(exactly: value)
    }
    var scrollbackMaximumBytes: Int? {
        guard let terminal else { return nil }
        var value: UInt = 0
        guard isSuccess(ghostty_terminal_get(
            terminal,
            GhosttyTerminalData(rawValue: 34),
            &value
        )) else { return nil }
        return Int(exactly: value)
    }

    var visibleText: String {
        snapshot().lines.map { line in
            line.filter { !$0.isContinuation }.map(\.character).reduce(into: "") { result, character in
                result.append(character)
            }
        }.joined(separator: "\n")
    }

    func scrollViewport(delta: Int) {
        guard let terminal else { return }
        var behavior = GhosttyTerminalScrollViewport(
            tag: GhosttyTerminalScrollViewportTag(rawValue: 2), value: .init()
        )
        behavior.value.delta = Int(delta)
        ghostty_terminal_scroll_viewport(terminal, behavior)
        viewportScrollPending = true
    }

    func scrollViewport(row: Int) {
        guard let terminal else { return }
        var behavior = GhosttyTerminalScrollViewport(
            tag: GhosttyTerminalScrollViewportTag(rawValue: 3), value: .init()
        )
        behavior.value.row = max(0, row)
        ghostty_terminal_scroll_viewport(terminal, behavior)
        viewportScrollPending = true
    }

    func scrollToBottom() {
        guard let terminal else { return }
        let behavior = GhosttyTerminalScrollViewport(
            tag: GhosttyTerminalScrollViewportTag(rawValue: 1), value: .init()
        )
        ghostty_terminal_scroll_viewport(terminal, behavior)
        viewportScrollPending = false
    }

    func snapshot() -> TerminalGridSnapshot {
        guard let terminal, let renderState, let rowIterator,
              isReady else {
            return TerminalGridSnapshot(
                columns: Int(columns), rows: Int(rows), lines: [], screenTopIndex: 0,
                totalRows: Int(rows), cursorRow: 0, cursorColumn: 0, cursorVisible: true,
                isAlternateScreen: false,
                defaultForeground: .default,
                defaultBackground: .default,
                cursorColor: .default,
                palette: []
            )
        }

        guard isSuccess(ghostty_render_state_update(renderState, terminal)) else {
            return cachedSnapshot ?? TerminalGridSnapshot(
                columns: Int(columns), rows: Int(rows), lines: [], screenTopIndex: 0,
                totalRows: Int(rows), cursorRow: 0, cursorColumn: 0, cursorVisible: true,
                isAlternateScreen: false,
                defaultForeground: .default,
                defaultBackground: .default,
                cursorColor: .default,
                palette: []
            )
        }

        var columns: UInt16 = 0
        var rows: UInt16 = 0
        _ = ghostty_render_state_get(renderState, GhosttyRenderStateData(rawValue: 1), &columns)
        _ = ghostty_render_state_get(renderState, GhosttyRenderStateData(rawValue: 2), &rows)

        var dirty = GhosttyRenderStateDirty(rawValue: 0)
        _ = ghostty_render_state_get(renderState, GhosttyRenderStateData(rawValue: 3), &dirty)

        var scrollbar = GhosttyTerminalScrollbar()
        _ = ghostty_terminal_get(
            terminal,
            GhosttyTerminalData(rawValue: 9),
            &scrollbar
        )
        let viewportTop = Int(min(scrollbar.offset, UInt64(Int.max)))
        let totalRows = Int(min(scrollbar.total, UInt64(Int.max)))
        let cachedShapeMatches = cachedSnapshot?.columns == Int(columns)
            && cachedSnapshot?.rows == Int(rows)
            && cachedSnapshot?.lines.count == Int(rows)
            && cachedSnapshot?.lines.allSatisfy { $0.count == Int(columns) } == true
        let viewportChanged = cachedSnapshot?.screenTopIndex != viewportTop

        // A clean render state is the common path while the app is idle. Do
        // not allocate a 256-entry color buffer or query cursor state for it.
        if dirty.rawValue == GHOSTTY_RENDER_STATE_DIRTY_FALSE.rawValue,
           cachedShapeMatches,
           !viewportChanged,
           let cachedSnapshot {
            viewportScrollPending = false
            _ = ghostty_render_state_clean(renderState)
            return cachedSnapshot
        }

        let alternateScreen = isAlternateScreen
        let readAllRows = !cachedShapeMatches || dirty.rawValue == GHOSTTY_RENDER_STATE_DIRTY_FULL.rawValue || viewportChanged
        let viewportDelta = viewportTop - (cachedSnapshot?.screenTopIndex ?? viewportTop)
        let canShiftViewport = viewportScrollPending
            && dirty.rawValue == GHOSTTY_RENDER_STATE_DIRTY_FULL.rawValue
            && cachedShapeMatches
            && viewportChanged
            && abs(viewportDelta) < Int(rows)
            && cachedSnapshot?.totalRows == max(Int(rows), totalRows)
            && cachedSnapshot?.isAlternateScreen == alternateScreen
        viewportScrollPending = false

        var cursor = GhosttyRenderStateCursor()
        cursor.size = MemoryLayout<GhosttyRenderStateCursor>.size
        _ = ghostty_render_state_get(renderState, GhosttyRenderStateData(rawValue: 18), &cursor)

        let colors: (foreground: TerminalColor, background: TerminalColor, cursor: TerminalColor, palette: [TerminalColor])
        if canShiftViewport, let cachedSnapshot {
            // A scroll operation does not change terminal colors. Reusing the
            // prior values avoids reading and converting all 256 palette
            // entries for every row crossed by a trackpad gesture.
            colors = (
                foreground: cachedSnapshot.defaultForeground,
                background: cachedSnapshot.defaultBackground,
                cursor: cachedSnapshot.cursorColor,
                palette: cachedSnapshot.palette
            )
        } else {
            var backgroundRGB = GhosttyColorRgb(r: 0, g: 0, b: 0)
            var foregroundRGB = GhosttyColorRgb(r: 0, g: 0, b: 0)
            // Terminal getters include effective OSC 4/10/11/12 overrides.
            let backgroundResult = ghostty_terminal_get(
                terminal, GhosttyTerminalData(rawValue: 19), &backgroundRGB
            )
            let foregroundResult = ghostty_terminal_get(
                terminal, GhosttyTerminalData(rawValue: 18), &foregroundRGB
            )
            var paletteRGB = Array(
                repeating: GhosttyColorRgb(r: 0, g: 0, b: 0),
                count: 256
            )
            let paletteResult = paletteRGB.withUnsafeMutableBufferPointer { buffer in
                ghostty_terminal_get(
                    terminal,
                    GhosttyTerminalData(rawValue: 21),
                    buffer.baseAddress
                )
            }
            let foreground = isSuccess(foregroundResult)
                ? terminalColor(foregroundRGB)
                : (configuredColors.map { terminalColor($0.foreground) } ?? .default)
            let background = isSuccess(backgroundResult)
                ? terminalColor(backgroundRGB)
                : (configuredColors.map { terminalColor($0.background) } ?? .default)
            var cursorRGB = GhosttyColorRgb(r: 0, g: 0, b: 0)
            let cursor = isSuccess(ghostty_terminal_get(
                terminal, GhosttyTerminalData(rawValue: 20), &cursorRGB
            ))
                ? terminalColor(cursorRGB)
                : (configuredColors.map { terminalColor($0.cursor) } ?? foreground)
            let palette = isSuccess(paletteResult)
                ? paletteRGB.map(terminalColor)
                : (configuredColors?.palette.map(terminalColor) ?? [])
            colors = (foreground, background, cursor, palette)
        }

        let blankLine = Array(
            repeating: TerminalCell(character: " ", style: TerminalTextStyle()),
            count: Int(columns)
        )
        var rowsToRead = 0..<0
        var lines: [[TerminalCell]]
        if canShiftViewport, let cachedLines = cachedSnapshot?.lines {
            let shift = abs(viewportDelta)
            if viewportDelta > 0 {
                lines = Array(cachedLines.dropFirst(shift))
                lines.append(contentsOf: Array(repeating: blankLine, count: shift))
                rowsToRead = (Int(rows) - shift)..<Int(rows)
            } else {
                lines = Array(repeating: blankLine, count: shift)
                lines.append(contentsOf: Array(cachedLines.dropLast(shift)))
                rowsToRead = 0..<shift
            }
        } else if readAllRows {
            lines = Array(repeating: blankLine, count: Int(rows))
        } else {
            lines = cachedSnapshot?.lines ?? []
        }

        var iterator = rowIterator
        _ = ghostty_render_state_get(renderState, GhosttyRenderStateData(rawValue: 4), &iterator)
        if canShiftViewport {
            var rowIndex = 0
            while ghostty_render_state_row_iterator_next(rowIterator) {
                if rowsToRead.contains(rowIndex) {
                    readRow(rowIterator, into: &lines[rowIndex], columns: Int(columns))
                }
                rowIndex += 1
            }
        } else if readAllRows {
            var rowIndex = 0
            while ghostty_render_state_row_iterator_next(rowIterator) {
                guard rowIndex < lines.count else { break }
                readRow(rowIterator, into: &lines[rowIndex], columns: Int(columns))
                rowIndex += 1
            }
        } else {
            var dirtyRow: UInt16 = 0
            while ghostty_render_state_row_iterator_next_dirty(rowIterator, &dirtyRow) {
                let rowIndex = Int(dirtyRow)
                guard lines.indices.contains(rowIndex) else { continue }
                readRow(rowIterator, into: &lines[rowIndex], columns: Int(columns))
            }
        }
        _ = ghostty_render_state_clean(renderState)

        let snapshot = TerminalGridSnapshot(
            columns: Int(columns),
            rows: Int(rows),
            lines: lines,
            screenTopIndex: viewportTop,
            totalRows: max(Int(rows), totalRows),
            cursorRow: cursor.viewport_has_value ? viewportTop + Int(cursor.viewport_y) : 0,
            cursorColumn: cursor.viewport_has_value ? Int(cursor.viewport_x) : 0,
            cursorVisible: cursor.visible,
            isAlternateScreen: alternateScreen,
            defaultForeground: colors.foreground,
            defaultBackground: colors.background,
            cursorColor: colors.cursor,
            palette: colors.palette
        )
        cachedSnapshot = snapshot
        return snapshot
    }

    private func readRow(
        _ rowIterator: GhosttyRenderStateRowIterator,
        into line: inout [TerminalCell],
        columns: Int
    ) {
        guard let rowCells else { return }
        var cells = rowCells
        _ = ghostty_render_state_row_get(rowIterator, GhosttyRenderStateRowData(rawValue: 3), &cells)
        var column = 0
        while column < columns, ghostty_render_state_row_cells_next(cells) {
            guard column < line.count else { break }
            line[column] = readCell(cells)
            column += 1
        }
    }

    private func readCell(_ cells: GhosttyRenderStateRowCells) -> TerminalCell {
        var length: UInt32 = 0
        _ = ghostty_render_state_row_cells_get(cells, GhosttyRenderStateRowCellsData(rawValue: 3), &length)
        var codepoints = Array(repeating: UInt32(0), count: max(1, Int(length)))
        if length > 0 {
            codepoints.withUnsafeMutableBufferPointer { buffer in
                _ = ghostty_render_state_row_cells_get(
                    cells,
                    GhosttyRenderStateRowCellsData(rawValue: 4),
                    buffer.baseAddress
                )
            }
        }

        var scalars = String.UnicodeScalarView()
        for codepoint in codepoints.prefix(Int(length)) {
            if let scalar = Unicode.Scalar(codepoint) { scalars.append(scalar) }
        }
        let character = scalars.isEmpty ? " " : Character(String(scalars))

        var style = GhosttyStyle()
        style.size = MemoryLayout<GhosttyStyle>.size
        _ = ghostty_render_state_row_cells_get(cells, GhosttyRenderStateRowCellsData(rawValue: 2), &style)

        var resolvedForeground = GhosttyColorRgb(r: 0, g: 0, b: 0)
        var background = GhosttyColorRgb(r: 0, g: 0, b: 0)
        let foregroundResult = ghostty_render_state_row_cells_get(cells, GhosttyRenderStateRowCellsData(rawValue: 6), &resolvedForeground)
        let backgroundResult = ghostty_render_state_row_cells_get(cells, GhosttyRenderStateRowCellsData(rawValue: 5), &background)

        var wide = GhosttyCellWide(rawValue: 0)
        var rawCell: GhosttyCell = 0
        _ = ghostty_render_state_row_cells_get(cells, GhosttyRenderStateRowCellsData(rawValue: 1), &rawCell)
        _ = ghostty_cell_get(rawCell, GhosttyCellData(rawValue: 3), &wide)

        var selected = false
        _ = ghostty_render_state_row_cells_get(
            cells,
            GhosttyRenderStateRowCellsData(rawValue: 7),
            &selected
        )

        let cellForeground: TerminalColor
        switch style.fg_color.tag.rawValue {
        case GHOSTTY_STYLE_COLOR_PALETTE.rawValue:
            let index = Int(style.fg_color.value.palette)
            // Ghostty intentionally leaves bold brightening to the caller.
            let brightIndex = style.bold && index < 8 ? index + 8 : index
            cellForeground = .ansi(brightIndex)
        case GHOSTTY_STYLE_COLOR_RGB.rawValue:
            let color = style.fg_color.value.rgb
            cellForeground = .rgb(red: color.r, green: color.g, blue: color.b)
        default:
            cellForeground = isSuccess(foregroundResult)
                ? .rgb(red: resolvedForeground.r, green: resolvedForeground.g, blue: resolvedForeground.b)
                : .default
        }

        let cellBackground: TerminalColor
        if isSuccess(backgroundResult) {
            cellBackground = .rgb(red: background.r, green: background.g, blue: background.b)
        } else {
            switch style.bg_color.tag.rawValue {
            case GHOSTTY_STYLE_COLOR_PALETTE.rawValue:
                cellBackground = .ansi(Int(style.bg_color.value.palette))
            case GHOSTTY_STYLE_COLOR_RGB.rawValue:
                let color = style.bg_color.value.rgb
                cellBackground = .rgb(red: color.r, green: color.g, blue: color.b)
            default:
                cellBackground = .default
            }
        }

        return TerminalCell(
            character: character,
            style: TerminalTextStyle(
                foreground: cellForeground,
                background: cellBackground,
                bold: style.bold,
                dim: style.faint,
                italic: style.italic,
                underline: style.underline != 0,
                strikethrough: style.strikethrough,
                blink: style.blink,
                invisible: style.invisible,
                inverse: style.inverse
            ),
            isContinuation: wide.rawValue == 2 || wide.rawValue == 3,
            isSelected: selected
        )
    }

    private func terminalColor(_ color: GhosttyColorRgb) -> TerminalColor {
        .rgb(red: color.r, green: color.g, blue: color.b)
    }

    private func mode(_ value: UInt16) -> Bool {
        guard let terminal else { return false }
        var config = GhosttyTerminalModeConfig(mode: GhosttyMode(value), value: false)
        guard isSuccess(ghostty_terminal_get(terminal, GhosttyTerminalData(rawValue: 37), &config)) else { return false }
        return config.value
    }

    private func key(for keyCode: UInt16) -> GhosttyKey? {
        switch keyCode {
        case 36, 76: return GHOSTTY_KEY_ENTER
        case 48: return GHOSTTY_KEY_TAB
        case 51: return GHOSTTY_KEY_BACKSPACE
        case 53: return GHOSTTY_KEY_ESCAPE
        case 114: return GHOSTTY_KEY_INSERT
        case 117: return GHOSTTY_KEY_DELETE
        case 123: return GHOSTTY_KEY_ARROW_LEFT
        case 124: return GHOSTTY_KEY_ARROW_RIGHT
        case 125: return GHOSTTY_KEY_ARROW_DOWN
        case 126: return GHOSTTY_KEY_ARROW_UP
        case 115: return GHOSTTY_KEY_HOME
        case 119: return GHOSTTY_KEY_END
        case 116: return GHOSTTY_KEY_PAGE_UP
        case 121: return GHOSTTY_KEY_PAGE_DOWN
        case 122: return GHOSTTY_KEY_F1
        case 120: return GHOSTTY_KEY_F2
        case 99: return GHOSTTY_KEY_F3
        case 118: return GHOSTTY_KEY_F4
        case 96: return GHOSTTY_KEY_F5
        case 97: return GHOSTTY_KEY_F6
        case 98: return GHOSTTY_KEY_F7
        case 100: return GHOSTTY_KEY_F8
        case 101: return GHOSTTY_KEY_F9
        case 109: return GHOSTTY_KEY_F10
        case 103: return GHOSTTY_KEY_F11
        case 111: return GHOSTTY_KEY_F12
        case 105: return GHOSTTY_KEY_F13
        case 107: return GHOSTTY_KEY_F14
        case 113: return GHOSTTY_KEY_F15
        case 106: return GHOSTTY_KEY_F16
        case 64: return GHOSTTY_KEY_F17
        case 79: return GHOSTTY_KEY_F18
        case 80: return GHOSTTY_KEY_F19
        case 90: return GHOSTTY_KEY_F20
        default: return nil
        }
    }

    private func readString(_ data: GhosttyTerminalData) -> String? {
        guard let terminal else { return nil }
        var value = GhosttyString(ptr: nil, len: 0)
        guard isSuccess(ghostty_terminal_get(terminal, data, &value)),
              let ptr = value.ptr, value.len > 0 else { return nil }
        return String(decoding: UnsafeBufferPointer(start: ptr, count: value.len), as: UTF8.self)
    }

    private func configureCallbacks() {
        guard let terminal else { return }
        let userdata = Unmanaged.passUnretained(self).toOpaque()
        _ = ghostty_terminal_set(
            terminal,
            GhosttyTerminalOption(rawValue: 0),
            UnsafeRawPointer(userdata)
        )

        // Callback options are passed as the function pointer itself. Passing
        // the address of a local Swift variable would leave Ghostty holding a
        // pointer to the stack; tmux and full-screen applications exercise
        // query responses often enough to turn that into a delayed crash.
        let callback = unsafeBitCast(Self.writePTYCallback, to: UnsafeRawPointer.self)
        _ = ghostty_terminal_set(
            terminal,
            GhosttyTerminalOption(rawValue: 1),
            callback
        )
    }

    private func readTerminal<T>(_ data: GhosttyTerminalData, defaultValue: T) -> T {
        guard let terminal else { return defaultValue }
        var value = defaultValue
        _ = withUnsafeMutablePointer(to: &value) { pointer in
            ghostty_terminal_get(terminal, data, pointer)
        }
        return value
    }

    private func isSuccess(_ result: GhosttyResult) -> Bool { result.rawValue == 0 }
}
