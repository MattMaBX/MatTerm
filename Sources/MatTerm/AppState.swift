import Foundation
import Combine
import AppKit
import SwiftUI
import GhosttyVt

enum SessionKind: Hashable {
    case local
    case ssh(SSHProfile)

    var title: String {
        switch self {
        case .local:
            return "~"
        case .ssh(let profile):
            return profile.tabHostName + " ~"
        }
    }

    var iconName: String {
        switch self {
        case .local:
            return "terminal"
        case .ssh:
            return "network"
        }
    }
}

enum SessionStatus: Equatable {
    case connecting
    case running
    case exited(Int32)
    case failed(String)

    var label: String {
        switch self {
        case .connecting:
            return "Connecting"
        case .running:
            return "Connected"
        case .exited:
            return "Exited"
        case .failed:
            return "Failed"
        }
    }

    var detail: String? {
        switch self {
        case .connecting, .running:
            return nil
        case .exited(let code):
            return code == 0 ? "Process finished" : "Process exited with code " + String(code)
        case .failed(let message):
            return message
        }
    }
}

struct TerminalTheme: CaseIterable, Hashable, Identifiable {
    let id: String
    let title: String
    let foregroundHex: String
    let backgroundHex: String
    let cursorHex: String
    let ansiHexColors: [String]

    static let allCases: [TerminalTheme] = TabbyBuiltInThemes.all

    var background: Color { Color(nsColor: appKitBackground) }
    var foreground: Color { Color(nsColor: appKitForeground) }
    var secondary: Color { Color(nsColor: appKitForeground.withAlphaComponent(0.62)) }
    var appKitBackground: NSColor { NSColor(hex: backgroundHex) }
    var appKitForeground: NSColor { NSColor(hex: foregroundHex) }
    var appKitCursor: NSColor { NSColor(hex: cursorHex) }
    var appKitANSIColors: [NSColor] { ansiHexColors.map(NSColor.init(hex:)) }

    var ghosttyColorConfiguration: TerminalColorConfiguration {
        func rgb(_ color: NSColor) -> GhosttyColorRgb {
            let color = color.usingColorSpace(.sRGB) ?? color
            return GhosttyColorRgb(
                r: UInt8(clamping: Int((color.redComponent * 255).rounded())),
                g: UInt8(clamping: Int((color.greenComponent * 255).rounded())),
                b: UInt8(clamping: Int((color.blueComponent * 255).rounded()))
            )
        }

        let base = appKitANSIColors.map(rgb)
        // The 216-color cube and grayscale ramp are part of Ghostty's color
        // semantics. In particular, it uses CIELAB interpolation rather than
        // the old xterm RGB formula. Generate the palette through the same C
        // API that resolves palette colors inside the terminal.
        var palette = Array(
            repeating: GhosttyColorRgb(r: 0, g: 0, b: 0),
            count: 256
        )
        palette.withUnsafeMutableBufferPointer { buffer in
            guard let pointer = buffer.baseAddress else { return }
            ghostty_color_palette_default(pointer)
            for index in 0..<min(16, base.count) {
                pointer[index] = base[index]
            }
            var background = rgb(appKitBackground)
            var foreground = rgb(appKitForeground)
            ghostty_color_palette_generate(
                pointer,
                nil,
                &background,
                &foreground,
                true,
                pointer
            )
        }
        return TerminalColorConfiguration(
            id: id,
            foreground: rgb(appKitForeground),
            background: rgb(appKitBackground),
            cursor: rgb(appKitCursor),
            palette: palette
        )
    }
}

private extension NSColor {
    convenience init(hex: String) {
        let value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let rgb = UInt64(value, radix: 16) else {
            self.init(srgbRed: 0, green: 0, blue: 0, alpha: 1)
            return
        }
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

@MainActor
final class TerminalAppearance: ObservableObject {
    @Published var fontFamily: String {
        didSet {
            defaults.set(fontFamily, forKey: Keys.fontFamily)
            invalidateFontCache()
        }
    }
    @Published var fontSize: Double {
        didSet {
            defaults.set(fontSize, forKey: Keys.fontSize)
            invalidateFontCache()
        }
    }
    @Published var lineSpacing: Double {
        didSet { defaults.set(lineSpacing, forKey: Keys.lineSpacing) }
    }
    @Published var theme: TerminalTheme {
        didSet { defaults.set(theme.id, forKey: Keys.theme) }
    }
    @Published var backgroundOpacity: Double {
        didSet { defaults.set(backgroundOpacity, forKey: Keys.backgroundOpacity) }
    }
    @Published var backgroundBlur: Double {
        didSet { defaults.set(backgroundBlur, forKey: Keys.backgroundBlur) }
    }
    @Published var cursorBlinkEnabled: Bool {
        didSet { defaults.set(cursorBlinkEnabled, forKey: Keys.cursorBlinkEnabled) }
    }

    private let defaults = UserDefaults.standard
    private var cachedFontFamily = ""
    private var cachedFontSize: CGFloat = -1
    private var cachedRegularFont: NSFont?
    private var cachedBoldFont: NSFont?
    private var cachedItalicFont: NSFont?
    private var cachedBoldItalicFont: NSFont?
    private var cachedCharacterWidth: CGFloat?
    private var cachedFontLineHeight: CGFloat?

    private enum Keys {
        static let fontFamily = "terminal.fontFamily"
        static let fontSize = "terminal.fontSize"
        static let lineSpacing = "terminal.lineSpacing"
        static let theme = "terminal.theme"
        static let backgroundOpacity = "terminal.backgroundOpacity"
        static let backgroundBlur = "terminal.backgroundBlur"
        static let cursorBlinkEnabled = "terminal.cursorBlinkEnabled"
    }

    init() {
        let savedFamily = defaults.string(forKey: Keys.fontFamily)
        if let savedFamily, Self.availableMonospacedFontFamilies.contains(savedFamily) {
            fontFamily = savedFamily
        } else {
            fontFamily = Self.defaultFontFamily
        }
        let savedSize = defaults.double(forKey: Keys.fontSize)
        fontSize = savedSize == 0 ? 13 : min(max(savedSize, 10), 28)
        let savedLineSpacing = defaults.object(forKey: Keys.lineSpacing) as? Double
        lineSpacing = min(max(savedLineSpacing ?? 0, 0), 12)
        let savedThemeID = defaults.string(forKey: Keys.theme) ?? ""
        theme = TerminalTheme.allCases.first { $0.id == savedThemeID }
            ?? TerminalTheme.allCases[0]
        let savedOpacity = defaults.object(forKey: Keys.backgroundOpacity) as? Double
        let savedBlur = defaults.object(forKey: Keys.backgroundBlur) as? Double
        // The original translucent defaults let the desktop and other windows
        // bleed through the terminal, which also made every ANSI color look
        // gray. Keep the controls, but start new/migrated profiles with a
        // crisp terminal surface.
        let isLegacyDefault = savedOpacity == 0.45 && savedBlur == 12
        backgroundOpacity = min(max(isLegacyDefault ? 1 : (savedOpacity ?? 1), 0), 1)
        backgroundBlur = min(max(isLegacyDefault ? 0 : (savedBlur ?? 0), 0), 24)
        cursorBlinkEnabled = defaults.object(forKey: Keys.cursorBlinkEnabled) as? Bool ?? true
    }

    static let availableMonospacedFontFamilies: [String] = NSFontManager.shared.availableFontFamilies
        .filter { family in
            guard let font = NSFont(name: family, size: 13) else { return false }
            return NSFontManager.shared.traits(of: font).contains(.fixedPitchFontMask)
        }
        .sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }

    static var defaultFontFamily: String {
        let preferred = ["Maple Mono NF CN", "SF Mono", "Menlo", "Monaco", "PT Mono"]
        return preferred.first(where: { availableMonospacedFontFamilies.contains($0) })
            ?? availableMonospacedFontFamilies.first
            ?? "Menlo"
    }

    func font(ofSize size: CGFloat, bold: Bool = false, italic: Bool = false) -> NSFont {
        if size == CGFloat(fontSize) {
            if cachedFontFamily != fontFamily || cachedFontSize != size {
                rebuildFontCache(for: size)
            }
            if italic {
                return bold ? cachedBoldItalicFont! : cachedItalicFont!
            }
            return bold ? cachedBoldFont! : cachedRegularFont!
        }

        let base = makeFont(ofSize: size, bold: bold)
        return italic ? NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask) : base
    }

    private func makeFont(ofSize size: CGFloat, bold: Bool) -> NSFont {
        let cascadeFonts = ["Maple Mono NF CN", "SF Mono", "Menlo", "Monaco"]
            .filter { $0 != fontFamily && Self.availableMonospacedFontFamilies.contains($0) }
            .map { NSFontDescriptor(name: $0, size: size) }
        let descriptor = NSFontDescriptor(name: fontFamily, size: size)
            .addingAttributes([.cascadeList: cascadeFonts])
        let base = NSFont(descriptor: descriptor, size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        guard bold else { return base }
        return NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask)
    }

    private func rebuildFontCache(for size: CGFloat) {
        let regular = makeFont(ofSize: size, bold: false)
        let bold = makeFont(ofSize: size, bold: true)
        cachedFontFamily = fontFamily
        cachedFontSize = size
        cachedRegularFont = regular
        cachedBoldFont = bold
        cachedItalicFont = NSFontManager.shared.convert(regular, toHaveTrait: .italicFontMask)
        cachedBoldItalicFont = NSFontManager.shared.convert(bold, toHaveTrait: .italicFontMask)
        cachedCharacterWidth = nil
        cachedFontLineHeight = nil
    }

    private func invalidateFontCache() {
        cachedFontFamily = ""
        cachedFontSize = -1
        cachedRegularFont = nil
        cachedBoldFont = nil
        cachedItalicFont = nil
        cachedBoldItalicFont = nil
        cachedCharacterWidth = nil
        cachedFontLineHeight = nil
    }

    var characterWidth: CGFloat {
        if let cachedCharacterWidth { return cachedCharacterWidth }
        let terminalFont = font(ofSize: CGFloat(fontSize))
        let asciiCellWidth = ("0" as NSString).size(withAttributes: [.font: terminalFont]).width
        let width = max(1, asciiCellWidth)
        cachedCharacterWidth = width
        return width
    }

    var lineHeight: CGFloat {
        fontLineHeight + CGFloat(lineSpacing)
    }

    var fontLineHeight: CGFloat {
        if let cachedFontLineHeight { return cachedFontLineHeight }
        let font = font(ofSize: CGFloat(fontSize))
        let height = max(1, ceil(font.ascender - font.descender + font.leading))
        cachedFontLineHeight = height
        return height
    }

    var isDarkTheme: Bool {
        guard let color = theme.appKitBackground.usingColorSpace(.sRGB) else {
            return true
        }
        let luminance = (0.2126 * color.redComponent)
            + (0.7152 * color.greenComponent)
            + (0.0722 * color.blueComponent)
        return luminance < 0.58
    }

    // Keep the theme tint and its transparency as one composited color so
    // the terminal backdrop and native materials respond consistently.
    var effectiveBackgroundColor: NSColor {
        theme.appKitBackground.withAlphaComponent(CGFloat(backgroundOpacity))
    }

    var effectiveBackground: Color {
        Color(nsColor: effectiveBackgroundColor)
    }

    func readableMutedColor(_ color: NSColor) -> NSColor {
        let background = theme.appKitBackground
        guard contrastRatio(color, against: background) < 2.2 else { return color }

        let foreground = theme.appKitForeground
        var candidate = mix(background, foreground, amount: 0.46)
        for amount in stride(from: 0.46, through: 0.72, by: 0.04) {
            candidate = mix(background, foreground, amount: amount)
            if contrastRatio(candidate, against: background) >= 2.2 {
                break
            }
        }
        return candidate
    }

    private func mix(_ first: NSColor, _ second: NSColor, amount: CGFloat) -> NSColor {
        guard let first = first.usingColorSpace(.sRGB),
              let second = second.usingColorSpace(.sRGB) else {
            return second
        }
        let amount = min(max(amount, 0), 1)
        return NSColor(
            srgbRed: first.redComponent + (second.redComponent - first.redComponent) * amount,
            green: first.greenComponent + (second.greenComponent - first.greenComponent) * amount,
            blue: first.blueComponent + (second.blueComponent - first.blueComponent) * amount,
            alpha: 1
        )
    }

    private func contrastRatio(_ first: NSColor, against second: NSColor) -> CGFloat {
        func luminance(of color: NSColor) -> CGFloat {
            guard let color = color.usingColorSpace(.sRGB) else { return 0 }
            func linearize(_ channel: CGFloat) -> CGFloat {
                channel <= 0.03928
                    ? channel / 12.92
                    : pow((channel + 0.055) / 1.055, 2.4)
            }
            return (0.2126 * linearize(color.redComponent))
                + (0.7152 * linearize(color.greenComponent))
                + (0.0722 * linearize(color.blueComponent))
        }

        let brighter = max(luminance(of: first), luminance(of: second))
        let darker = min(luminance(of: first), luminance(of: second))
        return (brighter + 0.05) / (darker + 0.05)
    }

    func increaseFontSize() {
        fontSize = min(fontSize + 1, 28)
    }

    func decreaseFontSize() {
        fontSize = max(fontSize - 1, 10)
    }

    func resetFontSize() {
        fontSize = 13
    }
}

enum TerminalSplitAxis {
    case horizontal
    case vertical
}

enum TerminalSplitDirection {
    case left
    case right
    case above
    case below

    var axis: TerminalSplitAxis {
        switch self {
        case .left, .right: return .horizontal
        case .above, .below: return .vertical
        }
    }

    var insertsBeforeFocusedPane: Bool {
        switch self {
        case .left, .above: return true
        case .right, .below: return false
        }
    }
}

indirect enum TerminalSplitNode {
    case leaf(TerminalSession)
    case split(axis: TerminalSplitAxis, first: TerminalSplitNode, second: TerminalSplitNode)

    var sessions: [TerminalSession] {
        switch self {
        case .leaf(let session): return [session]
        case .split(_, let first, let second): return first.sessions + second.sessions
        }
    }

    func contains(sessionID: UUID) -> Bool {
        sessions.contains { $0.id == sessionID }
    }

    func replacingLeaf(
        sessionID: UUID,
        with replacement: TerminalSplitNode
    ) -> TerminalSplitNode {
        switch self {
        case .leaf(let session):
            return session.id == sessionID ? replacement : self
        case .split(let axis, let first, let second):
            return .split(
                axis: axis,
                first: first.replacingLeaf(sessionID: sessionID, with: replacement),
                second: second.replacingLeaf(sessionID: sessionID, with: replacement)
            )
        }
    }

    func removingLeaf(sessionID: UUID) -> TerminalSplitNode? {
        switch self {
        case .leaf(let session):
            return session.id == sessionID ? nil : self
        case .split(let axis, let first, let second):
            let updatedFirst = first.removingLeaf(sessionID: sessionID)
            let updatedSecond = second.removingLeaf(sessionID: sessionID)
            switch (updatedFirst, updatedSecond) {
            case (nil, nil): return nil
            case (let remaining?, nil), (nil, let remaining?): return remaining
            case (let updatedFirst?, let updatedSecond?):
                return .split(axis: axis, first: updatedFirst, second: updatedSecond)
            }
        }
    }
}

@MainActor
final class TerminalWorkspace: ObservableObject, Identifiable {
    let id = UUID()
    @Published private(set) var root: TerminalSplitNode
    @Published private(set) var focusedSessionID: UUID
    @Published private(set) var title: String
    @Published private(set) var iconName: String
    @Published private(set) var status: SessionStatus

    private var sessionSubscriptions = Set<AnyCancellable>()
    var onSessionExited: ((TerminalSession) -> Void)?

    init(session: TerminalSession) {
        root = .leaf(session)
        focusedSessionID = session.id
        title = session.title
        iconName = session.iconName
        status = session.status
        observeSessions()
    }

    var sessions: [TerminalSession] { root.sessions }

    var focusedSession: TerminalSession? {
        sessions.first { $0.id == focusedSessionID } ?? sessions.first
    }

    func focus(sessionID: UUID) {
        guard let session = sessions.first(where: { $0.id == sessionID }) else { return }
        focusedSessionID = session.id
        title = session.title
        iconName = session.iconName
        status = session.status
        session.requestFocus()
    }

    @discardableResult
    func splitFocusedPane(
        direction: TerminalSplitDirection,
        scrollbackLineLimit: Int
    ) -> TerminalSession? {
        guard let focusedSession else { return nil }
        let newSession = TerminalSession(
            kind: focusedSession.kind,
            scrollbackLineLimit: scrollbackLineLimit
        )
        let newLeaf = TerminalSplitNode.leaf(newSession)
        let existingLeaf = TerminalSplitNode.leaf(focusedSession)
        let replacement: TerminalSplitNode
        if direction.insertsBeforeFocusedPane {
            replacement = .split(axis: direction.axis, first: newLeaf, second: existingLeaf)
        } else {
            replacement = .split(axis: direction.axis, first: existingLeaf, second: newLeaf)
        }
        root = root.replacingLeaf(sessionID: focusedSession.id, with: replacement)
        focusedSessionID = newSession.id
        title = newSession.title
        iconName = newSession.iconName
        status = newSession.status
        observeSessions()
        newSession.requestFocus()
        return newSession
    }

    @discardableResult
    func closePane(sessionID: UUID) -> Bool {
        guard let session = sessions.first(where: { $0.id == sessionID }) else { return false }
        session.stop()
        guard let updatedRoot = root.removingLeaf(sessionID: sessionID) else { return false }
        root = updatedRoot
        observeSessions()
        if focusedSessionID == sessionID, let replacement = focusedSession {
            focus(sessionID: replacement.id)
        }
        return true
    }

    func stopAllSessions() {
        sessions.forEach { $0.stop() }
        sessionSubscriptions.removeAll()
    }

    private func observeSessions() {
        sessionSubscriptions.removeAll()
        for session in sessions {
            session.$title
                .sink { [weak self] title in
                    guard let self, self.focusedSessionID == session.id else { return }
                    self.title = title
                }
                .store(in: &sessionSubscriptions)
            session.$status
                .sink { [weak self, session] status in
                    guard let self else { return }
                    if self.focusedSessionID == session.id {
                        self.status = status
                    }
                    guard case .exited = status else { return }
                    Task { @MainActor [weak self, weak session] in
                        guard let self, let session else { return }
                        self.onSessionExited?(session)
                    }
                }
                .store(in: &sessionSubscriptions)
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var workspaces: [TerminalWorkspace] = []
    @Published var selectedWorkspaceID: UUID?
    @Published var isSSHProfileSelectorPresented = false
    private var workspaceSubscriptions: [UUID: AnyCancellable] = [:]
    private var mainWindowOpener: (() -> Void)?
    private var cachedMainWindow: NSWindow?
    private var mainWindowCloseObserver: NSObjectProtocol?
    private var scrollbackLineLimit: Int

    init() {
        scrollbackLineLimit = AppPreferences.persistedScrollbackLineLimit()
        openLocalSession()
    }

    var selectedWorkspace: TerminalWorkspace? {
        guard let selectedWorkspaceID else { return nil }
        return workspaces.first { $0.id == selectedWorkspaceID }
    }

    var selectedSession: TerminalSession? {
        selectedWorkspace?.focusedSession
    }

    func openLocalSession() {
        openWorkspace(session: TerminalSession(
            kind: .local,
            scrollbackLineLimit: scrollbackLineLimit
        ))
    }

    func openSSHSession(profile: SSHProfile) {
        openWorkspace(session: TerminalSession(
            kind: .ssh(profile),
            scrollbackLineLimit: scrollbackLineLimit
        ))
    }

    func configureScrollback(maxLines: Int) {
        let clampedValue = AppPreferences.clampedScrollbackLineLimit(maxLines)
        scrollbackLineLimit = clampedValue
        for workspace in workspaces {
            workspace.sessions.forEach { $0.configureScrollback(maxLines: clampedValue) }
        }
    }

    func showSSHProfileSelector() {
        isSSHProfileSelectorPresented = true
    }

    func registerMainWindowOpener(_ opener: @escaping () -> Void) {
        mainWindowOpener = opener
    }

    func toggleMainWindow() {
        let settingsWindowIdentifier = "com_apple_SwiftUI_Settings_window"
        let appWindows = NSApp.windows.filter {
            $0.identifier?.rawValue != settingsWindowIdentifier
        }
        let discoveredWindow = appWindows.first(where: {
            $0.identifier?.rawValue == "com.matterm.main-window"
        }) ?? appWindows.first(where: { $0.title == "MatTerm" })
            ?? appWindows.first(where: { $0.isMainWindow })
        guard let window = cachedMainWindow ?? discoveredWindow else {
            NSApp.activate(ignoringOtherApps: true)
            mainWindowOpener?()
            return
        }
        trackMainWindow(window)

        if window.isVisible && NSApp.isActive && window.isKeyWindow {
            window.orderOut(nil)
            return
        }

        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { screen in
            screen.frame.contains(mouseLocation)
        } ?? NSScreen.main

        // A global shortcut is invoked while another Space may be active.
        // Ask macOS to move the window into that Space before ordering it.
        window.collectionBehavior.insert(.moveToActiveSpace)
        if let targetScreen, window.screen != targetScreen {
            move(window, to: targetScreen, around: mouseLocation)
        }

        // A hidden regular app must be explicitly unhidden before its window
        // can become key again, especially after the shortcut came from another app.
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }

    private func trackMainWindow(_ window: NSWindow) {
        guard cachedMainWindow !== window else { return }
        if let mainWindowCloseObserver {
            NotificationCenter.default.removeObserver(mainWindowCloseObserver)
        }
        cachedMainWindow = window
        mainWindowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.cachedMainWindow = nil
                self?.mainWindowCloseObserver = nil
            }
        }
    }

    private func move(_ window: NSWindow, to screen: NSScreen, around point: NSPoint) {
        let visibleFrame = screen.visibleFrame
        let size = window.frame.size
        let proposedOrigin = NSPoint(
            x: point.x - size.width / 2,
            y: point.y - size.height / 2
        )
        let maxX = max(visibleFrame.minX, visibleFrame.maxX - size.width)
        let maxY = max(visibleFrame.minY, visibleFrame.maxY - size.height)
        let origin = NSPoint(
            x: min(max(proposedOrigin.x, visibleFrame.minX), maxX),
            y: min(max(proposedOrigin.y, visibleFrame.minY), maxY)
        )
        window.setFrameOrigin(origin)
    }

    func select(_ workspace: TerminalWorkspace) {
        selectedWorkspaceID = workspace.id
        workspace.focusedSession?.requestFocus()
    }

    func focus(_ session: TerminalSession, in workspace: TerminalWorkspace) {
        guard workspaces.contains(where: { $0.id == workspace.id }) else { return }
        selectedWorkspaceID = workspace.id
        workspace.focus(sessionID: session.id)
    }

    func restart(_ session: TerminalSession) {
        session.restart()
    }

    func selectSession(at index: Int) {
        guard workspaces.indices.contains(index) else { return }
        select(workspaces[index])
    }

    func selectNextSession() {
        guard !workspaces.isEmpty,
              let selectedWorkspaceID,
              let index = workspaces.firstIndex(where: { $0.id == selectedWorkspaceID }) else { return }
        selectSession(at: (index + 1) % workspaces.count)
    }

    func selectPreviousSession() {
        guard !workspaces.isEmpty,
              let selectedWorkspaceID,
              let index = workspaces.firstIndex(where: { $0.id == selectedWorkspaceID }) else { return }
        selectSession(at: (index - 1 + workspaces.count) % workspaces.count)
    }

    func clearSelectedTerminal() {
        selectedSession?.clearDisplay()
    }

    func closeSelectedSession() {
        guard let selectedWorkspace else { return }
        closeWorkspace(id: selectedWorkspace.id)
    }

    func closeWorkspace(id: UUID) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        workspaceSubscriptions[id] = nil
        workspaces[index].stopAllSessions()
        workspaces.remove(at: index)
        if selectedWorkspaceID == id {
            selectedWorkspaceID = workspaces.indices.contains(index)
                ? workspaces[index].id
                : workspaces.last?.id
            selectedWorkspace?.focusedSession?.requestFocus()
        }
    }

    func closePane(_ session: TerminalSession, in workspace: TerminalWorkspace) {
        guard workspace.closePane(sessionID: session.id) else {
            closeWorkspace(id: workspace.id)
            return
        }
    }

    func splitSelectedPane(direction: TerminalSplitDirection) {
        guard let selectedWorkspace else { return }
        selectedWorkspace.splitFocusedPane(
            direction: direction,
            scrollbackLineLimit: scrollbackLineLimit
        )
    }

    private func openWorkspace(session: TerminalSession) {
        let workspace = TerminalWorkspace(session: session)
        let workspaceSubscription = workspace.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
        workspaceSubscriptions[workspace.id] = workspaceSubscription
        workspace.onSessionExited = { [weak self, weak workspace] session in
            guard let self, let workspace else { return }
            self.closePane(session, in: workspace)
        }
        workspaces.append(workspace)
        select(workspace)
    }
}
