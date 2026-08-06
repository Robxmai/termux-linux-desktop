# Support

## Tiers

| Tier | Capability | Status |
|---|---|---|
| 1 | ARM64 Termux + PRoot + XFCE + Termux:X11 | Supported baseline |
| 2 | Audio, touch, keyboard, controller | Supported where the host exposes the feature (VNC: supported via `desktop-vnc`) |
| 3 | Vulkan acceleration, validated on Qualcomm Adreno/Turnip 24.1.0 | Supported on this device class |
| 4 | Box64 (v0.3.7) + Wine 11.11 + DXVK 2.6.1 Windows applications | Supported on this device class |
| 5 | Steam and high-end D3D12 games | Stress-test only, per device and profile |

## Pinned runtime components (v0.2)

| Component | Pin | Rationale |
|---|---|---|
| Box64 | current master, pinned commit `ba373ab` (built from source) | 0.4.x dynarec regressions corrupted the X11 presentation path on Adreno 740 (grid-of-dots artifact); the regression is fixed upstream in master, which renders clean and translates the game session crypto correctly |
| Mesa Turnip | 24.1.0 | turnip 25.0.0+ rewrote the Vulkan X11 WSI ("direct rendering"); 26.x builds exhibit the same presentation corruption |
| DXVK | 2.6.1 | official release, validated with the pins above |
| Wine | 11.11 (wow64) | validated with the pins above |

## Diagnostics rules (learned on-device)

- **Never** set `DXVK_LOG_LEVEL=debug` with `DXVK_LOG_PATH` on this stack:
  the per-call logging stalls device creation under the pinned Box64 (and
  triggered a `vkMapMemory` assertion in this Wine build under load).
- A DXVK state cache built under one Box64 build can crash the next build at
  swapchain creation (`dxvk::DxvkError` in `ResetSwapChain`); clear
  `/tmp/dxvk-cache` after a Box64 upgrade.
- Older Box64 builds: v0.3.7 rendered clean but dropped the WoW realm session
  (instant disconnect at character list); v0.3.5 crashed shortly after
  swapchain creation. Both are superseded by the master pin.
- The stock `vulkan-validationlayers` package (1.3.275) does not know the
  modern pNext chains used by this driver stack and reports false-positive
  VUID errors; it can also cause `vkMapMemory` failures. Do not enable it.
- The default DXVK config spoofs a recognized GPU
  (`dxgi/d3d9.customVendorId = 10de`, device `1c03`) so older D3D9 clients
  enable their full shader path; without it, clients that do not recognize
  Turnip degrade rendering.
- On-device GPU smoke test: `desktop-gputest` (Winlator TestD3D) boots in
  seconds and is the fastest way to validate a driver swap.

## Known limitations (v0.2)

- WoW 3.3.5a realm login (character list) is validated with the pinned
  Box64 master build; rendering, audio, and login are all confirmed on-device.
- The login zoom animation from earlier stacks is not reproduced; it was a
  symptom of the corrupted render path and is intentionally not restored.

## Experimental claims

GPU acceleration, Windows applications, Steam, and high-end games are
experimental. A result on one device, driver, or profile does not imply
support on another. Do not file a bug report as if an experimental feature
were guaranteed.

## Tested devices

| Device | Android | Result | Date |
|---|---|---|---|
| Xiaomi Pad 6S Pro 12.4 (24018RPACC), Snapdragon 8 Gen 2, Adreno 740, 16 GB | 16 (API 36), Termux 0.118.3 (GitHub build), proot-distro 5.5.1 | Base desktop install, start, idempotent restart, status, doctor, stop, and reset all passed on-device; external PulseAudio preserved | 2026-08-05 |

On-device acceptance covered the full cycle: `desktop-install` (Ubuntu 24.04 as
`tld-ubuntu`), `desktop-start` with XFCE detected, a second `desktop-start`
reusing the owned session, `desktop-status` all PASS, `desktop-doctor --json`
with GPU PASS via Turnip, `desktop-stop` with zero remaining owned processes,
and `desktop-reset --yes` removing the environment, install tree, symlinks,
and state while preserving a timestamped backup. The user's pre-existing
PulseAudio server and PRoot environment were left untouched throughout.

## Reporting

Report bugs with:

- toolkit version and profile;
- Android version, Termux source, and device model;
- architecture and doctor output (`desktop-doctor --json`);
- the exact command that failed;
- whether the issue reproduces on the base profile.

Vulnerability reports must use the private security advisory path in
`SECURITY.md`, never a public issue.
