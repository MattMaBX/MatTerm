# MatTerm

> A native macOS terminal and SSH workspace built with Swift.

[简体中文](README.zh-CN.md)

MatTerm is a focused terminal app for macOS users who work locally and over SSH. It uses a native SwiftUI and AppKit interface, the system PTY, and the system OpenSSH client to keep the app responsive, lightweight, and closely integrated with macOS.

Current release: **v0.2.0**

## Features

- Local terminal sessions backed by a real PTY.
- SSH profiles imported from and synchronized with `~/.ssh/config`.
- New or edited profiles written back to the local OpenSSH configuration.
- ANSI colors, 256-color palette, and 24-bit truecolor rendering.
- Ghostty VT-based terminal parsing, rendering, scrolling, and mouse tracking.
- Native scrollback scrolling with a visible scrollbar in ordinary terminal mode.
- Tabby community color schemes included as built-in themes.
- Font family, font size, extra line spacing, cursor blinking, opacity, and blur controls.
- Compact tab layout with adaptive tab widths and a separate new-tab action.
- Keyboard-configurable SSH profile selector and pane splitting shortcuts.
- Left, right, above, and below terminal splits with independent focus and cursor state.
- Window size and position restoration, always-on-top mode, and a global show/hide shortcut.
- English and Simplified Chinese UI.

Port forwarding and arbitrary split layouts beyond the current directional pane workflow are not part of v0.2.0.

## Requirements

- macOS 26.0 or later.
- Swift 6.1 or later with a macOS 26 SDK for building from source.
- The distributed app contains both `arm64` and `x86_64` slices.

## Build And Run

```sh
git clone <repository-url>
cd MatTerm
./Scripts/build-app.sh
./Scripts/validate-app.sh
./Scripts/package-app.sh
open Build/MatTerm.app
```

The build script runs Ghostty VT core, PTY, multiplexer, appearance, and app-level checks, compiles both supported CPU architectures, creates an ad-hoc signed `Build/MatTerm.app`, and embeds the standard macOS icon. `Scripts/package-app.sh` creates a universal ZIP in `Artifacts/`.

GitHub Actions runs the same build on `macos-26`, uploads the ZIP as an Actions artifact, and creates a Release when a tag such as `v0.2.0` is pushed. To produce a Gatekeeper-friendly release, configure these repository secrets: `APPLE_CERTIFICATE_P12_BASE64`, `APPLE_CERTIFICATE_PASSWORD`, `APPLE_SIGNING_IDENTITY`, `APPLE_ID`, `APPLE_TEAM_ID`, and `APPLE_APP_PASSWORD`. When all are present, the workflow performs Developer ID signing, notarization, stapling, and then uploads the notarized ZIP. Without them, it intentionally produces an ad-hoc signed ZIP.

### v0.2.0

- Fixed ANSI color fills, terminal text contrast, and line-spacing alignment.
- Made normal-terminal scrollback buffered, smoother, and more reliable during long output.
- Added an effective configurable scrollback limit, text selection and copy support, and Cmd+Ctrl+F full-screen handling.
- Matched tmux trackpad scrolling to ordinary terminal scrolling and return ordinary local or SSH shells to the live prompt when input begins.

### v0.1.1

- Replaced the terminal viewport implementation with the Ghostty VT core while keeping the existing MatTerm interface.
- Fixed ordinary terminal scrollback input and added a native visible scrollbar.
- Kept tmux, Vim, and screen mouse tracking routed to the terminal application.
- Improved ANSI, 256-color, and truecolor rendering and removed background bleed-through artifacts.
- Reduced redraw work during scrolling and pane interaction.

For a compiler-only build:

```sh
swift build -c release
```

MatTerm is currently intended for personal use and source distribution. It is not configured for App Store distribution.

### Installing A GitHub Build

For a GitHub Actions artifact or Release ZIP:

1. Download and extract the ZIP.
2. Move `MatTerm.app` to `/Applications`.
3. Open it once with Control-click > **Open**, then confirm **Open**.

The default workflow uses an ad-hoc signature because no Apple Developer credentials are stored in the repository. A production workflow can perform Developer ID signing and notarization when the documented GitHub Actions secrets are configured. Without notarization, Gatekeeper may require the first-launch confirmation above. The app itself is universal and does not require Rosetta on Apple Silicon Macs.

## SSH Configuration

MatTerm uses the system OpenSSH client at `/usr/bin/ssh`.

- On launch, MatTerm reads the latest entries from `~/.ssh/config`.
- Opening the SSH profile selector refreshes the same file before showing profiles.
- Saving a profile updates the matching `Host` block or appends a new one.
- Unrecognized options and unrelated `Host` blocks are preserved when MatTerm updates a profile.
- Authentication remains managed by OpenSSH, SSH agents, and the identity files selected by the user. MatTerm does not store passwords.

Review the resulting `~/.ssh/config` before using it with other SSH tooling, especially when an existing `Host` block contains advanced configuration not represented by the profile editor.

## Project Layout

```text
Sources/MatTerm/      Application and terminal implementation
Resources/             Info.plist and icon sources
Scripts/               Build and runtime checks
Build/                 Local app output, ignored by Git
Artifacts/             Local release archives, ignored by Git
```

## License

MatTerm is released under the [MIT License](LICENSE).
