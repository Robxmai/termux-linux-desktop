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
Ubuntu 24.04 environment, provisions XFCE and the desktop user, installs the
GPU/Wine runtime, and writes the runtime manifest.

## Wine runtime source (required for the GPU/Wine runtime)

`desktop-install` provisions Box64 (master pin, built from source), Mesa Turnip
24.1.0, DXVK 2.6.1, Firefox ESR, and the diagnostic apps automatically. The
Wine runtime itself is provided by you:

1. Build Wine 11.11 for ARM64 (wow64 mode) or use a trusted prebuilt tree —
   see `docs/WINE_RUNTIME.md`.
2. Create a tarball of the wine tree:

   ```bash
   tar czf wine-11.11-amd64-wow64.tar.gz -C /path/to wine-11.11-amd64-wow64
   ```

3. Run the install with the tarball:

   ```bash
   TLD_WINE_RUNTIME_TARBALL=/path/to/wine-11.11-amd64-wow64.tar.gz desktop-install
   ```

`desktop-install` is idempotent; the runtime components are cached under
`$PREFIX/var/lib/termux-linux-desktop/runtime-cache`.

Online installs download these Wine-managed runtime installers automatically.
For offline installs, place these files in the runtime cache:

```text
wine-mono-11.1.0-x86.msi
wine-gecko-2.47.4-x86.msi
wine-gecko-2.47.4-x86_64.msi
```

They are installed into `/root/wine-runtime-prefix` through Box64 and the
pinned Wine runtime. Download them from the corresponding WineHQ release
directories before running `desktop-install`.

## Games

```bash
wow-install --game-dir "$HOME/WoW 3.3.5a"   # register a WoW install
wow-launch                                    # launch it on the desktop
desktop-gputest                               # GPU render test (TestD3D)
desktop-gputest --info                        # GPU info report
```

## Remote access

```bash
desktop-vnc start      # x11vnc on :5900, password: termux
desktop-vnc status
desktop-vnc stop
```

## Start the desktop

`start-gladio-desktop.sh` is the **only** launcher for the desktop. It
handles Termux:X11, PulseAudio, and then calls `desktop-start`, which starts
the guest XFCE session inline with the `C.UTF-8` locale (see
`docs/TROUBLESHOOTING.md` §11 for why the locale matters).

1. Open the Termux:X11 Android app and wait for the X11 socket to be ready.
2. Run:

```bash
bash start-gladio-desktop.sh
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
