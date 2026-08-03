#!/usr/bin/env bash

if ! declare -F tld_init_paths >/dev/null 2>&1 || ! declare -F tld_read_env_file >/dev/null 2>&1; then
  source "${BASH_SOURCE[0]%/*}/tld-common.sh"
fi

_tld_guest_lib_dir=${BASH_SOURCE[0]%/*}
if [[ "$_tld_guest_lib_dir" == "${BASH_SOURCE[0]}" ]]; then
  _tld_guest_lib_dir=.
fi
if [[ ! ${TLD_ROOTFS_ENV_FILE+x} ]]; then
  TLD_ROOTFS_ENV_FILE="$_tld_guest_lib_dir/../rootfs/ubuntu-24.04.env"
fi

_tld_guest_error() {
  printf 'guest: %s\n' "$*" >&2
  return 1
}

_tld_guest_prepare_paths() {
  if [[ -z ${PREFIX:-} || -z ${HOME:-} ]]; then
    _tld_guest_error 'PREFIX and HOME must be set before using guest functions'
    return 1
  fi
  tld_init_paths
}

_tld_guest_load_rootfs_env() {
  local env_file="${TLD_ROOTFS_ENV_FILE:-}"
  local line key
  local assignment_count=0
  local -A seen=()

  if [[ -z "$env_file" || ! -f "$env_file" || ! -r "$env_file" ]]; then
    _tld_guest_error "cannot read rootfs environment file: $env_file"
    return 1
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^(TLD_ROOTFS_IMAGE|TLD_ROOTFS_CONTAINER|TLD_ROOTFS_ARCH|TLD_ROOTFS_MIN_PROOT_DISTRO|TLD_GUEST_USER)= ]]; then
      key=${BASH_REMATCH[1]}
      if [[ ${seen[$key]+x} ]]; then
        _tld_guest_error "duplicate rootfs environment assignment: $key"
        return 1
      fi
      seen["$key"]=1
      (( assignment_count += 1 ))
    else
      _tld_guest_error "invalid rootfs environment assignment in: $env_file"
      return 1
    fi
  done < "$env_file"

  if (( assignment_count != 5 )); then
    _tld_guest_error "rootfs environment must contain exactly five assignments: $env_file"
    return 1
  fi

  unset TLD_ROOTFS_IMAGE TLD_ROOTFS_CONTAINER TLD_ROOTFS_ARCH TLD_ROOTFS_MIN_PROOT_DISTRO TLD_GUEST_USER
  if ! tld_read_env_file "$env_file"; then
    return 1
  fi

  if [[ "${TLD_ROOTFS_IMAGE-}" != 'ubuntu:24.04' ||
    "${TLD_ROOTFS_CONTAINER-}" != 'tld-ubuntu' ||
    "${TLD_ROOTFS_ARCH-}" != 'aarch64' ||
    "${TLD_ROOTFS_MIN_PROOT_DISTRO-}" != '5.5.0' ||
    "${TLD_GUEST_USER-}" != 'tld' ]]; then
    _tld_guest_error "rootfs environment is not the pinned Ubuntu 24.04 configuration: $env_file"
    return 1
  fi
}

_tld_guest_rootfs_dir() {
  printf '%s\n' "${TLD_ROOTFS_DIR:-$PREFIX/var/lib/proot-distro/installed-rootfs/$TLD_ROOTFS_CONTAINER}"
}

_tld_guest_manifest_path() {
  local rootfs_dir="${1-}"
  local manifest_file="${TLD_ROOTFS_MANIFEST_FILE:-}"

  if [[ -n "$manifest_file" ]]; then
    [[ -f "$manifest_file" ]] || return 1
    printf '%s\n' "$manifest_file"
    return 0
  fi
  if [[ -f "$rootfs_dir/manifest.json" ]]; then
    printf '%s\n' "$rootfs_dir/manifest.json"
    return 0
  fi
  if [[ -f "$rootfs_dir/etc/proot-distro/manifest.json" ]]; then
    printf '%s\n' "$rootfs_dir/etc/proot-distro/manifest.json"
    return 0
  fi
  return 1
}

_tld_guest_verify_rootfs() {
  local rootfs_dir="${1-}"
  local manifest_file manifest_digest manifest_hash

  if [[ ! -d "$rootfs_dir" ]]; then
    _tld_guest_error "container rootfs is missing: $rootfs_dir"
    return 1
  fi
  if ! manifest_file=$(_tld_guest_manifest_path "$rootfs_dir"); then
    _tld_guest_error "container manifest.json is missing: $rootfs_dir"
    return 1
  fi
  if ! manifest_digest=$(sha256sum "$manifest_file"); then
    _tld_guest_error "cannot hash container manifest: $manifest_file"
    return 1
  fi
  read -r manifest_hash _ <<< "$manifest_digest"
  if [[ ! "$manifest_hash" =~ ^[0-9a-fA-F]{64}$ ]]; then
    _tld_guest_error "sha256sum returned an invalid manifest hash: $manifest_file"
    return 1
  fi
  TLD_GUEST_ROOTFS_DIR="$rootfs_dir"
  TLD_GUEST_MANIFEST_FILE="$manifest_file"
  TLD_GUEST_MANIFEST_SHA256="$manifest_hash"
  TLD_GUEST_ROOTFS_MANIFEST_SHA256="$manifest_hash"
}

tld_guest_is_installed() {
  local rootfs_dir

  _tld_guest_prepare_paths || return 1
  _tld_guest_load_rootfs_env || return 1
  rootfs_dir=$(_tld_guest_rootfs_dir) || return 1
  [[ -d "$rootfs_dir" ]] || return 1
  _tld_guest_manifest_path "$rootfs_dir" >/dev/null
}

tld_guest_install_rootfs() {
  local command_name host_arch rootfs_dir install_status

  _tld_guest_prepare_paths || return 1
  _tld_guest_load_rootfs_env || return 1
  for command_name in proot-distro uname sha256sum; do
    tld_require_command "$command_name" || return 1
  done

  if ! host_arch=$(uname -m 2>/dev/null); then
    _tld_guest_error 'cannot determine host architecture'
    return 1
  fi
  if [[ "$host_arch" != 'aarch64' || "$TLD_ROOTFS_ARCH" != "$host_arch" ]]; then
    _tld_guest_error "unsupported host architecture: $host_arch; aarch64 is required"
    return 1
  fi

  rootfs_dir=$(_tld_guest_rootfs_dir) || return 1
  if [[ ! -d "$rootfs_dir" ]]; then
    if proot-distro install "$TLD_ROOTFS_IMAGE" --name "$TLD_ROOTFS_CONTAINER"; then
      :
    else
      install_status=$?
      _tld_guest_error "proot-distro install failed with status $install_status"
      return "$install_status"
    fi
  fi
  _tld_guest_verify_rootfs "$rootfs_dir"
}

tld_guest_run() {
  local command_string log_file log_dir run_status

  (( $# > 0 )) || {
    _tld_guest_error 'guest command is required'
    return 1
  }
  _tld_guest_prepare_paths || return 1
  _tld_guest_load_rootfs_env || return 1
  tld_require_command proot-distro || return 1

  if (( $# == 1 )); then
    command_string=$1
  else
    printf -v command_string '%q ' "$@"
    command_string=${command_string% }
  fi

  log_file="${TLD_GUEST_LOG_FILE:-$TLD_LOG_DIR/guest.log}"
  if [[ -L "$log_file" || ( -e "$log_file" && ! -f "$log_file" ) ]]; then
    _tld_guest_error "guest log is not a regular file: $log_file"
    return 1
  fi
  log_dir=${log_file%/*}
  if [[ "$log_dir" == "$log_file" ]]; then
    log_dir=.
  fi
  mkdir -p -- "$log_dir" || return 1

  if proot-distro login "$TLD_ROOTFS_CONTAINER" -- /bin/bash -lc "$command_string" >> "$log_file" 2>&1; then
    return 0
  else
    run_status=$?
    return "$run_status"
  fi
}

tld_guest_provision() {
  local guest_command

  _tld_guest_prepare_paths || return 1
  _tld_guest_load_rootfs_env || return 1
  guest_command=$'set -Eeuo pipefail\n'
  guest_command+=$'DEBIAN_FRONTEND=noninteractive apt-get update\n'
  guest_command+=$'DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends ca-certificates dbus-user-session dbus-x11 file iproute2 procps thunar xfce4-panel xfce4-session xfce4-terminal xfdesktop4 xfwm4 x11-xserver-utils\n'
  guest_command+="mkdir -p /home/$TLD_GUEST_USER"$'\n'
  guest_command+="if ! id -u $TLD_GUEST_USER >/dev/null 2>&1; then"$'\n'
  guest_command+="  useradd --create-home --home-dir /home/$TLD_GUEST_USER --shell /bin/bash $TLD_GUEST_USER"$'\n'
  guest_command+=$'fi\n'
  guest_command+="mkdir -p /home/$TLD_GUEST_USER/.config"$'\n'
  guest_command+="chown -R $TLD_GUEST_USER:$TLD_GUEST_USER /home/$TLD_GUEST_USER"$'\n'
  tld_guest_run "$guest_command"
}

tld_guest_copy_launcher() {
  local guest_command

  _tld_guest_prepare_paths || return 1
  _tld_guest_load_rootfs_env || return 1
  guest_command=$(cat <<'TLD_GUEST_COMMAND'
set -Eeuo pipefail
install -D -m 0755 /dev/stdin /usr/local/lib/termux-linux-desktop/start-guest.sh <<'TLD_LAUNCHER'
#!/usr/bin/env bash
set -Eeuo pipefail

export DISPLAY=${DISPLAY:-:0}
export PULSE_SERVER=${PULSE_SERVER:-tcp:127.0.0.1:4713}

command -v dbus-run-session >/dev/null 2>&1 || {
  printf '%s\n' 'required guest command not found: dbus-run-session' >&2
  exit 1
}
command -v startxfce4 >/dev/null 2>&1 || {
  printf '%s\n' 'required guest command not found: startxfce4' >&2
  exit 1
}
command -v xfce4-session >/dev/null 2>&1 || {
  printf '%s\n' 'required guest command not found: xfce4-session' >&2
  exit 1
}

exec dbus-run-session -- startxfce4
TLD_LAUNCHER
TLD_GUEST_COMMAND
)
  tld_guest_run "$guest_command"
}
