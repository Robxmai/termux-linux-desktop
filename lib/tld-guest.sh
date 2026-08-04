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

_tld_guest_test_mode() {
  [[ "${TLD_TEST_MODE:-0}" == 1 ]]
}

_tld_guest_validate_path_components() {
  local path="${1-}"
  local label="${2:-path}"
  local component current
  local -a components=()

  if [[ -z "$path" || "$path" != /* || "$path" == *$'\n'* || "$path" == *$'\r'* ]]; then
    _tld_guest_error "$label must be an absolute path without control characters"
    return 1
  fi

  IFS='/' read -r -a components <<< "$path"
  current='/'
  for component in "${components[@]}"; do
    [[ -z "$component" ]] && continue
    if [[ "$component" == '.' || "$component" == '..' ]]; then
      _tld_guest_error "$label contains a traversal component: $path"
      return 1
    fi
    if [[ "$current" == '/' ]]; then
      current="/$component"
    else
      current="$current/$component"
    fi
    if [[ -L "$current" ]]; then
      _tld_guest_error "$label contains a symlink component: $path"
      return 1
    fi
  done
}

_tld_guest_validate_test_path() {
  local path="${1-}"
  local label="${2:-test path}"
  local test_root="${TLD_TEST_ROOT:-}"
  local normalized_root

  if [[ -z "$test_root" || "$test_root" == '/' ]]; then
    _tld_guest_error 'TLD_TEST_ROOT must be a non-root test directory'
    return 1
  fi
  _tld_guest_validate_path_components "$test_root" 'TLD_TEST_ROOT' || return 1
  normalized_root=${test_root%/}
  if [[ "$path" != "$normalized_root" && "$path" != "$normalized_root/"* ]]; then
    _tld_guest_error "$label is outside TLD_TEST_ROOT: $path"
    return 1
  fi
  _tld_guest_validate_path_components "$path" "$label"
}

_tld_guest_prepare_paths() {
  if [[ -z ${PREFIX:-} || -z ${HOME:-} ]]; then
    _tld_guest_error 'PREFIX and HOME must be set before using guest functions'
    return 1
  fi
  tld_init_managed_paths || return 1
  _tld_guest_validate_path_components "$PREFIX" PREFIX || return 1
  _tld_guest_validate_path_components "$TLD_STATE_DIR" TLD_STATE_DIR || return 1
  _tld_guest_validate_path_components "$TLD_LOG_DIR" TLD_LOG_DIR || return 1
  if _tld_guest_test_mode; then
    _tld_guest_validate_path_components "${TLD_TEST_ROOT:-}" TLD_TEST_ROOT || return 1
  fi
}

_tld_guest_load_rootfs_env() {
  local env_file="${TLD_ROOTFS_ENV_FILE:-}"
  local line key
  local assignment_count=0
  local -A seen=()

  if ! _tld_guest_test_mode; then
    env_file="$_tld_guest_lib_dir/../rootfs/ubuntu-24.04.env"
  fi

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
  local derived_path="$PREFIX/var/lib/proot-distro/containers/$TLD_ROOTFS_CONTAINER/rootfs"

  if _tld_guest_test_mode && [[ ${TLD_ROOTFS_DIR+x} ]]; then
    _tld_guest_validate_test_path "$TLD_ROOTFS_DIR" TLD_ROOTFS_DIR || return 1
    printf '%s\n' "$TLD_ROOTFS_DIR"
    return 0
  fi
  _tld_guest_validate_path_components "$derived_path" rootfs || return 1
  printf '%s\n' "$derived_path"
}

_tld_guest_manifest_path() {
  local rootfs_dir="${1-}"
  local container_dir="${rootfs_dir%/*}"
  local manifest_file="$container_dir/manifest.json"

  if _tld_guest_test_mode && [[ ${TLD_ROOTFS_MANIFEST_FILE+x} ]]; then
    _tld_guest_validate_test_path "$TLD_ROOTFS_MANIFEST_FILE" TLD_ROOTFS_MANIFEST_FILE || return 1
    manifest_file="$TLD_ROOTFS_MANIFEST_FILE"
  else
    _tld_guest_validate_path_components "$manifest_file" manifest || return 1
  fi
  [[ -f "$manifest_file" ]] || return 1
  printf '%s\n' "$manifest_file"
}

_tld_guest_log_file() {
  local log_file="$TLD_LOG_DIR/guest.log"

  if _tld_guest_test_mode && [[ ${TLD_GUEST_LOG_FILE+x} ]]; then
    _tld_guest_validate_test_path "$TLD_GUEST_LOG_FILE" TLD_GUEST_LOG_FILE || return 1
    log_file="$TLD_GUEST_LOG_FILE"
  else
    _tld_guest_validate_path_components "$log_file" guest-log || return 1
  fi
  printf '%s\n' "$log_file"
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

_tld_guest_require_proot_version() {
  local version_output actual_major actual_minor actual_patch
  local floor_major floor_minor floor_patch actual_version

  if ! version_output=$(proot-distro --version 2>/dev/null); then
    _tld_guest_error 'cannot determine proot-distro version'
    return 1
  fi
  if [[ "$version_output" =~ ([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
    actual_major=$((10#${BASH_REMATCH[1]}))
    actual_minor=$((10#${BASH_REMATCH[2]}))
    actual_patch=$((10#${BASH_REMATCH[3]}))
    actual_version="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
  else
    _tld_guest_error "unparseable proot-distro version: $version_output"
    return 1
  fi
  if [[ "$TLD_ROOTFS_MIN_PROOT_DISTRO" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    floor_major=$((10#${BASH_REMATCH[1]}))
    floor_minor=$((10#${BASH_REMATCH[2]}))
    floor_patch=$((10#${BASH_REMATCH[3]}))
  else
    _tld_guest_error "invalid minimum proot-distro version: $TLD_ROOTFS_MIN_PROOT_DISTRO"
    return 1
  fi
  if (( actual_major < floor_major ||
    (actual_major == floor_major && actual_minor < floor_minor) ||
    (actual_major == floor_major && actual_minor == floor_minor && actual_patch < floor_patch) )); then
    _tld_guest_error "proot-distro $actual_version is below required version $TLD_ROOTFS_MIN_PROOT_DISTRO"
    return 1
  fi
  TLD_GUEST_PROOT_VERSION="$actual_version"
}

_tld_guest_lock_acquire() {
  local lock_file lock_fd old_umask

  if [[ ${TLD_GUEST_LOCK_FD+x} ]]; then
    _tld_guest_error 'guest lock is already held by this shell'
    return 1
  fi
  _tld_guest_validate_path_components "$TLD_STATE_DIR" TLD_STATE_DIR || return 1
  lock_file="$TLD_STATE_DIR/guest.lock"
  if [[ -L "$lock_file" || ( -e "$lock_file" && ! -f "$lock_file" ) ]]; then
    _tld_guest_error "guest lock is not a regular file: $lock_file"
    return 1
  fi
  tld_require_command flock || return 1

  old_umask=$(umask)
  umask 077
  if ! exec {lock_fd}>"$lock_file"; then
    umask "$old_umask"
    _tld_guest_error "cannot open guest lock: $lock_file"
    return 1
  fi
  umask "$old_umask"
  if ! chmod 600 "$lock_file"; then
    exec {lock_fd}>&-
    return 1
  fi
  if ! flock -x "$lock_fd"; then
    exec {lock_fd}>&-
    return 1
  fi
  TLD_GUEST_LOCK_FD="$lock_fd"
}

_tld_guest_lock_release() {
  local lock_fd="${TLD_GUEST_LOCK_FD:-}"
  local result=0

  if [[ "$lock_fd" =~ ^[0-9]+$ ]]; then
    flock -u "$lock_fd" || result=1
    exec {lock_fd}>&- || result=1
  fi
  unset TLD_GUEST_LOCK_FD
  return "$result"
}

_tld_guest_prepare_runtime() {
  _tld_guest_prepare_paths || return 1
  _tld_guest_load_rootfs_env || return 1
  tld_require_command proot-distro || return 1
  _tld_guest_require_proot_version
}

_tld_guest_login_args() {
  local log_file log_dir result

  log_file=$(_tld_guest_log_file) || return 1
  log_dir=${log_file%/*}
  mkdir -p -- "$log_dir" || return 1
  if proot-distro login "$TLD_ROOTFS_CONTAINER" -- "$@" >> "$log_file" 2>&1; then
    result=0
  else
    result=$?
  fi
  return "$result"
}

_tld_guest_login_script() {
  local script="${1-}"
  local log_file log_dir result

  [[ -n "$script" ]] || {
    _tld_guest_error 'internal guest script is empty'
    return 1
  }
  log_file=$(_tld_guest_log_file) || return 1
  log_dir=${log_file%/*}
  mkdir -p -- "$log_dir" || return 1
  if proot-distro login "$TLD_ROOTFS_CONTAINER" -- /bin/bash -lc "$script" >> "$log_file" 2>&1; then
    result=0
  else
    result=$?
  fi
  return "$result"
}

tld_guest_is_installed() {
  local rootfs_dir result

  _tld_guest_prepare_paths || return 1
  _tld_guest_load_rootfs_env || return 1
  _tld_guest_lock_acquire || return 1
  if rootfs_dir=$(_tld_guest_rootfs_dir) && [[ -d "$rootfs_dir" ]] && _tld_guest_manifest_path "$rootfs_dir" >/dev/null; then
    result=0
  else
    result=1
  fi
  _tld_guest_lock_release || result=1
  return "$result"
}

_tld_guest_install_rootfs_locked() {
  local rootfs_dir install_status

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

tld_guest_install_rootfs() {
  local command_name host_arch result

  _tld_guest_prepare_paths || return 1
  _tld_guest_load_rootfs_env || return 1
  for command_name in proot-distro uname sha256sum; do
    tld_require_command "$command_name" || return 1
  done
  _tld_guest_require_proot_version || return 1

  if ! host_arch=$(uname -m 2>/dev/null); then
    _tld_guest_error 'cannot determine host architecture'
    return 1
  fi
  if [[ "$host_arch" != 'aarch64' || "$TLD_ROOTFS_ARCH" != "$host_arch" ]]; then
    _tld_guest_error "unsupported host architecture: $host_arch; aarch64 is required"
    return 1
  fi

  _tld_guest_lock_acquire || return 1
  if _tld_guest_install_rootfs_locked; then
    result=0
  else
    result=$?
  fi
  _tld_guest_lock_release || result=1
  return "$result"
}

tld_guest_run() {
  local result

  (( $# > 0 )) || {
    _tld_guest_error 'guest command is required'
    return 1
  }
  _tld_guest_prepare_runtime || return 1
  _tld_guest_lock_acquire || return 1
  if _tld_guest_login_args "$@"; then
    result=0
  else
    result=$?
  fi
  _tld_guest_lock_release || result=1
  return "$result"
}

tld_guest_provision() {
  local guest_command result

  _tld_guest_prepare_runtime || return 1
  _tld_guest_lock_acquire || return 1
  guest_command=$'set -Eeuo pipefail\n'
  guest_command+=$'DEBIAN_FRONTEND=noninteractive apt-get update\n'
  guest_command+=$'DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates dbus-user-session dbus-x11 file iproute2 procps thunar xfce4-panel xfce4-session xfce4-terminal xfdesktop4 xfwm4 x11-xserver-utils\n'
  guest_command+="mkdir -p /home/$TLD_GUEST_USER"$'\n'
  guest_command+="if ! id -u $TLD_GUEST_USER >/dev/null 2>&1; then"$'\n'
  guest_command+="  useradd --create-home --home-dir /home/$TLD_GUEST_USER --shell /bin/bash $TLD_GUEST_USER"$'\n'
  guest_command+=$'fi\n'
  guest_command+="mkdir -p /home/$TLD_GUEST_USER/.config"$'\n'
  guest_command+="chown -R $TLD_GUEST_USER:$TLD_GUEST_USER /home/$TLD_GUEST_USER"$'\n'
  if _tld_guest_login_script "$guest_command"; then
    result=0
  else
    result=$?
  fi
  _tld_guest_lock_release || result=1
  return "$result"
}

tld_guest_copy_launcher() {
  local launcher_content guest_prefix guest_suffix guest_command result

  _tld_guest_prepare_runtime || return 1
  tld_require_command cat || return 1
  _tld_guest_lock_acquire || return 1

  if launcher_content=$(cat <<'TLD_LAUNCHER_CONTENT'
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
TLD_LAUNCHER_CONTENT
  ); then
    :
  else
    result=$?
    _tld_guest_error "cannot generate guest launcher content with status $result"
    _tld_guest_lock_release || result=1
    return "$result"
  fi
  if [[ -z "$launcher_content" ]]; then
    _tld_guest_error 'generated guest launcher content is empty'
    result=1
    _tld_guest_lock_release || result=1
    return "$result"
  fi

  if guest_prefix=$(cat <<'TLD_GUEST_PREFIX'
set -Eeuo pipefail
target_dir=/usr/local/lib/termux-linux-desktop
target="$target_dir/start-guest.sh"
if ! install -d -m 0755 "$target_dir"; then
  exit 1
fi
if ! temporary=$(mktemp "$target_dir/.start-guest.sh.XXXXXX"); then
  exit 1
fi
if ! copy_target=$(mktemp "$target_dir/.start-guest.sh.copy.XXXXXX"); then
  rm -f -- "$temporary" || true
  exit 1
fi
trap 'rm -f -- "$temporary" "$copy_target" || true' EXIT
if ! cat > "$temporary" <<'TLD_LAUNCHER'
TLD_GUEST_PREFIX
  ); then
    :
  else
    result=$?
    _tld_guest_error "cannot generate guest write command with status $result"
    _tld_guest_lock_release || result=1
    return "$result"
  fi
  if guest_suffix=$(cat <<'TLD_GUEST_SUFFIX'
then
  exit 1
fi
if [[ ! -s "$temporary" ]]; then
  exit 1
fi
if ! chmod 0755 "$temporary"; then
  exit 1
fi
if ! install -m 0755 "$temporary" "$copy_target"; then
  exit 1
fi
if [[ ! -s "$copy_target" ]]; then
  exit 1
fi
if ! mv -f -- "$copy_target" "$target"; then
  exit 1
fi
if [[ ! -s "$target" ]]; then
  exit 1
fi
if ! rm -f -- "$temporary"; then
  exit 1
fi
trap - EXIT
TLD_GUEST_SUFFIX
  ); then
    :
  else
    result=$?
    _tld_guest_error "cannot generate guest completion command with status $result"
    _tld_guest_lock_release || result=1
    return "$result"
  fi
  guest_command="$guest_prefix"$'\n'"$launcher_content"$'\nTLD_LAUNCHER\n'"$guest_suffix"

  if _tld_guest_login_script "$guest_command"; then
    result=0
  else
    result=$?
  fi
  _tld_guest_lock_release || result=1
  return "$result"
}
