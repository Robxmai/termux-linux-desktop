# Termux Linux Desktop v0.2.0

No-root ARM64 Android desktop toolkit: Termux + PRoot Ubuntu 24.04 + XFCE + Termux:X11,
now shipping a full GPU/Wine runtime so games run out of the box.

## What's new in v0.2

- **Wine/GPU runtime provisioning** (`desktop-install` stage `guest-runtime`):
  - **Box64** built from source at pinned master commit `ba373ab` — renders
    cleanly on Adreno (the 0.4.x presentation regression is fixed upstream)
    and translates the game session crypto correctly.
  - **Mesa Turnip 24.1.0** (Winlator component) — the last turnip build without
    the X11 WSI presentation corruption seen in 25.0.0+.
  - **Wine 11.11 wow64 runtime** installed from `TLD_WINE_RUNTIME_TARBALL`
    (see `docs/WINE_RUNTIME.md` for the build recipe).
  - **DXVK 2.6.1** (official release) with a system default `dxvk.conf` that
    spoofs a recognized GPU so old D3D9 clients enable their full shader path.
  - **Firefox ESR** installed and set as the default browser for the desktop user.
  - **Sound**: `libpulse0` + `PULSE_SERVER=tcp:127.0.0.1:4713` + `AAudio_sink`
    default — verified in-game audio.
  - **VNC remote access** (`desktop-vnc start`) — x11vnc on port 5900,
    password `termux`.
  - **GPU diagnostics** (`desktop-gputest`, `--info` for GPUInfo) using
    Winlator's TestD3D renderer test.
- **WoW integration** (`wow-install`, `wow-launch`):
  - Registers a WoW 3.3.5a install (overlay + prefix + desktop icon + launcher).
  - Host-side launcher with writable-overlay binds and source-integrity audit.
- **Profile v2** — `profiles/base.env` now requires the GPU/Wine runtime
  (`REQUIRES_GPU=true`, `REQUIRES_WINE=true`).
- 166/166 tests passing (151 prior + 15 new runtime/WoW/VNC/GPU tests).

## Component regression findings (shipped pins)

| Component | Pin | Why |
|---|---|---|
| box64 | master @ `ba373ab` (built from source) | 0.4.x dynarec regressions corrupted the X11 presentation path (grid artifact); fixed upstream in master. Older builds: 0.3.7 dropped the WoW realm session, 0.3.5 crashed |
| turnip | 24.1.0 | turnip 25.0.0+ rewrote the Vulkan X11 WSI ("direct rendering"); 26.x builds exhibit presentation corruption |
| DXVK | 2.6.1 | validated with the above pins |
| wine | 11.11 (wow64) | validated with the above pins |

Diagnostic rules learned during acceptance (see `docs/SUPPORT.md`):
never enable `DXVK_LOG_LEVEL=debug` with `DXVK_LOG_PATH` on this stack
(stalls device creation under box64 0.3.7); the stock
`vulkan-validationlayers` package (1.3.275) mis-handles modern pNext chains.

## On-device acceptance

Xiaomi Pad 6S Pro 12.4 (Snapdragon 8 Gen 2, Adreno 740, 16 GB), Android 16:
clean login-screen rendering (no grid), in-game audio routed to the AAudio
sink, Firefox default browser, VNC remote access, and GPU diagnostics all
verified with the pinned components.

## Known limitations

- The login zoom animation present in earlier stacks is not reproduced on this
  runtime; it was a symptom of the corrupted render path and is intentionally
  not restored.
- WoW realm login (character list) is validated on-device with the shipped
  pins: clean rendering, in-game audio, and working login/character list.
