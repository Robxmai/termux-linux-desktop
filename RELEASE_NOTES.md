# Termux Linux Desktop v0.1.0

No-root ARM64 Android desktop toolkit: Termux + PRoot Ubuntu 24.04 + XFCE + Termux:X11.

## What's included

- `install-toolkit` — transactional, sentinel-owned installer with rollback.
- `desktop-install` — preflight, pinned Ubuntu 24.04 environment, XFCE provisioning,
  runtime manifest, install-mode doctor.
- `desktop-start` / `desktop-stop` — ownership-based lifecycle; an external
  PulseAudio server is never stopped.
- `desktop-status` — exact PASS/WARN/FAIL/STOPPED headings.
- `desktop-doctor` — full diagnostics plus `--json` output.
- `desktop-profile` — list/apply/remove with strict name validation.
- `desktop-reset --yes` — timestamped backup, environment/install/state removal.
- Process ownership via PID + start-tick + command-line hash; no blanket kills.

## On-device acceptance

Xiaomi Pad 6S Pro 12.4 (Snapdragon 8 Gen 2, Adreno 740, 16 GB), Android 16,
Termux 0.118.3 (GitHub build), proot-distro 5.5.1: install, start, idempotent
restart, status, doctor, stop, and reset all passed; the pre-existing
PulseAudio server and PRoot environment were preserved throughout.

## Not included (experimental tracks, not shipped)

GPU profiles, Box64/Box86/Wine, Steam, and high-end D3D12 games are future
experimental tracks. See `docs/SUPPORT.md`.
