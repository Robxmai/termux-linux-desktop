# Architecture

Termux Linux Desktop is a layered toolkit. Each layer owns a clear set of
responsibilities and can be diagnosed independently.

```text
Android
  -> Termux host
      -> PRoot Ubuntu 24.04 environment
          -> XFCE desktop
              -> Termux:X11 display
```

## Host layer

The Termux host owns:

- dependency checks and downloads;
- the pinned Ubuntu environment through `proot-distro`;
- PulseAudio connectivity and ownership;
- the Termux:X11 socket;
- process ownership records, stop/cleanup, and logs;
- manifests, profiles, and reset.

Managed paths on the host:

```text
$PREFIX/opt/termux-linux-desktop/       installed toolkit
$PREFIX/var/lib/termux-linux-desktop/   state, manifests, process records
$PREFIX/var/log/termux-linux-desktop/   logs
$HOME/.config/termux-linux-desktop/     user configuration
```

## Environment layer

The Ubuntu 24.04 environment is a PRoot container named `tld-ubuntu`. It is
provisioned with XFCE, D-Bus, Thunar, a terminal, and diagnostics, and runs
with a non-privileged desktop user named `tld`. Guest root operations are
limited to installation and provisioning and are not Android root.

The guest launcher lives at:

```text
/usr/local/lib/termux-linux-desktop/start-guest.sh
```

It starts `dbus-run-session -- startxfce4` with the display and PulseAudio
endpoint provided by the host.

## Display and audio

Termux:X11 provides the display at `$PREFIX/tmp/.X11-unix/X0`. PulseAudio is
reached over `tcp:127.0.0.1:4713`; the toolkit records whether the endpoint is
external or owned so that shutdown never stops a user-managed server.

## Process ownership

Every toolkit-started process is recorded with its PID, start tick, and
command-line hash. Shutdown signals a process only after all three match, so a
recycled PID or an unrelated process is never touched.

## Windows compatibility

Box64, Box86, and Wine are optional experimental layers. They are not
installed by the base profile and each Windows application is expected to use
its own prefix.
