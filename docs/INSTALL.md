# Install

Termux Linux Desktop runs a Linux desktop on an ARM64 Android tablet without
root access. It uses Termux, PRoot, Ubuntu 24.04, and XFCE, and displays the
desktop through the Termux:X11 Android app.

## Prerequisites

- ARM64 (aarch64) Android tablet.
- Android 11 or newer.
- The Termux app and the Termux:X11 Android app, installed from matching
  trusted sources (F-Droid or the official GitHub releases; do not mix
  sources).
- At least 12 GB of free storage for the base desktop.

## Install Termux packages

Open Termux and run:

```bash
pkg update
pkg install -y git proot-distro pulseaudio
```

## Install the toolkit

```bash
git clone https://github.com/Robxmai/termux-linux-desktop.git
cd termux-linux-desktop
bash bin/install-toolkit
desktop-install
```

`install-toolkit` copies the toolkit into the Termux prefix and creates the
public commands. `desktop-install` preflights the device, installs the pinned
Ubuntu 24.04 environment, provisions XFCE and the desktop user, and writes the
runtime manifest.

## Start the desktop

1. Open the Termux:X11 Android app and wait for the X11 socket to be ready.
2. Run:

```bash
desktop-start
```

3. Check the session with:

```bash
desktop-status
desktop-doctor
```

## Troubleshooting

- `desktop-doctor` reports which prerequisite is missing and what to do.
- `desktop-stop` stops only processes owned by the toolkit.
- `desktop-reset --yes` backs up and removes toolkit-owned state.
- See `docs/RECOVERY.md` for repair paths and `docs/SUPPORT.md` for the
  support tiers.
