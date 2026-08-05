#!/usr/bin/env bash
set -Eeuo pipefail

TLD_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TLD_FAILURES=0

tld_check_fail() {
  printf 'FAIL %s\n' "$*"
  TLD_FAILURES=1
}

for TLD_SCRIPT in "$TLD_REPO_ROOT"/bin/* "$TLD_REPO_ROOT"/lib/*.sh; do
  if [[ -f "$TLD_SCRIPT" && ! -L "$TLD_SCRIPT" ]]; then
    if ! bash -n "$TLD_SCRIPT"; then
      tld_check_fail "syntax check failed for $TLD_SCRIPT"
    fi
  fi
done

for TLD_SCRIPT in "$TLD_REPO_ROOT"/bin/*; do
  if [[ -f "$TLD_SCRIPT" && ! -L "$TLD_SCRIPT" ]]; then
    if ! grep -q 'set -Eeuo pipefail' "$TLD_SCRIPT"; then
      tld_check_fail "missing strict mode in $TLD_SCRIPT"
    fi
  fi
done

for TLD_COMMAND in "$TLD_REPO_ROOT"/bin/*; do
  if [[ -f "$TLD_COMMAND" && ! -L "$TLD_COMMAND" ]]; then
    if [[ ! -x "$TLD_COMMAND" ]]; then
      tld_check_fail "public command is not executable: $TLD_COMMAND"
    fi
    if grep -E -q 'curl[[:space:]]+\|[[:space:]]*(sh|bash)|killall|[[:space:]]pkill[[:space:]]+-f|rm[[:space:]]+-rf[[:space:]]+("\$HOME"|"\$PREFIX")' "$TLD_COMMAND"; then
      tld_check_fail "forbidden runtime pattern in $TLD_COMMAND"
    fi
  fi
done

for TLD_LIBRARY in "$TLD_REPO_ROOT"/lib/*.sh; do
  if [[ -f "$TLD_LIBRARY" && ! -L "$TLD_LIBRARY" ]]; then
    if grep -E -q 'killall|[[:space:]]pkill[[:space:]]+-f' "$TLD_LIBRARY"; then
      tld_check_fail "forbidden process pattern in $TLD_LIBRARY"
    fi
  fi
done

for TLD_PUBLIC in desktop-install desktop-start desktop-stop desktop-status desktop-doctor desktop-profile desktop-reset; do
  if [[ ! -f "$TLD_REPO_ROOT/bin/$TLD_PUBLIC" ]]; then
    tld_check_fail "public command is missing: $TLD_PUBLIC"
  fi
done

for TLD_DOC in INSTALL ARCHITECTURE SUPPORT RECOVERY; do
  if [[ ! -f "$TLD_REPO_ROOT/docs/$TLD_DOC.md" ]]; then
    tld_check_fail "documentation is missing: docs/$TLD_DOC.md"
  fi
done

if (( TLD_FAILURES == 0 )); then
  printf '%s\n' 'PASS all script and documentation checks'
  exit 0
fi
exit 1
