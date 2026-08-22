# Application Compatibility Matrix

Validated on-device: **2026-08-22** · Host: Xiaomi Pad 6 Pro S (`tld-ubuntu` container) · Auditor: automated takeover session.

## Layer A — Native ARM64 Linux

Ubuntu 24.04.4 LTS (arm64), kernel aarch64 via proot.

| Component | Status | Version |
|---|---|---|
| bash / coreutils | OK | 5.2.21 |
| git | OK | 2.43.0 |
| Python | OK | 3.12.3 (+pip) |
| Node.js | OK | 18.19.1 (+npm) |
| GCC / G++ / make / cmake | OK | 13.3.0 toolchain |
| ffmpeg | OK | present |
| Java | OK | present |
| vim / sqlite3 | OK | installed 2026-08-22 (was missing) |
| Firefox / LibreOffice / thunar / xfce4-terminal | OK | desktop apps |
| apt-get check | OK | clean dependency state |

## Layer B — x86_64 Linux via Box64

| Component | Status | Detail |
|---|---|---|
| Box64 | OK | v0.4.5 Dynarec (`/usr/local/bin/box64`) |
| box86 | OK | present alongside |

## Layer C — Windows x86/x64 via Wine

| Component | Status | Detail |
|---|---|---|
| Wine runtime | OK | 11.11 amd64-wow64 at `/opt/wine-runtime/wine-11.11-amd64-wow64` |
| Managed prefix | OK | `/root/wine-runtime-prefix` (game/`wine-exe` default); `/root/.wine` legacy |
| `cmd.exe` smoke test | OK | `SMOKE_CMD_OK` through Box64+Wine (2026-08-22) |
| `wow-launcher` / `wow-launcher-dxvk-stable` | OK | paths verified against live tree |
| `wine-exe` generic launcher | OK | single entry point for any `.exe`; gladio-host dep present |
| Wine Mono / Gecko | OK | provisioned into managed prefix per `docs/WINE_RUNTIME.md` |

### Test record (2026-08-22)

```text
T1  box64 wine --version          -> wine-11.11                    PASS
T3  box64 wine cmd /c echo        -> SMOKE_CMD_OK                  PASS
T4  gladio-host binary present    -> 327832 bytes                  PASS
T2  fresh wineboot -i             -> >150 s (slow HW path)         SLOW*
```

`*` Fresh prefix creation works but is slow on this hardware. Use the
pre-provisioned `/root/wine-runtime-prefix`; do not re-init prefixes
casually. A smoke-test prefix was created and removed during this audit.

## Operational rules (learned the hard way)

1. **Always start x86_64 Wine through Box64** (`box64 $WINE_BIN ...`).
   Executing the wow64 loader directly fails with a misleading
   `No such file or directory`.
2. **Do not use Ubuntu's distro Wine** (`/usr/bin/wine` -> 9.0 arm64). It
   cannot run x86_64 games and will report missing i386 packages. The
   gaming stack is only `/opt/wine-runtime/...` via the wrappers in
   `/usr/local/bin` (`wow-launcher`, `wine-exe`, `winecfg`, `winereg`).
3. **Stale wineserver sockets** can block new clients after a crash
   (`a wine server seems to be running, but I cannot connect to it`).
   Check `ps -ef | grep wineserver` and clear orphaned processes before
   blaming the display stack.
4. **`proot-distro login tld-ubuntu` does not bind Termux `$HOME` by
   default.** Scripts must be piped over stdin (`bash -s`) or placed on
   a bound path. The desktop's own launch chain adds explicit binds.
5. `gpuinfo` is interactive-desktop oriented; from a headless login it
   may exit silently. Verify the GPU stack from within the desktop
   session or via the managed prefix tools instead.

## Gaps / follow-ups

- thunderbird, VS Code, flatpak are absent (by design so far). Add on demand.
- `gpuinfo` output should be captured inside a live desktop session for the
  acceptance record.
