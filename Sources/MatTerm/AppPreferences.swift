import AppKit
import SwiftUI
import Carbon.HIToolbox

enum AppLanguage: String, CaseIterable, Identifiable {
    case english
    case simplifiedChinese

    var id: String { rawValue }
}

enum AppDisplayMode: String, CaseIterable, Identifiable {
    case traditional
    case compact

    var id: String { rawValue }
}

enum AppText {
    case sessions
    case sshHosts
    case noSavedHosts
    case restartSession
    case closeTab
    case edit
    case delete
    case addSSHHost
    case importSSHConfig
    case newLocalTab
    case noActiveSession
    case openLocalTab
    case terminal
    case clearTerminal
    case increaseFontSize
    case decreaseFontSize
    case resetFontSize
    case nextTab
    case previousTab
    case selectTab(Int)
    case version
    case minimumMacOS
    case defaultShell
    case scrollback
    case colorScheme
    case font
    case fontSize
    case lineSpacing
    case backgroundOpacity
    case backgroundBlur
    case blinkingCursor
    case application
    case language
    case english
    case simplifiedChinese
    case keepWindowOnTop
    case displayMode
    case traditionalMode
    case compactMode
    case restartRequiredTitle
    case restartRequiredMessage
    case restartNow
    case restartLater
    case keyboardShortcuts
    case resetShortcuts
    case sshProfileSelector
    case searchSSHHosts
    case noMatchingSSHHosts
    case shortcutNeedsCommand
    case shortcutAlreadyInUse
    case splitLeft
    case splitRight
    case splitAbove
    case splitBelow
    case showSSHSelector
    case toggleWindow
    case chooseSSHHost
    case sshHost
    case name
    case host
    case username
    case port
    case identityFileOptional
    case chooseIdentityFile
    case cancel
    case save
    case okay
    case connected
    case connecting
    case exited
    case failed
    case processFinished
    case importedSSHHosts(Int)
    case noNewSSHHosts
    case importedSSHHostsMessage(Int)
    case noNewSSHHostsMessage
    case recordingShortcut
    case shortcutCaptureHelp

    func value(language: AppLanguage) -> String {
        switch language {
        case .english:
            switch self {
            case .sessions: return "Sessions"
            case .sshHosts: return "SSH Hosts"
            case .noSavedHosts: return "No saved hosts"
            case .restartSession: return "Restart Session"
            case .closeTab: return "Close Tab"
            case .edit: return "Edit"
            case .delete: return "Delete"
            case .addSSHHost: return "Add SSH host"
            case .importSSHConfig: return "Import from ~/.ssh/config"
            case .newLocalTab: return "New Local Tab"
            case .noActiveSession: return "No active session"
            case .openLocalTab: return "Open Local Tab"
            case .terminal: return "Terminal"
            case .clearTerminal: return "Clear Terminal"
            case .increaseFontSize: return "Increase Font Size"
            case .decreaseFontSize: return "Decrease Font Size"
            case .resetFontSize: return "Reset Font Size"
            case .nextTab: return "Next Tab"
            case .previousTab: return "Previous Tab"
            case .selectTab(let index): return "Select Tab \(index)"
            case .version: return "Version"
            case .minimumMacOS: return "Minimum macOS"
            case .defaultShell: return "Default shell"
            case .scrollback: return "Scrollback"
            case .colorScheme: return "Color scheme"
            case .font: return "Font"
            case .fontSize: return "Font size"
            case .lineSpacing: return "Line spacing"
            case .backgroundOpacity: return "Background opacity"
            case .backgroundBlur: return "Background blur"
            case .blinkingCursor: return "Blinking cursor"
            case .application: return "MatTerm"
            case .language: return "Language"
            case .english: return "English"
            case .simplifiedChinese: return "Simplified Chinese"
            case .keepWindowOnTop: return "Keep Window on Top"
            case .displayMode: return "Display Mode"
            case .traditionalMode: return "Traditional"
            case .compactMode: return "Compact"
            case .restartRequiredTitle: return "Restart Required"
            case .restartRequiredMessage: return "Restart MatTerm to apply the new display mode."
            case .restartNow: return "Restart Now"
            case .restartLater: return "Later"
            case .keyboardShortcuts: return "Keyboard Shortcuts"
            case .resetShortcuts: return "Reset Shortcuts"
            case .sshProfileSelector: return "SSH Profile Selector"
            case .searchSSHHosts: return "Search SSH hosts"
            case .noMatchingSSHHosts: return "No matching SSH hosts"
            case .shortcutNeedsCommand: return "Shortcuts must include Command."
            case .shortcutAlreadyInUse: return "This shortcut is already assigned."
            case .splitLeft: return "Split Left"
            case .splitRight: return "Split Right"
            case .splitAbove: return "Split Above"
            case .splitBelow: return "Split Below"
            case .showSSHSelector: return "Show SSH Profile Selector"
            case .toggleWindow: return "Show/Hide MatTerm"
            case .chooseSSHHost: return "Choose SSH Host"
            case .sshHost: return "SSH Host"
            case .name: return "Name"
            case .host: return "Host"
            case .username: return "Username"
            case .port: return "Port"
            case .identityFileOptional: return "Identity file (optional)"
            case .chooseIdentityFile: return "Choose identity file"
            case .cancel: return "Cancel"
            case .save: return "Save"
            case .okay: return "OK"
            case .connected: return "Connected"
            case .connecting: return "Connecting"
            case .exited: return "Exited"
            case .failed: return "Failed"
            case .processFinished: return "Process finished"
            case .importedSSHHosts: return "SSH Hosts Imported"
            case .noNewSSHHosts: return "No New Hosts"
            case .importedSSHHostsMessage(let count):
                return "Imported \(count) new host\(count == 1 ? "" : "s") from ~/.ssh/config."
            case .noNewSSHHostsMessage: return "No new hosts were found in ~/.ssh/config."
            case .recordingShortcut: return "Press shortcut"
            case .shortcutCaptureHelp: return "Click to record a shortcut. Press Escape to cancel."
            }
        case .simplifiedChinese:
            switch self {
            case .sessions: return "会话"
            case .sshHosts: return "SSH 主机"
            case .noSavedHosts: return "没有已保存的主机"
            case .restartSession: return "重新启动会话"
            case .closeTab: return "关闭标签页"
            case .edit: return "编辑"
            case .delete: return "删除"
            case .addSSHHost: return "添加 SSH 主机"
            case .importSSHConfig: return "从 ~/.ssh/config 导入"
            case .newLocalTab: return "新建本地标签页"
            case .noActiveSession: return "没有活动会话"
            case .openLocalTab: return "打开本地标签页"
            case .terminal: return "终端"
            case .clearTerminal: return "清空终端"
            case .increaseFontSize: return "增大字号"
            case .decreaseFontSize: return "减小字号"
            case .resetFontSize: return "重置字号"
            case .nextTab: return "下一个标签页"
            case .previousTab: return "上一个标签页"
            case .selectTab(let index): return "选择标签页 \(index)"
            case .version: return "版本"
            case .minimumMacOS: return "最低 macOS 版本"
            case .defaultShell: return "默认 Shell"
            case .scrollback: return "回滚缓冲区"
            case .colorScheme: return "配色方案"
            case .font: return "字体"
            case .fontSize: return "字号"
            case .lineSpacing: return "行间距"
            case .backgroundOpacity: return "背景不透明度"
            case .backgroundBlur: return "背景模糊"
            case .blinkingCursor: return "闪烁光标"
            case .application: return "MatTerm"
            case .language: return "语言"
            case .english: return "English"
            case .simplifiedChinese: return "简体中文"
            case .keepWindowOnTop: return "窗口置顶"
            case .displayMode: return "显示模式"
            case .traditionalMode: return "传统模式"
            case .compactMode: return "紧凑模式"
            case .restartRequiredTitle: return "需要重启"
            case .restartRequiredMessage: return "重启 MatTerm 后才能应用新的显示模式。"
            case .restartNow: return "立即重启"
            case .restartLater: return "稍后重启"
            case .keyboardShortcuts: return "键盘快捷键"
            case .resetShortcuts: return "恢复默认快捷键"
            case .sshProfileSelector: return "SSH 配置选择器"
            case .searchSSHHosts: return "搜索 SSH 主机"
            case .noMatchingSSHHosts: return "没有匹配的 SSH 主机"
            case .shortcutNeedsCommand: return "快捷键必须包含 Command 键。"
            case .shortcutAlreadyInUse: return "该快捷键已被使用。"
            case .splitLeft: return "向左分屏"
            case .splitRight: return "向右分屏"
            case .splitAbove: return "向上分屏"
            case .splitBelow: return "向下分屏"
            case .showSSHSelector: return "显示 SSH 配置选择器"
            case .toggleWindow: return "显示/隐藏 MatTerm"
            case .chooseSSHHost: return "选择 SSH 主机"
            case .sshHost: return "SSH 主机"
            case .name: return "名称"
            case .host: return "主机"
            case .username: return "用户名"
            case .port: return "端口"
            case .identityFileOptional: return "身份文件（可选）"
            case .chooseIdentityFile: return "选择身份文件"
            case .cancel: return "取消"
            case .save: return "保存"
            case .okay: return "好"
            case .connected: return "已连接"
            case .connecting: return "连接中"
            case .exited: return "已退出"
            case .failed: return "失败"
            case .processFinished: return "进程已结束"
            case .importedSSHHosts: return "已导入 SSH 主机"
            case .noNewSSHHosts: return "没有新的主机"
            case .importedSSHHostsMessage(let count): return "已从 ~/.ssh/config 导入 \(count) 个新主机。"
            case .noNewSSHHostsMessage: return "在 ~/.ssh/config 中没有发现新的主机。"
            case .recordingShortcut: return "按下快捷键"
            case .shortcutCaptureHelp: return "点击后按下快捷键，按 Escape 取消。"
            }
        }
    }
}

@MainActor
final class AppPreferences: ObservableObject {
    @Published var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Keys.language) }
    }
    @Published var alwaysOnTop: Bool {
        didSet { defaults.set(alwaysOnTop, forKey: Keys.alwaysOnTop) }
    }
    @Published var displayMode: AppDisplayMode {
        didSet { defaults.set(displayMode.rawValue, forKey: Keys.displayMode) }
    }

    // Window toolbar styling is initialized at launch and applied after restart.
    let activeDisplayMode: AppDisplayMode

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let language = "application.language"
        static let alwaysOnTop = "application.alwaysOnTop"
        static let displayMode = "application.displayMode"
    }

    init() {
        language = AppLanguage(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? .english
        alwaysOnTop = defaults.object(forKey: Keys.alwaysOnTop) as? Bool ?? false
        let savedMode = AppDisplayMode(rawValue: defaults.string(forKey: Keys.displayMode) ?? "") ?? .traditional
        displayMode = savedMode
        activeDisplayMode = savedMode
    }

    func text(_ value: AppText) -> String {
        value.value(language: language)
    }

    var displayModeNeedsRestart: Bool {
        displayMode != activeDisplayMode
    }

    func restartApplication() {
        let applicationURL = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.hides = false
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration) { application, error in
            DispatchQueue.main.async {
                guard application != nil, error == nil else {
                    NSSound.beep()
                    return
                }
                NSApp.terminate(nil)
            }
        }
    }
}

enum ShortcutAction: String, CaseIterable, Identifiable {
    case sshProfileSelector
    case toggleWindow
    case splitLeft
    case splitRight
    case splitAbove
    case splitBelow

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .sshProfileSelector: return AppText.showSSHSelector.value(language: language)
        case .toggleWindow: return AppText.toggleWindow.value(language: language)
        case .splitLeft: return AppText.splitLeft.value(language: language)
        case .splitRight: return AppText.splitRight.value(language: language)
        case .splitAbove: return AppText.splitAbove.value(language: language)
        case .splitBelow: return AppText.splitBelow.value(language: language)
        }
    }
}

struct ShortcutBinding: Codable, Equatable, Hashable {
    let key: String
    let modifiers: Int
    let keyCode: UInt16?

    private enum CodingKeys: String, CodingKey {
        case key
        case modifiers
        case keyCode
    }

    init(key: String, modifiers: Int, keyCode: UInt16? = nil) {
        self.key = key
        self.modifiers = modifiers
        self.keyCode = keyCode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        modifiers = try container.decode(Int.self, forKey: .modifiers)
        keyCode = try container.decodeIfPresent(UInt16.self, forKey: .keyCode)
    }

    static let command = 1
    static let option = 1 << 1
    static let shift = 1 << 2
    static let control = 1 << 3

    var includesCommand: Bool { modifiers & Self.command != 0 }

    static func == (lhs: ShortcutBinding, rhs: ShortcutBinding) -> Bool {
        lhs.key == rhs.key && lhs.modifiers == rhs.modifiers
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(key)
        hasher.combine(modifiers)
    }

    var keyboardShortcut: KeyboardShortcut? {
        guard let keyEquivalent else { return nil }
        return KeyboardShortcut(keyEquivalent, modifiers: eventModifiers)
    }

    private var keyEquivalent: KeyEquivalent? {
        switch key {
        case "up": return .upArrow
        case "down": return .downArrow
        case "left": return .leftArrow
        case "right": return .rightArrow
        case "return": return .return
        case "tab": return .tab
        case "escape": return .escape
        case "space": return .space
        default:
            guard let character = key.first, key.count == 1 else { return nil }
            return KeyEquivalent(character)
        }
    }

    private var eventModifiers: SwiftUI.EventModifiers {
        var result: SwiftUI.EventModifiers = []
        if modifiers & Self.command != 0 { result.insert(.command) }
        if modifiers & Self.option != 0 { result.insert(.option) }
        if modifiers & Self.shift != 0 { result.insert(.shift) }
        if modifiers & Self.control != 0 { result.insert(.control) }
        return result
    }

    var carbonKeyCode: UInt32? {
        if let keyCode { return UInt32(keyCode) }
        switch key {
        case "a": return UInt32(kVK_ANSI_A)
        case "b": return UInt32(kVK_ANSI_B)
        case "c": return UInt32(kVK_ANSI_C)
        case "d": return UInt32(kVK_ANSI_D)
        case "e": return UInt32(kVK_ANSI_E)
        case "f": return UInt32(kVK_ANSI_F)
        case "g": return UInt32(kVK_ANSI_G)
        case "h": return UInt32(kVK_ANSI_H)
        case "i": return UInt32(kVK_ANSI_I)
        case "j": return UInt32(kVK_ANSI_J)
        case "k": return UInt32(kVK_ANSI_K)
        case "l": return UInt32(kVK_ANSI_L)
        case "m": return UInt32(kVK_ANSI_M)
        case "n": return UInt32(kVK_ANSI_N)
        case "o": return UInt32(kVK_ANSI_O)
        case "p": return UInt32(kVK_ANSI_P)
        case "q": return UInt32(kVK_ANSI_Q)
        case "r": return UInt32(kVK_ANSI_R)
        case "s": return UInt32(kVK_ANSI_S)
        case "t": return UInt32(kVK_ANSI_T)
        case "u": return UInt32(kVK_ANSI_U)
        case "v": return UInt32(kVK_ANSI_V)
        case "w": return UInt32(kVK_ANSI_W)
        case "x": return UInt32(kVK_ANSI_X)
        case "y": return UInt32(kVK_ANSI_Y)
        case "z": return UInt32(kVK_ANSI_Z)
        case "space": return UInt32(kVK_Space)
        case "return": return UInt32(kVK_Return)
        case "tab": return UInt32(kVK_Tab)
        case "escape": return UInt32(kVK_Escape)
        case "up": return UInt32(kVK_UpArrow)
        case "down": return UInt32(kVK_DownArrow)
        case "left": return UInt32(kVK_LeftArrow)
        case "right": return UInt32(kVK_RightArrow)
        default: return nil
        }
    }

    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if modifiers & Self.command != 0 { result |= UInt32(cmdKey) }
        if modifiers & Self.option != 0 { result |= UInt32(optionKey) }
        if modifiers & Self.shift != 0 { result |= UInt32(shiftKey) }
        if modifiers & Self.control != 0 { result |= UInt32(controlKey) }
        return result
    }

    func displayString(language: AppLanguage) -> String {
        var parts: [String] = []
        if modifiers & Self.command != 0 { parts.append("Cmd") }
        if modifiers & Self.option != 0 { parts.append("Option") }
        if modifiers & Self.control != 0 { parts.append("Control") }
        if modifiers & Self.shift != 0 { parts.append("Shift") }
        let keyTitle: String
        switch key {
        case "up": keyTitle = "Up"
        case "down": keyTitle = "Down"
        case "left": keyTitle = "Left"
        case "right": keyTitle = "Right"
        case "return": keyTitle = "Return"
        case "tab": keyTitle = "Tab"
        case "escape": keyTitle = "Escape"
        case "space": keyTitle = "Space"
        default: keyTitle = key.uppercased()
        }
        return (parts + [keyTitle]).joined(separator: "+")
    }

    static func from(event: NSEvent) -> ShortcutBinding? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers = 0
        if flags.contains(.command) { modifiers |= Self.command }
        if flags.contains(.option) { modifiers |= Self.option }
        if flags.contains(.shift) { modifiers |= Self.shift }
        if flags.contains(.control) { modifiers |= Self.control }

        let key: String?
        switch event.keyCode {
        case 123: key = "left"
        case 124: key = "right"
        case 125: key = "down"
        case 126: key = "up"
        case 36, 76: key = "return"
        case 48: key = "tab"
        case 49: key = "space"
        default:
            key = event.charactersIgnoringModifiers?.lowercased()
        }

        guard let key, !key.isEmpty else { return nil }
        return ShortcutBinding(key: key, modifiers: modifiers, keyCode: event.keyCode)
    }
}

private final class CarbonGlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let hotKeyID = EventHotKeyID(signature: 0x48544247, id: 1)
    private let onPress: () -> Void

    init?(binding: ShortcutBinding, onPress: @escaping () -> Void) {
        guard let keyCode = binding.carbonKeyCode else { return nil }
        self.onPress = onPress

        var eventTypes = [EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )]
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                let owner = Unmanaged<CarbonGlobalHotKey>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                var eventHotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &eventHotKeyID
                )
                guard status == noErr,
                      eventHotKeyID.signature == owner.hotKeyID.signature,
                      eventHotKeyID.id == owner.hotKeyID.id else {
                    return noErr
                }
                owner.onPress()
                return noErr
            },
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
        guard handlerStatus == noErr else { return nil }

        let registrationStatus = RegisterEventHotKey(
            keyCode,
            binding.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registrationStatus == noErr else {
            if let eventHandlerRef {
                RemoveEventHandler(eventHandlerRef)
                self.eventHandlerRef = nil
            }
            return nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
    }
}

@MainActor
final class ShortcutStore: ObservableObject {
    @Published private(set) var bindings: [ShortcutAction: ShortcutBinding]
    private var eventMonitor: Any?
    private var globalHotKey: CarbonGlobalHotKey?
    private weak var runtimeAppState: AppState?
    private weak var runtimeProfileStore: SSHProfileStore?

    private let defaults = UserDefaults.standard
    private let defaultsKey = "application.shortcuts"

    private static let defaultBindings: [ShortcutAction: ShortcutBinding] = [
        .sshProfileSelector: ShortcutBinding(key: "o", modifiers: ShortcutBinding.command | ShortcutBinding.shift),
        .toggleWindow: ShortcutBinding(key: "space", modifiers: ShortcutBinding.command | ShortcutBinding.shift),
        .splitLeft: ShortcutBinding(key: "h", modifiers: ShortcutBinding.command | ShortcutBinding.shift),
        .splitRight: ShortcutBinding(key: "l", modifiers: ShortcutBinding.command | ShortcutBinding.shift),
        .splitAbove: ShortcutBinding(key: "k", modifiers: ShortcutBinding.command | ShortcutBinding.shift),
        .splitBelow: ShortcutBinding(key: "j", modifiers: ShortcutBinding.command | ShortcutBinding.shift)
    ]

    init() {
        if let data = defaults.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode([String: ShortcutBinding].self, from: data) {
            var loaded = Self.defaultBindings
            for action in ShortcutAction.allCases {
                if let binding = saved[action.rawValue], binding.includesCommand {
                    loaded[action] = binding
                }
            }
            bindings = loaded
        } else {
            bindings = Self.defaultBindings
        }
    }

    func binding(for action: ShortcutAction) -> ShortcutBinding {
        bindings[action] ?? Self.defaultBindings[action]!
    }

    func set(_ binding: ShortcutBinding, for action: ShortcutAction) -> AppText? {
        guard binding.includesCommand else { return .shortcutNeedsCommand }
        guard !bindings.contains(where: { $0.key != action && $0.value == binding }) else {
            return .shortcutAlreadyInUse
        }
        bindings[action] = binding
        save()
        if action == .toggleWindow, let runtimeAppState {
            installGlobalHotKey(appState: runtimeAppState)
        }
        return nil
    }

    func reset() {
        bindings = Self.defaultBindings
        save()
        if let runtimeAppState {
            installGlobalHotKey(appState: runtimeAppState)
        }
    }

    func installRuntimeHandler(appState: AppState, profileStore: SSHProfileStore) {
        guard eventMonitor == nil else { return }
        runtimeAppState = appState
        runtimeProfileStore = profileStore
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak appState] event in
            guard event.window?.identifier?.rawValue != "com_apple_SwiftUI_Settings_window" else {
                return event
            }
            guard let self,
                  let appState,
                  let action = self.bindings.first(where: { ShortcutBinding.from(event: event) == $0.value })?.key else {
                return event
            }

            // Carbon owns the window toggle so it also works while another app
            // is active. Keep this local path only as a fallback if registration
            // failed for an unsupported or conflicting key.
            if action == .toggleWindow, self.globalHotKey != nil {
                return nil
            }

            Task { @MainActor in
                switch action {
                case .sshProfileSelector:
                    self.runtimeProfileStore?.synchronizeFromOpenSSHConfig()
                    appState.showSSHProfileSelector()
                case .toggleWindow:
                    appState.toggleMainWindow()
                case .splitLeft:
                    appState.splitSelectedPane(direction: .left)
                case .splitRight:
                    appState.splitSelectedPane(direction: .right)
                case .splitAbove:
                    appState.splitSelectedPane(direction: .above)
                case .splitBelow:
                    appState.splitSelectedPane(direction: .below)
                }
            }
            return nil
        }
        installGlobalHotKey(appState: appState)
    }

    private func installGlobalHotKey(appState: AppState) {
        globalHotKey = nil
        guard let binding = bindings[.toggleWindow] else { return }
        globalHotKey = CarbonGlobalHotKey(binding: binding) { [weak appState] in
            guard let appState else { return }
            Task { @MainActor in
                appState.toggleMainWindow()
            }
        }
    }

    private func save() {
        let rawBindings = Dictionary(uniqueKeysWithValues: bindings.map { ($0.key.rawValue, $0.value) })
        guard let data = try? JSONEncoder().encode(rawBindings) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
}

struct KeyboardShortcutRecorder: NSViewRepresentable {
    let binding: ShortcutBinding
    let isRecording: Bool
    let recordingTitle: String
    let helpText: String
    let onBegin: () -> Void
    let onCapture: (ShortcutBinding) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton(title: "", target: nil, action: nil)
        button.bezelStyle = .rounded
        button.controlSize = .small
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.title = isRecording ? recordingTitle : binding.displayString(language: .english)
        button.toolTip = helpText
        button.isRecording = isRecording
        button.target = button
        button.action = #selector(ShortcutRecorderButton.beginRecordingFromAccessibility)
        button.onBegin = onBegin
        button.onCapture = onCapture
        button.onCancel = onCancel

        if !isRecording {
            button.stopRecordingCapture()
        }

        if isRecording, button.window?.firstResponder !== button {
            DispatchQueue.main.async {
                button.window?.makeFirstResponder(button)
            }
        }
    }
}

final class ShortcutRecorderButton: NSButton {
    var isRecording = false
    var onBegin: (() -> Void)?
    var onCapture: ((ShortcutBinding) -> Void)?
    var onCancel: (() -> Void)?
    private var isCapturing = false
    private var recordingMonitor: Any?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        beginRecordingFromAccessibility()
    }

    @objc func beginRecordingFromAccessibility() {
        guard !isCapturing else { return }
        isCapturing = true
        installRecordingMonitor()
        onBegin?()
        window?.makeFirstResponder(self)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            stopRecordingCapture()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isCapturing {
            return capture(event)
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        guard isCapturing else {
            super.keyDown(with: event)
            return
        }

        _ = capture(event)
    }

    func stopRecordingCapture() {
        isCapturing = false
        if let recordingMonitor {
            NSEvent.removeMonitor(recordingMonitor)
            self.recordingMonitor = nil
        }
    }

    private func installRecordingMonitor() {
        guard recordingMonitor == nil, let window else { return }
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak window] event in
            guard let self, let window, self.isCapturing, event.window === window else {
                return event
            }
            _ = self.capture(event)
            return nil
        }
    }

    @discardableResult
    private func capture(_ event: NSEvent) -> Bool {
        guard isCapturing else { return false }

        if event.keyCode == 53 {
            stopRecordingCapture()
            onCancel?()
            return true
        }

        guard let binding = ShortcutBinding.from(event: event), binding.includesCommand else {
            NSSound.beep()
            return true
        }
        stopRecordingCapture()
        onCapture?(binding)
        return true
    }
}
