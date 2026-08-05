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

## Reporting

Report bugs with:

- toolkit version and profile;
- Android version, Termux source, and device model;
- architecture and doctor output (`desktop-doctor --json`);
- the exact command that failed;
- whether the issue reproduces on the base profile.

Vulnerability reports must use the private security advisory path in
`SECURITY.md`, never a public issue.
