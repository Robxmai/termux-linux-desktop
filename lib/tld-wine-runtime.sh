#!/usr/bin/env bash

if ! declare -F tld_init_managed_paths >/dev/null 2>&1 || ! declare -F tld_log >/dev/null 2>&1; then
  source "${BASH_SOURCE[0]%/*}/tld-common.sh"
fi

_tld_wr_error() {
  printf 'wine-runtime: %s\n' "$*" >&2
  return 1
}

_tld_wr_test_mode() {
  [[ "${TLD_TEST_MODE:-0}" == 1 ]]
}

_tld_wr_cache_dir() {
  local cache_dir
  if _tld_wr_test_mode && [[ -n ${TLD_RUNTIME_CACHE_DIR:-} ]]; then
    printf '%s\n' "$TLD_RUNTIME_CACHE_DIR"
    return 0
  fi
  if ! tld_init_managed_paths; then
    return 1
  fi
  cache_dir="$TLD_STATE_DIR/runtime-cache"
  mkdir -p -- "$cache_dir" || return 1
  printf '%s\n' "$cache_dir"
}

_tld_wr_require_env_file() {
  if [[ ! ${TLD_ROOTFS_ENV_FILE+x} ]]; then
    TLD_ROOTFS_ENV_FILE="${BASH_SOURCE[0]%/*}/../rootfs/ubuntu-24.04.env"
  fi
  [[ -f "$TLD_ROOTFS_ENV_FILE" ]] || {
    _tld_wr_error "rootfs environment file not found: $TLD_ROOTFS_ENV_FILE"
    return 1
  }
}

tld_wine_runtime_versions() {
  printf 'box64=%s turnip=%s dxvk=%s wine=%s wine_mono=%s wine_gecko=%s firefox=%s\n' \
    "${TLD_BOX64_VERSION:-ba373ab4b3ae2ecbc9aeeece309817cad47ba421}" \
    "${TLD_TURNIP_VERSION:-24.1.0}" \
    "${TLD_DXVK_VERSION:-2.6.1}" \
    "${TLD_WINE_VERSION:-11.11}" \
    "${TLD_WINE_MONO_VERSION:-11.1.0}" \
    "${TLD_WINE_GECKO_VERSION:-2.47.4}" \
    "${TLD_FIREFOX:-esr}"
}

# ------------------------------------------------------------- downloads
_tld_wr_download() {
  local url="$1"
  local destination="$2"
  local label="${3:-component}"

  if [[ -s "$destination" ]]; then
    tld_log "runtime cache hit: $label"
    return 0
  fi
  if _tld_wr_test_mode; then
    _tld_wr_error "download attempted in test mode: $url"
    return 1
  fi
  tld_require_command curl || return 1
  tld_log "downloading $label from $url"
  if ! curl -L --fail --silent --show-error -o "$destination.tmp" "$url"; then
    rm -f -- "$destination.tmp"
    _tld_wr_error "download failed for $label: $url"
    return 1
  fi
  mv -f -- "$destination.tmp" "$destination" || return 1
  [[ -s "$destination" ]] || {
    _tld_wr_error "downloaded file is empty for $label"
    return 1
  }
  return 0
}

_tld_wr_firefox_version() {
  local version
  if _tld_wr_test_mode; then
    printf '%s\n' "${TLD_FIREFOX_ESR_VERSION:-140.13.0esr}"
    return 0
  fi
  version=$(curl -L --fail --silent 'https://product-details.mozilla.org/1.0/firefox_versions.json') || return 1
  version=${version#*\"FIREFOX_ESR\": \"}
  version=${version%%\"*}
  [[ "$version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?(esr)?$ ]] || return 1
  printf '%s\n' "$version"
}

tld_wine_runtime_fetch() {
  local cache_dir
  local box64_url turnip_url dxvk_url ff_version ff_url
  local mono_version gecko_version
  local patches_archive patches_dir apps_tar
  local wine_source="${TLD_WINE_RUNTIME_TARBALL:-}"

  cache_dir=$(_tld_wr_cache_dir) || return 1
  _tld_wr_require_env_file || return 1

  [[ -z ${TLD_SKIP_BOX64:-} ]] && {
    _tld_wr_download \
      "https://github.com/ptitSeb/box64/archive/refs/tags/${TLD_BOX64_VERSION:-ba373ab4b3ae2ecbc9aeeece309817cad47ba421}.tar.gz" \
      "$cache_dir/box64-${TLD_BOX64_VERSION:-ba373ab4b3ae2ecbc9aeeece309817cad47ba421}.tar.gz" 'box64 source' || return 1
  }

  [[ -z ${TLD_SKIP_TURNIP:-} ]] && {
    _tld_wr_download \
      "https://raw.githubusercontent.com/brunodev85/winlator/main/installable_components/turnip/turnip-${TLD_TURNIP_VERSION:-24.1.0}.tzst" \
      "$cache_dir/turnip-${TLD_TURNIP_VERSION:-24.1.0}.tzst" 'turnip driver' || return 1
  }

  [[ -z ${TLD_SKIP_DXVK:-} ]] && {
    _tld_wr_download \
      "https://github.com/doitsujin/dxvk/releases/download/v${TLD_DXVK_VERSION:-2.6.1}/dxvk-${TLD_DXVK_VERSION:-2.6.1}.tar.gz" \
      "$cache_dir/dxvk-${TLD_DXVK_VERSION:-2.6.1}.tar.gz" 'dxvk' || return 1
  }

  [[ -z ${TLD_SKIP_FIREFOX:-} ]] && {
    if ff_version=$(_tld_wr_firefox_version); then
      ff_url="https://ftp.mozilla.org/pub/firefox/releases/${ff_version}/linux-aarch64/en-US/firefox-${ff_version}.tar.xz"
      _tld_wr_download "$ff_url" "$cache_dir/firefox-esr.tar.xz" 'firefox esr' || return 1
    else
      tld_log 'warning: could not resolve Firefox ESR version; skipping firefox'
    fi
  }

  [[ -z ${TLD_SKIP_DIAG:-} ]] && {
    if [[ ! -s "$cache_dir/winlator-apps.tar.gz" ]]; then
      _tld_wr_download \
        'https://raw.githubusercontent.com/brunodev85/winlator-app/main/app/src/main/assets/rootfs_patches.tzst' \
        "$cache_dir/winlator-rootfs-patches.tzst" 'winlator diagnostics' || return 1
      patches_dir="$cache_dir/.patches-extract"
      rm -rf -- "$patches_dir"
      mkdir -p -- "$patches_dir" "$cache_dir/.apps"
      tar --zstd -xf "$cache_dir/winlator-rootfs-patches.tzst" -C "$patches_dir" \
        './opt/apps/TestD3D.exe' './opt/apps/GPUInfo.exe' 2>/dev/null || true
      if [[ -f "$patches_dir/opt/apps/TestD3D.exe" && -f "$patches_dir/opt/apps/GPUInfo.exe" ]]; then
        install -m 0755 "$patches_dir/opt/apps/TestD3D.exe" "$cache_dir/.apps/TestD3D.exe"
        install -m 0755 "$patches_dir/opt/apps/GPUInfo.exe" "$cache_dir/.apps/GPUInfo.exe"
        (cd "$cache_dir/.apps" && tar czf "$cache_dir/winlator-apps.tar.gz" TestD3D.exe GPUInfo.exe) || return 1
      fi
      rm -rf -- "$patches_dir" "$cache_dir/.apps"
    fi
  }

  if [[ -z ${TLD_SKIP_WINE:-} && -n "$wine_source" ]]; then
    if [[ "$wine_source" == http* ]]; then
      _tld_wr_download "$wine_source" "$cache_dir/${TLD_WINE_TREE_NAME:-wine-11.11-amd64-wow64}.tar.gz" 'wine runtime' || return 1
    elif [[ -f "$wine_source" ]]; then
      if [[ ! -s "$cache_dir/${TLD_WINE_TREE_NAME:-wine-11.11-amd64-wow64}.tar.gz" ]]; then
        install -m 0644 "$wine_source" "$cache_dir/${TLD_WINE_TREE_NAME:-wine-11.11-amd64-wow64}.tar.gz"
      fi
    else
      _tld_wr_error "wine runtime source not found: $wine_source"
      return 1
    fi
  fi

  if [[ -z ${TLD_SKIP_WINE:-} ]]; then
    mono_version="${TLD_WINE_MONO_VERSION:-11.1.0}"
    gecko_version="${TLD_WINE_GECKO_VERSION:-2.47.4}"
    _tld_wr_download \
      "https://dl.winehq.org/wine/wine-mono/$mono_version/wine-mono-$mono_version-x86.msi" \
      "$cache_dir/wine-mono-$mono_version-x86.msi" 'wine mono' || return 1
    _tld_wr_download \
      "https://dl.winehq.org/wine/wine-gecko/$gecko_version/wine-gecko-$gecko_version-x86.msi" \
      "$cache_dir/wine-gecko-$gecko_version-x86.msi" 'wine gecko x86' || return 1
    _tld_wr_download \
      "https://dl.winehq.org/wine/wine-gecko/$gecko_version/wine-gecko-$gecko_version-x86_64.msi" \
      "$cache_dir/wine-gecko-$gecko_version-x86_64.msi" 'wine gecko x86_64' || return 1
  fi
  tld_log "runtime components cached at $cache_dir"
  return 0
}

# ------------------------------------------------------------- provision
tld_wine_runtime_install() {
  local cache_dir guest_cache provision_script env_prefix
  local command

  if [[ -z ${TLD_ROOTFS_CONTAINER:-} ]]; then
    _tld_wr_require_env_file || return 1
    # shellcheck disable=SC1090
    source "$TLD_ROOTFS_ENV_FILE"
  fi
  cache_dir=$(_tld_wr_cache_dir) || return 1
  guest_cache="${TLD_GUEST_RUNTIME_CACHE:-/root/runtime-cache}"

  provision_script="${TLD_GUEST_PROVISION_SCRIPT:-${BASH_SOURCE[0]%/*}/../rootfs/guest-runtime-provision.sh}"
  [[ -f "$provision_script" ]] || {
    _tld_wr_error "guest provisioning script not found: $provision_script"
    return 1
  }

  env_prefix="TLD_RUNTIME_CACHE=$guest_cache"
  env_prefix+=" TLD_GUEST_USER=${TLD_GUEST_USER:-root}"
  env_prefix+=" TLD_WINE_VERSION=${TLD_WINE_VERSION:-11.11}"
  env_prefix+=" TLD_WINE_TREE_NAME=${TLD_WINE_TREE_NAME:-wine-11.11-amd64-wow64}"
  env_prefix+=" TLD_WINE_MONO_VERSION=${TLD_WINE_MONO_VERSION:-11.1.0}"
  env_prefix+=" TLD_WINE_GECKO_VERSION=${TLD_WINE_GECKO_VERSION:-2.47.4}"
  env_prefix+=" TLD_WINE_PREFIX=${TLD_WINE_PREFIX:-/root/wine-runtime-prefix}"
  env_prefix+=" TLD_WINE_INSTALL_DIR=${TLD_WINE_INSTALL_DIR:-/opt/wine-runtime}"
  env_prefix+=" TLD_BOX64_VERSION=${TLD_BOX64_VERSION:-ba373ab4b3ae2ecbc9aeeece309817cad47ba421}"
  env_prefix+=" TLD_TURNIP_VERSION=${TLD_TURNIP_VERSION:-24.1.0}"
  env_prefix+=" TLD_DXVK_VERSION=${TLD_DXVK_VERSION:-2.6.1}"

  if _tld_wr_test_mode; then
    command="proot-distro login ${TLD_ROOTFS_CONTAINER:-tld-ubuntu} --bind $cache_dir:$guest_cache -- env $env_prefix /bin/bash -lc <$(printf '%q' "$provision_script")"
    tld_log "$command"
    tld_require_command proot-distro || return 1
    return 0
  fi

  if ! proot-distro login "${TLD_ROOTFS_CONTAINER:-tld-ubuntu}" \
    --bind "$cache_dir:$guest_cache" \
    -- env $env_prefix /bin/bash -lc "$(cat "$provision_script")"; then
    _tld_wr_error 'guest runtime provisioning failed'
    return 1
  fi
  tld_log 'guest runtime provisioning complete'
  return 0
}

# --------------------------------------------------------------- verify
tld_wine_runtime_verify() {
  local checks
  if [[ -z ${TLD_ROOTFS_CONTAINER:-} ]]; then
    _tld_wr_require_env_file || return 1
    # shellcheck disable=SC1090
    source "$TLD_ROOTFS_ENV_FILE"
  fi
  checks=$'set -Eeuo pipefail\n'
  checks+=$'echo "box64=$(/usr/local/bin/box64 -v 2>&1 | head -1)"\n'
  checks+=$'echo "turnip=$(strings /usr/lib/aarch64-linux-gnu/libvulkan_freedreno.so 2>/dev/null | grep -m1 \"Mesa [0-9]\")"\n'
  checks+=$'echo "wine=$(/usr/local/bin/box64 /opt/wine-runtime/wine-11.11-amd64-wow64/bin/wine --version 2>/dev/null | head -1)"\n'
  checks+=$'echo "wine_mono=$(test -d /root/wine-runtime-prefix/drive_c/windows/mono/mono-2.0 && echo present || echo missing)"\n'
  checks+=$'echo "wine_gecko_x86=$(test -f /root/wine-runtime-prefix/drive_c/windows/syswow64/gecko/2.47.4/wine_gecko/VERSION && echo present || echo missing)"\n'
  checks+=$'echo "wine_gecko_x86_64=$(test -f /root/wine-runtime-prefix/drive_c/windows/system32/gecko/2.47.4/wine_gecko/VERSION && echo present || echo missing)"\n'
  checks+=$'echo "dxvk9=$(test -f /opt/wine-runtime/wine-11.11-amd64-wow64/lib/wine/x86_64-windows/d3d9.dll && echo present || echo missing)"\n'
  checks+=$'echo "firefox=$(/usr/local/bin/firefox --version 2>/dev/null | head -1)"\n'
  checks+=$'echo "vulkan=$(vulkaninfo --summary 2>/dev/null | grep -m1 deviceName || echo unavailable)"\n'
  checks+=$'echo "profile=$(test -f /usr/local/etc/wow-performance-profile.env && echo present || echo missing)"\n'
  if _tld_wr_test_mode; then
    tld_log "verify: $checks"
    return 0
  fi
  proot-distro login "${TLD_ROOTFS_CONTAINER:-tld-ubuntu}" -- /bin/bash -lc "$checks"
}

tld_wine_runtime_status() {
  local cache_dir
  if cache_dir=$(_tld_wr_cache_dir); then
    printf 'runtime cache: %s\n' "$cache_dir"
    printf 'box64 source: %s\n' "$( [[ -s "$cache_dir/box64-${TLD_BOX64_VERSION:-ba373ab4b3ae2ecbc9aeeece309817cad47ba421}.tar.gz" ]] && echo cached || echo missing)"
    printf 'turnip: %s\n' "$( [[ -s "$cache_dir/turnip-${TLD_TURNIP_VERSION:-24.1.0}.tzst" ]] && echo cached || echo missing)"
    printf 'dxvk: %s\n' "$( [[ -s "$cache_dir/dxvk-${TLD_DXVK_VERSION:-2.6.1}.tar.gz" ]] && echo cached || echo missing)"
    printf 'firefox: %s\n' "$( [[ -s "$cache_dir/firefox-esr.tar.xz" ]] && echo cached || echo missing)"
    printf 'wine runtime: %s\n' "$( [[ -s "$cache_dir/${TLD_WINE_TREE_NAME:-wine-11.11-amd64-wow64}.tar.gz" ]] && echo cached || echo missing)"
    printf 'wine mono: %s\n' "$( [[ -s "$cache_dir/wine-mono-${TLD_WINE_MONO_VERSION:-11.1.0}-x86.msi" ]] && echo cached || echo missing)"
    printf 'wine gecko: %s\n' "$( [[ -s "$cache_dir/wine-gecko-${TLD_WINE_GECKO_VERSION:-2.47.4}-x86.msi" && -s "$cache_dir/wine-gecko-${TLD_WINE_GECKO_VERSION:-2.47.4}-x86_64.msi" ]] && echo cached || echo missing)"
    printf 'diagnostics: %s\n' "$( [[ -s "$cache_dir/winlator-apps.tar.gz" ]] && echo cached || echo missing)"
  fi
  return 0
}
