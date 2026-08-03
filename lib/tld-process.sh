#!/usr/bin/env bash

if ! declare -F tld_validate_name >/dev/null 2>&1 || ! declare -F tld_read_env_file >/dev/null 2>&1; then
  source "${BASH_SOURCE[0]%/*}/tld-common.sh"
fi

_tld_process_get_start_ticks() {
  local pid="${1-}"
  local proc_root="${TLD_PROC_ROOT:-/proc}"
  local stat_file="$proc_root/$pid/stat"
  local stat_line remainder
  local -a fields=()

  if ! [[ "$pid" =~ ^[1-9][0-9]*$ && -r "$stat_file" ]]; then
    return 1
  fi
  stat_line=$(<"$stat_file") || return 1
  if [[ "$stat_line" =~ \)\ (.*)$ ]]; then
    remainder=${BASH_REMATCH[1]}
  else
    return 1
  fi
  read -r -a fields <<< "$remainder"
  (( ${#fields[@]} >= 20 )) || return 1
  TLD_PROCESS_START_TICKS="${fields[19]-}"
  [[ "$TLD_PROCESS_START_TICKS" =~ ^[0-9]+$ ]]
}

_tld_process_get_command_hash() {
  local cmdline_file="${1-}"
  local command_hash

  [[ -r "$cmdline_file" ]] || return 1
  if ! command_hash=$(tr '\0' '\n' < "$cmdline_file" | sha256sum | awk '{print $1}'); then
    return 1
  fi
  [[ "$command_hash" =~ ^[0-9a-fA-F]{64}$ ]] || return 1
  TLD_PROCESS_COMMAND_HASH="$command_hash"
}

_tld_process_load_record() {
  local record_file="${1-}"
  local expected_role="${2-}"
  local record_values
  local -a values=()

  if ! record_values=$(
    unset ROLE PID START_TICKS COMMAND_HASH
    tld_read_env_file "$record_file" || exit 1
    printf '%s\n' "${ROLE-}" "${PID-}" "${START_TICKS-}" "${COMMAND_HASH-}"
  ); then
    return 1
  fi
  mapfile -t values <<< "$record_values"
  (( ${#values[@]} == 4 )) || return 1
  TLD_PROCESS_ROLE="${values[0]-}"
  TLD_PROCESS_PID="${values[1]-}"
  TLD_PROCESS_START_TICKS="${values[2]-}"
  TLD_PROCESS_COMMAND_HASH="${values[3]-}"
  [[ "$TLD_PROCESS_ROLE" == "$expected_role" ]] || return 1
  [[ "$TLD_PROCESS_PID" =~ ^[1-9][0-9]*$ ]] || return 1
  [[ "$TLD_PROCESS_START_TICKS" =~ ^[0-9]+$ ]] || return 1
  [[ -n "$TLD_PROCESS_COMMAND_HASH" && "$TLD_PROCESS_COMMAND_HASH" != *$'\n'* ]] || return 1
}

_tld_process_record_path() {
  local role="${1-}"
  tld_validate_name "$role" || return 1
  printf '%s/processes/%s.env\n' "${TLD_STATE_DIR:?TLD_STATE_DIR must be initialized}" "$role"
}

_tld_process_prune_record() {
  rm -f -- "$1"
}

tld_process_record() {
  local role="${1-}"
  local pid="${2-}"
  local command_hash="${3-}"
  local process_dir record_file temporary

  if ! tld_validate_name "$role"; then
    printf 'invalid process role: %s\n' "$role" >&2
    return 1
  fi
  if ! [[ "$pid" =~ ^[1-9][0-9]*$ ]]; then
    printf 'invalid process PID for role %s\n' "$role" >&2
    return 1
  fi
  if [[ -z "$command_hash" || "$command_hash" == *$'\n'* || "$command_hash" == *$'\r'* ]]; then
    printf 'invalid command hash for role %s\n' "$role" >&2
    return 1
  fi
  if ! _tld_process_get_start_ticks "$pid"; then
    printf 'cannot read process start tick for PID %s\n' "$pid" >&2
    return 1
  fi

  process_dir="${TLD_STATE_DIR:?TLD_STATE_DIR must be initialized}/processes"
  record_file="$process_dir/$role.env"
  temporary="$record_file.tmp"
  mkdir -p -- "$process_dir" || return 1
  rm -f -- "$temporary" || return 1
  if ! {
    printf 'ROLE=%q\n' "$role"
    printf 'PID=%q\n' "$pid"
    printf 'START_TICKS=%q\n' "$TLD_PROCESS_START_TICKS"
    printf 'COMMAND_HASH=%q\n' "$command_hash"
  } > "$temporary"; then
    rm -f -- "$temporary"
    return 1
  fi
  if ! mv -f -- "$temporary" "$record_file"; then
    rm -f -- "$temporary"
    return 1
  fi
}

tld_process_is_owned() {
  local role="${1-}"
  local record_file proc_root recorded_start recorded_hash current_start current_hash

  if ! tld_validate_name "$role"; then
    return 1
  fi
  record_file=$(_tld_process_record_path "$role") || return 1
  if [[ ! -f "$record_file" ]] || ! _tld_process_load_record "$record_file" "$role"; then
    [[ -f "$record_file" ]] && _tld_process_prune_record "$record_file"
    return 1
  fi
  recorded_start="$TLD_PROCESS_START_TICKS"
  recorded_hash="$TLD_PROCESS_COMMAND_HASH"

  proc_root="${TLD_PROC_ROOT:-/proc}"
  if ! _tld_process_get_start_ticks "$TLD_PROCESS_PID"; then
    _tld_process_prune_record "$record_file"
    return 1
  fi
  current_start="$TLD_PROCESS_START_TICKS"
  if [[ "$current_start" != "$recorded_start" ]]; then
    _tld_process_prune_record "$record_file"
    return 1
  fi

  if ! _tld_process_get_command_hash "$proc_root/$TLD_PROCESS_PID/cmdline"; then
    _tld_process_prune_record "$record_file"
    return 1
  fi
  current_hash="$TLD_PROCESS_COMMAND_HASH"
  if [[ "$current_hash" != "$recorded_hash" ]]; then
    _tld_process_prune_record "$record_file"
    return 1
  fi
  return 0
}

tld_process_stop() {
  local role="${1-}"
  local record_file pid wait_seconds poll_seconds deadline

  if ! tld_validate_name "$role"; then
    return 1
  fi
  if ! tld_process_is_owned "$role"; then
    return 1
  fi
  record_file=$(_tld_process_record_path "$role") || return 1
  _tld_process_load_record "$record_file" "$role" || return 1
  pid="$TLD_PROCESS_PID"

  if ! tld_process_is_owned "$role"; then
    return 1
  fi
  _tld_process_load_record "$record_file" "$role" || return 1
  pid="$TLD_PROCESS_PID"
  if ! kill -TERM "$pid" 2>/dev/null; then
    return 1
  fi

  wait_seconds="${TLD_PROCESS_WAIT_SECONDS:-5}"
  poll_seconds="${TLD_PROCESS_POLL_SECONDS:-0.1}"
  if ! [[ "$wait_seconds" =~ ^[0-9]+$ && "$poll_seconds" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    wait_seconds=5
    poll_seconds=0.1
  fi
  deadline=$((SECONDS + wait_seconds))

  while tld_process_is_owned "$role"; do
    if (( SECONDS >= deadline )); then
      if ! tld_process_is_owned "$role"; then
        return 0
      fi
      _tld_process_load_record "$record_file" "$role" || return 1
      pid="$TLD_PROCESS_PID"
      if ! tld_process_is_owned "$role"; then
        return 0
      fi
      kill -KILL "$pid" 2>/dev/null || return 1
      _tld_process_prune_record "$record_file"
      return 0
    fi
    sleep "$poll_seconds"
  done
  return 0
}

tld_process_stop_all() {
  local process_dir="${TLD_STATE_DIR:?TLD_STATE_DIR must be initialized}/processes"
  local record role
  local result=0

  [[ -d "$process_dir" ]] || return 0
  for record in "$process_dir"/*.env; do
    [[ -e "$record" ]] || continue
    role=${record##*/}
    role=${role%.env}
    if ! tld_process_stop "$role"; then
      result=1
    fi
  done
  return "$result"
}

tld_process_prune() {
  local process_dir="${TLD_STATE_DIR:?TLD_STATE_DIR must be initialized}/processes"
  local record role

  [[ -d "$process_dir" ]] || return 0
  for record in "$process_dir"/*.env; do
    [[ -e "$record" ]] || continue
    role=${record##*/}
    role=${role%.env}
    if ! tld_validate_name "$role"; then
      _tld_process_prune_record "$record"
      continue
    fi
    tld_process_is_owned "$role" || true
  done
}
