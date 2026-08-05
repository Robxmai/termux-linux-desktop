# Support

## Tiers

| Tier | Capability | Status |
|---|---|---|
| 1 | ARM64 Termux + PRoot + XFCE + Termux:X11 | Supported baseline |
| 2 | Audio, touch, keyboard, controller | Supported where the host exposes the feature (VNC planned) |
| 3 | Vulkan acceleration, initially validated on Qualcomm Adreno/Turnip | Experimental per device |
| 4 | Box64/Box86 + Wine Windows applications | Experimental per application |
| 5 | Steam and high-end D3D12 games | Stress-test only, per device and profile |

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
