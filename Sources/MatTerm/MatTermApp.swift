import SwiftUI

@main
struct MatTermApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var profileStore = SSHProfileStore()
    @StateObject private var terminalAppearance = TerminalAppearance()
    @StateObject private var preferences = AppPreferences()
    @StateObject private var shortcutStore = ShortcutStore()

    var body: some Scene {
        WindowGroup {
            MainView(
                appState: appState,
                profileStore: profileStore,
                initialDisplayMode: preferences.activeDisplayMode
            )
                .environmentObject(terminalAppearance)
                .environmentObject(preferences)
                .environmentObject(shortcutStore)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(preferences.text(.newLocalTab)) {
                    appState.openLocalSession()
                }
                .keyboardShortcut("t", modifiers: [.command])

                Button(preferences.text(.closeTab)) {
                    appState.closeSelectedSession()
                }
                .keyboardShortcut("w", modifiers: [.command])

                Button(preferences.text(.clearTerminal)) {
                    appState.clearSelectedTerminal()
                }
                .keyboardShortcut("k", modifiers: [.command])

                Button(preferences.text(.increaseFontSize)) {
                    terminalAppearance.increaseFontSize()
                }
                .keyboardShortcut("+", modifiers: [.command])

                Button(preferences.text(.decreaseFontSize)) {
                    terminalAppearance.decreaseFontSize()
                }
                .keyboardShortcut("-", modifiers: [.command])

                Button(preferences.text(.resetFontSize)) {
                    terminalAppearance.resetFontSize()
                }
                .keyboardShortcut("0", modifiers: [.command])

                Button(preferences.text(.restartSession)) {
                    if let session = appState.selectedSession {
                        appState.restart(session)
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button(preferences.text(.nextTab)) {
                    appState.selectNextSession()
                }
                .keyboardShortcut("}", modifiers: [.command, .shift])

                Button(preferences.text(.previousTab)) {
                    appState.selectPreviousSession()
                }
                .keyboardShortcut("{", modifiers: [.command, .shift])

                Button(preferences.text(.showSSHSelector)) {
                    profileStore.synchronizeFromOpenSSHConfig()
                    appState.showSSHProfileSelector()
                }
                .keyboardShortcut(shortcutStore.binding(for: .sshProfileSelector).keyboardShortcut ?? KeyboardShortcut("o", modifiers: [.command, .shift]))

                Button(preferences.text(.toggleWindow)) {
                    appState.toggleMainWindow()
                }
                .keyboardShortcut(shortcutStore.binding(for: .toggleWindow).keyboardShortcut ?? KeyboardShortcut(.space, modifiers: [.command, .shift]))

                Button(preferences.text(.splitLeft)) {
                    appState.splitSelectedPane(direction: .left)
                }
                .keyboardShortcut(shortcutStore.binding(for: .splitLeft).keyboardShortcut ?? KeyboardShortcut("h", modifiers: [.command, .shift]))

                Button(preferences.text(.splitRight)) {
                    appState.splitSelectedPane(direction: .right)
                }
                .keyboardShortcut(shortcutStore.binding(for: .splitRight).keyboardShortcut ?? KeyboardShortcut("l", modifiers: [.command, .shift]))

                Button(preferences.text(.splitAbove)) {
                    appState.splitSelectedPane(direction: .above)
                }
                .keyboardShortcut(shortcutStore.binding(for: .splitAbove).keyboardShortcut ?? KeyboardShortcut("k", modifiers: [.command, .shift]))

                Button(preferences.text(.splitBelow)) {
                    appState.splitSelectedPane(direction: .below)
                }
                .keyboardShortcut(shortcutStore.binding(for: .splitBelow).keyboardShortcut ?? KeyboardShortcut("j", modifiers: [.command, .shift]))

                ForEach(0..<9, id: \.self) { index in
                    Button(preferences.text(.selectTab(index + 1))) {
                        appState.selectSession(at: index)
                    }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [.command])
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(terminalAppearance)
                .environmentObject(preferences)
                .environmentObject(shortcutStore)
        }
    }
}
