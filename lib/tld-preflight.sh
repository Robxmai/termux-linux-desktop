#!/usr/bin/env bash

if ! declare -F tld_require_command >/dev/null 2>&1; then
  source "${BASH_SOURCE[0]%/*}/tld-common.sh"
fi

tld_check_architecture() {
  local architecture
  if ! architecture=$(uname -m 2>/dev/null); then
    printf '%s\n' 'FAIL architecture=unknown; run this toolkit on an ARM64 device'
    return 1
  fi
  if [[ "$architecture" == 'aarch64' ]]; then
    printf 'PASS architecture=%s\n' "$architecture"
    return 0
  fi
  printf 'FAIL architecture=%s; use an aarch64/ARM64 Termux environment\n' "$architecture"
  return 1
}

tld_check_prerequisite_commands() {
  local command_name
  local result=0
  for command_name in bash pkg proot-distro pactl; do
    if tld_require_command "$command_name" >/dev/null 2>&1; then
      printf 'PASS command=%s\n' "$command_name"
    else
      printf 'FAIL command=%s; install it or make it available on PATH\n' "$command_name"
      result=1
    fi
  done
  return "$result"
}

tld_check_host_prerequisites() {
  local result=0

  if ! tld_check_architecture; then
    result=1
  fi

  if [[ -n ${PREFIX:-} && -d "${PREFIX:-}" ]]; then
    printf 'PASS PREFIX=%s\n' "$PREFIX"
  else
    printf '%s\n' 'FAIL PREFIX is unset or is not a directory; set PREFIX to the Termux prefix'
    result=1
  fi

  if [[ -n ${HOME:-} && -d "${HOME:-}" ]]; then
    printf 'PASS HOME=%s\n' "$HOME"
  else
    printf '%s\n' 'FAIL HOME is unset or is not a directory; set HOME to the Termux home'
    result=1
  fi

  if ! tld_check_prerequisite_commands; then
    result=1
  fi
  return "$result"
}

tld_check_storage() {
  local required_bytes="${1-}"
  local warning_bytes="${2-}"
  local storage_path="${TLD_STORAGE_PATH:-${PREFIX:-.}}"
  local available_kb available_bytes

  if ! [[ "$required_bytes" =~ ^[0-9]+$ && "$warning_bytes" =~ ^[0-9]+$ && "$warning_bytes" -ge "$required_bytes" ]]; then
    printf '%s\n' 'FAIL storage thresholds are invalid; use numeric warning and required byte values'
    return 1
  fi

  if ! available_kb=$(df -Pk "$storage_path" 2>/dev/null | awk 'NR == 2 { print $4; exit }'); then
    printf 'FAIL storage could not be inspected at %s; check the mounted filesystem\n' "$storage_path"
    return 1
  fi
  if ! [[ "$available_kb" =~ ^[0-9]+$ ]]; then
    printf 'FAIL storage returned no usable capacity for %s; check the mounted filesystem\n' "$storage_path"
    return 1
  fi
  available_bytes=$((available_kb * 1024))

  if (( available_bytes < required_bytes )); then
    printf 'FAIL storage_available_bytes=%s required_bytes=%s; free more storage\n' "$available_bytes" "$required_bytes"
    return 1
  fi
  if (( available_bytes < warning_bytes )); then
    printf 'WARN storage_available_bytes=%s warning_bytes=%s; free storage before installation\n' "$available_bytes" "$warning_bytes"
    return 0
  fi
  printf 'PASS storage_available_bytes=%s warning_bytes=%s\n' "$available_bytes" "$warning_bytes"
}

tld_check_x11_socket() {
  local socket_path="${TLD_X11_SOCKET:-}"
  local mode="${TLD_X11_MODE:-start}"

  if [[ -z "$socket_path" ]]; then
    if [[ -z ${PREFIX:-} ]]; then
      printf '%s\n' 'FAIL X11 socket path is unavailable; set PREFIX or TLD_X11_SOCKET'
      return 1
    fi
    socket_path="$PREFIX/tmp/.X11-unix/X0"
  fi

  if [[ -S "$socket_path" ]]; then
    printf 'PASS x11_socket=%s\n' "$socket_path"
    return 0
  fi
  if [[ "$mode" == 'install' ]]; then
    printf 'WARN x11_socket=%s is missing; start Termux:X11 before launching the desktop\n' "$socket_path"
    return 0
  fi
  printf 'FAIL x11_socket=%s is missing; start Termux:X11 and retry\n' "$socket_path"
  return 1
}
