# Sill architecture

```text
Workspace chrome (Rail / Ring / Composer / Palette)
        │ layout.toml + OSC 7501 / 133 / hooks
Surface Manager (macOS AppKit · Linux single chrome backend)
        │ C ABI
libghostty (parse · grid · encode · render)
        │ posix PTY
shell / official agent CLI / ssh
```

## Today in this tree

- `core/sill-core` (Rust, `staticlib` + `rlib`, C header in `include/sill.h`):
  - `osc` — streaming scanner for OSC 7501, OSC 133 (A/B/C/D command marks),
    OSC 7 (cwd). Runs **off** the render thread (NFR-P9); feed it raw PTY bytes,
    it emits structured events. Unknown OSC/keys are skipped without consuming
    the stream.
  - `state` — the five-point status model (`idle|working|done|blocked|error`
    + `clear`) and the per-pane `StatusStore` with layered `id` records.
  - `layout` — `layout.toml` (version 1) read/write; restore contract in
    `docs/layout.md`.
  - `ghostty_import` — Ghostty config key mapping → mapped/similar/dropped report.
  - `ffi` — the exported C ABI used by chrome backends.
- `cli/sill` (Rust): `sill state`, `sill export layout`, `sill import ghostty`,
  `sill bench --suite=v1`. `sill state` writes adapter events under
  `~/.config/sill/state/` — events without `pid` are dropped (FR-008).
- `apps/macos` (Swift, SwiftPM → `dist/Sill.app`): AppKit/SwiftUI chrome.
  Terminal surfaces conform to `SillSurface`; `SwiftTermSurface` (pure-Swift VT,
  real posix PTY) is the **development backend** so J1/J2 run end-to-end today.
  `LibghosttySurface` will bind `vendor/libghostty` through the same protocol.

## libghostty seam

`vendor/README.md` pins the intended ghostty commit. The app never talks to the
PTY or the VT parser directly — only to `SillSurface`:

```swift
protocol SillSurface: AnyObject {
    var view: NSView { get }
    func spawn(argv: [String], cwd: URL, env: [String: String]) throws
    func write(_ data: Data)            // composer → PTY (bracketed paste)
    func onOutput(_ cb: (Data) -> Void) // PTY → scanner tee → render
    var isAltScreen: Bool { get }       // forces Raw (FR-006)
    func terminate()
}
```

Because state parsing is a tee on the byte stream, swapping the backend does not
change the rail/ring/composer path. Hot-path NFRs are measured with the real
libghostty backend in `sill bench` — Terminal Mode numbers are never used as the
product figure.

## Errors worth remembering (PRD §11)

libghostty load failure → exit 1 + native alert. Provider missing from PATH →
Home card error, no fake pane. 7501 without `state` → dropped. Bad `msg` base64 →
drop msg keep state. Alt-screen → Raw locked. Paste with ESC → confirm; cancel
writes nothing.
