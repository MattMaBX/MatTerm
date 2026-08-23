import AppKit
import SwiftUI

struct ProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var preferences: AppPreferences
    @StateObject private var formState: ProfileFormState
    let onSave: (SSHProfile) -> Void

    init(profile: SSHProfile, onSave: @escaping (SSHProfile) -> Void) {
        _formState = StateObject(wrappedValue: ProfileFormState(profile: profile))
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(preferences.text(.sshHost))
                .font(.title2.weight(.semibold))

            Form {
                TextField(preferences.text(.name), text: $formState.draft.name)
                TextField(preferences.text(.host), text: $formState.draft.host)
                TextField(preferences.text(.username), text: $formState.draft.username)
                Stepper(value: $formState.draft.port, in: 1...65_535) {
                    LabeledContent(preferences.text(.port), value: String(formState.draft.port))
                }
                HStack(spacing: 8) {
                    TextField(preferences.text(.identityFileOptional), text: $formState.draft.identityPath)
                    Button {
                        chooseIdentityFile()
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help(preferences.text(.chooseIdentityFile))
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button(preferences.text(.cancel)) {
                    dismiss()
                }
                Button(preferences.text(.save)) {
                    let normalized = SSHProfile(
                        id: formState.draft.id,
                        name: formState.draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? formState.draft.host : formState.draft.name,
                        host: formState.draft.host.trimmingCharacters(in: .whitespacesAndNewlines),
                        port: formState.draft.port,
                        username: formState.draft.username.trimmingCharacters(in: .whitespacesAndNewlines),
                        identityPath: formState.draft.identityPath.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                    onSave(normalized)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(formState.draft.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 450)
    }

    private func chooseIdentityFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh", isDirectory: true)

        guard panel.runModal() == .OK, let url = panel.url else { return }
        formState.draft.identityPath = url.path
    }
}

@MainActor
private final class ProfileFormState: ObservableObject {
    @Published var draft: SSHProfile

    init(profile: SSHProfile) {
        draft = profile
    }
}
