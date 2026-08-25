# Embedded libghostty-vt

This directory contains the pinned `libghostty-vt` artifact used by MatTerm.
It is built from Ghostty commit `6a508fd5e34c7e222c052a6d00bb3891ff3feace`
(the `main` commit inspected during the integration) with Zig 0.16 and the
`-Demit-lib-vt -Doptimize=ReleaseFast` options.

The terminal state machine, VT parser, scrollback model, render-state API, key
encoder, and mouse encoder are provided by this library. The surrounding
SwiftUI/AppKit code only adapts those APIs to MatTerm's existing UI.

The upstream license is included in `LICENSE`.
