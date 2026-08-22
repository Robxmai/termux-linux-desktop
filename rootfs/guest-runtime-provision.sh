#!/usr/bin/env bash
# Guest-side wine/GPU runtime provisioning for termux-linux-desktop.
# Runs INSIDE the tld-ubuntu container as root via:
#   proot-distro login <container> --bind <cache>:<guest-cache> -- bash -lc "$(cat this file)"
# Idempotent. Each component is installed from the shared runtime cache.
set -Eeuo pipefail

RUNTIME_CACHE="${TLD_RUNTIME_CACHE:-/root/runtime-cache}"
GUEST_USER="${TLD_GUEST_USER:-root}"
WINE_VERSION="${TLD_WINE_VERSION:-11.11}"
WINE_TREE_NAME="${TLD_WINE_TREE_NAME:-wine-11.11-amd64-wow64}"
WINE_INSTALL_DIR="${TLD_WINE_INSTALL_DIR:-/opt/wine-runtime}"
RUNTIME_VERSION_FILE="/usr/local/etc/termux-linux-desktop-runtime.env"

log() { printf '[runtime] %s\n' "$*"; }
fail() { printf '[runtime] ERROR: %s\n' "$*" >&2; return 1; }

has_file() { [[ -f "$1" ]]; }

# ---------------------------------------------------------------- packages
install_packages() {
  log "installing runtime packages"
  DEBIAN_FRONTEND=noninteractive apt-get update >/dev/null 2>&1 || fail "apt-get update"
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates curl file tar xz-utils gcc g++ make cmake git cabextract \
    python3 python3-venv python3-pip perl nodejs npm ruby-full php-cli \
    golang-go rustc cargo openjdk-17-jre mono-complete \
    dotnet-runtime-8.0 aspnetcore-runtime-8.0 \
    libpulse0 libasound2t64 libdbus-glib-1-2 libxt6 alsa-utils pulseaudio-utils \
    xdg-utils x11vnc tigervnc-scraping-server scrot ffmpeg \
    gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-libav \
    box86-android:armhf libc6:armhf libgcc-s1:armhf libstdc++6:armhf \
    libvulkan1:arm64 mesa-vulkan-drivers:arm64 libgl1-mesa-dri:arm64 libglx-mesa0:arm64 \
    libegl-mesa0:arm64 libgl1:arm64 libgles2:arm64 libgbm1:arm64 mesa-utils:arm64 >/dev/null 2>&1 || fail "apt-get install"
  # Avoid pulling distro wine32:armhf and its conflicting Mesa Vulkan ICD.
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends winetricks >/dev/null 2>&1 || fail "winetricks install"
  return 0
}

# ------------------------------------------------------------------- box64
install_box64() {
  local version="${TLD_BOX64_VERSION:-ba373ab4b3ae2ecbc9aeeece309817cad47ba421}"
  local archive="$RUNTIME_CACHE/box64-$version.tar.gz"
  local build_dir="/tmp/box64-build"
  local pin_file="/usr/local/etc/box64-pin.env"

  if [[ -f "$pin_file" ]] && grep -q "$version" "$pin_file" 2>/dev/null &&
    command -v /usr/local/bin/box64 >/dev/null 2>&1; then
    log "box64 $version already installed"
    return 0
  fi
  has_file "$archive" || fail "box64 source archive missing from cache: $archive"
  rm -rf "$build_dir"
  mkdir -p "$build_dir"
  tar xzf "$archive" -C "$build_dir" --strip-components=1 || fail "box64 extract"
  cmake -S "$build_dir" -B "$build_dir/build" -DCMAKE_BUILD_TYPE=Release \
    -DARM_DYNAREC=ON -DCMAKE_C_FLAGS="-O3" >/dev/null 2>&1 || fail "box64 cmake"
  cmake --build "$build_dir/build" -j"$(nproc)" >/dev/null 2>&1 || fail "box64 build"
  install -m 0755 "$build_dir/build/box64" /usr/local/bin/box64 || fail "box64 install"
  printf 'box64_pin=%s
' "$version" > "$pin_file"
  log "box64 $version installed"
  return 0
}

# ------------------------------------------------------------------ turnip
install_turnip() {
  local version="${TLD_TURNIP_VERSION:-24.1.0}"
  local archive="$RUNTIME_CACHE/turnip-$version.tzst"
  local extract_dir="/tmp/turnip-extract"
  local driver="/usr/lib/aarch64-linux-gnu/libvulkan_freedreno.so"

  has_file "$archive" || fail "turnip archive missing from cache: $archive"
  rm -rf "$extract_dir"
  mkdir -p "$extract_dir"
  tar --zstd -xf "$archive" -C "$extract_dir" || fail "turnip extract"
  local so
  so=$(find "$extract_dir" -name 'libvulkan_freedreno.so' -print -quit)
  [[ -n "$so" ]] || fail "turnip archive has no libvulkan_freedreno.so"
  if [[ -f "$driver" && ! -f "$driver.toolkit-backup" ]]; then
    cp -p "$driver" "$driver.toolkit-backup"
  fi
  install -m 0755 "$so" "$driver" || fail "turnip install"
  ldconfig >/dev/null 2>&1 || true
  log "turnip $version installed"
  return 0
}

# -------------------------------------------------------------------- wine
install_wine() {
  local archive="$RUNTIME_CACHE/$WINE_TREE_NAME.tar.gz"
  local target="$WINE_INSTALL_DIR/$WINE_TREE_NAME"

  if [[ -x "$target/bin/wine" ]]; then
    log "wine runtime already installed at $target"
    return 0
  fi
  has_file "$archive" || fail "wine runtime archive missing from cache: $archive"
  mkdir -p "$WINE_INSTALL_DIR"
  tar xzf "$archive" -C "$WINE_INSTALL_DIR" || fail "wine extract"
  [[ -x "$target/bin/wine" ]] || fail "wine archive has no bin/wine"
  log "wine $WINE_VERSION installed"
  return 0
}

# ----------------------------------------------------------- wine components
install_wine_components() {
  local target="$WINE_INSTALL_DIR/$WINE_TREE_NAME"
  local prefix="${TLD_WINE_PREFIX:-/root/wine-runtime-prefix}"
  local box64_bin="${TLD_BOX64_BIN:-/usr/local/bin/box64}"
  local gecko_version="${TLD_WINE_GECKO_VERSION:-2.47.4}"
  local mono_version="${TLD_WINE_MONO_VERSION:-11.1.0}"
  local mono_msi="$RUNTIME_CACHE/wine-mono-$mono_version-x86.msi"
  local gecko_x86_msi="$RUNTIME_CACHE/wine-gecko-$gecko_version-x86.msi"
  local gecko_x64_msi="$RUNTIME_CACHE/wine-gecko-$gecko_version-x86_64.msi"

  [[ -x "$target/bin/wine" ]] || fail "wine runtime missing: $target/bin/wine"
  [[ -x "$box64_bin" ]] || fail "box64 runtime missing: $box64_bin"
  has_file "$mono_msi" || fail "Wine Mono installer missing from cache: $mono_msi"
  has_file "$gecko_x86_msi" || fail "Wine Gecko x86 installer missing from cache: $gecko_x86_msi"
  has_file "$gecko_x64_msi" || fail "Wine Gecko x86_64 installer missing from cache: $gecko_x64_msi"

  if [[ ! -d "$prefix/drive_c/windows/mono/mono-2.0" ]]; then
    env DISPLAY="${DISPLAY:-:0}" WINEPREFIX="$prefix" WINEDEBUG=-all \
      WINEDLLOVERRIDES=winebth=d timeout 300 "$box64_bin" "$target/bin/wine" \
      msiexec /i "$mono_msi" /qn || fail "Wine Mono install"
  fi

  if [[ ! -f "$prefix/drive_c/windows/system32/gecko/$gecko_version/wine_gecko/VERSION" ]]; then
    env DISPLAY="${DISPLAY:-:0}" WINEPREFIX="$prefix" WINEDEBUG=-all \
      WINEDLLOVERRIDES=winebth=d timeout 300 "$box64_bin" "$target/bin/wine" \
      msiexec /i "$gecko_x64_msi" /qn || fail "Wine Gecko x86_64 install"
  fi

  if [[ ! -f "$prefix/drive_c/windows/syswow64/gecko/$gecko_version/wine_gecko/VERSION" ]]; then
    env DISPLAY="${DISPLAY:-:0}" WINEPREFIX="$prefix" WINEDEBUG=-all \
      WINEDLLOVERRIDES=winebth=d timeout 300 "$box64_bin" "$target/bin/wine" \
      msiexec /i "$gecko_x86_msi" /qn || fail "Wine Gecko x86 install"
  fi

  [[ -d "$prefix/drive_c/windows/mono/mono-2.0" ]] || fail "Wine Mono prefix files missing"
  [[ -f "$prefix/drive_c/windows/system32/gecko/$gecko_version/wine_gecko/VERSION" ]] || fail "Wine Gecko x86_64 prefix files missing"
  [[ -f "$prefix/drive_c/windows/syswow64/gecko/$gecko_version/wine_gecko/VERSION" ]] || fail "Wine Gecko x86 prefix files missing"
  if id -u "$GUEST_USER" >/dev/null 2>&1; then
    chown -R "$GUEST_USER:$GUEST_USER" "$prefix"
  fi
  log "Wine Mono $mono_version and Gecko $gecko_version installed in $prefix"
  return 0
}

# ----------------------------------------------------------- runtime libs
# libdl is the dynamic-loading library (dlopen/dlsym/dlclose). Box64 needs
# the unversioned libdl.so linker name to wrap dlopen for x86_64 Wine, and
# Windows installers commonly dlopen("libdl.so") too. The .so.2 versioned
# files ship with libc6, but the unversioned symlink only comes with
# libc6-dev — so create it explicitly for every emulation directory.
# VITAL: must be present before Wine/Box64 ever runs.
#
# libc.so has the same trap in reverse: Ubuntu ships it as an ASCII linker
# script (GROUP libc.so.6 ...), so dlopen("/lib/aarch64-linux-gnu/libc.so")
# fails with "invalid ELF header". Some installers dlopen libc.so directly.
# We replace the linker script with a real ELF copy of libc.so.6 (saved as
# .ldscript for toolchains) so dlopen() works while ld still links.
configure_runtime_libs() {
  local d src

  for d in \
    /usr/lib/x86_64-linux-gnu \
    /usr/lib/aarch64-linux-gnu \
    /usr/lib/arm-linux-gnueabihf \
    /usr/lib/box64-x86_64-linux-gnu; do
    if [[ -f "$d/libdl.so.2" && ! -e "$d/libdl.so" ]]; then
      ln -s libdl.so.2 "$d/libdl.so" || fail "cannot link $d/libdl.so"
      log "linked $d/libdl.so -> libdl.so.2"
    fi
  done
  if [[ -d /usr/lib/box86-i386-linux-gnu && -f /usr/lib/i386-linux-gnu/libdl.so.2 ]]; then
    ln -sf /usr/lib/i386-linux-gnu/libdl.so.2 /usr/lib/box86-i386-linux-gnu/libdl.so.2 2>/dev/null || true
    ln -sf /usr/lib/i386-linux-gnu/libdl.so.2 /usr/lib/box86-i386-linux-gnu/libdl.so 2>/dev/null || true
    log "linked box86 i386 libdl"
  fi

  # libc.so: replace ASCII linker scripts with real ELF copies so dlopen()
  # works (installers that dlopen libc.so otherwise fail with
  # "invalid ELF header"). Keep the original script as .ldscript.
  for d in /lib/aarch64-linux-gnu /usr/lib/x86_64-linux-gnu /usr/lib/arm-linux-gnueabihf; do
    src="$d/libc.so.6"
    [[ -f "$src" ]] || continue
    if [[ -f "$d/libc.so" ]] && ! head -c 4 "$d/libc.so" 2>/dev/null | grep -q ELF; then
      cp -a "$d/libc.so" "$d/libc.so.ldscript" 2>/dev/null || true
      cp -a "$src" "$d/libc.so" || fail "cannot replace $d/libc.so"
      log "replaced $d/libc.so linker script with ELF copy (original kept as .ldscript)"
    fi
    if [[ ! -e "$d/libc.so" ]]; then
      cp -a "$src" "$d/libc.so" || fail "cannot create $d/libc.so"
      log "created $d/libc.so (ELF copy of libc.so.6)"
    fi
  done
  if [[ ! -e /usr/lib/box64-x86_64-linux-gnu/libc.so ]]; then
    ln -sf /usr/lib/x86_64-linux-gnu/libc.so /usr/lib/box64-x86_64-linux-gnu/libc.so 2>/dev/null || true
    log "linked box64 libc.so"
  fi

  log "runtime libraries configured (libdl.so + libc.so ELF for all emulation arches)"
  return 0
}

# ------------------------------------------------- wine registry overrides
# Bake the wined3d DLL overrides and environment into the Wine prefix so
# every .exe launch uses builtin D3D9/DXGI (no DXVK) regardless of shell env.
configure_wine_registry() {
  local prefix="${TLD_WINE_PREFIX:-/root/wine-runtime-prefix}"
  local box64_bin="${TLD_BOX64_BIN:-/usr/local/bin/box64}"
  local wine_bin="$WINE_INSTALL_DIR/$WINE_TREE_NAME/bin/wine"
  local dll

  [[ -x "$wine_bin" ]] || return 0
  [[ -d "$prefix" ]] || return 0

  for dll in mscoree d3d9 d3d10core d3d11 dxgi ddraw dinput8; do
    env WINEPREFIX="$prefix" DISPLAY="${DISPLAY:-:0}" WINEDEBUG=-all \
      "$box64_bin" "$wine_bin" reg add "HKCU\\Software\\Wine\\DllOverrides\\$dll" /v "" /d builtin /f >/dev/null 2>&1 || true
  done
  for dll in winemac.drv winewayland.drv; do
    env WINEPREFIX="$prefix" DISPLAY="${DISPLAY:-:0}" WINEDEBUG=-all \
      "$box64_bin" "$wine_bin" reg add "HKCU\\Software\\Wine\\DllOverrides\\$dll" /v "" /d disabled /f >/dev/null 2>&1 || true
  done
  # Wine 11.11 selects the X11 desktop driver from this display-device key;
  # the HKCU Graphics value alone does not make winex11.drv load.
  env WINEPREFIX="$prefix" DISPLAY="${DISPLAY:-:0}" WINEDEBUG=-all \
    "$box64_bin" "$wine_bin" reg add "HKCU\\Software\\Wine\\Drivers" /v Graphics /d x11 /f >/dev/null 2>&1 || true
  env WINEPREFIX="$prefix" DISPLAY="${DISPLAY:-:0}" WINEDEBUG=-all \
    "$box64_bin" "$wine_bin" reg add "HKCU\\Software\\Wine\\X11 Driver" /v UseEGL /d N /f >/dev/null 2>&1 || true
  env WINEPREFIX="$prefix" DISPLAY="${DISPLAY:-:0}" WINEDEBUG=-all \
    "$box64_bin" "$wine_bin" reg add "HKLM\\System\\CurrentControlSet\\Control\\Video\\{00000000-0000-0000-0000-000000000000}\\0000" /v GraphicsDriver /d "C:\\windows\\system32\\winex11.drv" /f >/dev/null 2>&1 || true
  env WINEPREFIX="$prefix" DISPLAY="${DISPLAY:-:0}" WINEDEBUG=-all \
    "$box64_bin" "$wine_bin" reg add "HKCU\\Environment" /v TEMP /d "C:\\users\\$GUEST_USER\\AppData\\Local\\Temp" /f >/dev/null 2>&1 || true
  env WINEPREFIX="$prefix" DISPLAY="${DISPLAY:-:0}" WINEDEBUG=-all \
    "$box64_bin" "$wine_bin" reg add "HKCU\\Environment" /v TMP /d "C:\\users\\$GUEST_USER\\AppData\\Local\\Temp" /f >/dev/null 2>&1 || true
  env WINEPREFIX="$prefix" DISPLAY="${DISPLAY:-:0}" WINEDEBUG=-all \
    "$box64_bin" "$wine_bin" reg add "HKCU\\Environment" /v DISPLAY /d ":0" /f >/dev/null 2>&1 || true
  env WINEPREFIX="$prefix" DISPLAY="${DISPLAY:-:0}" WINEDEBUG=-all \
    "$box64_bin" "$wine_bin" reg add "HKCU\\Environment" /v PULSE_SERVER /d "tcp:127.0.0.1:4713" /f >/dev/null 2>&1 || true
  log "wine registry configured: wined3d builtin overrides + X11/GLX driver + environment"
  return 0
}

# -------------------------------------------------------------------- dxvk
# wined3d (Wine's built-in D3D) is the default renderer and is required by
# the wine-exe launcher. DXVK is opt-in (TLD_ENABLE_DXVK=1) and never
# overwrites the wine builtins: the builtins are kept in place and DXVK is
# installed alongside, so wine-exe (builtin d3d9) keeps working.
install_dxvk() {
  local version="${TLD_DXVK_VERSION:-2.6.1}"
  local archive="$RUNTIME_CACHE/dxvk-$version.tar.gz"
  local wine_windows="$WINE_INSTALL_DIR/$WINE_TREE_NAME/lib/wine/x86_64-windows"
  local extract_dir="/tmp/dxvk-extract"
  local dll

  [[ "${TLD_ENABLE_DXVK:-0}" == 1 ]] || {
    log "dxvk skipped (wined3d is the default renderer; set TLD_ENABLE_DXVK=1 to opt in)"
    return 0
  }

  [[ -d "$wine_windows" ]] || fail "wine tree missing x86_64-windows: $wine_windows"
  has_file "$archive" || fail "dxvk archive missing from cache: $archive"
  rm -rf "$extract_dir"
  mkdir -p "$extract_dir"
  tar xzf "$archive" -C "$extract_dir" || fail "dxvk extract"
  local dll_dir="$extract_dir/dxvk-$version/x64"
  [[ -d "$dll_dir" ]] || dll_dir="$extract_dir/x64"
  [[ -d "$dll_dir" ]] || fail "dxvk archive has no x64 dll directory"
  for dll in d3d9 dxgi d3d11; do
    install -m 0644 "$dll_dir/$dll.dll" "$wine_windows/$dll.dll.dxvk" || fail "dxvk install $dll"
  done
  log "dxvk $version installed alongside wine builtins (opt-in: wine-exe still uses wined3d)"
  return 0
}

# ----------------------------------------------------------------- locale
configure_locale() {
  local profile_file=/etc/profile.d/01-locale-fix.sh
  local rc_file

  cat > "$profile_file" <<'EOF'
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
EOF
  chmod 0644 "$profile_file"

  for rc_file in /root/.bashrc /root/.profile "/root/.bashrc" "/root/.profile"; do
    if [[ -f "$rc_file" ]]; then
      if ! grep -q 'export LANG=C.UTF-8' "$rc_file"; then
        printf '\nexport LANG=C.UTF-8\nexport LC_ALL=C.UTF-8\n' >> "$rc_file"
      fi
    fi
  done
  log "configured C.UTF-8 locale for desktop sessions and shells"
  return 0
}

# ----------------------------------------------------------------- firefox
install_firefox() {
  local archive="$RUNTIME_CACHE/firefox-esr.tar.xz"
  local target="/opt/firefox-esr"

  if [[ -x "$target/firefox" ]]; then
    log "firefox already installed"
  else
    has_file "$archive" || fail "firefox archive missing from cache: $archive"
    mkdir -p "$target"
    tar xf "$archive" -C "$target" --strip-components=1 || fail "firefox extract"
    [[ -x "$target/firefox" ]] || fail "firefox archive has no firefox binary"
    ln -sf "$target/firefox" /usr/local/bin/firefox
    mkdir -p /usr/share/applications /usr/share/pixmaps
    cp "$target/browser/chrome/icons/default/default128.png" /usr/share/pixmaps/firefox-esr.png 2>/dev/null || true
    cat > /usr/share/applications/firefox-esr.desktop <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Firefox ESR
GenericName=Web Browser
Comment=Browse the World Wide Web
Exec=/usr/local/bin/firefox %u
Icon=/usr/share/pixmaps/firefox-esr.png
Terminal=false
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;
StartupNotify=true
EOF
    update-desktop-database /usr/share/applications 2>/dev/null || true
    log "firefox installed"
  fi
  # default browser for the desktop user
  su - "$GUEST_USER" -s /bin/bash -c '
    mkdir -p "$HOME/.config"
    printf "[Default Applications]\nx-scheme-handler/http=firefox-esr.desktop\nx-scheme-handler/https=firefox-esr.desktop\ntext/html=firefox-esr.desktop\n" > "$HOME/.config/mimeapps.list"
    export DISPLAY=:0
    xdg-settings set default-web-browser firefox-esr.desktop >/dev/null 2>&1 || true
  ' || true
  return 0
}

# ------------------------------------------------------------ winlator apps
install_diag_apps() {
  local archive="$RUNTIME_CACHE/winlator-apps.tar.gz"
  local target="/opt/apps"

  if [[ -x "$target/TestD3D.exe" && -x "$target/GPUInfo.exe" ]]; then
    log "diagnostic apps already installed"
    return 0
  fi
  has_file "$archive" || fail "winlator apps archive missing from cache: $archive"
  mkdir -p "$target"
  tar xzf "$archive" -C "$target" || fail "winlator apps extract"
  chmod 0755 "$target/TestD3D.exe" "$target/GPUInfo.exe" 2>/dev/null || true
  [[ -x "$target/TestD3D.exe" && -x "$target/GPUInfo.exe" ]] || fail "winlator apps archive incomplete"
  log "diagnostic apps installed"
  return 0
}

# -------------------------------------------------------------- configs
write_runtime_configs() {
  local profile=/usr/local/etc/wow-performance-profile.env
  local dxvk_conf=/usr/local/etc/dxvk.conf
  local wine_env=/usr/local/lib/wine-runtime-env.sh
  local global_profile=/usr/local/lib/apply-wine-global-profile.sh
  local overlay=/usr/local/lib/prepare-wow-overlay.sh
  local launcher=/usr/local/bin/wow-launcher
  local runtime_env="$RUNTIME_VERSION_FILE"

  mkdir -p /usr/local/etc /usr/local/lib

  cat > "$profile" <<'EOF'
WOW_PERFORMANCE_PROFILE=msaa-off
WOW_DXVK_CONFIG_FILE=/usr/local/etc/dxvk.conf
WOW_GX_MULTISAMPLE=0
WOW_TU_DEBUG=noconform,noubwc
WOW_MESA_VK_WSI_PRESENT_MODE=mailbox
WOW_MESA_VK_WSI_USE_HWBUF=1
WOW_WINEESYNC=0
WOW_WINEFSYNC=0

# Box64 dynarec: validated-safe explicit defaults.
# The aggressive Winlator Performance preset (BIGBLOCK=3, WEAKBARRIER=2,
# FASTNAN/FASTROUND=1, NATIVEFLAGS=1) reproduces the rendering-corruption
# artifact class on this stack; do not re-enable without on-device A/B tests.
export BOX64_DYNAREC_SAFEFLAGS=1
export BOX64_DYNAREC_BIGBLOCK=1
export BOX64_DYNAREC_WEAKBARRIER=1

# On-screen diagnostics HUD (fps/drawcalls/frametimes); disable for releases
export DXVK_HUD=fps,drawcalls,frametimes
EOF

  cat > "$dxvk_conf" <<'EOF'
# System default DXVK configuration.
# Spoofs a well-known GPU so older D3D9 clients enable their full shader path.
dxgi.customDeviceId = 1c03
dxgi.customVendorId = 10de
dxgi.customDeviceDesc = "NVIDIA GeForce GTX 1060"

d3d9.customDeviceId = 1c03
d3d9.customVendorId = 10de
d3d9.customDeviceDesc = "NVIDIA GeForce GTX 1060"

# FIXES rendering artifacts on Turnip (Adreno 740): DXVK's default 8 parallel
# shader-compiler threads race on this driver and corrupt the frame.
# Serializing compilation + capping frame latency yields clean frames at full
# speed (verified: TestD3D 560 fps, zero artifacts via VNC + termux-x11).
dxvk.numCompilerThreads = 1
d3d9.maxFrameLatency = 1
EOF

  cat > "$wine_env" <<'EOF'
#!/usr/bin/env bash
# Shared, conservative runtime defaults for every Wine/Box64 application.
export WINEPREFIX="${WINEPREFIX:-/root/wine-runtime-prefix}"
export WINE_MONO_CACHE_DIR="${WINE_MONO_CACHE_DIR:-/root/runtime-cache}"
export DISPLAY="${DISPLAY:-:0}"
export PULSE_SERVER="${PULSE_SERVER:-tcp:127.0.0.1:4713}"

export GALLIUM_DRIVER="${GALLIUM_DRIVER:-zink}"
export LIBGL_ALWAYS_SOFTWARE=0
export MESA_GL_VERSION_OVERRIDE="${MESA_GL_VERSION_OVERRIDE:-4.6COMPAT}"
export MESA_GLES_VERSION_OVERRIDE="${MESA_GLES_VERSION_OVERRIDE:-3.2}"
export VK_ICD_FILENAMES="${VK_ICD_FILENAMES:-/usr/share/vulkan/icd.d/freedreno_icd.json}"
export BOX64_LD_LIBRARY_PATH="/usr/lib/box64-x86_64-linux-gnu${BOX64_LD_LIBRARY_PATH:+:$BOX64_LD_LIBRARY_PATH}"

export ZINK_DESCRIPTORS=lazy
export ZINK_DEBUG=compact

export MESA_NO_ERROR=0
export vblank_mode=1
export DXVK_CONFIG_FILE="${DXVK_CONFIG_FILE:-/usr/local/etc/dxvk.conf}"

export XCURSOR_SIZE="${XCURSOR_SIZE:-24}"
export XCURSOR_THEME="${XCURSOR_THEME:-xcursor-fix}"

: "${WINEDLLOVERRIDES:=mscoree=b,d3d9=n,d3d10core=n,d3d11=n,dxgi=n,ddraw=n,winemac.drv=d,winewayland.drv=d}"
export WINEDLLOVERRIDES
EOF

  cat > "$global_profile" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

WINEPREFIX="${WINEPREFIX:-/root/.wine}"
SYSTEM_REG="$WINEPREFIX/system.reg"
MARKER="$WINEPREFIX/.global-wine-profile-v1"

if [[ ! -f "$SYSTEM_REG" ]]; then
    echo "Wine prefix is not initialized: $WINEPREFIX" >&2
    exit 1
fi
if [[ -f "$MARKER" ]]; then
    exit 0
fi

BACKUP="$SYSTEM_REG.before-global-profile-$(date +%Y%m%d-%H%M%S)"
cp -p "$SYSTEM_REG" "$BACKUP"
TEMP="$SYSTEM_REG.global-profile.$$.tmp"
trap 'rm -f "$TEMP"' EXIT

awk '
function clear_seen(    key) {
    for (key in seen) delete seen[key]
}
function emit_missing() {
    if (!seen["CSDVersion"]) print "\"CSDVersion\"=\"\""
    if (!seen["CurrentBuild"]) print "\"CurrentBuild\"=\"22000\""
    if (!seen["CurrentBuildNumber"]) print "\"CurrentBuildNumber\"=\"22000\""
    if (!seen["CurrentMajorVersionNumber"]) print "\"CurrentMajorVersionNumber\"=dword:0000000a"
    if (!seen["CurrentMinorVersionNumber"]) print "\"CurrentMinorVersionNumber\"=dword:00000000"
    if (!seen["CurrentVersion"]) print "\"CurrentVersion\"=\"6.3\""
    if (!seen["ProductName"]) print "\"ProductName\"=\"Microsoft Windows 11\""
}
BEGIN { target = 0 }
{
    is_target = index($0, "[Software\\\\Microsoft\\\\Windows NT\\\\CurrentVersion]") == 1 || index($0, "[Software\\\\Wow6432Node\\\\Microsoft\\\\Windows NT\\\\CurrentVersion]") == 1
    if ($0 ~ /^\[/) {
        if (target) emit_missing()
        target = is_target
        if (target) clear_seen()
    }
    if (target) {
        if ($0 ~ /^"CSDVersion"=/) { print "\"CSDVersion\"=\"\""; seen["CSDVersion"] = 1; next }
        if ($0 ~ /^"CurrentBuild"=/) { print "\"CurrentBuild\"=\"22000\""; seen["CurrentBuild"] = 1; next }
        if ($0 ~ /^"CurrentBuildNumber"=/) { print "\"CurrentBuildNumber\"=\"22000\""; seen["CurrentBuildNumber"] = 1; next }
        if ($0 ~ /^"CurrentMajorVersionNumber"=/) { print "\"CurrentMajorVersionNumber\"=dword:0000000a"; seen["CurrentMajorVersionNumber"] = 1; next }
        if ($0 ~ /^"CurrentMinorVersionNumber"=/) { print "\"CurrentMinorVersionNumber\"=dword:00000000"; seen["CurrentMinorVersionNumber"] = 1; next }
        if ($0 ~ /^"CurrentVersion"=/) { print "\"CurrentVersion\"=\"6.3\""; seen["CurrentVersion"] = 1; next }
        if ($0 ~ /^"ProductName"=/) { print "\"ProductName\"=\"Microsoft Windows 11\""; seen["ProductName"] = 1; next }
    }
    print
}
END { if (target) emit_missing() }
' "$SYSTEM_REG" > "$TEMP"

if [[ ! -s "$TEMP" ]]; then
    echo "Registry rewrite produced an empty file." >&2
    exit 1
fi
mv "$TEMP" "$SYSTEM_REG"
trap - EXIT
printf 'profile=global-wine-v1\nbackup=%s\n' "$BACKUP" > "$MARKER"
EOF

  cat > "$overlay" <<'EOF'
#!/usr/bin/env bash
# Prepare the persistent writable WoW directories used by the desktop bind.
set -Eeuo pipefail

GAME_DIR="${WOW_GAME_DIR:-/data/data/com.termux/files/home/WoW 3.3.5a}"
OVERLAY_ROOT="${WOW_OVERLAY_ROOT:-/root/wow-tests/desktop-wow-overlay}"
WRITABLE_DIRS=(Cache Errors Logs Screenshots WTF)

[[ -f "$GAME_DIR/Wow.exe" ]] || {
    echo "WoW executable not found: $GAME_DIR/Wow.exe" >&2
    exit 1
}

mkdir -p "$OVERLAY_ROOT"
for dir in "${WRITABLE_DIRS[@]}"; do
    if [[ ! -d "$OVERLAY_ROOT/$dir" ]]; then
        mkdir -p "$OVERLAY_ROOT/$dir"
        if [[ -d "$GAME_DIR/$dir" ]]; then
            cp -a "$GAME_DIR/$dir/." "$OVERLAY_ROOT/$dir/"
        fi
    fi
    [[ -d "$OVERLAY_ROOT/$dir" ]] || {
        echo "Could not prepare overlay directory: $OVERLAY_ROOT/$dir" >&2
        exit 1
    }
done

if [[ ! -f "$OVERLAY_ROOT/.ready" ]]; then
    printf 'source=%s\ncreated=%s\n' "$GAME_DIR" "$(date -Is)" > "$OVERLAY_ROOT/.ready"
fi

probe="$OVERLAY_ROOT/.write-test.$$"
: > "$probe"
rm -f "$probe"
printf 'wow-overlay-ready=%s\n' "$OVERLAY_ROOT"
EOF

  cat > "$launcher" <<'EOF'
#!/usr/bin/env bash
# Launcher for x86_64 Windows games through Box64 + Wine + DXVK.
set -Eeuo pipefail

GAME_DIR="${WOW_GAME_DIR:-/data/data/com.termux/files/home/WoW 3.3.5a}"
WOW_EXE="${WOW_EXE:-$GAME_DIR/Wow.exe}"
BOX64_BIN="${BOX64_BIN:-/usr/local/bin/box64}"
WINE_BIN="${WINE_BIN:-/opt/wine-runtime/wine-11.11-amd64-wow64/bin/wine}"
PROOT_BIN="${PROOT_BIN:-/data/data/com.termux/files/usr/bin/proot}"
OVERLAY_ROOT="${WOW_OVERLAY_ROOT:-/root/wow-tests/desktop-wow-overlay}"
OVERLAY_BOUND="${WOW_OVERLAY_BOUND:-0}"
PREPARE_OVERLAY="/usr/local/lib/prepare-wow-overlay.sh"
WRITABLE_DIRS=(Cache Errors Logs Screenshots WTF)
SOURCE_MANIFEST="$OVERLAY_ROOT/source-manifest.txt"
POST_SOURCE_MANIFEST="$OVERLAY_ROOT/source-manifest.after.txt"

[[ -f "$WOW_EXE" ]] || { echo "WoW executable not found: $WOW_EXE" >&2; exit 1; }
[[ -x "$BOX64_BIN" ]] || { echo "Box64 runtime is unavailable." >&2; exit 1; }
[[ -x "$WINE_BIN" ]] || { echo "Wine runtime is unavailable: $WINE_BIN" >&2; exit 1; }

WOW_GAME_DIR="$GAME_DIR" WOW_OVERLAY_ROOT="$OVERLAY_ROOT" "$PREPARE_OVERLAY" > /dev/null

for dir in "${WRITABLE_DIRS[@]}"; do
    [[ -d "$OVERLAY_ROOT/$dir" ]] || { echo "Writable overlay directory is missing: $OVERLAY_ROOT/$dir" >&2; exit 1; }
done
write_probe="$OVERLAY_ROOT/.write-test.$$"
: > "$write_probe"
rm -f "$write_probe"

build_source_manifest() {
    find "$GAME_DIR" \
        \( -path "$GAME_DIR/Cache" -o -path "$GAME_DIR/Errors" \
        -o -path "$GAME_DIR/Logs" -o -path "$GAME_DIR/Screenshots" \
        -o -path "$GAME_DIR/WTF" \) -prune -o \
        -type f -printf '%P|%s|%T@|%m\n' | LC_ALL=C sort
}

if [[ ! -f "$SOURCE_MANIFEST" ]]; then
    build_source_manifest > "$SOURCE_MANIFEST"
fi

audit_complete=0
audit_source_integrity() {
    build_source_manifest > "$POST_SOURCE_MANIFEST"
    audit_complete=1
    if ! cmp -s "$SOURCE_MANIFEST" "$POST_SOURCE_MANIFEST"; then
        echo "ERROR: WoW modified files outside the writable overlay." >&2
        diff -u "$SOURCE_MANIFEST" "$POST_SOURCE_MANIFEST" >&2 || true
        return 1
    fi
}

WOW_WTF="$OVERLAY_ROOT/WTF"
cd "$GAME_DIR"

if [[ ! -f "$WOW_WTF/Config.wtf" ]]; then
cat > "$WOW_WTF/Config.wtf" <<'WTF'
SET locale "enUS"
SET realmList "logon.warmane.com"
SET hwDetect "0"
SET gxMultisample "0"
SET gxMultisampleQuality "0"
SET videoOptionsVersion "3"
SET movie "0"
SET Gamma "1.000000"
SET readTOS "1"
SET readEULA "1"
SET Sound_OutputDriverName "System Default"
SET Sound_MusicVolume "0.40000000596046"
SET Sound_AmbienceVolume "0.60000002384186"
SET Sound_NumChannels "32"
SET Sound_EnableHardware "0"
SET farclip "397"
SET specular "1"
SET groundEffectDensity "24"
SET projectedTextures "1"
SET realmName "Icecrown"
WTF
fi

PROFILE_FILE="${WOW_PROFILE_FILE:-/usr/local/etc/wow-performance-profile.env}"
if [[ -f "$PROFILE_FILE" ]]; then
    source "$PROFILE_FILE"
fi
WOW_PERFORMANCE_PROFILE="${WOW_PERFORMANCE_PROFILE:-baseline}"
WOW_DXVK_CONFIG_FILE="${WOW_DXVK_CONFIG_FILE:-/usr/local/etc/dxvk.conf}"
WOW_GX_MULTISAMPLE="${WOW_GX_MULTISAMPLE:-0}"
WOW_TU_DEBUG="${WOW_TU_DEBUG:-noconform,noubwc}"
WOW_MESA_VK_WSI_PRESENT_MODE="${WOW_MESA_VK_WSI_PRESENT_MODE:-mailbox}"
WOW_MESA_VK_WSI_USE_HWBUF="${WOW_MESA_VK_WSI_USE_HWBUF:-1}"
WOW_WINEESYNC="${WOW_WINEESYNC:-0}"
WOW_WINEFSYNC="${WOW_WINEFSYNC:-0}"

tmp_wtf="$WOW_WTF/Config.wtf.tmp.$$"
awk -v value="$WOW_GX_MULTISAMPLE" '
    BEGIN { replaced = 0 }
    /^SET gxMultisample / {
        if (!replaced) {
            printf "SET gxMultisample \"%s\"\n", value
            replaced = 1
        }
        next
    }
    { print }
    END {
        if (!replaced) printf "SET gxMultisample \"%s\"\n", value
    }
' "$WOW_WTF/Config.wtf" > "$tmp_wtf"
mv "$tmp_wtf" "$WOW_WTF/Config.wtf"

export WINEPREFIX="${WOW_WINEPREFIX:-/root/.wine}"
source /usr/local/lib/wine-runtime-env.sh
unset MESA_LOADER_DRIVER_OVERRIDE

if ! WINEPREFIX="$WINEPREFIX" BOX64_BIN="$BOX64_BIN" WINE_BIN="$WINE_BIN" /usr/local/lib/apply-wine-global-profile.sh; then
    echo "Global Wine profile could not be applied." >&2
    exit 1
fi

export MESA_NO_ERROR=0
export vblank_mode=0
export DXVK_CONFIG_FILE="$WOW_DXVK_CONFIG_FILE"
export TU_DEBUG="$WOW_TU_DEBUG"
export MESA_VK_WSI_PRESENT_MODE="$WOW_MESA_VK_WSI_PRESENT_MODE"
export MESA_VK_WSI_USE_HWBUF="$WOW_MESA_VK_WSI_USE_HWBUF"
export WINEESYNC="$WOW_WINEESYNC"
export WINEFSYNC="$WOW_WINEFSYNC"
export mesa_glthread=true
export MESA_SHADER_CACHE_DISABLE=false
export MESA_SHADER_CACHE_MAX_SIZE=512MB
export DXVK_STATE_CACHE_PATH=/tmp/dxvk-cache
export DXVK_STATE_CACHE=1
export MESA_EXTENSION_MAX_YEAR=2003
export force_s3tc_enable=true
export WINEDLLOVERRIDES="mscoree=b,d3d9=n,d3d10core=n,d3d11=n,dxgi=n,ddraw=n,winemac.drv=d,winewayland.drv=d"
export PULSE_SINK="AAudio_sink"
export PULSE_LATENCY_MSEC=60
export WINEDEBUG="${WINEDEBUG:--all}"

if command -v xinput > /dev/null 2>&1; then
    xinput disable "Lorie touch"  2>/dev/null || true
    xinput disable "Lorie pen"    2>/dev/null || true
    xinput disable "Lorie eraser" 2>/dev/null || true
    restore_input_devices() {
        xinput enable "Lorie touch" 2>/dev/null || true
        xinput enable "Lorie pen" 2>/dev/null || true
        xinput enable "Lorie eraser" 2>/dev/null || true
    }
    restore_input_devices_on_exit() { restore_input_devices; }
else
    restore_input_devices_on_exit() { :; }
fi

on_exit() {
    restore_input_devices_on_exit
    if [[ "$audit_complete" -eq 0 ]]; then
        audit_source_integrity || true
    fi
}
trap on_exit EXIT

if [[ "$OVERLAY_BOUND" == 1 ]]; then
    command=("$BOX64_BIN" "$WINE_BIN" "$WOW_EXE")
else
    bind_args=()
    for dir in "${WRITABLE_DIRS[@]}"; do
        bind_args+=(-b "$OVERLAY_ROOT/$dir:$GAME_DIR/$dir")
    done
    command=("$PROOT_BIN" --kill-on-exit "${bind_args[@]}" "$BOX64_BIN" "$WINE_BIN" "$WOW_EXE")
fi

set +e
if command -v ionice > /dev/null 2>&1; then
    ionice -c 2 -n 0 "${command[@]}"
    status=$?
else
    "${command[@]}"
    status=$?
fi
set -e

if ! audit_source_integrity; then
    [[ "$status" -eq 0 ]] && status=1
fi

exit "$status"
EOF

  chmod 0755 "$global_profile" "$overlay" "$launcher"

  cat > "$runtime_env" <<EOF
TLD_RUNTIME_VERSION=2
TLD_BOX64_VERSION=${TLD_BOX64_VERSION:-ba373ab4b3ae2ecbc9aeeece309817cad47ba421}
TLD_TURNIP_VERSION=${TLD_TURNIP_VERSION:-24.1.0}
TLD_DXVK_VERSION=${TLD_DXVK_VERSION:-2.6.1}
TLD_WINE_VERSION=$WINE_VERSION
TLD_WINE_TREE_NAME=$WINE_TREE_NAME
TLD_WINE_INSTALL_DIR=$WINE_INSTALL_DIR
TLD_FIREFOX=esr
EOF
  log "runtime configs written"
  return 0
}

# ------------------------------------------------------ xfce compositor
# XFCE compositing renders a black screen through Termux:X11 (verified
# 2026-08-10). Pre-configure the xfwm4 profile so a fresh session is never
# black. Runs before XFCE ever starts, so it writes the channel directly.
configure_xfce_compositor() {
  local xfce_dir="/root/.config/xfce4/xfconf/xfce-perchannel-xml"
  local xfwm_file="$xfce_dir/xfwm4.xml"

  mkdir -p "$xfce_dir"
  if [[ -f "$xfwm_file" ]]; then
    sed -i 's|<property name="use_compositing" type="bool" value="true"/>|<property name="use_compositing" type="bool" value="false"/>|' "$xfwm_file"
  fi
  if ! grep -q 'name="use_compositing"' "$xfwm_file" 2>/dev/null; then
    cat >> "$xfwm_file" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="use_compositing" type="bool" value="false"/>
  </property>
</channel>
EOF
  fi
  chown -R root:root "$xfce_dir" 2>/dev/null || true
  log "xfce compositing disabled for Termux:X11"
  return 0
}

# ------------------------------------------------------------- shortcuts
write_desktop_shortcuts() {
  local home="/root"
  local cfg="$home/.config"
  local panel="$cfg/xfce4/panel"
  local apps_dir="$home/.local/share/applications"

  mkdir -p "$cfg/xfce4" "$panel/launcher-17" "$panel/launcher-18" "$panel/launcher-19" "$panel/launcher-21" "$apps_dir"

  # XFCE helpers: makes exo-open based panel buttons resolve to real apps
  cat > "$cfg/xfce4/helpers.rc" <<'EOF'
TerminalEmulator=xfce4-terminal
TerminalEmulatorDismissed=true
FileManager=Thunar
FileManagerDismissed=true
WebBrowser=firefox
WebBrowserDismissed=true
EOF

  cat > "$panel/launcher-17/17859613901.desktop" <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Terminal Emulator
Exec=xfce4-terminal
Icon=org.xfce.terminalemulator
Terminal=false
Categories=System;TerminalEmulator;
EOF

  cat > "$panel/launcher-18/17859613902.desktop" <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=File Manager
Exec=Thunar
Icon=org.xfce.filemanager
Terminal=false
Categories=System;FileManager;
EOF

  cat > "$panel/launcher-19/17859613903.desktop" <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Web Browser
GenericName=Web Browser
Comment=Browse the World Wide Web
Exec=/usr/local/bin/firefox %u
Icon=/usr/share/pixmaps/firefox-esr.png
Terminal=false
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;
EOF

  cat > /usr/local/bin/gpuinfo <<'EOF'
#!/usr/bin/env bash
# Launch the native GPUInfo diagnostic with the managed Wine prefix.
set -Eeuo pipefail

BOX64_BIN="${BOX64_BIN:-/usr/local/bin/box64}"
WINE_BIN="${WINE_BIN:-/opt/wine-runtime/wine-11.11-amd64-wow64/bin/wine}"
GPUINFO_PREFIX="${GPUINFO_PREFIX:-/root/wine-runtime-prefix}"

[[ -x "$BOX64_BIN" ]] || { printf 'box64 not found: %s\n' "$BOX64_BIN" >&2; exit 1; }
[[ -x "$WINE_BIN" ]] || { printf 'wine not found: %s\n' "$WINE_BIN" >&2; exit 1; }
[[ -f /opt/apps/GPUInfo.exe ]] || { printf 'GPUInfo.exe is not installed\n' >&2; exit 1; }

export DISPLAY="${DISPLAY:-:0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
export WINEPREFIX="$GPUINFO_PREFIX"
export LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-0}"
export GALLIUM_DRIVER="${GALLIUM_DRIVER:-zink}"
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-mscoree=b,d3d9=b,d3d10core=b,d3d11=b,dxgi=b,ddraw=b,winemac.drv=d,winewayland.drv=d}"
export WINEESYNC=0
export WINEFSYNC=0
export WINEDEBUG="${WINEDEBUG:--all}"

if [[ ! -f "$WINEPREFIX/system.reg" ]]; then
  mkdir -p "$WINEPREFIX"
  timeout 120 "$BOX64_BIN" "$WINE_BIN" wineboot --init >/dev/null 2>&1 || true
fi
[[ -f "$WINEPREFIX/system.reg" ]] || { printf 'GPUInfo Wine prefix could not be initialized\n' >&2; exit 1; }

exec "$BOX64_BIN" "$WINE_BIN" /opt/apps/GPUInfo.exe "$@"
EOF
  chmod 0755 /usr/local/bin/gpuinfo

  cat > /usr/local/bin/winecfg <<'EOF'
#!/usr/bin/env bash
# Open Wine Configuration for the same prefix used by wine-exe.
set -Eeuo pipefail

BOX64_BIN="${BOX64_BIN:-/usr/local/bin/box64}"
WINE_BIN="${WINE_BIN:-/opt/wine-runtime/wine-11.11-amd64-wow64/bin/wine}"

[[ -x "$BOX64_BIN" ]] || { printf 'box64 not found: %s\n' "$BOX64_BIN" >&2; exit 1; }
[[ -x "$WINE_BIN" ]] || { printf 'wine not found: %s\n' "$WINE_BIN" >&2; exit 1; }
[[ -f "${WINEPREFIX:-/root/wine-runtime-prefix}/system.reg" ]] || {
  printf 'Wine prefix is not initialized: %s\n' "${WINEPREFIX:-/root/wine-runtime-prefix}" >&2
  exit 1
}

export WINEPREFIX="${WINEPREFIX:-/root/wine-runtime-prefix}"
export DISPLAY="${DISPLAY:-:0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-mscoree=b}"
export WINEDEBUG="${WINEDEBUG:--all}"
exec "$BOX64_BIN" "$WINE_BIN" winecfg "$@"
EOF
  chmod 0755 /usr/local/bin/winecfg

  cat > /usr/local/bin/winereg <<'EOF'
#!/usr/bin/env bash
# Open Wine Registry Editor for the managed Wine prefix.
set -Eeuo pipefail

BOX64_BIN="${BOX64_BIN:-/usr/local/bin/box64}"
WINE_BIN="${WINE_BIN:-/opt/wine-runtime/wine-11.11-amd64-wow64/bin/wine}"
WINEPREFIX="${WINEPREFIX:-/root/wine-runtime-prefix}"

[[ -x "$BOX64_BIN" ]] || { printf 'box64 not found: %s\n' "$BOX64_BIN" >&2; exit 1; }
[[ -x "$WINE_BIN" ]] || { printf 'wine not found: %s\n' "$WINE_BIN" >&2; exit 1; }
[[ -f "$WINEPREFIX/system.reg" ]] || { printf 'Wine prefix is not initialized: %s\n' "$WINEPREFIX" >&2; exit 1; }

export DISPLAY="${DISPLAY:-:0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
export WINEPREFIX
export WINEDEBUG="${WINEDEBUG:--all}"
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-mscoree=b}"
exec "$BOX64_BIN" "$WINE_BIN" regedit "$@"
EOF
  chmod 0755 /usr/local/bin/winereg

  cat > "$apps_dir/GPUInfo.desktop" <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=GPUInfo
GenericName=GPU Diagnostic
Comment=Inspect the active Wine OpenGL/Vulkan renderer
Exec=/usr/local/bin/gpuinfo
Icon=applications-graphics
Terminal=false
Categories=System;Graphics;Utility;
StartupNotify=true
StartupWMClass=GPUInfo.exe
NoDisplay=false
EOF
  chmod 0644 "$apps_dir/GPUInfo.desktop"
  cp "$apps_dir/GPUInfo.desktop" "$panel/launcher-21/17859613905.desktop"
  chmod 0644 "$panel/launcher-21/17859613905.desktop"

  cat > "$apps_dir/winecfg.desktop" <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Wine Configuration
GenericName=Wine Settings
Comment=Adjust Wine settings for the managed Windows prefix
Exec=/usr/local/bin/winecfg
Icon=wine
Terminal=false
Categories=Settings;System;
StartupNotify=true
NoDisplay=false
EOF
  chmod 0644 "$apps_dir/winecfg.desktop"

  cat > "$apps_dir/winereg.desktop" <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Wine Registry Editor
GenericName=Wine Registry Settings
Comment=Edit the managed Wine registry
Exec=/usr/local/bin/winereg
Icon=wine
Terminal=false
Categories=Settings;System;
StartupNotify=true
NoDisplay=false
EOF
  chmod 0644 "$apps_dir/winereg.desktop"
  update-desktop-database "$apps_dir" >/dev/null 2>&1 || true

  chown -R "$GUEST_USER:$GUEST_USER" "$cfg/xfce4/panel" "$cfg/xfce4/helpers.rc" "$apps_dir/GPUInfo.desktop" "$apps_dir/winecfg.desktop" "$apps_dir/winereg.desktop" 2>/dev/null || true
  log "desktop shortcuts, GPUInfo, Wine Configuration, and Registry Editor launchers written"
  return 0
}

# --------------------------------------------------------- wine-exe
write_wine_exe_launcher() {
  local guest_home="/root"
  local game_dir="/data/data/com.termux/files/home/WoW 3.3.5a"
  local desktop_dir="$guest_home/Desktop"
  local apps_dir="$guest_home/.local/share/applications"

  mkdir -p /usr/local/bin "$desktop_dir" "$apps_dir"

  cat > /usr/local/bin/wine-exe <<'EOF'
#!/usr/bin/env bash
# Generic per-EXE launcher: runs ANY Windows .exe through Box64 + Wine (wined3d).
# Usage: wine-exe /path/to/Game.exe [args...]
set -Eeuo pipefail

WOW_GAME_DIR="${WOW_GAME_DIR:-/data/data/com.termux/files/home/WoW 3.3.5a}"
BOX64_BIN="${BOX64_BIN:-/usr/local/bin/box64}"
WINE_BIN="${WINE_BIN:-/opt/wine-runtime/wine-11.11-amd64-wow64/bin/wine}"
WINEPREFIX_DEFAULT="${WINEPREFIX_DEFAULT:-/root/wine-runtime-prefix}"
GLADIO_HOST_BIN="${GLADIO_HOST_BIN:-/data/data/com.termux/files/home/gladio-linux/host-build/gladio-host}"
GLADIO_CLIENT_BUILD="${GLADIO_CLIENT_BUILD:-/data/data/com.termux/files/home/gladio-tunnel-build/client-build-glibc}"
GLADIO_SOCKET="${GLADIO_SOCKET:-/data/data/com.termux/files/home/gladio-tunnel-build/runtime/gladio-wine.sock}"
GLADIO_LOG="${GLADIO_LOG:-/data/data/com.termux/files/home/gladio-tunnel-build/runtime/gladio-wine-host.log}"

if [[ $# -lt 1 ]]; then
  echo "usage: wine-exe <path-to-exe> [args...]" >&2
  exit 1
fi
EXE_PATH="${1-}"
shift

if [[ "$EXE_PATH" != /* && -f "$WOW_GAME_DIR/$EXE_PATH" ]]; then
  EXE_PATH="$WOW_GAME_DIR/$EXE_PATH"
fi
[[ -f "$EXE_PATH" ]] || { echo "executable not found: $EXE_PATH" >&2; exit 1; }
[[ -x "$BOX64_BIN" ]] || { echo "box64 not found: $BOX64_BIN" >&2; exit 1; }
[[ -x "$WINE_BIN" ]] || { echo "wine not found: $WINE_BIN" >&2; exit 1; }

export WINEPREFIX="${WINEPREFIX:-$WINEPREFIX_DEFAULT}"
export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}"
export PULSE_SERVER="${PULSE_SERVER:-tcp:127.0.0.1:4713}"
export PULSE_SINK="${PULSE_SINK:-AAudio_sink}"
export PULSE_LATENCY_MSEC=60

# Fast-start overlay: WINE_GLADIO_NO_DEVICE_SERVICES=1 runs Wine from a
# disposable overlay prefix whose system.reg has the virtual device service
# and enum sections (PlugPlay, winebus, wineusb, winebth, winehid) removed.
# Those services block Wine's loader under PRoot for minutes. The production
# prefix is never modified; the overlay is rebuilt only when system.reg
# changes. Wine re-creates the service keys from the Enum entries at
# shutdown, so the overlay system.reg is re-stripped on every launch.
if [[ "${WINE_GLADIO_NO_DEVICE_SERVICES:-0}" == 1 ]]; then
  if [[ -f "$WINEPREFIX/system.reg" ]]; then
    prefix_hash="$(printf '%s' "$WINEPREFIX" | sha256sum | cut -c1-12)"
    overlay="/root/wine-faststart-$prefix_hash"
    source_hash="$(sha256sum "$WINEPREFIX/system.reg" | cut -d' ' -f1)"
    source_mtime="$(stat -c %Y "$WINEPREFIX/system.reg")"
    strip_devices() {
      awk 'tolower($0) ~ /^\[[^]]*(plugplay|winebth|winebus|winehid|wineusb)[^]]*\]/ { skip=1; next }
           skip && /^$/ { skip=0; next }
           !skip { print }' "$1" > "$1.new" && mv "$1.new" "$1"
    }
    if [[ ! -f "$overlay/system.reg" || "$(cat "$overlay/.source-hash" 2>/dev/null || true)" != "$source_hash $source_mtime" ]]; then
      rm -rf "$overlay"
      mkdir -p "$overlay"
      cp -p "$WINEPREFIX/system.reg" "$overlay/system.reg"
      strip_devices "$overlay/system.reg"
      cp -p "$WINEPREFIX/user.reg" "$overlay/user.reg" 2>/dev/null || true
      cp -p "$WINEPREFIX/userdef.reg" "$overlay/userdef.reg" 2>/dev/null || true
      cp -p "$WINEPREFIX/.update-timestamp" "$overlay/.update-timestamp" 2>/dev/null || true
      cp -p "$WINEPREFIX/wineserver" "$overlay/wineserver" 2>/dev/null || true
      for entry in "$WINEPREFIX"/*; do
        name="$(basename "$entry")"
        case "$name" in system.reg|user.reg|userdef.reg|.update-timestamp|wineserver) continue ;; esac
        ln -s "$entry" "$overlay/$name" 2>/dev/null || true
      done
      printf '%s %s' "$source_hash" "$source_mtime" > "$overlay/.source-hash"
    fi
    strip_devices "$overlay/system.reg"
    export WINEPREFIX="$overlay"
    printf 'wine-exe: device services disabled, overlay prefix=%s\n' "$overlay" >&2
  else
    printf 'wine-exe: WINE_GLADIO_NO_DEVICE_SERVICES=1 ignored (no system.reg in %s)\n' "$WINEPREFIX" >&2
  fi
fi

export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-d3d9=b,d3d10core=b,d3d11=b,dxgi=b,ddraw=b,winemac.drv=d,winewayland.drv=d}"
export WINEESYNC=0
export WINEFSYNC=0
export WINEDEBUG="${WINEDEBUG:--all}"

GLADIO_PRELOAD=""
if [[ "${WINE_GLADIO:-0}" == 1 ]]; then
  [[ -x "$GLADIO_HOST_BIN" ]] || { echo "gladio host not found: $GLADIO_HOST_BIN" >&2; exit 1; }
  [[ -f "$GLADIO_CLIENT_BUILD/libGL.so.1" ]] || { echo "gladio guest client not found: $GLADIO_CLIENT_BUILD/libGL.so.1" >&2; exit 1; }

  mkdir -p "${GLADIO_SOCKET%/*}" "${GLADIO_LOG%/*}"
  # Loader diagnostics belong to the Wine child, not the Android host daemon.
  unset LD_DEBUG LD_DEBUG_OUTPUT LD_PRELOAD BOX64_LD_PRELOAD
  if [[ ! -S "$GLADIO_SOCKET" ]] || ! pgrep -x gladio-host >/dev/null 2>&1; then
    if [[ -S "$GLADIO_SOCKET" ]] && pgrep -x gladio-host >/dev/null 2>&1; then
      echo "gladio host is running without the expected socket: $GLADIO_SOCKET" >&2
      exit 1
    fi
    rm -f "$GLADIO_SOCKET"
    nohup env DISPLAY="$DISPLAY" GLADIO_SWAP_INTERVAL="${GLADIO_SWAP_INTERVAL:-0}" \
      GALLIUM_DRIVER="${GLADIO_GALLIUM_DRIVER:-zink}" \
      "$GLADIO_HOST_BIN" "$GLADIO_SOCKET" > "$GLADIO_LOG" 2>&1 < /dev/null &
    gladio_host_pid="$!"
    for _ in $(seq 1 30); do
      [[ -S "$GLADIO_SOCKET" ]] && break
      kill -0 "$gladio_host_pid" 2>/dev/null || break
      sleep 0.5
    done
  fi
  [[ -S "$GLADIO_SOCKET" ]] || { echo "gladio host did not create socket: $GLADIO_SOCKET" >&2; cat "$GLADIO_LOG" >&2 || true; exit 1; }

  unset LIBGL_ALWAYS_SOFTWARE GALLIUM_DRIVER MESA_LOADER_DRIVER_OVERRIDE
  export GLADIO_X11_SERVER_PATH="$GLADIO_SOCKET"
  export LD_LIBRARY_PATH="$GLADIO_CLIENT_BUILD${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  GLADIO_PRELOAD="${GLADIO_WINE_PRELOAD:-$GLADIO_CLIENT_BUILD/libGL.so.1}"
  printf 'wine-exe: renderer=gladio exe=%s socket=%s\n' "$EXE_PATH" "$GLADIO_SOCKET" >&2
else
  # wined3d fallback: software GL (llvmpipe) so no DRI3 is needed.
  export LIBGL_ALWAYS_SOFTWARE=1
  export GALLIUM_DRIVER=llvmpipe
fi

# Single-instance guard: never start a second copy of the same exe, or two
# WoW instances share one prefix and produce a black fullscreen window.
# Match ONLY the actual wine binary running the exe (not this launcher's
# own cmdline, which would self-match and block every launch).
EXE_BASE="$(basename "$EXE_PATH")"
if pgrep -f "wine-11\.11-amd64-wow64/bin/wine .*${EXE_BASE}" > /dev/null 2>&1; then
  echo "wine-exe: $EXE_BASE already running; not starting a duplicate" >&2
  exit 0
fi

cd "$(dirname "$EXE_PATH")"
wine_env=()
if [[ -n "$GLADIO_PRELOAD" ]]; then
  wine_env+=("BOX64_LIBGL=$GLADIO_PRELOAD" "BOX64_LD_PRELOAD=$GLADIO_PRELOAD")
fi
exec ionice -c 2 -n 0 env "${wine_env[@]}" "$BOX64_BIN" "$WINE_BIN" "$EXE_PATH" "$@"
EOF
  chmod 0755 /usr/local/bin/wine-exe

  cat > "$apps_dir/wine-exe.desktop" <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Wine (wined3d)
GenericName=Windows executable
Comment=Run a Windows .exe through Box64 + Wine (wined3d)
Exec=/usr/local/bin/wine-exe %f
Icon=applications-games
Terminal=false
Categories=Utility;Game;
MimeType=application/x-ms-dos-executable;application/x-msdownload;application/exe;application/x-msi;
NoDisplay=false
EOF
  chmod 0644 "$apps_dir/wine-exe.desktop"

  if [[ -f "$guest_home/.config/mimeapps.list" ]]; then
    sed -i '/^application\/x-ms-dos-executable=/d;/^application\/x-msdownload=/d' "$guest_home/.config/mimeapps.list"
  fi
  cat >> "$guest_home/.config/mimeapps.list" <<'EOF'
[Default Applications]
application/x-ms-dos-executable=wine-exe.desktop
application/x-msdownload=wine-exe.desktop
application/exe=wine-exe.desktop
application/x-msi=wine-exe.desktop
EOF

  write_shortcut() {
    local name="$1" exe="$2" comment="$3"
    cat > "$desktop_dir/$name.desktop" <<EOFS
[Desktop Entry]
Version=1.0
Type=Application
Name=$name
Comment=$comment
Exec=/usr/local/bin/wine-exe "$game_dir/$exe"
Icon=applications-games
Terminal=false
Categories=Game;Utility;
StartupNotify=true
EOFS
    chmod 0755 "$desktop_dir/$name.desktop"
    cp "$desktop_dir/$name.desktop" "$apps_dir/$name.desktop"
  }

  write_shortcut "World of Warcraft" "Wow.exe" "Launch WoW through Wine (wined3d)"
  write_shortcut "WoW Repair" "Repair.exe" "WoW repair utility (wined3d)"
  write_shortcut "WoW Error" "WowError.exe" "WoW error reporter (wined3d)"
  cat > "$desktop_dir/WoW Gladio Fast Start.desktop" <<EOFS
[Desktop Entry]
Version=1.0
Type=Application
Name=WoW (Gladio Fast Start)
GenericName=World of Warcraft
Comment=Launch WoW with the Gladio renderer, GPU (zink) and fast-start overlay
Exec=env WINE_GLADIO=1 WINE_GLADIO_NO_DEVICE_SERVICES=1 GALLIUM_DRIVER=zink /usr/local/bin/wine-exe "$game_dir/Wow.exe"
Icon=applications-games
Terminal=false
Categories=Game;Utility;
StartupNotify=false
EOFS
  chmod 0755 "$desktop_dir/WoW Gladio Fast Start.desktop"
  cp "$desktop_dir/WoW Gladio Fast Start.desktop" "$apps_dir/WoW Gladio Fast Start.desktop"

  chown -R "$GUEST_USER:$GUEST_USER" "$desktop_dir" "$apps_dir" "$guest_home/.config/mimeapps.list" 2>/dev/null || true
  log "wine-exe launcher, .exe association, and WoW shortcuts written"
  return 0
}

# -------------------------------------------------------- Debian packages
write_deb_package_handler() {
  local guest_home="/root"
  local apps_dir="$guest_home/.local/share/applications"
  local mime_file="$guest_home/.config/mimeapps.list"

  mkdir -p /usr/local/bin "$apps_dir" "${mime_file%/*}"

  cat > /usr/local/bin/deb-install <<'EOF'
#!/usr/bin/env bash
# Install one Debian package through apt with an explicit terminal confirmation.
set -Eeuo pipefail

if (( $# != 1 )); then
  printf 'usage: deb-install /path/to/package.deb\n' >&2
  exit 2
fi

DEB_PATH="$1"
[[ -f "$DEB_PATH" ]] || {
  printf 'package file not found: %s\n' "$DEB_PATH" >&2
  exit 1
}
dpkg-deb --info "$DEB_PATH" >/dev/null 2>&1 || {
  printf 'not a valid Debian package: %s\n' "$DEB_PATH" >&2
  exit 1
}
[[ -t 0 && -t 1 ]] || {
  printf 'open the package from the desktop, or run this command in a terminal\n' >&2
  exit 1
}

DEB_PATH="$(readlink -f -- "$DEB_PATH")"
printf 'Package: %s\n' "$(dpkg-deb --field "$DEB_PATH" Package)"
printf 'Version: %s\n' "$(dpkg-deb --field "$DEB_PATH" Version)"
printf 'This runs the package maintainer scripts as root inside the guest.\n'
printf 'Install this package and resolve dependencies? [y/N] '
read -r answer
case "${answer,,}" in
  y|yes) ;;
  *) printf 'Installation cancelled.\n'; exit 0 ;;
esac

cd "$(dirname -- "$DEB_PATH")"
exec apt-get install -y "./$(basename -- "$DEB_PATH")"
EOF
  chmod 0755 /usr/local/bin/deb-install

  cat > "$apps_dir/deb-install.desktop" <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Install Debian Package
GenericName=Package Installer
Comment=Install a Debian package with apt
Exec=/usr/local/bin/deb-install %f
Icon=system-software-install
Terminal=true
Categories=System;PackageManager;
MimeType=application/vnd.debian.binary-package;application/x-deb;
NoDisplay=false
EOF
  chmod 0644 "$apps_dir/deb-install.desktop"

  if [[ -f "$mime_file" ]]; then
    sed -i '/^application\/vnd\.debian\.binary-package=/d;/^application\/x-deb=/d' "$mime_file"
  fi
  cat >> "$mime_file" <<'EOF'

[Default Applications]
application/vnd.debian.binary-package=deb-install.desktop
application/x-deb=deb-install.desktop
EOF

  update-desktop-database "$apps_dir" >/dev/null 2>&1 || true
  chown -R "$GUEST_USER:$GUEST_USER" "$apps_dir" "$mime_file" 2>/dev/null || true
  log "Debian package installer and .deb MIME associations written"
  return 0
}

# ------------------------------------------------------------------ vncpass
setup_vnc_password() {
  if [[ ! -f "/root/.vncpasswd" ]]; then
    mkdir -p "/root"
    x11vnc -storepasswd termux "/root/.vncpasswd" >/dev/null 2>&1 || true
    chown "$GUEST_USER:$GUEST_USER" "/root/.vncpasswd" 2>/dev/null || true
  fi
  return 0
}

# ------------------------------------------------------------------- main
main() {
  local component skip_var
  for component in packages box64 turnip wine wine_components runtime_libs dxvk firefox diag configs locale wine_registry wine_exe deb_handler shortcuts vncpass compositor; do
    skip_var="TLD_SKIP_$component"
    if [[ -n "${!skip_var:-}" ]]; then
      log "skipping $component"
      continue
    fi
    case "$component" in
      packages) install_packages ;;
      box64)    install_box64 ;;
      turnip)   install_turnip ;;
      wine)     install_wine ;;
      wine_components)
        if [[ -n "${TLD_SKIP_wine:-}" ]]; then
          log "skipping wine_components"
        else
          install_wine_components
        fi
        ;;
      runtime_libs) configure_runtime_libs ;;
      dxvk)     install_dxvk ;;
      firefox)  install_firefox ;;
      diag)     install_diag_apps ;;
      configs)  write_runtime_configs ;;
      locale)   configure_locale ;;
      wine_registry) configure_wine_registry ;;
      wine_exe) write_wine_exe_launcher ;;
      deb_handler) write_deb_package_handler ;;
      shortcuts) write_desktop_shortcuts ;;
      vncpass)  setup_vnc_password ;;
      compositor) configure_xfce_compositor ;;
    esac || fail "$component"
  done
  log "runtime provisioning complete"
  return 0
}

main
