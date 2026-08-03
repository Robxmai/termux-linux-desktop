#!/usr/bin/env bash

if ! declare -F tld_validate_name >/dev/null 2>&1 || ! declare -F tld_read_env_file >/dev/null 2>&1; then
  source "${BASH_SOURCE[0]%/*}/tld-common.sh"
fi

_tld_process_get_start_ticks() {
  local pid="${1-}"
  local proc_root="${TLD_PROC_ROOT:-/proc}"
  local stat_file="$proc_root/$pid/stat"
  local stat_line suffix
  local -a fields=()

  if ! [[ "$pid" =~ ^[1-9][0-9]*$ && -r "$stat_file" ]]; then
    return 1
  fi
  stat_line=$(<"$stat_file") || return 1
  suffix=${stat_line##*') '}
  [[ "$suffix" != "$stat_line" ]] || return 1
  read -r -a fields <<< "$suffix"
  (( ${#fields[@]} >= 20 )) || return 1
  TLD_PROCESS_START_TICKS="${fields[19]-}"
  [[ "$TLD_PROCESS_START_TICKS" =~ ^[0-9]+$ ]]
}

_tld_process_get_command_hash() {
  local cmdline_file="${1-}"
  local command_hash

  [[ -r "$cmdline_file" ]] || return 1
  if ! command_hash=$(
    set -o pipefail
    tr '\0' '\n' < "$cmdline_file" | sha256sum | awk '{print $1}'
  ); then
    return 1
  fi
  [[ "$command_hash" =~ ^[0-9a-fA-F]{64}$ ]] || return 1
  TLD_PROCESS_COMMAND_HASH="$command_hash"
}

_tld_process_record_path() {
  local role="${1-}"
  tld_validate_name "$role" || return 1
  printf '%s/processes/%s.env\n' "${TLD_STATE_DIR:?TLD_STATE_DIR must be initialized}" "$role"
}

_tld_process_lock_acquire() {
  local role="${1-}"
  local process_dir lock_file old_umask lock_fd

  tld_validate_name "$role" || return 1
  process_dir="${TLD_STATE_DIR:?TLD_STATE_DIR must be initialized}/processes"
  mkdir -p -- "$process_dir" || return 1
  lock_file="$process_dir/$role.lock"
  if [[ -L "$lock_file" ]]; then
    printf 'process lock is a symlink: %s\n' "$lock_file" >&2
    return 1
  fi
  if ! command -v flock >/dev/null 2>&1; then
    printf '%s\n' 'required command not found: flock; install it or add it to PATH' >&2
    return 1
  fi

  old_umask=$(umask)
  umask 077
  if ! exec {lock_fd}>"$lock_file"; then
    umask "$old_umask"
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
  TLD_PROCESS_LOCK_FD="$lock_fd"
}

_tld_process_lock_release() {
  local lock_fd="${TLD_PROCESS_LOCK_FD:-}"
  if [[ "$lock_fd" =~ ^[0-9]+$ ]]; then
    flock -u "$lock_fd" || true
    exec {lock_fd}>&-
  fi
  unset TLD_PROCESS_LOCK_FD
}

_tld_process_make_temp() {
  local template="${1-}"
  local old_umask temporary

  old_umask=$(umask)
  umask 077
  if ! temporary=$(mktemp "$template"); then
    umask "$old_umask"
    return 1
  fi
  umask "$old_umask"
  if ! chmod 600 "$temporary"; then
    rm -f -- "$temporary" || true
    return 1
  fi
  printf '%s\n' "$temporary"
}

_tld_process_load_record() {
  local record_file="${1-}"
  local expected_role="${2-}"
  local record_values
  local -a values=()

  if [[ -L "$record_file" || ! -f "$record_file" ]]; then
    return 1
  fi
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

_tld_process_validate_owned() {
  local role="${1-}"
  local record_file recorded_start recorded_hash current_start current_hash

  record_file=$(_tld_process_record_path "$role") || return 1
  if ! _tld_process_load_record "$record_file" "$role"; then
    return 1
  fi
  recorded_start="$TLD_PROCESS_START_TICKS"
  recorded_hash="$TLD_PROCESS_COMMAND_HASH"
  if ! _tld_process_get_start_ticks "$TLD_PROCESS_PID"; then
    return 1
  fi
  current_start="$TLD_PROCESS_START_TICKS"
  if [[ "$current_start" != "$recorded_start" ]]; then
    return 1
  fi
  if ! _tld_process_get_command_hash "${TLD_PROC_ROOT:-/proc}/$TLD_PROCESS_PID/cmdline"; then
    return 1
  fi
  current_hash="$TLD_PROCESS_COMMAND_HASH"
  if [[ "$current_hash" != "$recorded_hash" ]]; then
    return 1
  fi
  TLD_PROCESS_START_TICKS="$recorded_start"
  TLD_PROCESS_COMMAND_HASH="$recorded_hash"
}

_tld_process_owned_state() {
  local pid="${1-}"
  local expected_start="${2-}"
  local expected_hash="${3-}"
  local proc_root="${TLD_PROC_ROOT:-/proc}"
  local current_start current_hash

  if [[ ! -r "$proc_root/$pid/stat" ]]; then
    return 0
  fi
  if ! _tld_process_get_start_ticks "$pid"; then
    return 2
  fi
  current_start="$TLD_PROCESS_START_TICKS"
  if [[ "$current_start" != "$expected_start" ]]; then
    return 2
  fi
  if ! _tld_process_get_command_hash "$proc_root/$pid/cmdline"; then
    return 2
  fi
  current_hash="$TLD_PROCESS_COMMAND_HASH"
  if [[ "$current_hash" != "$expected_hash" ]]; then
    return 2
  fi
  return 1
}

_tld_process_prune_record() {
  rm -f -- "$1"
}

_tld_process_prune_role() {
  local role="${1-}"
  local record_file

  _tld_process_lock_acquire "$role" || return 1
  record_file=$(_tld_process_record_path "$role") || {
    _tld_process_lock_release
    return 1
  }
  if ! _tld_process_validate_owned "$role"; then
    _tld_process_prune_record "$record_file" || true
  fi
  _tld_process_lock_release
}

tld_process_record() {
  local role="${1-}"
  local pid="${2-}"
  local command_hash="${3-}"
  local process_dir record_file temporary
  local result=1

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
  if ! _tld_process_lock_acquire "$role"; then
    return 1
  fi

  process_dir="${TLD_STATE_DIR:?TLD_STATE_DIR must be initialized}/processes"
  record_file="$process_dir/$role.env"
  if [[ -L "$record_file" || ( -e "$record_file" && ! -f "$record_file" ) ]]; then
    printf 'process record target is not a regular file: %s\n' "$record_file" >&2
  elif ! _tld_process_get_start_ticks "$pid"; then
    printf 'cannot read process start tick for PID %s\n' "$pid" >&2
  elif ! temporary=$(_tld_process_make_temp "$record_file.tmp.XXXXXXXXXX"); then
    printf 'cannot create process record temporary file beside: %s\n' "$record_file" >&2
  elif ! {
    printf 'ROLE=%q\n' "$role"
    printf 'PID=%q\n' "$pid"
    printf 'START_TICKS=%q\n' "$TLD_PROCESS_START_TICKS"
    printf 'COMMAND_HASH=%q\n' "$command_hash"
  } > "$temporary"; then
    rm -f -- "$temporary" || true
  elif [[ -L "$record_file" || ( -e "$record_file" && ! -f "$record_file" ) ]]; then
    rm -f -- "$temporary" || true
    printf 'process record target changed to a non-regular file: %s\n' "$record_file" >&2
  elif ! mv -f -- "$temporary" "$record_file"; then
    rm -f -- "$temporary" || true
  else
    result=0
  fi
  _tld_process_lock_release
  return "$result"
}

tld_process_is_owned() {
  local role="${1-}"
  local record_file
  local result=1

  if ! tld_validate_name "$role"; then
    return 1
  fi
  if ! _tld_process_lock_acquire "$role"; then
    return 1
  fi
  record_file=$(_tld_process_record_path "$role") || {
    _tld_process_lock_release
    return 1
  }
  if _tld_process_validate_owned "$role"; then
    result=0
  else
    _tld_process_prune_record "$record_file" || true
  fi
  _tld_process_lock_release
  return "$result"
}

_tld_process_wait_for_termination() {
  local pid="${1-}"
  local expected_start="${2-}"
  local expected_hash="${3-}"
  local wait_seconds="${4-}"
  local poll_seconds="${5-}"
  local deadline state

  deadline=$((SECONDS + wait_seconds))
  while :; do
    if _tld_process_owned_state "$pid" "$expected_start" "$expected_hash"; then
      state=0
    else
      state=$?
    fi
    case "$state" in
      0)
        return 0
        ;;
      2)
        return 2
        ;;
      1)
        if (( SECONDS >= deadline )); then
          return 1
        fi
        sleep "$poll_seconds" || return 2
        ;;
      *)
        return 2
        ;;
    esac
  done
}

tld_process_stop() {
  local role="${1-}"
  local record_file pid expected_start expected_hash
  local wait_seconds poll_seconds kill_wait_seconds state

  if ! tld_validate_name "$role"; then
    return 1
  fi
  if ! _tld_process_lock_acquire "$role"; then
    return 1
  fi
  record_file=$(_tld_process_record_path "$role") || {
    _tld_process_lock_release
    return 1
  }
  if ! _tld_process_validate_owned "$role"; then
    _tld_process_prune_record "$record_file" || true
    _tld_process_lock_release
    return 1
  fi
  pid="$TLD_PROCESS_PID"
  expected_start="$TLD_PROCESS_START_TICKS"
  expected_hash="$TLD_PROCESS_COMMAND_HASH"
  wait_seconds="${TLD_PROCESS_WAIT_SECONDS:-5}"
  poll_seconds="${TLD_PROCESS_POLL_SECONDS:-0.1}"
  if ! [[ "$wait_seconds" =~ ^[0-9]+$ && "$poll_seconds" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    wait_seconds=5
    poll_seconds=0.1
  fi

  if ! kill -TERM "$pid" 2>/dev/null; then
    _tld_process_lock_release
    return 1
  fi
  if _tld_process_wait_for_termination "$pid" "$expected_start" "$expected_hash" "$wait_seconds" "$poll_seconds"; then
    _tld_process_prune_record "$record_file" || true
    _tld_process_lock_release
    return 0
  else
    state=$?
  fi
  if (( state == 2 )); then
    _tld_process_prune_record "$record_file" || true
    _tld_process_lock_release
    return 1
  fi

  if _tld_process_owned_state "$pid" "$expected_start" "$expected_hash"; then
    state=0
  else
    state=$?
  fi
  if (( state == 0 )); then
    _tld_process_prune_record "$record_file" || true
    _tld_process_lock_release
    return 0
  fi
  if (( state != 1 )); then
    _tld_process_prune_record "$record_file" || true
    _tld_process_lock_release
    return 1
  fi
  if ! kill -KILL "$pid" 2>/dev/null; then
    _tld_process_lock_release
    return 1
  fi

  kill_wait_seconds="${TLD_PROCESS_KILL_WAIT_SECONDS:-$wait_seconds}"
  if ! [[ "$kill_wait_seconds" =~ ^[0-9]+$ ]]; then
    kill_wait_seconds="$wait_seconds"
  fi
  if _tld_process_wait_for_termination "$pid" "$expected_start" "$expected_hash" "$kill_wait_seconds" "$poll_seconds"; then
    _tld_process_prune_record "$record_file" || true
    _tld_process_lock_release
    return 0
  else
    state=$?
  fi
  if (( state != 1 )); then
    _tld_process_prune_record "$record_file" || true
  fi
  _tld_process_lock_release
  return 1
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
  local result=0

  [[ -d "$process_dir" ]] || return 0
  for record in "$process_dir"/*.env; do
    [[ -e "$record" ]] || continue
    role=${record##*/}
    role=${role%.env}
    if ! tld_validate_name "$role"; then
      rm -f -- "$record" || result=1
      continue
    fi
    if ! _tld_process_prune_role "$role"; then
      result=1
    fi
  done
  return "$result"
}
