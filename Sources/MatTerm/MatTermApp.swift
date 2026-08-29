import AppKit
import SwiftUI

@MainActor
final class MatTermAppDelegate: NSObject, NSApplicationDelegate {
    var openMainWindow: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The main window can be hidden without making MatTerm an agent app.
        // Keep its Dock presence and event loop alive for the global shortcut.
        NSApp.setActivationPolicy(.regular)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        sender.setActivationPolicy(.regular)
        sender.unhide(nil)
        guard let window = sender.windows.first(where: {
            $0.identifier?.rawValue == "com.matterm.main-window"
        }) else {
            sender.activate(ignoringOtherApps: true)
            openMainWindow?()
            return false
        }

        window.collectionBehavior.insert(.moveToActiveSpace)
        sender.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        return false
    }
}

@main
struct MatTermApp: App {
    @NSApplicationDelegateAdaptor(MatTermAppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @StateObject private var appState = AppState()
    @StateObject private var profileStore = SSHProfileStore()
    @StateObject private var terminalAppearance = TerminalAppearance()
    @StateObject private var preferences = AppPreferences()
    @StateObject private var shortcutStore = ShortcutStore()

    var body: some Scene {
        Window("MatTerm", id: "main") {
            MainView(
                appState: appState,
                profileStore: profileStore
            )
                .onAppear {
                    appDelegate.openMainWindow = {
                        openWindow(id: "main")
                    }
                    appState.registerMainWindowOpener {
                        openWindow(id: "main")
                    }
                }
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
                .environmentObject(appState)
                .environmentObject(terminalAppearance)
                .environmentObject(preferences)
                .environmentObject(shortcutStore)
        }
    }
}
