@preconcurrency import AppKit
import SwiftUI
import GhosttyVt

struct TerminalView: View {
    @ObservedObject var session: TerminalSession
    let isFocusedPane: Bool
    let onFocus: () -> Void
    @EnvironmentObject private var terminalAppearance: TerminalAppearance
    @EnvironmentObject private var preferences: AppPreferences

    var body: some View {
        GeometryReader { proxy in
            TerminalOutputView(
                session: session,
                appearance: terminalAppearance,
                metaKeyEnabled: preferences.metaKeyEnabled,
                isFocusedPane: isFocusedPane,
                onFocus: onFocus
            )
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
        // Keep the PTY geometry identical to the renderer's cell origin. A
        // different inset here changes the advertised tmux width by several
        // columns and makes pane borders drift from the pixels on screen.
        let horizontalInset = terminalGridInset * 2
        let verticalInset = terminalGridInset * 2
        let columns = UInt16(max(2, min(512, Int((size.width - horizontalInset) / terminalAppearance.characterWidth))))
        let rows = UInt16(max(2, min(256, Int((size.height - verticalInset) / terminalAppearance.lineHeight))))
        session.configureColors(terminalAppearance.theme.ghosttyColorConfiguration)
        session.resize(columns: columns, rows: rows)
        session.start()
    }
}

struct TerminalBackdropView: NSViewRepresentable {
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

final class TerminalBackdropNSView: NSView {
    private let visualEffectView = NSVisualEffectView()
    private let colorView = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.isOpaque = false
        layer?.borderWidth = 0
        layer?.borderColor = NSColor.clear.cgColor
        colorView.wantsLayer = true
        colorView.layer?.isOpaque = false
        colorView.layer?.borderWidth = 0
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .inactive
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.isOpaque = false
        visualEffectView.layer?.borderWidth = 0
        addSubview(visualEffectView)
        addSubview(colorView, positioned: .above, relativeTo: visualEffectView)
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
        // Apply opacity to the theme color itself. This keeps every backdrop
        // surface in the same color space instead of fading an opaque layer.
        colorView.layer?.backgroundColor = appearance.effectiveBackgroundColor.cgColor
        colorView.alphaValue = 1

        if appearance.backgroundBlur <= 0.01 {
            visualEffectView.state = .inactive
            visualEffectView.alphaValue = 0
        } else {
            visualEffectView.state = .active
            // AppKit exposes blur as native materials rather than a raw radius.
            visualEffectView.material = material(for: appearance.backgroundBlur)
            // The material already contains a tint. A restrained alpha keeps
            // the desktop visible instead of stacking two opaque surfaces.
            let blurFraction = min(max(appearance.backgroundBlur / 24, 0), 1)
            visualEffectView.alphaValue = 0.08 + (blurFraction * 0.16)
            visualEffectView.appearance = NSAppearance(
                named: appearance.isDarkTheme ? .darkAqua : .aqua
            )
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

private let terminalGridInset = CGFloat(14)

private struct TerminalCellPosition: Equatable {
    let column: Int
    let row: Int
}

private struct ResolvedTerminalColors {
    let foreground: NSColor
    let background: NSColor
}

private final class TerminalScrollView: NSScrollView {
    func updateTerminalMouseMode() {
        guard let grid = documentView as? TerminalGridView,
              let session = grid.session else { return }
        let terminalMouseMode = session.mouseTracking != .off
            let alternateScreen = grid.snapshot?.isAlternateScreen ?? session.displayGrid.isAlternateScreen
        // Keep the native scroller present in normal primary-screen mode. It
        // remains disabled by AppKit when the document is no taller than the
        // viewport, but it must not disappear just because the current frame
        // has not observed the first scrollback row yet.
        hasVerticalScroller = !terminalMouseMode && !alternateScreen
        verticalScrollElasticity = terminalMouseMode || alternateScreen ? .none : .automatic
    }

    func passThroughScrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let grid = documentView as? TerminalGridView,
              let session = grid.session else {
            super.scrollWheel(with: event)
            return
        }
        if session.mouseTracking != .off {
            grid.handleScrollWheel(with: event)
        } else {
            passThroughScrollWheel(with: event)
        }
    }
}

private final class TerminalClipView: NSClipView {
    weak var terminalGridView: TerminalGridView?
    private var boundsObserver: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        installBoundsObserver()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        installBoundsObserver()
    }

    private func installBoundsObserver() {
        postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: self,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.terminalGridView?.scheduleNativeViewportUpdate()
            }
        }
    }

    deinit {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
    }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // The document can be shorter than the viewport (an empty shell or a
        // freshly-created alternate screen). Forward the whole pane to the
        // terminal responder so clicking an empty tmux pane still changes
        // focus and sends the correct viewport coordinates.
        guard bounds.contains(point), let terminalGridView else {
            return super.hitTest(point)
        }
        return terminalGridView
    }

    override func scrollWheel(with event: NSEvent) {
        guard let grid = terminalGridView, let session = grid.session else {
            super.scrollWheel(with: event)
            return
        }
        if session.mouseTracking != .off {
            grid.handleScrollWheel(with: event)
        } else {
            (enclosingScrollView as? TerminalScrollView)?.passThroughScrollWheel(with: event)
        }
    }

    override func viewBoundsChanged(_ notification: Notification) {
        super.viewBoundsChanged(notification)
    }
}

// acceptsMouseMovedEvents belongs to the window, not to an individual pane.
// A single coordinator keeps all tmux/Vim panes eligible for motion reports.
@MainActor
private final class TerminalMouseMotionCoordinator {
    static let shared = TerminalMouseMotionCoordinator()

    private let grids = NSHashTable<TerminalGridView>.weakObjects()

    func register(_ grid: TerminalGridView, in window: NSWindow) {
        grids.add(grid)
        update(window)
    }

    func unregister(_ grid: TerminalGridView, from window: NSWindow?) {
        grids.remove(grid)
        if let window { update(window) }
    }

    func update(_ grid: TerminalGridView) {
        guard let window = grid.window else { return }
        update(window)
    }

    private func update(_ window: NSWindow) {
        window.acceptsMouseMovedEvents = grids.allObjects.contains {
            $0.window === window && $0.session?.mouseTracking == .anyMotion
        }
    }
}

private struct TerminalOutputView: NSViewRepresentable {
    @ObservedObject var session: TerminalSession
    @ObservedObject var appearance: TerminalAppearance
    let metaKeyEnabled: Bool
    let isFocusedPane: Bool
    let onFocus: () -> Void

    func makeNSView(context: Context) -> TerminalScrollView {
        let scrollView = TerminalScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        // Keep the scrollback thumb visible while the pointer is over the
        // terminal content instead of relying on overlay-scroller discovery.
        scrollView.scrollerStyle = .legacy
        scrollView.backgroundColor = .clear
        scrollView.wantsLayer = true
        scrollView.layer?.borderWidth = 0
        scrollView.layer?.borderColor = NSColor.clear.cgColor

        let clipView = TerminalClipView(frame: .zero)
        clipView.drawsBackground = false
        scrollView.contentView = clipView

        let grid = TerminalGridView()
        grid.wantsLayer = true
        grid.layer?.backgroundColor = NSColor.clear.cgColor
        grid.session = session
        grid.terminalAppearance = appearance
        grid.metaKeyEnabled = metaKeyEnabled
        grid.isFocusedPane = isFocusedPane
        grid.onFocus = onFocus
        grid.configure()
        session.configureColors(appearance.theme.ghosttyColorConfiguration)
        clipView.terminalGridView = grid
        scrollView.documentView = grid
        scrollView.updateTerminalMouseMode()

        if isFocusedPane {
            DispatchQueue.main.async { grid.focus() }
        }
        return scrollView
    }

    func updateNSView(_ nsView: TerminalScrollView, context: Context) {
        guard let grid = nsView.documentView as? TerminalGridView else { return }
        grid.session = session
        grid.terminalAppearance = appearance
        grid.metaKeyEnabled = metaKeyEnabled
        grid.onFocus = onFocus
        session.configureColors(appearance.theme.ghosttyColorConfiguration)
        grid.updateFocusState(isFocusedPane)
        grid.updateAppearance()
        grid.updateMouseTracking()
        grid.updateContent()
        nsView.updateTerminalMouseMode()

        if isFocusedPane,
           nsView.window?.firstResponder !== grid,
           nsView.window?.firstResponder == nsView.window?.contentView {
            DispatchQueue.main.async { grid.focus() }
        }
        if isFocusedPane, context.coordinator.lastFocusRevision != session.focusRevision {
            context.coordinator.lastFocusRevision = session.focusRevision
            DispatchQueue.main.async { grid.focus() }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator { var lastFocusRevision = -1 }
}

/// Fixed-cell AppKit terminal renderer.
///
/// NSTextView is deliberately not used here. Its line breaking and layout
/// manager operate on paragraphs; terminal output is a mutable matrix. Drawing
/// each cell at `column * characterWidth` is what keeps tmux pane borders,
/// full-screen redraws and cursor coordinates stable.
@MainActor
private final class TerminalGridView: NSTextView {
    weak var session: TerminalSession?
    weak var terminalAppearance: TerminalAppearance?
    var onFocus: (() -> Void)?
    var metaKeyEnabled = true
    var isFocusedPane = true

    private(set) var snapshot: TerminalGridSnapshot?
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
    private var cachedPaletteColors: [NSColor] = []
    private var cachedNSColors: [TerminalColor: NSColor] = [:]
    private var cachedStyleColors: [TerminalTextStyle: ResolvedTerminalColors] = [:]
    private var synchronizingNativeViewport = false
    private var nativeViewportUpdateScheduled = false
    private var cursorBlinkTimer: Timer?
    private var windowKeyObserver: NSObjectProtocol?
    private var cursorBlinkOn = true
    private var lastMouseTracking: TerminalMouseTracking?
    private var pressedMouseButton: Int?
    private var selectionAnchor: TerminalCellPosition?
    private var selectionBase: TerminalCellPosition?
    private var selectionRectangle = false
    private weak var registeredWindow: NSWindow?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func configure() {
        // Keep NSTextView as the native input/accessibility host. Its text
        // system is not used for rendering; draw(_:) below owns every cell.
        isEditable = false
        isSelectable = true
        isRichText = false
        allowsUndo = false
        usesFontPanel = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        insertionPointColor = .clear
        drawsBackground = false
        backgroundColor = .clear
        textContainerInset = .zero
        textContainer?.lineFragmentPadding = 0
        textContainer?.widthTracksTextView = false
        isVerticallyResizable = false
        isHorizontallyResizable = false
        focusRingType = .none
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        updateAppearance()
        updateMouseTracking()
        updateContent()
    }

    func updateMouseTracking() {
        guard let session else { return }
        if lastMouseTracking != session.mouseTracking {
            lastMouseTracking = session.mouseTracking
            if session.mouseTracking == .off { pressedMouseButton = nil }
        }
        TerminalMouseMotionCoordinator.shared.update(self)
    }

    func focus() {
        guard let window, window.isVisible else { return }
        if window.firstResponder !== self { _ = window.makeFirstResponder(self) }
    }

    func updateAppearance() {
        guard let appearance = terminalAppearance else { return }
        let changed = lastFontFamily != appearance.fontFamily
            || lastFontSize != appearance.fontSize
            || lastLineSpacing != appearance.lineSpacing
            || lastTheme != appearance.theme
        guard changed else { return }
        lastFontFamily = appearance.fontFamily
        lastFontSize = appearance.fontSize
        lastLineSpacing = appearance.lineSpacing
        lastTheme = appearance.theme
        cachedANSIColors = appearance.theme.appKitANSIColors
        cachedPaletteColors.removeAll(keepingCapacity: true)
        cachedNSColors.removeAll(keepingCapacity: true)
        cachedStyleColors.removeAll(keepingCapacity: true)
        lastDisplayRevision = 0
        lastCursorBlinkOn = nil
        lastCursorBlinkEnabled = nil
        updateContent()
    }

    func updateContent() {
        guard let session, let appearance = terminalAppearance else { return }
        let contentChanged = lastDisplayRevision != session.displayRevision
        let fontChanged = lastFontSize != appearance.fontSize
            || lastFontFamily != appearance.fontFamily
            || lastLineSpacing != appearance.lineSpacing
        let blinkSettingChanged = lastCursorBlinkEnabled != appearance.cursorBlinkEnabled
        let blinkChanged = lastCursorBlinkOn != cursorBlinkOn
        let focusChanged = lastFocusState != isFocusedPane
        guard contentChanged || fontChanged || blinkSettingChanged || blinkChanged || focusChanged else { return }

        if contentChanged || fontChanged || blinkSettingChanged || focusChanged {
            cursorBlinkOn = true
        }
        // AppKit's scroll position and Ghostty's viewport are independent.
        // When output extends the buffer while the user is at the live end,
        // move both to the bottom before taking the render snapshot. Moving
        // only the document leaves Ghostty rendering the old viewport rows,
        // so the prompt and subsequent input appear below a scrollbar that
        // already claims to be at the bottom.
        let shouldFollowOutput = isAtBottom
        if contentChanged || fontChanged {
            var updatedSnapshot = session.displayGrid
            if shouldFollowOutput, !updatedSnapshot.isAlternateScreen {
                session.scrollToBottom()
                updatedSnapshot = session.displayGrid
            }
            snapshot = updatedSnapshot
            if let snapshot {
                updateRenderColors(snapshot)
            }
            updateDocumentFrame()
            synchronizeNativeViewport()
            invalidateVisibleTerminalArea()
            if snapshot?.isAlternateScreen == true {
                scrollDocumentToTop()
            } else if shouldFollowOutput {
                scrollDocumentToBottom()
            }
        } else if blinkChanged || blinkSettingChanged || focusChanged {
            invalidateVisibleTerminalArea()
        }

        lastDisplayRevision = session.displayRevision
        lastFontFamily = appearance.fontFamily
        lastFontSize = appearance.fontSize
        lastLineSpacing = appearance.lineSpacing
        lastCursorBlinkOn = cursorBlinkOn
        lastCursorBlinkEnabled = appearance.cursorBlinkEnabled
        lastFocusState = isFocusedPane
    }

    func updateFocusState(_ focused: Bool) {
        guard isFocusedPane != focused else {
            if lastFocusState == nil { updateContent() }
            return
        }
        isFocusedPane = focused
        cursorBlinkOn = true
        updateContent()
    }

    private var isAtBottom: Bool {
        guard let scrollView = enclosingScrollView else { return true }
        let clipView = scrollView.contentView
        let maxY = max(0, NSMaxY(bounds) - clipView.bounds.height)
        return clipView.bounds.minY >= maxY - 0.5
    }

    private func scrollDocumentToBottom() {
        guard let scrollView = enclosingScrollView else { return }
        let clipView = scrollView.contentView
        let maxY = max(0, NSMaxY(bounds) - clipView.bounds.height)
        var clipBounds = clipView.bounds
        clipBounds.origin = NSPoint(x: clipBounds.origin.x, y: maxY)
        clipView.bounds = clipBounds
        scrollView.reflectScrolledClipView(clipView)
    }

    private func scrollDocumentToTop() {
        guard let scrollView = enclosingScrollView else { return }
        let clipView = scrollView.contentView
        var clipBounds = clipView.bounds
        clipBounds.origin = NSPoint(x: clipBounds.origin.x, y: 0)
        clipView.bounds = clipBounds
        scrollView.reflectScrolledClipView(clipView)
    }

    func scheduleNativeViewportUpdate() {
        guard !nativeViewportUpdateScheduled else { return }
        nativeViewportUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.nativeViewportUpdateScheduled = false
            self.nativeViewportDidChange()
        }
    }

    func nativeViewportDidChange() {
        guard !synchronizingNativeViewport,
              let session,
              let snapshot,
              let appearance = terminalAppearance,
              !snapshot.isAlternateScreen,
              session.mouseTracking == .off else { return }
        guard let scrollView = enclosingScrollView else { return }
        let lineHeight = max(1, appearance.lineHeight)
        let maxRow = max(0, snapshot.totalRows - snapshot.rows)
        let clipView = scrollView.contentView
        let maxY = max(0, NSMaxY(bounds) - clipView.bounds.height)

        // The document's physical bottom is often between terminal row
        // boundaries because the viewport height is not a whole number of
        // line heights. Rounding the coordinate can therefore resolve to the
        // penultimate row even while the native scroller is at 1.0, hiding
        // the prompt. The bottom is a distinct terminal viewport state.
        if clipView.bounds.minY >= maxY - 0.5 {
            guard snapshot.screenTopIndex != maxRow else { return }
            session.scrollToBottom()
            updateContent()
            return
        }

        let row = min(maxRow, max(0, Int((clipView.bounds.minY / lineHeight).rounded())))
        guard row != snapshot.screenTopIndex else { return }
        session.scrollViewport(row: row)
        // Native scrolling can move the clip view before SwiftUI gets a
        // chance to re-enter updateNSView. Refresh the viewport synchronously
        // so newly exposed history rows are drawn instead of showing the
        // document's never-painted background.
        updateContent()
    }

    private func synchronizeNativeViewport() {
        guard let snapshot,
              let appearance = terminalAppearance,
              let scrollView = enclosingScrollView,
              !snapshot.isAlternateScreen,
              session?.mouseTracking == .off else { return }
        let lineHeight = max(1, appearance.lineHeight)
        let maxY = max(0, bounds.height - scrollView.contentView.bounds.height)
        let targetY = min(maxY, max(0, CGFloat(snapshot.screenTopIndex) * lineHeight))
        var clipBounds = scrollView.contentView.bounds
        guard abs(clipBounds.origin.y - targetY) > 0.5 else { return }
        clipBounds.origin.y = targetY
        synchronizingNativeViewport = true
        scrollView.contentView.bounds = clipBounds
        scrollView.reflectScrolledClipView(scrollView.contentView)
        synchronizingNativeViewport = false
    }

    private func updateDocumentFrame() {
        guard let session,
              let scrollView = enclosingScrollView,
              let appearance = terminalAppearance else { return }
        let viewport = scrollView.contentView.bounds.size
        guard viewport.width > 1, viewport.height > 1 else { return }
        let rows = snapshot?.contentRowCount ?? Int(session.rows)
        let width = max(viewport.width, CGFloat(snapshot?.columns ?? Int(session.columns)) * appearance.characterWidth + terminalGridInset * 2)
        let height = max(viewport.height, CGFloat(rows) * appearance.lineHeight + terminalGridInset * 2)
        let documentSize = NSSize(width: width, height: height)
        if frame.size != documentSize {
            frame = NSRect(origin: .zero, size: documentSize)
        }
    }

    private func invalidateVisibleTerminalArea() {
        guard let clipView = enclosingScrollView?.contentView else {
            setNeedsDisplay(visibleRect)
            return
        }
        let rect = convert(clipView.bounds, from: clipView).intersection(bounds)
        guard !rect.isNull, !rect.isEmpty else { return }

        // Scrolling changes the mapping between absolute document rows and
        // Ghostty's viewport rows. AppKit may move an existing backing-store
        // image before this invalidation arrives, so repainting only an
        // exposed band can leave the rest of the viewport blank or stale.
        // Repaint the whole visible terminal area; draw(_:) still limits work
        // to visible rows and the color caches keep the hot path cheap.
        setNeedsDisplay(rect)
    }

    private func resizeSessionToViewport() {
        guard let session,
              let appearance = terminalAppearance,
              let scrollView = enclosingScrollView else { return }
        let viewport = scrollView.contentView.bounds.size
        guard viewport.width > 1, viewport.height > 1 else { return }
        let columns = UInt16(max(2, min(512, Int((viewport.width - terminalGridInset * 2) / appearance.characterWidth))))
        let rows = UInt16(max(2, min(256, Int((viewport.height - terminalGridInset * 2) / appearance.lineHeight))))
        guard columns != lastTerminalColumns || rows != lastTerminalRows else { return }
        lastTerminalColumns = columns
        lastTerminalRows = rows
        session.resize(columns: columns, rows: rows)
    }

    override func layout() {
        super.layout()
        // NSScrollView can lay out its document before the SwiftUI host has
        // its final pane width. Recompute the document frame on every layout
        // pass so the hit-test area always covers the complete pane, not just
        // the width of the first short prompt.
        updateDocumentFrame()
        resizeSessionToViewport()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let snapshot, let appearance = terminalAppearance else { return }
        let characterWidth = appearance.characterWidth
        // A terminal row has two separate dimensions: the height occupied by
        // its glyph/background and the distance to the next row. Keeping the
        // configurable spacing out of the cell rectangle prevents Powerline
        // prompt backgrounds and their arrow glyphs from changing shape when
        // the user only asks for more space between rows.
        let cellHeight = appearance.fontLineHeight
        let rowHeight = appearance.lineHeight
        // AppKit may reuse a layer's old dirty rect while a clip view is
        // moved to a distant scrollback position. Derive the render range
        // from the current clip bounds so newly exposed history is never
        // mistaken for the old bottom-of-document rows.
        let visibleDocumentRect: NSRect
        if let clipView = enclosingScrollView?.contentView {
            visibleDocumentRect = convert(clipView.bounds, from: clipView)
                .intersection(bounds)
        } else {
            visibleDocumentRect = dirtyRect.intersection(bounds)
        }
        guard !visibleDocumentRect.isNull, !visibleDocumentRect.isEmpty else { return }
        let drawRect = dirtyRect.intersects(visibleDocumentRect)
            ? dirtyRect.intersection(visibleDocumentRect)
            : visibleDocumentRect
        let firstRow = max(0, Int(floor((drawRect.minY - terminalGridInset) / rowHeight)) - 1)
        let lastRow = min(snapshot.contentRowCount - 1, Int(ceil((drawRect.maxY - terminalGridInset) / rowHeight)) + 1)
        guard firstRow <= lastRow else { return }

        NSGraphicsContext.saveGraphicsState()
        // A default terminal cell is transparent. The themed backdrop behind
        // this document owns the opacity and blur; painting Ghostty's default
        // background here would make the opacity slider appear ineffective.
        // Clear the dirty pixels first so an old opaque backing-store sample
        // cannot survive a scroll or an opacity change.
        NSColor.clear.setFill()
        drawRect.fill(using: .copy)
        for row in firstRow...lastRow {
            let line = snapshot.line(at: row)
            let y = terminalGridInset + CGFloat(row) * rowHeight
            let firstColumn = max(0, Int(floor((drawRect.minX - terminalGridInset) / characterWidth)) - 1)
            let lastColumn = min(snapshot.columns - 1, Int(ceil((drawRect.maxX - terminalGridInset) / characterWidth)) + 1)
            guard firstColumn <= lastColumn else { continue }

            // Paint backgrounds first so a later cell can never cover text
            // from an earlier cell in the same row. Keep adjacent cells with
            // the same resolved color in one fill. `characterWidth` is often
            // fractional (for example with SF Mono at non-integral sizes),
            // and filling every cell independently makes Core Graphics
            // antialias each fractional edge. On a long colored run those
            // blended edges become the visible vertical stripes seen in the
            // terminal. A single run has antialiasing only at its two outer
            // edges, so the interior remains solid.
            var backgroundRunColor: NSColor?
            var backgroundRunRect = NSRect.zero

            func flushBackgroundRun() {
                guard let backgroundRunColor,
                      !backgroundRunRect.isEmpty else { return }
                backgroundRunColor.setFill()
                backgroundRunRect.fill()
            }

            for column in firstColumn...lastColumn {
                let cell = line.indices.contains(column)
                    ? line[column]
                    : TerminalCell(character: " ", style: TerminalTextStyle())
                let isCursor = cursorIsAt(snapshot: snapshot, row: row, column: column)
                let width = cell.isContinuation ? 0 : (line.indices.contains(column + 1) && line[column + 1].isContinuation ? 2 : 1)
                guard width > 0 else { continue }
                let rect = NSRect(
                    x: terminalGridInset + CGFloat(column) * characterWidth,
                    y: y,
                    width: characterWidth * CGFloat(width),
                    height: cellHeight
                )
                let colors = colors(for: cell.style, snapshot: snapshot, appearance: appearance)
                let background = cell.isSelected
                    ? NSColor.selectedTextBackgroundColor
                    : isCursor
                    ? nsColor(for: snapshot.cursorColor, fallback: appearance.theme.appKitCursor)
                    : colors.background
                guard background.alphaComponent > 0 else {
                    flushBackgroundRun()
                    backgroundRunColor = nil
                    backgroundRunRect = .zero
                    continue
                }

                let canAppend = backgroundRunColor?.isEqual(background) == true
                    && abs(NSMaxX(backgroundRunRect) - rect.minX) < 0.5
                if !canAppend {
                    flushBackgroundRun()
                    backgroundRunColor = background
                    backgroundRunRect = rect
                } else {
                    backgroundRunRect.size.width = NSMaxX(rect) - backgroundRunRect.minX
                }
            }
            flushBackgroundRun()

            // Coalesce adjacent cells with the same style into one attributed
            // string. This avoids one dictionary and one attributed string per
            // cell during scrolling and full-screen redraws.
            var runString = ""
            var runStyle: TerminalTextStyle?
            var runIsCursor = false
            var runIsSelected = false
            var runRect = NSRect.zero

            func flushTextRun() {
                guard !runString.isEmpty, let style = runStyle else { return }
                let styleColors = colors(for: style, snapshot: snapshot, appearance: appearance)
                let textBackground = runIsSelected
                    ? NSColor.selectedTextBackgroundColor
                    : (styleColors.background.alphaComponent > 0
                        ? styleColors.background
                        : nsColor(for: snapshot.defaultBackground, fallback: appearance.theme.appKitBackground))
                var foreground = runIsSelected
                    ? NSColor.selectedTextColor
                    : runIsCursor
                    ? nsColor(for: snapshot.defaultBackground, fallback: appearance.theme.appKitBackground)
                    : styleColors.foreground
                if style.dim {
                    foreground = foreground.blended(withFraction: 0.28, of: textBackground) ?? foreground
                }
                if !runIsCursor && !runIsSelected {
                    foreground = readableForeground(
                        foreground,
                        on: textBackground,
                        fallback: nsColor(
                            for: snapshot.defaultForeground,
                            fallback: appearance.theme.appKitForeground
                        )
                    )
                }
                let font = appearance.font(
                    ofSize: CGFloat(appearance.fontSize),
                    bold: style.bold,
                    italic: style.italic
                )
                var attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: foreground
                ]
                if style.underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
                if style.strikethrough {
                    attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                }
                NSAttributedString(string: runString, attributes: attributes).draw(in: runRect)
                runString.removeAll(keepingCapacity: true)
                runStyle = nil
                runIsCursor = false
                runIsSelected = false
                runRect = .zero
            }

            for column in firstColumn...lastColumn {
                let cell = line.indices.contains(column)
                    ? line[column]
                    : TerminalCell(character: " ", style: TerminalTextStyle())
                let isCursor = cursorIsAt(snapshot: snapshot, row: row, column: column)
                let width = cell.isContinuation ? 0 : (line.indices.contains(column + 1) && line[column + 1].isContinuation ? 2 : 1)
                guard width > 0 else { continue }
                let rect = NSRect(
                    x: terminalGridInset + CGFloat(column) * characterWidth,
                    y: y,
                    width: characterWidth * CGFloat(width),
                    height: cellHeight
                )
                let hidden = cell.character == " "
                    || cell.style.invisible
                    || (cell.style.blink && !cursorBlinkOn)
                guard !hidden else {
                    flushTextRun()
                    continue
                }

                let adjacent = !runString.isEmpty
                    && runStyle == cell.style
                    && runIsCursor == isCursor
                    && runIsSelected == cell.isSelected
                    && abs(NSMaxX(runRect) - rect.minX) < 0.5
                if !adjacent { flushTextRun() }
                if runString.isEmpty {
                    runStyle = cell.style
                    runIsCursor = isCursor
                    runIsSelected = cell.isSelected
                    runRect = rect
                } else {
                    runRect.size.width += rect.width
                }
                runString.append(String(cell.character))
            }
            flushTextRun()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func cursorIsAt(snapshot: TerminalGridSnapshot, row: Int, column: Int) -> Bool {
        guard snapshot.cursorVisible, isFocusedPane, cursorBlinkOn else { return false }
        let cursorRow = snapshot.documentCursorRow
        guard row == cursorRow else { return false }
        let clampedColumn = min(max(0, snapshot.cursorColumn), max(0, snapshot.columns - 1))
        return column == clampedColumn
    }

    private func colors(
        for style: TerminalTextStyle,
        snapshot: TerminalGridSnapshot,
        appearance: TerminalAppearance
    ) -> ResolvedTerminalColors {
        if let cached = cachedStyleColors[style] {
            return cached
        }
        let defaultForeground = nsColor(
            for: snapshot.defaultForeground,
            fallback: appearance.theme.appKitForeground
        )
        let defaultBackground = nsColor(
            for: snapshot.defaultBackground,
            fallback: appearance.theme.appKitBackground
        )
        let resolved: ResolvedTerminalColors
        if style.inverse {
            resolved = ResolvedTerminalColors(
                foreground: nsColor(for: style.background, fallback: defaultBackground),
                background: nsColor(for: style.foreground, fallback: defaultForeground)
            )
        } else {
            resolved = ResolvedTerminalColors(
                foreground: nsColor(for: style.foreground, fallback: defaultForeground),
                background: nsColor(for: style.background, fallback: .clear)
            )
        }
        cachedStyleColors[style] = resolved
        return resolved
    }

    private func readableForeground(
        _ foreground: NSColor,
        on background: NSColor,
        fallback: NSColor
    ) -> NSColor {
        guard let foreground = foreground.usingColorSpace(.sRGB),
              let background = background.usingColorSpace(.sRGB),
              let fallback = fallback.usingColorSpace(.sRGB) else {
            return foreground
        }

        func luminance(_ color: NSColor) -> CGFloat {
            func linear(_ component: CGFloat) -> CGFloat {
                component <= 0.03928
                    ? component / 12.92
                    : pow((component + 0.055) / 1.055, 2.4)
            }
            return (0.2126 * linear(color.redComponent))
                + (0.7152 * linear(color.greenComponent))
                + (0.0722 * linear(color.blueComponent))
        }

        func contrast(_ color: NSColor, against background: NSColor) -> CGFloat {
            let first = luminance(color)
            let second = luminance(background)
            return (max(first, second) + 0.05) / (min(first, second) + 0.05)
        }

        let minimumContrast: CGFloat = 2.15
        guard contrast(foreground, against: background) < minimumContrast else {
            return foreground
        }

        let white = NSColor.white.usingColorSpace(.sRGB)!
        let black = NSColor.black.usingColorSpace(.sRGB)!
        let fallbackTarget = contrast(fallback, against: background) >= minimumContrast
            ? fallback
            : (contrast(white, against: background) >= contrast(black, against: background) ? white : black)

        for step in 1...8 {
            let fraction = CGFloat(step) / 8
            let candidate = foreground.blended(withFraction: fraction, of: fallbackTarget) ?? fallbackTarget
            if contrast(candidate, against: background) >= minimumContrast {
                return candidate
            }
        }
        return fallbackTarget
    }

    private func updateRenderColors(_ snapshot: TerminalGridSnapshot) {
        cachedNSColors.removeAll(keepingCapacity: true)
        cachedStyleColors.removeAll(keepingCapacity: true)
        cachedPaletteColors = snapshot.palette.map { color in
            nsColor(for: color, fallback: .clear)
        }
    }

    override func viewDidMoveToWindow() {
        let previousWindow = registeredWindow
        TerminalMouseMotionCoordinator.shared.unregister(self, from: previousWindow)
        super.viewDidMoveToWindow()
        cursorBlinkTimer?.invalidate()
        cursorBlinkTimer = nil
        if let windowKeyObserver {
            NotificationCenter.default.removeObserver(windowKeyObserver)
            self.windowKeyObserver = nil
        }
        if let window {
            registeredWindow = window
            TerminalMouseMotionCoordinator.shared.register(self, in: window)
            let timer = Timer(timeInterval: 0.55, target: self, selector: #selector(toggleCursorBlink), userInfo: nil, repeats: true)
            cursorBlinkTimer = timer
            RunLoop.main.add(timer, forMode: .common)
            windowKeyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    if self?.isFocusedPane == true { self?.focus() }
                }
            }
        } else {
            registeredWindow = nil
        }
        DispatchQueue.main.async { [weak self] in
            if self?.isFocusedPane == true { self?.focus() }
            self?.updateDocumentFrame()
        }
    }

    @objc private func toggleCursorBlink() {
        guard isFocusedPane else { return }
        guard terminalAppearance?.cursorBlinkEnabled == true else {
            if !cursorBlinkOn { cursorBlinkOn = true; updateContent() }
            return
        }
        cursorBlinkOn.toggle()
        updateContent()
    }

    override func mouseDown(with event: NSEvent) {
        onFocus?()
        focus()
        if let session, session.mouseTracking != .off {
            pressedMouseButton = mouseButton(for: event)
            sendMouse(.press, event: event, button: pressedMouseButton ?? -1, anyButtonPressed: true)
            return
        }

        guard event.buttonNumber == 0 else { return }
        let position = terminalPosition(for: event)
        if event.clickCount >= 3 {
            selectionAnchor = position
            selectionBase = position
            selectionRectangle = false
            selectLine(at: position)
        } else if event.clickCount == 2 {
            selectionAnchor = position
            selectionBase = position
            selectionRectangle = false
            selectWord(at: position)
        } else {
            selectionAnchor = event.modifierFlags.contains(.shift)
                ? (selectionBase ?? position)
                : position
            if !event.modifierFlags.contains(.shift) {
                selectionBase = position
            }
            selectionRectangle = event.modifierFlags.contains(.option)
            if !event.modifierFlags.contains(.shift) {
                session?.clearSelection()
            } else if let selectionAnchor, selectionAnchor != position {
                _ = session?.setSelection(
                    startColumn: selectionAnchor.column,
                    startRow: selectionAnchor.row,
                    endColumn: position.column,
                    endRow: position.row,
                    rectangle: selectionRectangle
                )
            }
        }
    }

    override func mouseUp(with event: NSEvent) {
        if let session, session.mouseTracking != .off {
            sendMouse(.release, event: event, button: pressedMouseButton ?? mouseButton(for: event), anyButtonPressed: false)
            pressedMouseButton = nil
            return
        }
        guard event.buttonNumber == 0 else { return }
        selectionAnchor = nil
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { session?.sendFocusEvent(true) }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { session?.sendFocusEvent(false) }
        return resigned
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let session, session.mouseTracking != .off else {
            onFocus?()
            focus()
            return
        }
        mouseDown(with: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        guard let session, session.mouseTracking != .off else {
            guard let menu = menu(for: event) else { return }
            NSMenu.popUpContextMenu(menu, with: event, for: self)
            return
        }
        mouseUp(with: event)
    }
    override func otherMouseDown(with event: NSEvent) { mouseDown(with: event) }
    override func otherMouseUp(with event: NSEvent) { mouseUp(with: event) }

    override func mouseDragged(with event: NSEvent) {
        guard let session else { return }
        if session.mouseTracking == .buttonMotion || session.mouseTracking == .anyMotion {
            sendMouse(.motion, event: event, button: pressedMouseButton ?? -1, anyButtonPressed: pressedMouseButton != nil)
            return
        }
        guard let anchor = selectionAnchor else { return }
        let position = terminalPosition(for: event)
        _ = session.setSelection(
            startColumn: anchor.column,
            startRow: anchor.row,
            endColumn: position.column,
            endRow: position.row,
            rectangle: selectionRectangle
        )
    }

    override func rightMouseDragged(with event: NSEvent) { mouseDragged(with: event) }
    override func otherMouseDragged(with event: NSEvent) { mouseDragged(with: event) }

    override func mouseMoved(with event: NSEvent) {
        guard session?.mouseTracking == .anyMotion else { return }
        sendMouse(.motion, event: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard session?.mouseTracking == .off else { return super.menu(for: event) }
        let menu = NSMenu()
        let copy = NSMenuItem(title: "Copy", action: #selector(copy(_:)), keyEquivalent: "")
        copy.target = self
        copy.isEnabled = session?.selectedText()?.isEmpty == false
        menu.addItem(copy)
        let selectAll = NSMenuItem(title: "Select All", action: #selector(selectAll(_:)), keyEquivalent: "")
        selectAll.target = self
        menu.addItem(selectAll)
        return menu
    }

    override func scrollWheel(with event: NSEvent) {
        guard session?.mouseTracking != .off else {
            // Content hit-testing is routed to this view so tmux/Vim can own
            // mouse input. Ordinary wheel events still belong to NSScrollView
            // so AppKit moves its clip view and native scroller.
            (enclosingScrollView as? TerminalScrollView)?.passThroughScrollWheel(with: event)
            return
        }
        handleScrollWheel(with: event)
    }

    func handleScrollWheel(with event: NSEvent) {
        guard let session, session.mouseTracking != .off else { return }
        onFocus?()
        focus()
        let delta = abs(event.scrollingDeltaY) > .ulpOfOne ? event.scrollingDeltaY : event.deltaY
        guard abs(delta) > .ulpOfOne else { return }
        sendMouse(delta > 0 ? .scrollUp : .scrollDown, event: event, anyButtonPressed: false)
    }

    override func paste(_ sender: Any?) { pasteClipboardContents() }

    override func copy(_ sender: Any?) { copySelection() }

    override func selectAll(_ sender: Any?) { selectAllTerminalContent() }

    override func cancelOperation(_ sender: Any?) {
        session?.clearSelection()
        selectionAnchor = nil
        selectionBase = nil
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else { return super.performKeyEquivalent(with: event) }
        if event.keyCode == 8 {
            copySelection()
            return true
        }
        if event.keyCode == 9 {
            pasteClipboardContents()
            return true
        }
        if event.keyCode == 0 {
            selectAllTerminalContent()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        if let text = insertString as? String { session?.send(text) }
    }

    override func keyDown(with event: NSEvent) {
        guard let session else { super.keyDown(with: event); return }
        if event.modifierFlags.contains(.command) {
            switch event.keyCode {
            case 8: copySelection()
            case 9: pasteClipboardContents()
            case 0: selectAllTerminalContent()
            default: super.keyDown(with: event)
            }
            return
        }
        if event.modifierFlags.contains(.control),
           let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first {
            let value = scalar.value
            if value == 0x20 { session.send("\0"); return }
            if (0x40...0x7F).contains(value), let controlScalar = UnicodeScalar(value & 0x1F) {
                session.send(String(controlScalar)); return
            }
        }
        if let sequence = escapeSequence(for: event) {
            session.send(sequence)
        } else if event.modifierFlags.contains(.option) {
            if metaKeyEnabled,
               let characters = event.charactersIgnoringModifiers,
               !characters.isEmpty {
                session.send("\u{1B}" + characters)
            } else if let characters = event.characters, !characters.isEmpty {
                session.send(characters)
            } else {
                interpretKeyEvents([event])
            }
        } else {
            interpretKeyEvents([event])
        }
    }

    private func pasteClipboardContents() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        session?.paste(text)
    }

    private func copySelection() {
        guard let text = session?.selectedText(), !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func selectAllTerminalContent() {
        guard let session else { return }
        let snapshot = session.displayGrid
        guard snapshot.contentRowCount > 0, snapshot.columns > 0 else { return }
        _ = session.setSelection(
            startColumn: 0,
            startRow: 0,
            endColumn: snapshot.columns - 1,
            endRow: snapshot.contentRowCount - 1
        )
    }

    private func terminalPosition(for event: NSEvent) -> TerminalCellPosition {
        let point = convert(event.locationInWindow, from: nil)
        return terminalPosition(for: point)
    }

    private func terminalPosition(for point: NSPoint) -> TerminalCellPosition {
        let characterWidth = max(1, terminalAppearance?.characterWidth ?? 8)
        let rowHeight = max(1, terminalAppearance?.lineHeight ?? 16)
        let columns = max(1, snapshot?.columns ?? Int(session?.columns ?? 1))
        let rows = max(1, snapshot?.contentRowCount ?? Int(session?.rows ?? 1))
        let column = min(
            max(0, Int(floor((point.x - terminalGridInset) / characterWidth))),
            columns - 1
        )
        let row = min(
            max(0, Int(floor((point.y - terminalGridInset) / rowHeight))),
            rows - 1
        )
        return TerminalCellPosition(column: column, row: row)
    }

    private func selectWord(at position: TerminalCellPosition) {
        guard let session, let snapshot else { return }
        let line = snapshot.line(at: position.row)
        guard line.indices.contains(position.column) else { return }
        let target = line[position.column].character
        guard target != " " else { return }
        let targetIsWord = isWordCharacter(target)
        func matches(_ cell: TerminalCell) -> Bool {
            guard cell.character != " " else { return false }
            return isWordCharacter(cell.character) == targetIsWord
        }
        var start = position.column
        var end = position.column
        while start > 0, matches(line[start - 1]) { start -= 1 }
        while end + 1 < line.count, matches(line[end + 1]) { end += 1 }
        _ = session.setSelection(
            startColumn: start,
            startRow: position.row,
            endColumn: end,
            endRow: position.row
        )
    }

    private func selectLine(at position: TerminalCellPosition) {
        guard let session else { return }
        let columns = max(1, snapshot?.columns ?? Int(session.columns))
        _ = session.setSelection(
            startColumn: 0,
            startRow: position.row,
            endColumn: columns - 1,
            endRow: position.row
        )
    }

    private func isWordCharacter(_ character: Character) -> Bool {
        if character == "_" { return true }
        return character.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
    }

    private func escapeSequence(for event: NSEvent) -> String? {
        guard let session,
              let data = session.encodedKeyEvent(
                keyCode: event.keyCode,
                modifiers: keyboardModifierCode(event.modifierFlags),
                optionAsAlt: metaKeyEnabled,
                repeatEvent: event.isARepeat
            ) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private func mouseButton(for event: NSEvent) -> Int {
        switch event.buttonNumber { case 1: return 1; case 2: return 2; default: return 0 }
    }

    private func sendMouse(
        _ kind: TerminalMouseEventKind,
        event: NSEvent,
        button: Int = -1,
        anyButtonPressed: Bool = false
    ) {
        guard let session else { return }
        let point: NSPoint
        if let clipView = enclosingScrollView?.contentView {
            let p = clipView.convert(event.locationInWindow, from: nil)
            point = NSPoint(x: p.x - clipView.bounds.minX, y: p.y - clipView.bounds.minY)
        } else {
            point = convert(event.locationInWindow, from: nil)
        }
        let characterWidth = max(1, terminalAppearance?.characterWidth ?? 8)
        let lineHeight = max(1, terminalAppearance?.lineHeight ?? 16)
        let column = Int(floor((point.x - terminalGridInset) / characterWidth)) + 1
        let row = Int(floor((point.y - terminalGridInset) / lineHeight)) + 1
        session.sendMouse(
            kind: kind,
            button: button,
            column: min(max(1, column), Int(session.columns)),
            row: min(max(1, row), Int(session.rows)),
            modifiers: mouseModifierCode(event.modifierFlags),
            anyButtonPressed: anyButtonPressed
        )
    }

    private func mouseModifierCode(_ flags: NSEvent.ModifierFlags) -> Int {
        var code = 0
        if flags.contains(.shift) { code |= 1 }
        if flags.contains(.control) { code |= 2 }
        if flags.contains(.option) { code |= 4 }
        if flags.contains(.command) { code |= 8 }
        return code
    }

    private func keyboardModifierCode(_ flags: NSEvent.ModifierFlags) -> UInt16 {
        var code: UInt16 = 0
        if flags.contains(.shift) { code |= 1 }
        if flags.contains(.control) { code |= 2 }
        if flags.contains(.option) && metaKeyEnabled { code |= 4 }
        if flags.contains(.command) { code |= 8 }
        return code
    }

    private func nsColor(for color: TerminalColor, fallback: NSColor) -> NSColor {
        switch color {
        case .default: return fallback
        case .rgb(let red, let green, let blue):
            if let cached = cachedNSColors[color] { return cached }
            let value = NSColor(
                srgbRed: CGFloat(red) / 255,
                green: CGFloat(green) / 255,
                blue: CGFloat(blue) / 255,
                alpha: 1
            )
            cachedNSColors[color] = value
            return value
        case .ansi(let index):
            if cachedPaletteColors.indices.contains(index) { return cachedPaletteColors[index] }
            return ansiColor(index)
        }
    }

    private func ansiColor(_ index: Int) -> NSColor {
        if cachedANSIColors.indices.contains(index) {
            return cachedANSIColors[index]
        }
        let palette: [NSColor] = [
            NSColor(srgbRed: 0.12, green: 0.12, blue: 0.12, alpha: 1),
            NSColor(srgbRed: 0.92, green: 0.28, blue: 0.28, alpha: 1),
            NSColor(srgbRed: 0.34, green: 0.78, blue: 0.42, alpha: 1),
            NSColor(srgbRed: 0.92, green: 0.72, blue: 0.28, alpha: 1),
            NSColor(srgbRed: 0.36, green: 0.60, blue: 0.96, alpha: 1),
            NSColor(srgbRed: 0.72, green: 0.46, blue: 0.86, alpha: 1),
            NSColor(srgbRed: 0.28, green: 0.78, blue: 0.78, alpha: 1),
            NSColor(srgbRed: 0.86, green: 0.86, blue: 0.86, alpha: 1),
            NSColor(srgbRed: 0.40, green: 0.40, blue: 0.40, alpha: 1),
            NSColor(srgbRed: 1.00, green: 0.40, blue: 0.40, alpha: 1),
            NSColor(srgbRed: 0.46, green: 0.92, blue: 0.54, alpha: 1),
            NSColor(srgbRed: 1.00, green: 0.82, blue: 0.38, alpha: 1),
            NSColor(srgbRed: 0.52, green: 0.70, blue: 1.00, alpha: 1),
            NSColor(srgbRed: 0.86, green: 0.58, blue: 1.00, alpha: 1),
            NSColor(srgbRed: 0.38, green: 0.92, blue: 0.92, alpha: 1),
            NSColor.white
        ]
        if index < palette.count { return palette[max(index, 0)] }
        if index >= 232 && index <= 255 {
            let value = CGFloat(8 + (index - 232) * 10) / 255
            return NSColor(srgbRed: value, green: value, blue: value, alpha: 1)
        }
        let colorIndex = max(0, min(215, index - 16))
        let red = colorIndex / 36
        let green = (colorIndex / 6) % 6
        let blue = colorIndex % 6
        func channel(_ value: Int) -> CGFloat { value == 0 ? 0 : CGFloat(55 + value * 40) / 255 }
        return NSColor(srgbRed: channel(red), green: channel(green), blue: channel(blue), alpha: 1)
    }
}
