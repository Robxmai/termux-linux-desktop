# Termux Linux Desktop

Termux Linux Desktop is a no-root ARM64 Android toolkit built from Termux,
PRoot Linux, XFCE, and Termux:X11. Optional Box64, Box86, and Wine components
can extend compatibility with selected desktop software.

## Product Boundary

This project targets a portable Linux desktop environment on ARM64 Android
devices without root access. Windows applications and games are experimental;
compatibility, performance, input, graphics, and stability vary by device and
software.

This repository does not include proprietary games, Windows files, Steam
credentials, or DRM/anti-cheat bypasses. Use only software and data you are
legally entitled to use.

## Prerequisites

- An ARM64 Android device with sufficient storage, memory, and sustained power.
- Android 11 or newer; this is the validated baseline for v0.1.
- Termux and the Termux:X11 Android app installed from matching trusted
  sources: either F-Droid for both or official GitHub releases for both. Do
  not mix sources.
- Termux:X11 requires both the Android Termux:X11 app and its matching
  `termux-x11-nightly` companion package inside Termux.
- The standard Termux core utilities must include `flock`; it is required for
  process ownership locking.
- Network access for package and rootfs installation.
- A backup of any personal configuration before recovery or reinstallation.

## First Run

Install the matching Termux and Termux:X11 Android applications from either
F-Droid or the official GitHub releases. Install the matching
`termux-x11-nightly` companion package from the same source family; do not mix
F-Droid and GitHub builds.

From the repository checkout, run these commands in the Termux host:

```sh
pkg install -y proot-distro pulseaudio
command -v flock
bash bin/install-toolkit
desktop-install
```

`desktop-install` creates the pinned Ubuntu 24.04 PRoot guest named
`tld-ubuntu`, provisions the non-root `tld` user, and installs the base XFCE
desktop. Start the matching Termux:X11 Android app before launching the
desktop; installation warns when its socket is not ready.

The base installation does not require package upgrades, repository changes,
GPU acceleration, Box64, Box86, Wine, Steam, or game packages. Add optional
compatibility layers only after the base desktop starts reliably.

## Support

Start with [Recovery](#recovery), then search the
[repository issue tracker](../../issues) before opening a new support issue.
Include the device model, Android release, ARM64 ABI, Termux source and
version, PRoot distribution, exact commands, and sanitized output. Do not
include account sign-in material or internal network details.

## Recovery

1. Exit XFCE and the PRoot session, then stop the Termux:X11 process.
2. Retry `desktop-install` before adding optional compatibility components.
3. If the Ubuntu environment is disposable, remove and recreate it:

    ```sh
    proot-distro remove tld-ubuntu
    desktop-install
    ```

   Back up personal configuration first. Reinstalling the environment deletes
   its files.

## Security

Read [SECURITY.md](SECURITY.md) before reporting a security concern or sharing
diagnostic material.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) for the change, testing, evidence, and
hardware details expected in a contribution.

## License

The [Apache License 2.0](LICENSE) covers original materials in this repository
only. Termux, XFCE, Ubuntu, Wine, and other dependencies retain their own
licenses.
