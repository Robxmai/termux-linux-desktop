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

`start-gladio-desktop.sh` is the only launcher for the desktop. It delegates
to `desktop-start`, which starts the guest session inline (no separate guest
launcher script):

```text
proot-distro login ... --detach -- bash -c 'export DISPLAY=:0
export PULSE_SERVER=tcp:127.0.0.1:4713
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
exec dbus-run-session -- startxfce4'
```

The session always runs with the `C.UTF-8` locale so terminals and TUI
applications render Unicode instead of `?`. The same locale is written to
`/etc/profile.d/01-locale-fix.sh` and the desktop user's shell files by the
`locale` provisioning stage.

## Display and audio

Termux:X11 provides the display at `$PREFIX/tmp/.X11-unix/X0`. PulseAudio is
reached over `tcp:127.0.0.1:4713`; the toolkit records whether the endpoint is
external or owned so that shutdown never stops a user-managed server.

## Process ownership

Every toolkit-started process is recorded with its PID, start tick, and
command-line hash. Shutdown signals a process only after all three match, so a
recycled PID or an unrelated process is never touched.

## Windows compatibility

Box64 (master pin `ba373ab`), Wine 11.11 (wow64), and DXVK 2.6.1 are provisioned by
`desktop-install` (stage `guest-runtime`) and pinned by the base profile
v2. Each Windows application uses its own Wine prefix; games registered with
`wow-install` get a writable overlay (Cache/Errors/Logs/Screenshots/WTF) bound
over the read-only game tree, and the launcher audits the source tree for
modifications on exit.

### Runtime layout (guest)

| Path | Purpose |
|---|---|
| `/opt/wine-runtime/wine-11.11-amd64-wow64` | Wine runtime tree |
| `/usr/local/bin/box64` | Box64 master pin `ba373ab` (source build; pin marker at `/usr/local/etc/box64-pin.env`) |
| `/usr/lib/aarch64-linux-gnu/libvulkan_freedreno.so` | Mesa Turnip 24.1.0 (stock backup at `.toolkit-backup`) |
| `/usr/local/etc/dxvk.conf` | Default DXVK config (GPU spoof) |
| `/usr/local/etc/wow-performance-profile.env` | Game launcher profile |
| `/usr/local/lib/wine-runtime-env.sh` | Shared Wine/Box64 runtime defaults |
| `/usr/local/bin/wow-launcher` | Game launcher (overlay + audit) |
| `/opt/apps/` | Diagnostics (TestD3D, GPUInfo) |
| `/opt/firefox-esr` | Firefox ESR (default browser for the desktop user) |

### Host layer additions

| Path | Purpose |
|---|---|
| `$TLD_STATE_DIR/runtime-cache` | Downloaded runtime components |
| `$TLD_STATE_DIR/wow.env` | Registered game install (dir, overlay, prefix) |

### Component cache

`lib/tld-wine-runtime.sh` downloads components on the host into
`$TLD_STATE_DIR/runtime-cache` and bind-mounts the cache into the guest for
provisioning; the guest script `rootfs/guest-runtime-provision.sh` is
idempotent and skippable per component (`TLD_SKIP_*`).
