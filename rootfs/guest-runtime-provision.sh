#!/usr/bin/env bash
# Guest-side wine/GPU runtime provisioning for termux-linux-desktop.
# Runs INSIDE the tld-ubuntu container as root via:
#   proot-distro login <container> --bind <cache>:<guest-cache> -- bash -lc "$(cat this file)"
# Idempotent. Each component is installed from the shared runtime cache.
set -Eeuo pipefail

RUNTIME_CACHE="${TLD_RUNTIME_CACHE:-/root/runtime-cache}"
GUEST_USER="${TLD_GUEST_USER:-tld}"
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
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates curl file tar xz-utils gcc g++ make cmake git \
    libpulse0 libasound2t64 libdbus-glib-1-2 libxt6 \
    xdg-utils x11vnc scrot >/dev/null 2>&1 || fail "apt-get install"
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

# -------------------------------------------------------------------- dxvk
install_dxvk() {
  local version="${TLD_DXVK_VERSION:-2.6.1}"
  local archive="$RUNTIME_CACHE/dxvk-$version.tar.gz"
  local wine_windows="$WINE_INSTALL_DIR/$WINE_TREE_NAME/lib/wine/x86_64-windows"
  local extract_dir="/tmp/dxvk-extract"

  [[ -d "$wine_windows" ]] || fail "wine tree missing x86_64-windows: $wine_windows"
  if has_file "$wine_windows/d3d9.dll" && [[ ! -f "$wine_windows/d3d9.dll.toolkit-backup" ]]; then
    cp -p "$wine_windows/d3d9.dll" "$wine_windows/d3d9.dll.toolkit-backup"
    cp -p "$wine_windows/dxgi.dll" "$wine_windows/dxgi.dll.toolkit-backup"
    cp -p "$wine_windows/d3d11.dll" "$wine_windows/d3d11.dll.toolkit-backup"
  fi
  has_file "$archive" || fail "dxvk archive missing from cache: $archive"
  rm -rf "$extract_dir"
  mkdir -p "$extract_dir"
  tar xzf "$archive" -C "$extract_dir" || fail "dxvk extract"
  local dll_dir="$extract_dir/dxvk-$version/x64"
  [[ -d "$dll_dir" ]] || dll_dir="$extract_dir/x64"
  [[ -d "$dll_dir" ]] || fail "dxvk archive has no x64 dll directory"
  install -m 0644 "$dll_dir/d3d9.dll" "$dll_dir/dxgi.dll" "$dll_dir/d3d11.dll" "$wine_windows/" || fail "dxvk install"
  log "dxvk $version installed"
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
WOW_TU_DEBUG=sysmem,noconform
WOW_MESA_VK_WSI_PRESENT_MODE=mailbox
WOW_MESA_VK_WSI_USE_HWBUF=1
WOW_WINEESYNC=0
WOW_WINEFSYNC=0
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
EOF

  cat > "$wine_env" <<'EOF'
#!/usr/bin/env bash
# Shared, conservative runtime defaults for every Wine/Box64 application.
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

: "${WINEDLLOVERRIDES:=d3d9=n,d3d10core=n,d3d11=n,dxgi=n,ddraw=n,winemac.drv=d,winewayland.drv=d}"
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
WOW_TU_DEBUG="${WOW_TU_DEBUG:-sysmem,noconform}"
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
unset MESA_LOADER_DRIVER_OVERRIDE DXVK_HUD

if ! WINEPREFIX="$WINEPREFIX" BOX64_BIN="$BOX64_BIN" WINE_BIN="$WINE_BIN" /usr/local/lib/apply-wine-global-profile.sh; then
    echo "Global Wine profile could not be applied." >&2
    exit 1
fi

export BOX64_DYNAREC=1
export BOX64_DYNAREC_BIGBLOCK=1
export BOX64_DYNAREC_SAFEFLAGS=1
export BOX64_DYNAREC_WEAKBARRIER=1
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
export WINEDLLOVERRIDES="d3d9=n,d3d10core=n,d3d11=n,dxgi=n,ddraw=n,winemac.drv=d,winewayland.drv=d"
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

# ------------------------------------------------------------------ vncpass
setup_vnc_password() {
  if [[ ! -f "/home/$GUEST_USER/.vncpasswd" ]]; then
    mkdir -p "/home/$GUEST_USER"
    x11vnc -storepasswd termux "/home/$GUEST_USER/.vncpasswd" >/dev/null 2>&1 || true
    chown "$GUEST_USER:$GUEST_USER" "/home/$GUEST_USER/.vncpasswd" 2>/dev/null || true
  fi
  return 0
}

# ------------------------------------------------------------------- main
main() {
  local component
  for component in packages box64 turnip wine dxvk firefox diag configs vncpass; do
    if [[ -n "${TLD_SKIP_$component:-}" ]]; then
      log "skipping $component"
      continue
    fi
    case "$component" in
      packages) install_packages ;;
      box64)    install_box64 ;;
      turnip)   install_turnip ;;
      wine)     install_wine ;;
      dxvk)     install_dxvk ;;
      firefox)  install_firefox ;;
      diag)     install_diag_apps ;;
      configs)  write_runtime_configs ;;
      vncpass)  setup_vnc_password ;;
    esac || fail "$component"
  done
  log "runtime provisioning complete"
  return 0
}

main
