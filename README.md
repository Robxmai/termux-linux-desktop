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
- Network access for package installation and updates.
- A backup of any personal configuration before recovery or reinstallation.

## First Run

Run these commands from the Termux host:

```sh
pkg update && pkg upgrade
pkg install x11-repo proot-distro termux-x11-nightly
command -v flock
proot-distro install debian
termux-x11 :0 &
proot-distro login debian --shared-tmp
```

After `proot-distro login debian --shared-tmp` opens the Debian PRoot guest,
run these commands inside the guest:

```sh
apt update
apt install xfce4 dbus-x11
export DISPLAY=:0
startxfce4
```

This is a minimal bootstrap sequence, not a guarantee of application or game
compatibility. Box64, Box86, and Wine are optional and should be added only
after the base desktop starts reliably.

## Support

Start with [Recovery](#recovery), then search the
[repository issue tracker](../../issues) before opening a new support issue.
Include the device model, Android release, ARM64 ABI, Termux source and
version, PRoot distribution, exact commands, and sanitized output. Do not
include account sign-in material or internal network details.

## Recovery

1. Exit XFCE and the PRoot session, then stop the Termux:X11 process.
2. Update Termux packages and retry the base desktop before adding optional
   compatibility components.
3. If the Debian environment is disposable, remove and recreate it:

   ```sh
   proot-distro remove debian
   proot-distro install debian
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
