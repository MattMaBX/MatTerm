<p align="center">
  <img src="Resources/AppIcon.svg" width="112" alt="MatTerm icon">
</p>

<h1 align="center">MatTerm</h1>

<p align="center">A native terminal workspace for macOS.</p>

<p align="center">
  <a href="https://github.com/MattMaBX/MatTerm/releases">Download</a>
  &nbsp;|&nbsp;
  <a href="https://github.com/MattMaBX/MatTerm/issues">Report an issue</a>
  &nbsp;|&nbsp;
  <a href="README.zh-CN.md">简体中文</a>
</p>

MatTerm is a focused terminal for people who move between local shells and SSH hosts all day. It uses native SwiftUI and AppKit surfaces, a real PTY, the system OpenSSH client, and the Ghostty VT core to deliver a terminal that belongs on macOS without giving up the workflows expected from a modern terminal.

**Current version:** v0.2.2

## Highlights

- **Local and SSH in one workspace.** Open local tabs or connect through profiles synchronized with `~/.ssh/config`.
- **A proper terminal surface.** ANSI, 256-color, and truecolor output; configurable scrollback; text selection and copy; and buffered native scrolling for long output.
- **Multiplexer-aware input.** Mouse tracking, pane resizing, and wheel events remain available to tmux, Vim, and screen when they take ownership of the terminal.
- **Tabs and directional splits.** Create left, right, above, or below panes with independent focus and cursor state.
- **Comfortable daily use.** Built-in Tabby themes, font and line-spacing controls, cursor settings, background opacity, plus a persistent window layout.
- **Built for macOS.** Full-screen support, standard keyboard shortcuts, universal `arm64` and `x86_64` builds, and English or Simplified Chinese UI.

## Get MatTerm

### Download a release

1. Download the latest universal ZIP from [Releases](https://github.com/MattMaBX/MatTerm/releases).
2. Extract it and move `MatTerm.app` to `/Applications`.
3. Open the app normally. If macOS shows a Gatekeeper warning for an ad-hoc-signed build, Control-click the app, choose **Open**, then confirm.

The application is built for macOS 26.0 or later and includes both Apple Silicon and Intel slices. It does not require Rosetta on Apple Silicon.

### Build from source

Building requires Swift 6.1 or later and a macOS 26 SDK.

```sh
git clone https://github.com/MattMaBX/MatTerm.git
cd MatTerm
./Scripts/build-app.sh
open Build/MatTerm.app
```

The build creates a universal app bundle at `Build/MatTerm.app` with an ad-hoc signature. To check an existing bundle:

```sh
./Scripts/validate-app.sh Build/MatTerm.app
```

## Everyday Shortcuts

| Action | Default shortcut |
| --- | --- |
| New local tab | `Cmd+T` |
| Close tab | `Cmd+W` |
| SSH profile selector | `Cmd+Shift+O` |
| Split left, right, above, below | `Cmd+Shift+H` / `Cmd+Shift+L` / `Cmd+Shift+K` / `Cmd+Shift+J` |
| Next or previous tab | `Cmd+Shift+}` or `Cmd+Shift+{` |
| Full screen | `Cmd+Ctrl+F` |

The SSH selector and pane-splitting shortcuts can be changed in Settings.

## SSH, Credentials, and Configuration

MatTerm uses `/usr/bin/ssh`; authentication continues to be handled by OpenSSH, your SSH agent, and the identity files you choose. MatTerm does not store passwords or private keys.

- Profiles are read from `~/.ssh/config` on launch and refreshed before the SSH selector opens.
- Creating or editing a profile updates the matching `Host` block, or appends one when needed.
- Unrecognized directives and unrelated host blocks are preserved when MatTerm writes the file.

Review `~/.ssh/config` after editing a profile that shares a host block with advanced OpenSSH settings. That file remains the source of truth and can always be edited directly.

## What's New in v0.2.2

- The SSH profile selector now follows the active terminal theme with an opaque, high-contrast search field and selection state.
- The toolbar, sidebar, and empty workspace now follow the active terminal theme with readable interface contrast.
- Simplified background customization to a single opacity control.
- Settings can be dismissed with Escape or Cmd+W, and the tab strip stays hidden when no tabs are open.

## Current Scope

MatTerm is intentionally focused. It does not yet include a dedicated port-forwarding interface or arbitrary drag-and-drop pane layouts. Directional splits cover the current pane workflow.

## Development

Run the terminal regression suite before opening a pull request:

```sh
./Scripts/check-terminal.sh all
./Scripts/check-appearance.sh
./Scripts/build-app.sh
./Scripts/validate-app.sh Build/MatTerm.app
```

Bug reports and feature requests are welcome through [GitHub Issues](https://github.com/MattMaBX/MatTerm/issues).

## License

MatTerm is available under the [MIT License](LICENSE).
