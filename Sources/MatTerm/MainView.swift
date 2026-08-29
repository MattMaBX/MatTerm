import AppKit
import SwiftUI
import Carbon.HIToolbox

private enum ImportNotice: Identifiable {
    case imported(Int)
    case noneFound

    var id: String {
        switch self {
        case .imported(let count): return "imported-\(count)"
        case .noneFound: return "none-found"
        }
    }

    @MainActor
    func title(using preferences: AppPreferences) -> String {
        switch self {
        case .imported(let count): return preferences.text(.importedSSHHosts(count))
        case .noneFound: return preferences.text(.noNewSSHHosts)
        }
    }

    @MainActor
    func message(using preferences: AppPreferences) -> String {
        switch self {
        case .imported(let count): return preferences.text(.importedSSHHostsMessage(count))
        case .noneFound: return preferences.text(.noNewSSHHostsMessage)
        }
    }
}

struct MainView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var profileStore: SSHProfileStore
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var shortcutStore: ShortcutStore
    @EnvironmentObject private var terminalAppearance: TerminalAppearance
    @Environment(\.openSettings) private var openSettings
    @StateObject private var viewState: MainViewState

    init(
        appState: AppState,
        profileStore: SSHProfileStore
    ) {
        self.appState = appState
        self.profileStore = profileStore
        _viewState = StateObject(wrappedValue: MainViewState())
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $viewState.sidebarVisibility) {
            SidebarView(
                appState: appState,
                profileStore: profileStore,
                editingProfile: $viewState.editingProfile,
                importNotice: $viewState.importNotice
            )
        } detail: {
            SessionWorkspaceView(appState: appState)
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 258, max: 340)
        .frame(minWidth: 920, minHeight: 620)
        .background(
            WindowConfigurationView(
                alwaysOnTop: preferences.alwaysOnTop
            )
        )
        .sheet(item: $viewState.editingProfile) { profile in
            ProfileEditorView(profile: profile) { savedProfile in
                profileStore.upsert(savedProfile)
                viewState.editingProfile = nil
            }
        }
        .sheet(isPresented: $appState.isSSHProfileSelectorPresented) {
            SSHProfileSelectorView(appState: appState, profileStore: profileStore)
        }
        .onAppear {
            shortcutStore.installRuntimeHandler(appState: appState, profileStore: profileStore)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    openSettings()
                } label: {
                    Text(preferences.text(.application))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(toolbarForeground)
                        .fixedSize()
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
            }
            ToolbarItem(placement: .principal) {
                CompactTabStrip(appState: appState)
            }
            ToolbarItem(placement: .primaryAction) {
                Button { appState.openLocalSession() } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(toolbarForeground)
                }
                .buttonStyle(.borderless)
                .help(preferences.text(.newLocalTab))
            }
        }
        .toolbarBackground(
            terminalAppearance.theme.background,
            for: .windowToolbar
        )
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbarColorScheme(
            terminalAppearance.isDarkTheme ? .dark : .light,
            for: .windowToolbar
        )
    }

    private var toolbarForeground: Color {
        terminalAppearance.isDarkTheme ? .white : .black
    }
}

private struct WindowConfigurationView: NSViewRepresentable {
    let alwaysOnTop: Bool

    func makeNSView(context: Context) -> WindowConfigurationNSView {
        return WindowConfigurationNSView(alwaysOnTop: alwaysOnTop)
    }

    func updateNSView(_ nsView: WindowConfigurationNSView, context: Context) {
        nsView.configureWindow(alwaysOnTop: alwaysOnTop)
    }
}

private final class WindowConfigurationNSView: NSView {
    private var alwaysOnTop: Bool
    private let frameDefaultsKey = "application.mainWindowFrame"
    private var frameObservers: [NSObjectProtocol] = []
    private var hasRestoredFrame = false
    private var restoreScheduled = false
    private var titlebarMouseMonitor: Any?
    private var isDraggingWindow = false
    private var dragStartMouseLocation = NSPoint.zero
    private var dragStartWindowOrigin = NSPoint.zero

    init(alwaysOnTop: Bool) {
        self.alwaysOnTop = alwaysOnTop
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        alwaysOnTop = false
        super.init(coder: coder)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeFrameObservers()
        removeTitlebarMouseMonitor()
        configureWindow(alwaysOnTop: alwaysOnTop)
        installFrameObservers()
        scheduleFrameRestore()
    }

    func configureWindow(alwaysOnTop: Bool) {
        self.alwaysOnTop = alwaysOnTop
        guard let window else { return }
        window.identifier = NSUserInterfaceItemIdentifier("com.matterm.main-window")
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = alwaysOnTop ? .floating : .normal
        window.toolbarStyle = .unifiedCompact
        window.titlebarAppearsTransparent = true
        // The compact toolbar owns the visible app name so its contrast
        // follows the terminal theme instead of the system titlebar.
        window.titleVisibility = .hidden
        hideNativeTitle(in: window, hidden: true)
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            self.hideNativeTitle(in: window, hidden: true)
        }
        window.styleMask.insert(.fullSizeContentView)
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        installTitlebarMouseMonitor(for: window)
        scheduleFrameRestore()
    }

    private func hideNativeTitle(in window: NSWindow, hidden: Bool) {
        guard let frameView = window.contentView?.superview else { return }
        updateNativeTitle(in: frameView, hidden: hidden)
    }

    private func updateNativeTitle(in view: NSView, hidden: Bool) {
        for subview in view.subviews {
            if let textField = subview as? NSTextField,
               textField.stringValue == "MatTerm" {
                textField.isHidden = hidden
            }
            updateNativeTitle(in: subview, hidden: hidden)
        }
    }

    private func installTitlebarMouseMonitor(for window: NSWindow) {
        guard titlebarMouseMonitor == nil else { return }

        let eventMask = NSEvent.EventTypeMask.leftMouseDown
            .union(.leftMouseDragged)
            .union(.leftMouseUp)
        titlebarMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask) { [weak self, weak window] event in
            guard let self, let window else {
                return event
            }

            if self.isDraggingWindow {
                switch event.type {
                case .leftMouseDragged:
                    self.updateWindowDrag(with: event, in: window)
                    return nil
                case .leftMouseUp:
                    self.isDraggingWindow = false
                    return nil
                default:
                    return event
                }
            }

            guard event.type == .leftMouseDown,
                  event.window === window,
                  self.isTitlebarEvent(event, in: window),
                  !self.isInteractiveTitlebarControl(at: event.locationInWindow, in: window) else {
                return event
            }

            self.beginWindowDrag(with: event, in: window)
            return nil
        }
    }

    private func removeTitlebarMouseMonitor() {
        isDraggingWindow = false
        guard let titlebarMouseMonitor else { return }
        NSEvent.removeMonitor(titlebarMouseMonitor)
        self.titlebarMouseMonitor = nil
    }

    private func isTitlebarEvent(_ event: NSEvent, in window: NSWindow) -> Bool {
        let point = event.locationInWindow
        let frame = window.frame
        let titlebarTop = frame.height - 36
        let isNearResizeEdge = point.x <= 6 || point.x >= frame.width - 6 || point.y >= frame.height - 6
        return point.y >= titlebarTop && !isNearResizeEdge
    }

    private func beginWindowDrag(with event: NSEvent, in window: NSWindow) {
        isDraggingWindow = true
        dragStartMouseLocation = window.convertToScreen(NSRect(origin: event.locationInWindow, size: .zero)).origin
        dragStartWindowOrigin = window.frame.origin
    }

    private func updateWindowDrag(with event: NSEvent, in window: NSWindow) {
        let mouseLocation = window.convertToScreen(NSRect(origin: event.locationInWindow, size: .zero)).origin
        let delta = NSPoint(
            x: mouseLocation.x - dragStartMouseLocation.x,
            y: mouseLocation.y - dragStartMouseLocation.y
        )
        window.setFrameOrigin(NSPoint(
            x: dragStartWindowOrigin.x + delta.x,
            y: dragStartWindowOrigin.y + delta.y
        ))
    }

    private func isInteractiveTitlebarControl(at point: NSPoint, in window: NSWindow) -> Bool {
        for buttonType in [
            NSWindow.ButtonType.closeButton,
            .miniaturizeButton,
            .zoomButton,
            .documentIconButton,
            .documentVersionsButton
        ] {
            guard let button = window.standardWindowButton(buttonType) else { continue }
            let buttonFrame = button.convert(button.bounds, to: nil)
            if buttonFrame.contains(point) { return true }
        }

        guard let frameView = window.contentView?.superview else { return false }
        let framePoint = frameView.convert(point, from: nil)
        var view = frameView.hitTest(framePoint)
        while let current = view {
            if current is NSControl || String(describing: type(of: current)).contains("Hosting") {
                return true
            }
            view = current.superview
        }
        return false
    }

    private func installFrameObservers() {
        guard let window, frameObservers.isEmpty else { return }
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.didMoveNotification,
            NSWindow.didResizeNotification,
            NSWindow.didEndLiveResizeNotification,
            NSApplication.willTerminateNotification
        ]
        frameObservers = names.map { name in
            center.addObserver(
                forName: name,
                object: name == NSApplication.willTerminateNotification ? nil : window,
                queue: .main
            ) { [weak self, weak window] _ in
                Task { @MainActor [weak self, weak window] in
                    guard let self else { return }
                    if name == NSApplication.willTerminateNotification || self.window === window {
                        self.saveWindowFrame()
                    }
                }
            }
        }
    }

    private func removeFrameObservers() {
        let center = NotificationCenter.default
        frameObservers.forEach(center.removeObserver)
        frameObservers.removeAll()
    }

    private func scheduleFrameRestore() {
        guard window != nil, !hasRestoredFrame, !restoreScheduled else { return }
        restoreScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil else { return }
            self.restoreScheduled = false
            self.hasRestoredFrame = true
            self.restoreWindowFrame()
        }
    }

    private func restoreWindowFrame() {
        guard let window,
              let savedValue = UserDefaults.standard.string(forKey: frameDefaultsKey) else { return }

        let savedFrame = NSRectFromString(savedValue)
        guard savedFrame.width >= 920,
              savedFrame.height >= 620,
              savedFrame.width.isFinite,
              savedFrame.height.isFinite else { return }

        if NSScreen.screens.contains(where: { savedFrame.intersects($0.visibleFrame) }) {
            window.setFrame(savedFrame, display: true)
            return
        }

        // Keep a disconnected display from making the app launch off-screen.
        guard let visibleFrame = NSScreen.main?.visibleFrame else { return }
        let width = min(savedFrame.width, visibleFrame.width)
        let height = min(savedFrame.height, visibleFrame.height)
        let origin = NSPoint(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.midY - height / 2
        )
        window.setFrame(
            NSRect(origin: origin, size: NSSize(width: width, height: height)),
            display: true
        )
    }

    private func saveWindowFrame() {
        guard let window, window.frame.width >= 1, window.frame.height >= 1 else { return }
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: frameDefaultsKey)
    }
}

private struct SettingsWindowConfigurationView: NSViewRepresentable {
    func makeNSView(context: Context) -> SettingsWindowConfigurationNSView {
        SettingsWindowConfigurationNSView()
    }

    func updateNSView(_ nsView: SettingsWindowConfigurationNSView, context: Context) {
        nsView.configureWindow()
    }
}

private final class SettingsWindowConfigurationNSView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureWindow()
    }

    func configureWindow() {
        guard let window else { return }
        // Keep settings above the main terminal even when the latter is floating.
        window.level = .modalPanel
    }
}

@MainActor
private final class MainViewState: ObservableObject {
    @Published var editingProfile: SSHProfile?
    @Published var importNotice: ImportNotice?
    @Published var sidebarVisibility: NavigationSplitViewVisibility

    init() {
        sidebarVisibility = .detailOnly
    }
}

private struct SidebarView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var profileStore: SSHProfileStore
    @EnvironmentObject private var preferences: AppPreferences
    @Environment(\.colorScheme) private var systemColorScheme
    @Binding var editingProfile: SSHProfile?
    @Binding var importNotice: ImportNotice?

    var body: some View {
        List {
            Section(preferences.text(.sessions)) {
                ForEach(appState.workspaces) { workspace in
                    Button {
                        appState.select(workspace)
                    } label: {
                        SessionRow(workspace: workspace, isSelected: appState.selectedWorkspaceID == workspace.id)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(preferences.text(.restartSession)) {
                            workspace.sessions.forEach { appState.restart($0) }
                        }
                        Button(preferences.text(.closeTab), role: .destructive) {
                            appState.closeWorkspace(id: workspace.id)
                        }
                    }
                }
            }

            Section(preferences.text(.sshHosts)) {
                if profileStore.profiles.isEmpty {
                    Text(preferences.text(.noSavedHosts))
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    ForEach(profileStore.profiles) { profile in
                        Button {
                            appState.openSSHSession(profile: profile)
                        } label: {
                            ProfileRow(profile: profile)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(preferences.text(.edit)) { editingProfile = profile }
                            Button(preferences.text(.delete), role: .destructive) {
                                profileStore.delete(profile)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                Button { editingProfile = SSHProfile() } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help(preferences.text(.addSSHHost))

                Button {
                    let importedCount = profileStore.importOpenSSHConfig()
                    importNotice = importedCount == 0 ? .noneFound : .imported(importedCount)
                } label: {
                    Image(systemName: "arrow.down.doc")
                }
                .buttonStyle(.borderless)
                .help(preferences.text(.importSSHConfig))

                Spacer()

                Button { appState.openLocalSession() } label: {
                    Image(systemName: "terminal")
                }
                .buttonStyle(.borderless)
                .help(preferences.text(.newLocalTab))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .navigationTitle(preferences.text(.application))
        .environment(\.colorScheme, resolvedColorScheme)
        .alert(item: $importNotice) { notice in
            Alert(
                title: Text(notice.title(using: preferences)),
                message: Text(notice.message(using: preferences)),
                dismissButton: .default(Text(preferences.text(.okay)))
            )
        }
    }

    private var resolvedColorScheme: ColorScheme {
        switch preferences.sidebarAppearance {
        case .dark: return .dark
        case .light: return .light
        case .system: return systemColorScheme
        }
    }
}

private struct SessionRow: View {
    @ObservedObject var workspace: TerminalWorkspace
    @EnvironmentObject private var preferences: AppPreferences
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: workspace.iconName)
                .frame(width: 18)
                .foregroundStyle(isSelected ? .primary : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(workspace.title).lineLimit(1)
                Text(statusLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Circle().fill(statusColor).frame(width: 7, height: 7)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.18) : .clear)
    }

    private var status: SessionStatus { workspace.status }

    private var statusLabel: String {
        switch status {
        case .running: return preferences.text(.connected)
        case .connecting: return preferences.text(.connecting)
        case .exited: return preferences.text(.exited)
        case .failed: return preferences.text(.failed)
        }
    }

    private var statusColor: Color {
        switch status {
        case .running: return .green
        case .connecting: return .orange
        case .exited, .failed: return .secondary
        }
    }
}

private struct ProfileRow: View {
    let profile: SSHProfile

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "network").frame(width: 18).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name).lineLimit(1)
                Text(profile.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct SessionWorkspaceView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            if let workspace = appState.selectedWorkspace {
                WorkspaceRootView(appState: appState, workspace: workspace)
            } else {
                EmptySessionView { appState.openLocalSession() }
            }
        }
        .background(Color.clear)
    }
}

private struct WorkspaceRootView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var workspace: TerminalWorkspace

    var body: some View {
        SplitNodeView(appState: appState, workspace: workspace, node: workspace.root)
    }
}

private struct SplitNodeView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var workspace: TerminalWorkspace
    let node: TerminalSplitNode

    var body: some View {
        switch node {
        case .leaf(let session):
            ActivePaneView(appState: appState, workspace: workspace, session: session)
        case .split(let axis, let first, let second):
            if axis == .horizontal {
                HSplitView {
                    SplitNodeView(appState: appState, workspace: workspace, node: first)
                        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                    SplitNodeView(appState: appState, workspace: workspace, node: second)
                        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VSplitView {
                    SplitNodeView(appState: appState, workspace: workspace, node: first)
                        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                    SplitNodeView(appState: appState, workspace: workspace, node: second)
                        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct ActivePaneView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var workspace: TerminalWorkspace
    @ObservedObject var session: TerminalSession
    @EnvironmentObject private var terminalAppearance: TerminalAppearance
    @EnvironmentObject private var preferences: AppPreferences

    private var isFocused: Bool { workspace.focusedSessionID == session.id }

    var body: some View {
        ZStack {
            TerminalBackdropView(appearance: terminalAppearance)
                .allowsHitTesting(false)
            VStack(spacing: 0) {
                TerminalView(
                    session: session,
                    isFocusedPane: isFocused,
                    onFocus: { appState.focus(session, in: workspace) }
                )
                    .id(session.id)
                SessionStatusBar(session: session, appearance: terminalAppearance) {
                    Spacer(minLength: 0)
                    Button { appState.restart(session) } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help(preferences.text(.restartSession))
                }
                .padding(.horizontal, 12)
                .frame(height: 28)
            }
        }
        .clipped()
    }
}

private struct SessionStatusBar<Content: View>: View {
    @ObservedObject var session: TerminalSession
    @ObservedObject var appearance: TerminalAppearance
    @EnvironmentObject private var preferences: AppPreferences
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(statusColor).frame(width: 7, height: 7)
            Text(statusLabel).font(.caption).foregroundStyle(appearance.theme.secondary)
            if let detail = session.status.detail {
                Text(localizedDetail(detail))
                    .font(.caption)
                    .foregroundStyle(appearance.theme.secondary)
                    .lineLimit(1)
            }
            content()
        }
    }

    private var statusLabel: String {
        switch session.status {
        case .running: return preferences.text(.connected)
        case .connecting: return preferences.text(.connecting)
        case .exited: return preferences.text(.exited)
        case .failed: return preferences.text(.failed)
        }
    }

    private var statusColor: Color {
        switch session.status {
        case .running: return .green
        case .connecting: return .orange
        case .exited, .failed: return .secondary
        }
    }

    private func localizedDetail(_ detail: String) -> String {
        if detail == "Process finished" { return preferences.text(.processFinished) }
        if detail.hasPrefix("Process exited with code ") {
            return preferences.language == .simplifiedChinese
                ? "进程已退出，代码 " + detail.replacingOccurrences(of: "Process exited with code ", with: "")
                : detail
        }
        return detail
    }
}

private struct CompactTabStrip: View {
    @ObservedObject var appState: AppState

    fileprivate static let tabHeight: CGFloat = 24
    private let maximumWidth: CGFloat = 720

    private var contentWidth: CGFloat {
        let tabWidths = appState.workspaces.map { compactTabWidth(for: $0) }
        return tabWidths.reduce(0, +)
    }

    private var tabStripWidth: CGFloat {
        min(max(80, contentWidth + 4), maximumWidth)
    }

    private func compactTabWidth(for workspace: TerminalWorkspace) -> CGFloat {
        let isSelected = workspace.id == appState.selectedWorkspaceID
        let titleWidth = TabItem.compactTitleWidth(for: workspace.title, isSelected: isSelected)
        let visibleElementWidths: CGFloat = 14 + titleWidth + 14
        let elementSpacing: CGFloat = isSelected ? 15 : 10
        return 16 + visibleElementWidths + elementSpacing
    }

    var body: some View {
        let width = tabStripWidth
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(appState.workspaces.enumerated()), id: \.element.id) { index, workspace in
                    TabItem(
                        workspace: workspace,
                        isSelected: workspace.id == appState.selectedWorkspaceID,
                        onSelect: { appState.select(workspace) },
                        onClose: { appState.closeWorkspace(id: workspace.id) },
                        showsDivider: index < appState.workspaces.count - 1
                    )
                }
            }
            .padding(.leading, 0)
            .padding(.trailing, 4)
            .frame(minWidth: width - 8, minHeight: Self.tabHeight, alignment: .center)
        }
        .frame(width: width, height: Self.tabHeight)
    }
}

private struct TabItem: View {
    @ObservedObject var workspace: TerminalWorkspace
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var terminalAppearance: TerminalAppearance
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    var showsDivider = false

    var body: some View {
        HStack(spacing: 6) {
            activeIndicator
            Image(systemName: workspace.iconName).font(.caption)
            Text(workspace.title)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: Self.compactTitleWidth(for: workspace.title, isSelected: isSelected), alignment: .leading)
            Button(action: onClose) {
                Image(systemName: "xmark").font(.caption2.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .help(preferences.text(.closeTab))
        }
        .padding(.horizontal, 8)
        .frame(height: CompactTabStrip.tabHeight)
        .foregroundStyle(isSelected ? toolbarForeground : toolbarForeground.opacity(0.64))
        .fontWeight(isSelected ? .medium : .regular)
        .background {
            if isSelected {
                Capsule()
                    .fill(terminalAppearance.theme.foreground.opacity(0.14))
            }
        }
        .overlay(alignment: .trailing) {
            if showsDivider {
                Rectangle()
                    .fill(terminalAppearance.theme.foreground.opacity(0.12))
                    .frame(width: 0.5, height: 16)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }

    private var toolbarForeground: Color {
        terminalAppearance.isDarkTheme ? .white : .black
    }

    fileprivate static func compactTitleWidth(for title: String, isSelected: Bool) -> CGFloat {
        let font = NSFont.systemFont(
            ofSize: NSFont.smallSystemFontSize,
            weight: isSelected ? .medium : .regular
        )
        return min(
            260,
            max(36, ceil((title as NSString).size(withAttributes: [.font: font]).width))
        )
    }

    @ViewBuilder
    private var activeIndicator: some View {
        if isSelected {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
        }
    }

}

private struct EmptySessionView: View {
    @EnvironmentObject private var preferences: AppPreferences
    let onOpen: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "terminal.fill").font(.system(size: 34)).foregroundStyle(.secondary)
            Text(preferences.text(.noActiveSession)).font(.title3.weight(.medium))
            Button(preferences.text(.openLocalTab), action: onOpen)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var terminalAppearance: TerminalAppearance
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var shortcutStore: ShortcutStore
    @StateObject private var settingsState = SettingsViewState()

    var body: some View {
        Form {
            Section(preferences.text(.application)) {
                LabeledContent(preferences.text(.version), value: "0.2.0")
                Picker(preferences.text(.language), selection: $preferences.language) {
                    Text(preferences.text(.english)).tag(AppLanguage.english)
                    Text(preferences.text(.simplifiedChinese)).tag(AppLanguage.simplifiedChinese)
                }
                Toggle(preferences.text(.keepWindowOnTop), isOn: $preferences.alwaysOnTop)
                Picker(preferences.text(.sidebarAppearance), selection: $preferences.sidebarAppearance) {
                    Text(preferences.text(.sidebarSystem)).tag(SidebarAppearance.system)
                    Text(preferences.text(.sidebarDark)).tag(SidebarAppearance.dark)
                    Text(preferences.text(.sidebarLight)).tag(SidebarAppearance.light)
                }
            }

            Section(preferences.text(.terminal)) {
                LabeledContent(preferences.text(.scrollback)) {
                    HStack(spacing: 8) {
                        TextField("", value: $preferences.scrollbackLineLimit, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .frame(width: 110)
                            .accessibilityLabel(preferences.text(.scrollback))
                        Stepper(
                            "",
                            value: $preferences.scrollbackLineLimit,
                            in: AppPreferences.scrollbackLineLimitRange,
                            step: 1_000
                        )
                        .labelsHidden()
                        Text(preferences.language == .simplifiedChinese ? "行" : "lines")
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .leading)
                    }
                }
                Picker(preferences.text(.colorScheme), selection: $terminalAppearance.theme) {
                    ForEach(TerminalTheme.allCases) { theme in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(theme.background.opacity(terminalAppearance.backgroundOpacity))
                                .overlay { Circle().fill(theme.foreground).frame(width: 6, height: 6) }
                                .frame(width: 24, height: 16)
                            Text(theme.title)
                        }
                        .tag(theme)
                    }
                }
                Picker(preferences.text(.font), selection: $terminalAppearance.fontFamily) {
                    ForEach(TerminalAppearance.availableMonospacedFontFamilies, id: \.self) { family in
                        Text(family).font(.custom(family, size: 13)).tag(family)
                    }
                }
                SliderSetting(title: preferences.text(.fontSize), value: $terminalAppearance.fontSize, range: 10...28, step: 1, suffix: " pt")
                SliderSetting(title: preferences.text(.lineSpacing), value: $terminalAppearance.lineSpacing, range: 0...12, step: 1, suffix: " pt")
                SliderSetting(title: preferences.text(.backgroundOpacity), value: $terminalAppearance.backgroundOpacity, range: 0...1, step: 0.05, suffix: "%", displayMultiplier: 100)
                SliderSetting(title: preferences.text(.backgroundBlur), value: $terminalAppearance.backgroundBlur, range: 0...24, step: 1, suffix: "")
                Toggle(preferences.text(.blinkingCursor), isOn: $terminalAppearance.cursorBlinkEnabled)
                Toggle(preferences.text(.metaKey), isOn: $preferences.metaKeyEnabled)
            }

            Section(preferences.text(.keyboardShortcuts)) {
                ForEach(ShortcutAction.allCases) { action in
                    HStack {
                        Text(action.title(language: preferences.language))
                        Spacer(minLength: 16)
                        KeyboardShortcutRecorder(
                            binding: shortcutStore.binding(for: action),
                            isRecording: settingsState.recordingAction == action,
                            recordingTitle: preferences.text(.recordingShortcut),
                            helpText: preferences.text(.shortcutCaptureHelp),
                            onBegin: {
                                settingsState.shortcutError = nil
                                settingsState.recordingAction = action
                            },
                            onCapture: { binding in
                                settingsState.shortcutError = shortcutStore.set(binding, for: action)
                                settingsState.recordingAction = nil
                            },
                            onCancel: {
                                settingsState.recordingAction = nil
                                settingsState.shortcutError = nil
                            }
                        )
                        .frame(width: 145)
                    }
                }
                Button(preferences.text(.resetShortcuts)) {
                    shortcutStore.reset()
                    settingsState.recordingAction = nil
                }
                if let shortcutError = settingsState.shortcutError {
                    Text(preferences.text(shortcutError)).foregroundStyle(.red).font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 570, height: 640)
        .padding()
        .background(SettingsWindowConfigurationView())
        .onAppear {
            appState.configureScrollback(maxLines: preferences.scrollbackLineLimit)
        }
        .onChange(of: preferences.scrollbackLineLimit) { _, maxLines in
            appState.configureScrollback(maxLines: maxLines)
        }
    }
}

@MainActor
private final class SettingsViewState: ObservableObject {
    @Published var recordingAction: ShortcutAction?
    @Published var shortcutError: AppText?
}

private struct SliderSetting: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let suffix: String
    var displayMultiplier: Double = 1

    var body: some View {
        HStack {
            Text(title)
            Slider(value: $value, in: range, step: step)
            Text("\(Int((value * displayMultiplier).rounded()))\(suffix)")
                .monospacedDigit()
                .frame(width: 55, alignment: .trailing)
        }
    }
}

private struct SSHProfileSelectorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var appState: AppState
    @ObservedObject var profileStore: SSHProfileStore
    @EnvironmentObject private var preferences: AppPreferences
    @StateObject private var selectorState = SSHProfileSelectorState()
    @FocusState private var searchIsFocused: Bool

    private var filteredProfiles: [SSHProfile] {
        guard !selectorState.query.isEmpty else { return profileStore.profiles }
        return profileStore.profiles.filter {
            $0.name.localizedCaseInsensitiveContains(selectorState.query)
                || $0.host.localizedCaseInsensitiveContains(selectorState.query)
                || $0.username.localizedCaseInsensitiveContains(selectorState.query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(preferences.text(.chooseSSHHost)).font(.headline)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
            }
            .padding()
            TextField(preferences.text(.searchSSHHosts), text: $selectorState.query)
                .textFieldStyle(.roundedBorder)
                .focused($searchIsFocused)
                .onSubmit { connectSelectedProfile() }
                .padding(.horizontal)
            List(filteredProfiles) { profile in
                Button {
                    connect(profile)
                } label: { ProfileRow(profile: profile) }
                .buttonStyle(.plain)
                .listRowBackground(
                    profile.id == selectorState.selectedProfileID
                        ? Color.accentColor.opacity(0.18)
                        : Color.clear
                )
            }
            .overlay {
                if filteredProfiles.isEmpty {
                    Text(preferences.text(.noMatchingSSHHosts)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 430, height: 430)
        .padding(.bottom, 8)
        .background(
            SelectorWindowAccessor { window in
                selectorState.installKeyboardMonitor(
                    for: window,
                    profiles: { filteredProfiles },
                    onConnect: { profile in connect(profile) },
                    onDismiss: { dismiss() }
                )
            }
        )
        .onAppear {
            selectorState.selectFirst(from: filteredProfiles)
            DispatchQueue.main.async {
                searchIsFocused = true
            }
        }
        .onDisappear {
            selectorState.removeKeyboardMonitor()
        }
        .onChange(of: selectorState.query) { _, _ in
            selectorState.selectFirst(from: filteredProfiles)
        }
        .onChange(of: profileStore.profiles) { _, _ in
            selectorState.selectFirst(from: filteredProfiles)
        }
    }

    private func connectSelectedProfile() {
        guard let profile = filteredProfiles.first(where: { $0.id == selectorState.selectedProfileID })
                ?? filteredProfiles.first else { return }
        connect(profile)
    }

    private func connect(_ profile: SSHProfile) {
        appState.openSSHSession(profile: profile)
        dismiss()
    }
}

private struct SelectorWindowAccessor: NSViewRepresentable {
    let onWindowChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> SelectorWindowAccessorNSView {
        SelectorWindowAccessorNSView(onWindowChange: onWindowChange)
    }

    func updateNSView(_ nsView: SelectorWindowAccessorNSView, context: Context) {
        nsView.onWindowChange = onWindowChange
        onWindowChange(nsView.window)
    }
}

private final class SelectorWindowAccessorNSView: NSView {
    var onWindowChange: (NSWindow?) -> Void

    init(onWindowChange: @escaping (NSWindow?) -> Void) {
        self.onWindowChange = onWindowChange
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange(window)
        scheduleSearchFieldFocus()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        scheduleSearchFieldFocus()
    }

    private func scheduleSearchFieldFocus() {
        guard let window else { return }
        for delay in [0.0, 0.05, 0.15] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak window] in
                guard let self, let window, window.isVisible else { return }
                self.focusSearchField(in: window)
            }
        }
    }

    private func focusSearchField(in window: NSWindow) {
        window.contentView?.layoutSubtreeIfNeeded()
        guard let field = editableTextField(in: window.contentView) else { return }
        if window.firstResponder !== field {
            window.makeFirstResponder(field)
        }
    }

    private func editableTextField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let field = view as? NSTextField, field.isEditable, field.isEnabled {
            return field
        }
        for subview in view.subviews.reversed() {
            if let field = editableTextField(in: subview) {
                return field
            }
        }
        return nil
    }
}

@MainActor
private final class SSHProfileSelectorState: ObservableObject {
    @Published var query = ""
    @Published var selectedProfileID: SSHProfile.ID?

    private var keyboardMonitor: Any?
    private weak var selectorWindow: NSWindow?

    func selectFirst(from profiles: [SSHProfile]) {
        guard !profiles.isEmpty else {
            selectedProfileID = nil
            return
        }
        if let selectedProfileID, profiles.contains(where: { $0.id == selectedProfileID }) {
            return
        }
        selectedProfileID = profiles[0].id
    }

    func installKeyboardMonitor(
        for window: NSWindow?,
        profiles: @escaping () -> [SSHProfile],
        onConnect: @escaping (SSHProfile) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        guard let window else { return }
        if selectorWindow === window, keyboardMonitor != nil { return }
        removeKeyboardMonitor()
        selectorWindow = window
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak window] event in
            guard let self, let window, event.window === window else { return event }
            let protectedModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
            guard event.modifierFlags.intersection(protectedModifiers).isEmpty else { return event }

            let available = profiles()
            switch event.keyCode {
            case UInt16(kVK_UpArrow):
                self.moveSelection(in: available, offset: -1)
                return nil
            case UInt16(kVK_DownArrow):
                self.moveSelection(in: available, offset: 1)
                return nil
            case UInt16(kVK_Return), UInt16(kVK_ANSI_KeypadEnter):
                guard let profile = available.first(where: { $0.id == self.selectedProfileID })
                        ?? available.first else { return nil }
                onConnect(profile)
                return nil
            case UInt16(kVK_Escape):
                onDismiss()
                return nil
            default:
                return event
            }
        }
    }

    func removeKeyboardMonitor() {
        if let keyboardMonitor {
            NSEvent.removeMonitor(keyboardMonitor)
            self.keyboardMonitor = nil
        }
        selectorWindow = nil
    }

    private func moveSelection(in profiles: [SSHProfile], offset: Int) {
        guard !profiles.isEmpty else { return }
        let currentIndex = selectedProfileID.flatMap { id in
            profiles.firstIndex { $0.id == id }
        } ?? (offset > 0 ? -1 : 0)
        let nextIndex = (currentIndex + offset + profiles.count) % profiles.count
        selectedProfileID = profiles[nextIndex].id
    }
}
