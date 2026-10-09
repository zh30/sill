# vendor/libghostty

libghostty (the Ghostty VT core's embeddable C ABI) is consumed **pinned to an
explicit commit** (PRD FR-001: "钉 libghostty commit，升级显式").

Status: not yet vendored. The macOS app currently runs surfaces through the
`SillSurface` dev backend (`SwiftTermSurface`, pure-Swift VT + real posix PTY)
so J1/J2 are exercisable; `LibghosttySurface` binds here next.

Pinning plan:

```bash
# ghostty builds libghostty via zig; the pinned commit is recorded below.
git clone https://github.com/ghostty-org/ghostty vendor/ghostty
cd vendor/ghostty && git checkout <PINNED_COMMIT>
zig build -Dapp-runtime=none  # emits libghostty + headers
```

- Pin: _TBD_ (first vendoring PR picks a dated nightly and records it here).
- Upgrade: deliberate PR bumping this file + the checkout — never implicit.
- Linux chrome and `sill bench` hot-path cases light up with the same vendored lib.
