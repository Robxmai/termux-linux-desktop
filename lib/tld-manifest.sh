#!/usr/bin/env bash

if ! declare -F tld_read_env_file >/dev/null 2>&1; then
  source "${BASH_SOURCE[0]%/*}/tld-common.sh"
fi

_tld_manifest_valid_key() {
  [[ "${1-}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]
}

_tld_manifest_has_unsupported_control() {
  case "${1-}" in
    *$'\x01'*|*$'\x02'*|*$'\x03'*|*$'\x04'*|*$'\x05'*|*$'\x06'*|*$'\x07'*|*$'\x08'*|*$'\x09'*|*$'\x0a'*|*$'\x0b'*|*$'\x0c'*|*$'\x0d'*|*$'\x0e'*|*$'\x0f'*|*$'\x10'*|*$'\x11'*|*$'\x12'*|*$'\x13'*|*$'\x14'*|*$'\x15'*|*$'\x16'*|*$'\x17'*|*$'\x18'*|*$'\x19'*|*$'\x1a'*|*$'\x1b'*|*$'\x1c'*|*$'\x1d'*|*$'\x1e'*|*$'\x1f'*|*$'\x7f'*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

_tld_manifest_has_non_ascii() {
  local LC_ALL=C
  local non_ascii_pattern='[^ -~]'
  [[ "${1-}" =~ $non_ascii_pattern ]]
}

_tld_manifest_make_temp() {
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

tld_manifest_begin() {
  local action="${1-}"
  if [[ -z "$action" ]]; then
    printf '%s\n' 'manifest action is required' >&2
    return 1
  fi
  if _tld_manifest_has_unsupported_control "$action"; then
    printf '%s\n' 'manifest action contains unsupported control characters' >&2
    return 1
  fi
  if _tld_manifest_has_non_ascii "$action"; then
    printf '%s\n' 'manifest action must contain printable ASCII only' >&2
    return 1
  fi

  declare -gA TLD_MANIFEST_VALUES
  TLD_MANIFEST_VALUES=()
  TLD_MANIFEST_VALUES[manifest_version]='1'
  TLD_MANIFEST_VALUES[toolkit_version]='0.1.0'
  TLD_MANIFEST_VALUES[action]="$action"
  TLD_MANIFEST_VALUES[created_at]="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}

tld_manifest_set() {
  local key="${1-}"
  local value="${2-}"

  if ! _tld_manifest_valid_key "$key"; then
    printf 'invalid manifest key: %s\n' "$key" >&2
    return 1
  fi
  if ! declare -p TLD_MANIFEST_VALUES >/dev/null 2>&1; then
    printf '%s\n' 'manifest must be initialized with tld_manifest_begin first' >&2
    return 1
  fi
  if _tld_manifest_has_unsupported_control "$value"; then
    printf 'manifest value contains unsupported control characters for key: %s\n' "$key" >&2
    return 1
  fi
  if _tld_manifest_has_non_ascii "$value"; then
    printf 'manifest value must contain printable ASCII only for key: %s\n' "$key" >&2
    return 1
  fi
  TLD_MANIFEST_VALUES["$key"]="$value"
}

tld_manifest_commit() {
  local file="${1-}"
  local temporary
  local key write_failed

  if [[ -z "$file" ]]; then
    printf '%s\n' 'manifest output file is required' >&2
    return 1
  fi
  if ! declare -p TLD_MANIFEST_VALUES >/dev/null 2>&1; then
    printf '%s\n' 'manifest must be initialized with tld_manifest_begin first' >&2
    return 1
  fi
  if [[ -L "$file" || ( -e "$file" && ! -f "$file" ) ]]; then
    printf 'manifest target is not a regular file: %s\n' "$file" >&2
    return 1
  fi

  if ! temporary=$(_tld_manifest_make_temp "$file.tmp.XXXXXXXXXX"); then
    printf 'cannot create manifest temporary file beside: %s\n' "$file" >&2
    return 1
  fi
  if ! {
    write_failed=0
    for key in "${!TLD_MANIFEST_VALUES[@]}"; do
      if ! printf '%s=%q\n' "$key" "${TLD_MANIFEST_VALUES[$key]}"; then
        write_failed=1
        break
      fi
    done
    (( write_failed == 0 ))
  } > "$temporary"; then
    rm -f -- "$temporary" || true
    printf 'cannot write manifest temporary file: %s\n' "$temporary" >&2
    return 1
  fi
  if [[ -L "$file" || ( -e "$file" && ! -f "$file" ) ]]; then
    rm -f -- "$temporary" || true
    printf 'manifest target changed to a non-regular file: %s\n' "$file" >&2
    return 1
  fi
  if ! mv -f -- "$temporary" "$file"; then
    rm -f -- "$temporary" || true
    printf 'cannot atomically install manifest: %s\n' "$file" >&2
    return 1
  fi
}

tld_manifest_require() {
  local file="${1-}"
  local key="${2-}"
  local expected="${3-}"

  if ! _tld_manifest_valid_key "$key"; then
    printf 'invalid manifest key: %s\n' "$key" >&2
    return 1
  fi
  if ! (
    set -- "$key" "$expected"
    unset ROLE PID START_TICKS COMMAND_HASH
    unset "${1}"
    if ! tld_read_env_file "$file"; then
      return 1
    fi
    if ! declare -p "$1" >/dev/null 2>&1; then
      return 1
    fi
    [[ "${!1}" == "$2" ]]
  ); then
    printf 'manifest requirement failed: %s expected %s=%s\n' "$file" "$key" "$expected" >&2
    return 1
  fi
}
