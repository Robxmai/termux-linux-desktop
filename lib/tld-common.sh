#!/usr/bin/env bash

tld_init_paths() {
  : "${PREFIX:?PREFIX must be set before initializing paths}"
  : "${HOME:?HOME must be set before initializing paths}"

  if [[ ! ${TLD_STATE_DIR+x} ]]; then
    TLD_STATE_DIR="$PREFIX/var/lib/termux-linux-desktop"
  fi
  if [[ ! ${TLD_LOG_DIR+x} ]]; then
    TLD_LOG_DIR="$PREFIX/var/log/termux-linux-desktop"
  fi
  if [[ ! ${TLD_CONFIG_DIR+x} ]]; then
    TLD_CONFIG_DIR="$HOME/.config/termux-linux-desktop"
  fi
  if [[ ! ${TLD_INSTALL_DIR+x} ]]; then
    TLD_INSTALL_DIR="$PREFIX/opt/termux-linux-desktop"
  fi
  if [[ ! ${TLD_INSTANCE_FILE+x} ]]; then
    TLD_INSTANCE_FILE="$TLD_STATE_DIR/instance.env"
  fi

  mkdir -p -- "$TLD_STATE_DIR" "$TLD_LOG_DIR" "$TLD_CONFIG_DIR"
}

tld_init_managed_paths() {
  if [[ "${TLD_TEST_MODE:-0}" == 1 ]]; then
    tld_init_paths
    return
  fi

  : "${PREFIX:?PREFIX must be set before initializing managed paths}"
  : "${HOME:?HOME must be set before initializing managed paths}"
  TLD_STATE_DIR="$PREFIX/var/lib/termux-linux-desktop"
  TLD_LOG_DIR="$PREFIX/var/log/termux-linux-desktop"
  TLD_CONFIG_DIR="$HOME/.config/termux-linux-desktop"
  TLD_INSTALL_DIR="$PREFIX/opt/termux-linux-desktop"
  TLD_INSTANCE_FILE="$TLD_STATE_DIR/instance.env"
  tld_init_paths
}

tld_log() {
  local log_dir="${TLD_LOG_DIR:?TLD_LOG_DIR must be initialized before logging}"
  local line
  printf -v line '[%s] %s' "$(date '+%H:%M:%S')" "$*"
  if ! printf '%s\n' "$line" >> "$log_dir/desktop.log"; then
    return 1
  fi
  printf '%s\n' "$line"
}

tld_die() {
  local line
  printf -v line '[%s] ERROR: %s' "$(date '+%H:%M:%S')" "$*"
  if [[ -n ${TLD_LOG_DIR:-} ]]; then
    printf '%s\n' "$line" >> "$TLD_LOG_DIR/desktop.log"
  fi
  printf '%s\n' "$line" >&2
  return 1
}

tld_require_command() {
  local command_name="${1-}"
  if [[ -z "$command_name" ]]; then
    printf '%s\n' 'required command name is missing; provide a command to check' >&2
    return 1
  fi
  if command -v "$command_name" >/dev/null 2>&1; then
    return 0
  fi
  printf 'required command not found: %s; install it or add it to PATH\n' "$command_name" >&2
  return 1
}

tld_validate_name() {
  local name="${1-}"
  [[ "$name" != "." && "$name" != ".." && "$name" =~ ^[A-Za-z0-9._-]+$ ]]
}

tld_is_true() {
  local value="${1-}"
  case "${value,,}" in
    1|true|yes|on)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

_tld_decode_env_value() {
  local raw="${1-}"
  local decoded=''
  local char next
  local index=0
  local length=${#raw}
  local in_single=0
  local in_double=0

  while (( index < length )); do
    char=${raw:index:1}

    if (( in_single )); then
      if [[ "$char" == "'" ]]; then
        in_single=0
      else
        decoded+="$char"
      fi
      ((index += 1))
      continue
    fi

    if (( in_double )); then
      if [[ "$char" == '"' ]]; then
        in_double=0
        ((index += 1))
        continue
      fi
      if [[ "$char" == \\ ]]; then
        ((index += 1))
        if (( index >= length )); then
          return 1
        fi
        decoded+=${raw:index:1}
        ((index += 1))
        continue
      fi
      if [[ "$char" == '$' || "$char" == '`' || "$char" == ';' || "$char" == '&' || "$char" == '|' || "$char" == '<' || "$char" == '>' ]]; then
        return 1
      fi
      decoded+="$char"
      ((index += 1))
      continue
    fi

    if [[ "$char" == "'" ]]; then
      in_single=1
      ((index += 1))
      continue
    fi
    if [[ "$char" == '"' ]]; then
      in_double=1
      ((index += 1))
      continue
    fi
    if [[ "$char" == \\ ]]; then
      ((index += 1))
      if (( index >= length )); then
        return 1
      fi
      decoded+=${raw:index:1}
      ((index += 1))
      continue
    fi
    if [[ "$char" == '$' || "$char" == '`' || "$char" == ';' || "$char" == '&' || "$char" == '|' || "$char" == '<' || "$char" == '>' || "$char" == '(' || "$char" == ')' || "$char" == '{' || "$char" == '}' || "$char" == '[' || "$char" == ']' || "$char" == '*' || "$char" == '?' || "$char" == '!' || "$char" == $'\t' || "$char" == ' ' ]]; then
      return 1
    fi
    decoded+="$char"
    ((index += 1))
  done

  (( in_single == 0 && in_double == 0 )) || return 1
  [[ "$decoded" != *$'\n'* && "$decoded" != *$'\r'* ]] || return 1
  TLD_READ_VALUE="$decoded"
}

tld_read_env_file() {
  local file="${1-}"
  local line key raw allowed_key
  local enforce_allowlist=0
  local -A parsed=() allowed_keys=() seen_keys=()

  if (( $# > 1 )); then
    enforce_allowlist=1
    shift
    for allowed_key in "$@"; do
      if [[ ! "$allowed_key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        printf 'invalid environment allowlist key: %s\n' "$allowed_key" >&2
        return 1
      fi
      allowed_keys["$allowed_key"]=1
    done
  fi

  if [[ -z "$file" || ! -f "$file" || ! -r "$file" ]]; then
    printf 'cannot read environment file: %s\n' "$file" >&2
    return 1
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" != *$'\r' ]] || {
      printf 'invalid carriage return in environment file: %s\n' "$file" >&2
      return 1
    }
    [[ -z "$line" || "$line" == \#* ]] && continue
    if [[ ! "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      printf 'invalid environment assignment in: %s\n' "$file" >&2
      return 1
    fi
    key=${BASH_REMATCH[1]}
    raw=${BASH_REMATCH[2]}
    if (( enforce_allowlist )) && [[ -z ${allowed_keys[$key]+x} ]]; then
      printf 'unknown environment key: %s\n' "$key" >&2
      return 1
    fi
    if [[ -n ${seen_keys[$key]+x} ]]; then
      printf 'duplicate environment key: %s\n' "$key" >&2
      return 1
    fi
    seen_keys["$key"]=1
    if ! _tld_decode_env_value "$raw"; then
      printf 'unsafe environment value for %s in: %s\n' "$key" "$file" >&2
      return 1
    fi
    parsed["$key"]="$TLD_READ_VALUE"
  done < "$file"

  for key in "${!parsed[@]}"; do
    if ! declare -g -- "$key=${parsed[$key]}"; then
      printf 'cannot assign environment variable: %s\n' "$key" >&2
      return 1
    fi
  done
}
