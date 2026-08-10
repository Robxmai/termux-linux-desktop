# Troubleshooting & Debug Log: Rendering Issues on Adreno 740 (2026-08-06)

## ✅ RESOLVED (2026-08-07): the DXVK artifacts

**Root cause: DXVK's parallel shader compilation racing on Turnip.**
With the default 8 compiler threads, DXVK 2.6.x/2.4.1 corrupts rendered
frames on this driver (Adreno 740, turnip 24.1.0).

**Fix (verified via VNC + on-display):**
```ini
# /usr/local/etc/dxvk.conf
dxvk.numCompilerThreads = 1
d3d9.maxFrameLatency = 1
```
Result: TestD3D 560 fps, ZERO artifacts.

This document is the accumulated debugging record for the "artifacts" and
"white screen" problems seen when running D3D9 apps (TestD3D, WoW 3.3.5a)
through this toolkit on a Xiaomi Pad 6S Pro (Snapdragon 8 Gen 2, Adreno 740).

It exists so that a future session (or a fresh contributor) does not have to
re-derive any of this. Read it before touching the GPU/Wine stack.

---

## 1. The two distinct problems

### Problem A — "wineserver deadlock / frozen at 8 compiler threads" (SOLVED)
Symptom: game creates the swapchain then freezes; process wchan = `pipe_read`
on a pipe it holds both ends of; wineserver spins `get_window_tree` in a loop;
HUD fps ~140 (stale frame). NOT a crash — a livelock between wine and the
X11 window setup.

**Root cause: poisoned `user.reg` (HKCU) in the wine prefix.** Written by
earlier WoW runs. Fix: regenerate the prefix's HKCU (delete `user.reg` or
clone the prefix without it). The game then runs at full speed.

### Problem B — artifacts with DXVK / white screen with WineD3D (UNSOLVED)
- DXVK (d3d9=n): renders at 300-500 fps but with intermittent artifacts.
- WineD3D builtin (d3d9=b): GL context initializes (zink) but presents
  NOTHING — white/blank window. Proven on termux-x11 :0 AND Xvfb :99, with
  box64 0.4.5, 0.3.7 and 0.3.6, turnip 24.1.0/25.0.0, DXVK 2.6.1/2.4.1.

---

## 2. Clean-install gaps found in the provisioning (all fixed in repo)

The original `guest-runtime-provision.sh` was missing the entire GPU
userspace stack, so a fresh install could not run ANY GPU app:

| Gap | Symptom | Fix (now in the script) |
|-----|---------|-------------------------|
| No vulkan loader (`libvulkan.so.1`) | `Failed to load libvulkan.so.1` | `apt-get install libvulkan1` |
| No mesa Vulkan/GL drivers | zink `VK_ERROR_INITIALIZATION_FAILED` | `mesa-vulkan-drivers libgl1-mesa-dri libglx-mesa0 libegl-mesa0 libgl1 libgles2 mesa-utils` |
| apt turnip overwrites the kgsl-capable turnip | `VK_ERROR_INITIALIZATION_FAILED` (apt turnip lacks kgsl support; Android uses /dev/kgsl-3d0, apt build expects msm DRM) | re-deploy `turnip-24.1.0.tzst`'s `libvulkan_freedreno.so` AFTER apt install |
| dxvk dlls not installed (no prefix at provision time) | `d3d9.dll not found` | create prefix via `wineboot -i` then install dxvk (x64→system32, x32→syswow64) |
| TestD3D/GPUInfo not installed | empty `winlator-apps/` | copy from `winlator-apps.tar.gz` (or host copies) |

## 3. Wine prefix gotchas (D3D9 = 32-bit!)

- TestD3D.exe and WoW are **32-bit**. In wow64 wine, 32-bit dlls live in
  `drive_c/windows/syswow64/` and MUST be the **x32** builds
  (DXVK: `x32/` dir; wine builtin: `lib/wine/i386-windows/`).
- Mixing x64 dlls into syswow64 → `c000007b` (BAD_IMAGE_FORMAT).
- Fresh `wineboot -i` on wine 11.11 needs the prefix dir to already exist.
- `user.reg` (HKCU) accumulates display/audio settings that can poison the
  X11 window setup — see Problem A. Keep WoW's real config in WTF, not HKCU.
- Do not run `wineboot` with `DISPLAY` set if the display is in a bad state;
  boot headless (`unset DISPLAY`).

## 4. box64 build traps (v0.3.6 on Ubuntu 24.04/glibc 2.39)

Building box64 inside the proot container:

1. **NEVER pass `-DRV64=ON`** — enables RISC-V codegen → `-march=rv64gc`
   errors. Use `-DARM64=ON -DARM_DYNAREC=ON`.
2. **The container environment carries `ANDROID_ROOT`/`ANDROID_DATA`**
   (passed through proot). CMake auto-detects "Android" and adds `-DANDROID`,
   which compiles the *Android* entrypoint (`my___libc_init`) instead of
   `my___libc_start_main` → wine fails with
   `Global Symbol __libc_start_main not found` / `Warning, function
   my___libc_start_main not found`.
   **Fix: `-DANDROID=OFF -DTERMUX=OFF -DWINLATOR_GLIBC=OFF`.**
   Verify: `nm -D box64 | grep my___libc_start_main` must print a symbol.
3. **Build INSIDE the container**, not on the termux host (host = bionic
   toolchain; the pthread GNU extensions are undeclared there — do NOT patch
   threads.c with extern declarations; the container's glibc 2.39 declares
   them natively and the patch creates "conflicting types").
4. Provisioning-style command (proven):
   `cmake .. -DCMAKE_BUILD_TYPE=Release -DARM64=ON -DARM_DYNAREC=ON -DANDROID=OFF -DTERMUX=OFF`
5. Note: proot-distro binds the termux home into the container
   (`/data/data/com.termux/files/home` = both sides); keep builds there.

## 5. The WineD3D white screen (why "use wined3d" did not work here)

- WineD3D renders via OpenGL. On mesa 25.x for Adreno the ONLY accelerated
  GL is **zink** (GL-over-Vulkan). zink's GLX presentation requires the
  **DRI3** X extension.
- **termux-x11 does not provide DRI3** (`libEGL warning: DRI3 error: Could
  not get DRI3 device`). Xvfb doesn't either. Result: GL context is created
  (`GL_RENDERER "zink Vulkan 1.3 (Turnip Adreno (TM) 740 (MESA_TURNIP))"`)
  but the swapchain never reaches the window → white.
- Proven independent of: box64 version (0.4.5 / 0.3.7 / 0.3.6), turnip
  version (24.1.0 / 25.0.0 / 26.1.99), DXVK presence, prefix state, X server
  instance (termux-x11 fresh vs 23h-old, Xvfb).
- The user's Winlator (2025-06, v8.0) is clean with WineD3D+Turnip because
  Winlator ships its OWN X server whose GLX/present path works without DRI3.

## 6. The DXVK artifacts (the remaining bug)

- All DXVK combos tested artifact: turnip 24.1.0/25.0.0, DXVK 2.6.1/2.4.1
  (2.4.1 reduced frequency, did not fix), box64 0.4.5/0.3.7/0.3.6, safe
  dynarec flags, clean HKCU, fresh container, fresh X server, reboot,
  compositor off, audio off, present modes immediate/fifo, HWBUF on/off.
- Not throttling (39C), not caches, not the prefix.
- Hypothesis: corruption is in the DXVK→X11 present path (GPU blit into the
  XShm buffer / termux-x11 copy). The next lever is the X server itself
  (Winlator-style server with a different present path, or present via
  non-shm).

## 7. Reference matrix (Winlator v8.0, 2025-06 — user-reported CLEAN)

| Component | Clean (Winlator 8.0) | This stack |
|-----------|----------------------|------------|
| box64 | 0.3.1 devel | 0.4.5 / 0.3.7 / 0.3.6 |
| turnip | 24.3.0 devel | 24.1.0 (kgsl) |
| DXVK | 2.4.1 | 2.6.1 / 2.4.1 |
| DX wrapper | WineD3D (user test) | WineD3D / DXVK |
| X server | Winlator XServer | termux-x11 |
| wine | ~10.3 | 11.11 wow64 |

## 8. Debug harness

`~/tld-debug-harness.sh` (host side): fingerprints the stack, records a 1s
process timeline + 5s OOM/state snapshots, starts wineserver with
`WINEDEBUG=+server,+nsi`, and on death bundles logcat/dmesg/logs into
`~/tld-debug-bundle-<ts>.tgz`. Use it for any new GPU issue.

## 9. Session log / status

- 2026-08-06: deadlock (Problem A) fixed via clean HKCU. Artifacts (Problem
  B) still open; wined3d path proven broken on termux-x11 (no DRI3).
  Fresh container reinstalled; provisioning gaps fixed in repo.
  box64 0.3.6 built in-container (ANDROID=OFF).
- Next: test a DRI3-capable X server or Winlator's XServer for the game
  display; retest DXVK artifacts there.

---

## 10. RESOLVED: XFCE Black Screen With Cursor (2026-08-10)

### Symptom

Termux:X11 displayed a black screen with a working cursor even though the
PRoot guest, XFCE session, window manager, panel, and X11 connection were
healthy.

### Root Cause

XFCE compositing was enabled but its composite surface was not rendering
correctly through Termux:X11. The Android display showed the empty black
surface while the cursor remained visible. Linux startup itself was healthy.

### Fix

Inside the managed guest, with `DISPLAY=:0`:

```bash
xfconf-query -c xfwm4 -p /general/use_compositing -s false
xfwm4 --replace
```

The setting persists in the guest XFCE profile. The normal desktop launcher
was then restarted and verified with a fresh screenshot showing the wallpaper,
panel, icons, and Firefox.

### Verification

Process checks and `xdpyinfo` are insufficient for this failure. Always capture
and inspect a screenshot. A raw X11 root capture may contain valid pixels while
the displayed composite surface is black.

---

## 11. RESOLVED: Unicode Renders as `?` in Terminals and TUIs (2026-08-10)

### Symptom

TUI applications such as OpenCode rendered every non-ASCII character as `?`
(`????????`) inside `xfce4-terminal` on the desktop, while fonts were fine
(`fc-match` returned DejaVu Sans Mono).

### Root Cause

The XFCE session was launched with **no locale environment at all**
(`LANG`, `LC_ALL`, and `LC_CTYPE` unset). glibc then fell back to the POSIX
locale (`ANSI_X3.4-1968`), so any program that calls `setlocale()` treats the
terminal as ASCII-only and transliterates Unicode to `?`.

Why was the locale unset? The session was started through a non-login
`bash -c` chain, so `/etc/profile.d/*.sh` never ran. The `01-locale-fix.sh`
helper only ran `locale-check`, which merely validates an *existing* value and
does not assign one when everything is unset. The `runsv` service env had
`LANG=en_US.UTF-8`, but `en_US.UTF-8` is **not generated** in the guest (only
`C`, `C.utf8`, `POSIX` exist), so glibc fell back to C anyway.

### Fix

1. `desktop-start` now launches the guest session inline with an explicit
   UTF-8 locale:

   ```bash
   proot-distro login "$TLD_GUEST_CONTAINER" --user "$TLD_GUEST_USER" \
     --shared-tmp --shared-x11 --detach -- bash -c 'export DISPLAY=:0
   export PULSE_SERVER=tcp:127.0.0.1:4713
   export LANG=C.UTF-8
   export LC_ALL=C.UTF-8
   exec dbus-run-session -- startxfce4'
   ```

2. The `guest-runtime-provision.sh` `locale` stage writes
   `/etc/profile.d/01-locale-fix.sh` and appends the same exports to
   `/root/.bashrc`, `/root/.profile`, `/root/.bashrc`, and
   `/root/.profile`, so every login shell in the guest is UTF-8 too.

`C.UTF-8` was chosen because it is the only UTF-8 locale generated in the
Ubuntu 24.04 PRoot guest (`locale -a` shows `C`, `C.utf8`, `POSIX`); no
`locale-gen` is required.

### Single Launcher Rule

`start-gladio-desktop.sh` is the **only** launcher for the desktop. There is
no separate guest launch script (the former `start-guest.sh` was removed).
All session startup is inline inside `desktop-start`; users should never be
told to run any other script to bring up the desktop.

### Verification

- `locale charmap` in the guest reports `UTF-8`.
- `tr '\0' '\n' < /proc/<xfce4-session pid>/environ | grep LANG` reports
  `LANG=C.UTF-8` and `LC_ALL=C.UTF-8`.
- OpenCode and other TUIs render box-drawing characters and CJK correctly.

---

## 12. VITAL: libdl.so must exist for every emulation architecture

### What it is

`libdl` is the dynamic-loading library (`dlopen` / `dlsym` / `dlclose`).
Box64 wraps `dlopen` for x86_64 Wine, and Windows installers
(e.g. `lark.exe`) commonly load `libdl.so` by its **unversioned** linker
name. `libc6` ships only `libdl.so.2`; the `libdl.so` symlink normally comes
from `libc6-dev` and is easy to miss.

### The failure mode

- `box64` logs `Cannot find libdl.so` (or the loader reports
  `error while loading shared libraries: libdl.so`) the first time a program
  calls `dlopen`.
- Missing emulation libraries are a common cause of "black screen" or
  instant-exit launches: Wine loads, but the emulated loader cannot resolve
  the libraries it needs, so the process dies before creating a window.

### Fix (installed by the `runtime-libs` provision stage)

```bash
ln -s libdl.so.2 /usr/lib/x86_64-linux-gnu/libdl.so
ln -s libdl.so.2 /usr/lib/aarch64-linux-gnu/libdl.so
ln -s libdl.so.2 /usr/lib/arm-linux-gnueabihf/libdl.so
ln -s libdl.so.2 /usr/lib/box64-x86_64-linux-gnu/libdl.so
```

Verification: `BOX64_LOG=1 box64 .../bin/wine --version` prints
`Using native(wrapped) libdl.so.2`.

## 13. Wine registry: wined3d overrides and environment

The `wine-registry` provision stage bakes the following into
`HKCU\Software\Wine\DllOverrides` so **every** .exe launch uses wined3d
(Wine builtin D3D), matching the Winlator "no DXVK" profile:

- `d3d9`, `d3d10core`, `d3d11`, `dxgi`, `ddraw`, `dinput8` = `builtin`
- `winemac.drv`, `winewayland.drv` = `disabled`

And into `HKCU\Environment`:

- `TEMP` / `TMP` = `C:\users\<guest user>\AppData\Local\Temp`
- `DISPLAY` = `:0`
- `PULSE_SERVER` = `tcp:127.0.0.1:4713`

Check with:

```bash
box64 .../bin/wine reg query "HKCU\Software\Wine\DllOverrides"
box64 .../bin/wine reg query "HKCU\Environment"
```


