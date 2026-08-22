# Linux Full-Computer Desktop and Runtime Checklist

This is the acceptance checklist for the project. The primary product is a
general-purpose Ubuntu 24.04 ARM64 Linux workstation through XFCE and
Termux:X11. It must support normal file, web, office, media, terminal,
development, and desktop application use. WoW is a secondary graphics
validation application, not the desktop product.

No item is complete without command output or a saved run record. Every binary
runtime must have a pinned version, source, architecture, and verification
command recorded in the runtime manifest.

Every runtime family listed below is required for the baseline. A missing source
archive or unsupported architecture is a release blocker, not permission to
silently omit the runtime.

PRoot cannot provide Android kernel drivers, systemd, udev, or unrestricted
hardware access. Those capabilities must use the documented Termux/Android
bridge or be recorded as unavailable; they must not be falsely reported as
native Linux support.

## 1. Host Prerequisites

- [ ] ARM64 Android device and sufficient storage, memory, and power verified.
- [ ] Termux and Termux:X11 installed from the same trusted source family.
- [ ] Matching `termux-x11-nightly` package installed in Termux.
- [ ] Termux packages installed: `git`, `proot-distro`, `pulseaudio`, `flock`.
- [ ] `termux-x11` socket is available at `:0`.
- [ ] Termux host PulseAudio TCP endpoint is available at `127.0.0.1:4713`.
- [ ] No cleanup command can match `tailscaled`, `tailscale`, or
      `com.termux.x11`.

## 2. Ubuntu Desktop Baseline

- [ ] Ubuntu `24.04` ARM64 rootfs is installed as `tld-ubuntu`.
- [ ] Ubuntu repositories include `main`, `universe`, `restricted`, and
      `multiverse` for `noble`, `noble-updates`, and `noble-security`.
- [ ] Package metadata is current and the install is not left in a broken
      `dpkg` state.
- [ ] Full XFCE is installed with package recommendations enabled, not with
      `--no-install-recommends`:
      `xfce4`, `xfce4-goodies`, `thunar`, `xfce4-terminal`.
- [ ] `winetricks` is installed as a targeted exception without recommendations;
      Ubuntu's recommendation chain pulls `wine32:armhf`, which conflicts with
      the ARM64 Turnip Vulkan ICD.
- [ ] XFCE services are present: `xfce4-session`, `xfce4-panel`, `xfdesktop4`,
      `xfwm4`.
- [ ] Session services are present: `dbus-user-session`, `dbus-x11`,
      `dbus-run-session`.
- [ ] X11 desktop utilities are present: `x11-utils`, `x11-xserver-utils`,
      `xauth`, `xdg-utils`, `x11vnc`.
- [ ] Fonts are installed: DejaVu, Liberation, Noto core, and Noto mono.
- [ ] Desktop helpers are installed: `file`, `procps`, `iproute2`, `curl`,
      `wget`, `ca-certificates`, `tar`, `xz-utils`, `unzip`, `p7zip-full`,
      `git`.
- [ ] `startxfce4`, `xfce4-session`, `xfce4-terminal`, `thunar`, and
      `dbus-run-session` resolve from `PATH`.
- [ ] The supported launch path is `start-linux-desktop.sh` followed by the
      XFCE session, not an undocumented nested desktop shortcut.

## 2A. Full-Computer Software Baseline

- [ ] A terminal and shell baseline is installed: `bash`, `coreutils`,
      `util-linux`, `procps`, `htop`, `btop`, `man-db`, and `manpages`.
- [ ] File management is installed and usable: `thunar`, `file-roller`,
      `gvfs`, `gvfs-backends`, and `udisks2` where the PRoot environment can
      use them.
- [ ] Debian package management is installed and usable: `dpkg`, `dpkg-deb`,
      and `apt-get` resolve from `PATH`.
- [ ] `application/vnd.debian.binary-package` and `application/x-deb` default
      to the desktop Debian installer, not File Roller or an archive viewer.
- [ ] Double-clicking a valid `.deb` opens a terminal confirmation and runs
      `apt-get install -y ./package.deb`, including dependency resolution; the
      handler rejects invalid package files without changing system state.
- [ ] Web browsing is installed and usable: Firefox ESR with its desktop entry,
      certificates, fonts, multimedia libraries, and download integration.
- [ ] Office and document tools are installed: LibreOffice, a PDF viewer such
      as Evince, and a plain-text editor such as Mousepad.
- [ ] Image and media tools are installed: Ristretto, `mpv`, `ffmpeg`, and
      GStreamer base/good/bad/ugly plugins required by supported media.
- [ ] Archive support is installed: `zip`, `unzip`, `p7zip-full`, `tar`,
      `gzip`, `bzip2`, `xz-utils`, and `zstd`.
- [ ] Clipboard and input integration is installed and tested: `xclip`,
      `xsel`, `xdotool`, `xinput`, and `x11-utils`.
- [ ] Screenshot and remote desktop tools are installed and tested: `scrot`,
      `x11vnc`, and the documented VNC password/port configuration.
- [ ] Network tools are installed: `iproute2`, `iputils-ping`, `dnsutils`,
      `net-tools`, `openssh-client`, `rsync`, `curl`, and `wget`.
- [ ] Security and certificate tools are installed: `openssl`, `gnupg`,
      `ca-certificates`, and `debian-archive-keyring`.
- [ ] Locale, timezone, keyboard, and language settings are configured for
      the intended user and survive desktop restart.
- [ ] The tablet can open, edit, save, copy, move, archive, download, and
      upload ordinary files through the desktop without WoW installed.
- [ ] A valid local `.deb` passes `dpkg-deb --info` and
      `apt-get install --simulate ./package.deb`; the live install path is
      tested separately with an approved package.
- [ ] `GPUInfo` is present in the XFCE Applications menu and taskbar and runs
      against the managed Wine prefix without triggering a second Mono setup.
- [ ] `Wine Configuration` is present in the XFCE Applications menu and opens
      `winecfg` against the managed Wine prefix used by `.exe` launches.
- [ ] `Wine Registry Editor` is present in the XFCE Applications menu and opens
      `regedit` against that same prefix; `mscoree` is explicitly registered as
      Wine builtin and is not disabled by the runtime environment.
- [ ] The tablet can browse the web, play supported media, open PDFs, and
      create/edit office documents through the desktop without WoW installed.

## 2B. Android and PRoot Capability Boundary

- [ ] Termux shared storage is exposed through an explicit, tested mount or
      bind path; arbitrary host filesystem access is not assumed.
- [ ] Clipboard transfer works in both directions between Android and XFCE.
- [ ] Keyboard, mouse, touch, stylus, and hardware-key behavior is tested and
      documented through Termux:X11/Lorie.
- [ ] Audio playback works through the Termux PulseAudio/AAudio bridge.
- [ ] Display modes, rotation behavior, and the requested frame rate are
      recorded from the live Termux:X11 session.
- [ ] Network access works through the Android network stack without relying
      on unavailable Linux kernel networking services.
- [ ] Camera, microphone, Bluetooth, USB, printing, notifications, and power
      management are each marked `SUPPORTED`, `BRIDGED`, or `UNAVAILABLE` with
      evidence. No unsupported hardware feature is presented as complete.
- [ ] The desktop does not require systemd, a display manager, udev rules,
      kernel modules, Docker, or privileged mounts to start and operate.

## 3. Native Linux Runtime Families

- [ ] Core ABI libraries are installed and loadable: `libc6`, `libgcc-s1`,
      `libstdc++6`, `libatomic1`, `zlib1g`, `libunwind8`, `libssl3t64`, and
      `libicu74`.
- [ ] Native application runtime is installed: `python3`, `python3-venv`,
      `python3-pip`, `perl`, `nodejs`, `npm`, `ruby`, `php-cli`, `golang-go`,
      `rustc`, and `cargo`.
- [ ] Java runtime is installed: `openjdk-17-jre` and its certificate/font
      integration are verified.
- [ ] Native GUI libraries required by installed applications are present,
      including GTK and X11 dependencies pulled by the full XFCE install.
- [ ] Audio/video libraries are installed: `libpulse0`, `libasound2t64`,
      `alsa-utils`, `ffmpeg`, and the required GStreamer base/good plugins.
- [ ] Browser runtime is installed and verified: Firefox ESR, including its
      desktop entry and font/rendering dependencies.
- [ ] Any additional language runtime used by a supported desktop application
      is added to the manifest and this checklist before that application is
      accepted.

## 4. Graphics Runtime

- [ ] Vulkan loader and diagnostics are installed: `libvulkan1` and
      `vulkan-tools`.
- [ ] Mesa/OpenGL libraries are installed: `libgl1-mesa-dri`, `libglx-mesa0`,
      `libegl-mesa0`, `libgl1`, `libgles2`, `libgbm1`, and `mesa-utils`.
- [ ] Turnip version, archive, architecture, and SHA-256 are recorded.
- [ ] Gladio version, archive, architecture, and SHA-256 are recorded.
- [ ] Native Gladio host starts and reports EGL/GLES readiness.
- [ ] Native Gladio probe reports GL version, vendor, renderer, and one
      presented frame.
- [ ] The active graphics settings explicitly record whether the run uses
      Gladio or the declared fallback; no silent Zink substitution is allowed.
- [ ] Shader-cache settings, frame pacing, and display mode are recorded.

## 5. Binary Compatibility Runtime

- [ ] Box64 version, source/archive, architecture, interpreter, and SHA-256
      are recorded and `box64 -v` passes.
- [ ] Box86 version, source/archive, architecture, interpreter, and SHA-256 are
      recorded and `box86 -v` passes.
- [ ] Box86 ARMHF support is enabled with `armhf` multiarch, the signed
      `ryanfortner.github.io/box86-debs` repository, its `KEY.gpg`, and the
      selected `box86-android:armhf` package.
- [ ] Box86 ARMHF loader libraries are installed: `libc6:armhf`,
      `libgcc-s1:armhf`, and `libstdc++6:armhf`.
- [ ] The canonical desktop Wine runtime is installed as a complete wow64
      tree, including both PE32+ and PE32 DLL trees.
- [ ] The Wine version, source/archive, architecture, and SHA-256 are recorded.
- [ ] Wine prefix creation is tested with a clean disposable prefix.
- [ ] Prefix `dosdevices/z:` maps to the Linux filesystem needed by desktop
      applications; it must not accidentally point only at the Wine rootfs.
- [ ] Wine runtime dependencies pass `ldd`/loader checks with no unresolved
      libraries.
- [ ] Wine Esync/Fsync settings are recorded and verified.

## 6. Wine and Managed-Code Runtimes

- [ ] Native Linux Mono runtime is installed: `mono-complete`.
- [ ] `mono --version` passes and a managed-code smoke test executes.
- [ ] Microsoft .NET runtime is installed from Ubuntu Noble packages:
      `dotnet-runtime-8.0` and `aspnetcore-runtime-8.0`.
- [ ] `dotnet --list-runtimes` reports the installed .NET and ASP.NET Core
      runtimes.
- [ ] Wine Mono is installed and verified inside the Wine prefix. This is
      separate from the native Linux `mono-complete` package.
- [ ] Wine Gecko is installed and verified for applications using embedded
      HTML.
- [ ] Required Windows .NET Framework components are documented per supported
      application, installed through the approved component path, and checked
      in both `system32` and `syswow64` where applicable.
- [ ] `vcrun2005`, `vcrun2010`, DirectSound, DirectMusic, XAudio, WM Decoder,
      DirectShow, and DirectPlay selections match the profile manifest.
- [ ] `dmusic32` behavior is explicitly recorded; native loading must not be
      claimed if the ARM64/PRoot `modify_ldt` limitation forces builtin mode.

## 7. Direct3D and Multimedia Compatibility

- [ ] WineD3D is installed and its OpenGL path is independently probed.
- [ ] DXVK version, archive, architecture, and SHA-256 are recorded.
- [ ] VKD3D version, archive, architecture, and SHA-256 are recorded.
- [ ] D3D9, D3D11, DXGI, and D3D12 component overrides are explicit in the
      profile and verified by load probes.
- [ ] Audio transport is explicitly selected as ALSA or PulseAudio; the
      effective fallback is recorded when ALSA is unavailable.
- [ ] A 30-second audio test creates a real sink input without underruns.

## 8. Desktop Settings and Services

- [ ] `DISPLAY=:0` is propagated into the guest session.
- [ ] `XDG_RUNTIME_DIR`, DBus session variables, and `PULSE_SERVER` are valid.
- [ ] Termux:X11 is started at the requested frame rate without restarting or
      killing the protected Android display process.
- [ ] One PulseAudio service, one XFCE session, and one desktop supervisor are
      running after startup.
- [ ] Desktop services have dependency ordering: PulseAudio and Termux:X11
      before XFCE.
- [ ] Desktop stop cleans up toolkit-owned processes without touching protected
      services.
- [ ] Desktop restart restores the same display, audio, and runtime settings.
- [ ] The desktop remains usable without WoW or any Windows application.

## 9. Verification Commands and Evidence

- [ ] `desktop-doctor` passes the host, rootfs, desktop, graphics, audio, and
      runtime checks.
- [ ] `desktop-status` reports the expected services and session.
- [ ] `startxfce4` launches through `dbus-run-session` on the live X11 display.
- [ ] `mono --version` and `dotnet --list-runtimes` output is saved.
- [ ] `box64 -v`, `box86 -v` (if installed), and Wine version output is saved.
- [ ] `vulkaninfo --summary`, `glxinfo`, `xdpyinfo`, and `pactl info` output is
      saved.
- [ ] Every runtime has an `ldd`/loader check and no missing dependency.
- [ ] Runtime manifest records package name, version, source, architecture,
      checksum where applicable, and verification result.
- [ ] A clean desktop run has no orphaned DBus, XFCE, PulseAudio, Wine, or
      Box64 processes after shutdown.

## 10. Secondary WoW Graphics Probe

- [ ] WoW is launched only after the desktop checklist passes.
- [ ] WoW uses a disposable prefix and does not modify the desktop baseline.
- [ ] Gladio host logs a real WoW drawable and at least one
      `GLADIO_HOST_PRESENT` event.
- [ ] The probe records renderer identity, frame/present behavior, artifacts,
      input, audio, and exit cleanup.
- [ ] 120 FPS and capture tests are run only after real WoW presentation is
      confirmed.
- [ ] WoW failures are classified as graphics/runtime probe failures, not
      desktop installation failures.

## 11. Release Gate

- [ ] All required checklist items are complete.
- [ ] Any item marked `UNVERIFIED`, `BLOCKED`, or `EMULATED` has an owner,
      reason, fallback, and follow-up evidence path.
- [ ] The final desktop/runtime manifest is archived with the verification run.
- [ ] The supported installation and startup commands are documented and
      reproducible from a clean `tld-ubuntu` environment.
