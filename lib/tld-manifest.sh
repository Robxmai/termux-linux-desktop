#!/usr/bin/env bash

if ! declare -F tld_read_env_file >/dev/null 2>&1; then
  source "${BASH_SOURCE[0]%/*}/tld-common.sh"
fi

_tld_manifest_valid_key() {
  [[ "${1-}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]
}

tld_manifest_begin() {
  local action="${1-}"
  if [[ -z "$action" ]]; then
    printf '%s\n' 'manifest action is required' >&2
    return 1
  fi
  if [[ "$action" == *$'\n'* || "$action" == *$'\r'* ]]; then
    printf '%s\n' 'manifest action must be single-line' >&2
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
  if [[ "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
    printf 'manifest value must be single-line for key: %s\n' "$key" >&2
    return 1
  fi
  TLD_MANIFEST_VALUES["$key"]="$value"
}

tld_manifest_commit() {
  local file="${1-}"
  local temporary
  local key

  if [[ -z "$file" ]]; then
    printf '%s\n' 'manifest output file is required' >&2
    return 1
  fi
  if ! declare -p TLD_MANIFEST_VALUES >/dev/null 2>&1; then
    printf '%s\n' 'manifest must be initialized with tld_manifest_begin first' >&2
    return 1
  fi

  temporary="$file.tmp"
  if ! rm -f -- "$temporary"; then
    printf 'cannot clear manifest temporary file: %s\n' "$temporary" >&2
    return 1
  fi
  if ! {
    for key in "${!TLD_MANIFEST_VALUES[@]}"; do
      printf '%s=%q\n' "$key" "${TLD_MANIFEST_VALUES[$key]}" || exit 1
    done
  } > "$temporary"; then
    rm -f -- "$temporary"
    printf 'cannot write manifest temporary file: %s\n' "$temporary" >&2
    return 1
  fi
  if ! mv -f -- "$temporary" "$file"; then
    rm -f -- "$temporary"
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
    tld_read_env_file "$file" || exit 1
    declare -p "$1" >/dev/null 2>&1 || exit 1
    [[ "${!1}" == "$2" ]]
  ); then
    printf 'manifest requirement failed: %s expected %s=%s\n' "$file" "$key" "$expected" >&2
    return 1
  fi
}
