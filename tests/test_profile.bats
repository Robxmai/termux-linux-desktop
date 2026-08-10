#!/usr/bin/env bats

setup() {
  export TLD_TEST_ROOT="$BATS_TEST_TMPDIR/tld"
  export HOME="$TLD_TEST_ROOT/home"
  export PREFIX="$TLD_TEST_ROOT/prefix"
  export TLD_STATE_DIR="$TLD_TEST_ROOT/state"
  export TLD_LOG_DIR="$TLD_TEST_ROOT/log"
  export TLD_CONFIG_DIR="$TLD_TEST_ROOT/config"
  export TLD_INSTALL_DIR="$TLD_TEST_ROOT/install"
  export TLD_INSTANCE_FILE="$TLD_STATE_DIR/instance.env"
  export TLD_LIB_DIR="$BATS_TEST_DIRNAME/../lib"
  export TLD_PROC_ROOT="$TLD_TEST_ROOT/proc"
  export TLD_TEST_BIN="$TLD_TEST_ROOT/bin"
  export TLD_TEST_MODE=1
  export TLD_X11_SOCKET="$TLD_TEST_ROOT/x11.sock"
  export TLD_TEST_CALL_LOG="$TLD_TEST_ROOT/calls.log"

  unset TLD_ROOTFS_DIR TLD_ROOTFS_MANIFEST_FILE TLD_GUEST_LOG_FILE TLD_ROOTFS_ENV_FILE
  unset TLD_X11_MODE TLD_AUDIO_OWNER

  mkdir -p "$HOME" "$PREFIX/bin" "$PREFIX/opt" "$TLD_STATE_DIR" "$TLD_LOG_DIR" "$TLD_CONFIG_DIR" "$TLD_TEST_BIN" "$TLD_PROC_ROOT"
  : > "$TLD_TEST_CALL_LOG"

  export TLD_REAL_PATH="$PATH"
  export TLD_REAL_SHA256SUM="$(PATH="$TLD_REAL_PATH" command -v sha256sum)"
  export PATH="$TLD_TEST_BIN:$TLD_REAL_PATH"

  export TLD_TEST_ROOTFS_DIR="$PREFIX/var/lib/proot-distro/containers/tld-ubuntu/rootfs"
  export TLD_TEST_MANIFEST_FILE="$PREFIX/var/lib/proot-distro/containers/tld-ubuntu/manifest.json"
  export TLD_ROOTFS_ENV_FILE="$TLD_TEST_ROOT/ubuntu.env"
  mkdir -p "$TLD_TEST_ROOTFS_DIR/usr/local/lib/termux-linux-desktop" "$TLD_TEST_ROOTFS_DIR/etc/profile.d"
  printf '%s\n' '{"architecture":"arm64"}' > "$TLD_TEST_MANIFEST_FILE"
  printf '%s\n' 'export LANG=C.UTF-8' 'export LC_ALL=C.UTF-8' > "$TLD_TEST_ROOTFS_DIR/etc/profile.d/01-locale-fix.sh"
  printf '%s\n' \
    "TLD_ROOTFS_IMAGE='ubuntu:24.04'" \
    "TLD_ROOTFS_CONTAINER='tld-ubuntu'" \
    "TLD_ROOTFS_ARCH='aarch64'" \
    "TLD_ROOTFS_MIN_PROOT_DISTRO='5.5.0'" \
    "TLD_GUEST_USER='tld'" \
    > "$TLD_ROOTFS_ENV_FILE"

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -Eeuo pipefail' \
    'printf "proot-distro %s\\n" "$*" >> "${TLD_TEST_CALL_LOG:?}"' \
    'printf "%s\\n" "5.5.0"' \
    > "$TLD_TEST_BIN/proot-distro"

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -Eeuo pipefail' \
    'printf "pactl %s\\n" "$*" >> "${TLD_TEST_CALL_LOG:?}"' \
    'if [[ -f "${TLD_TEST_ROOT:?}/audio-ready" ]]; then' \
    '  exit 0' \
    'fi' \
    'exit 1' \
    > "$TLD_TEST_BIN/pactl"

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "uname\\n" >> "${TLD_TEST_CALL_LOG:?}"' \
    'printf "%s\\n" "${TLD_TEST_ARCH:-aarch64}"' \
    > "$TLD_TEST_BIN/uname"

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'exec "${TLD_REAL_SHA256SUM:?}" "$@"' \
    > "$TLD_TEST_BIN/sha256sum"

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -Eeuo pipefail' \
    'REAL_FLOCK=$(PATH="$TLD_REAL_PATH" command -v flock)' \
    '[[ -n "$REAL_FLOCK" ]] || exit 127' \
    'exec "$REAL_FLOCK" "$@"' \
    > "$TLD_TEST_BIN/flock"

  kill() {
    if [[ "${TLD_TEST_MODE:-0}" != 1 ]]; then
      command kill "$@"
      return $?
    fi
    if [[ "${TLD_TEST_KILL_REMOVES:-0}" == 1 ]]; then
      rm -rf -- "${TLD_PROC_ROOT:?}/${2:?}"
    fi
    return 0
  }
  export -f kill

  chmod +x "$TLD_TEST_BIN"/*
}

_tld_write_manifest() {
  printf '%s\n' \
    'manifest_version=1' \
    'toolkit_version=0.1.0' \
    'action=install' \
    'created_at=2026-01-02T03:04:05Z' \
    'status=installed' \
    'architecture=aarch64' \
    'rootfs_image=ubuntu:24.04' \
    'rootfs_container=tld-ubuntu' \
    'profile=base' \
    'profile_version=2' \
    'runtime=wine-11.11-amd64-wow64' \
    "rootfs_manifest_sha256=$("$TLD_REAL_SHA256SUM" "$TLD_TEST_MANIFEST_FILE" | awk '{print $1}')" \
    > "$TLD_INSTANCE_FILE"
}

_tld_make_x11_socket() {
  python3 - "$TLD_X11_SOCKET" <<'PY'
import socket, sys
s = socket.socket(socket.AF_UNIX)
s.bind(sys.argv[1])
PY
}

@test "profile list prints base and the active profile" {
  _tld_write_manifest

  run bash "$BATS_TEST_DIRNAME/../bin/desktop-profile" list

  [ "$status" -eq 0 ]
  [[ "$output" == *'base'* ]]
  [[ "$output" == *'active: base'* ]]
}

@test "profile apply base is idempotent" {
  _tld_write_manifest

  run bash "$BATS_TEST_DIRNAME/../bin/desktop-profile" apply base

  [ "$status" -eq 0 ]
  [[ "$output" == *'already active'* ]]
  [ ! -e "$TLD_STATE_DIR/profile.env" ]
}

@test "profile apply of an unknown profile fails without state" {
  _tld_write_manifest

  run bash "$BATS_TEST_DIRNAME/../bin/desktop-profile" apply nope

  [ "$status" -ne 0 ]
  [ ! -e "$TLD_STATE_DIR/profile.env" ]
}

@test "profile names with traversal or metacharacters are rejected" {
  _tld_write_manifest

  run bash "$BATS_TEST_DIRNAME/../bin/desktop-profile" apply '../x'

  [ "$status" -ne 0 ]

  run bash "$BATS_TEST_DIRNAME/../bin/desktop-profile" apply 'a b'

  [ "$status" -ne 0 ]

  run bash "$BATS_TEST_DIRNAME/../bin/desktop-profile" apply 'a;rm -rf'

  [ "$status" -ne 0 ]
  [ ! -e "$TLD_STATE_DIR/profile.env" ]
}

@test "profile remove base refuses" {
  _tld_write_manifest

  run bash "$BATS_TEST_DIRNAME/../bin/desktop-profile" remove base

  [ "$status" -ne 0 ]
  [[ "$output" == *'cannot be removed'* ]]
}

@test "profile apply requires an installed toolkit" {
  run bash "$BATS_TEST_DIRNAME/../bin/desktop-profile" apply base

  [ "$status" -ne 0 ]
  [[ "$output" == *'not installed'* ]]
}

@test "doctor full mode passes for a healthy installed toolkit" {
  _tld_write_manifest
  : > "$TLD_TEST_ROOT/audio-ready"
  _tld_make_x11_socket

  run bash "$BATS_TEST_DIRNAME/../bin/desktop-doctor"

  [ "$status" -eq 0 ]
  [[ "$output" == *'PASS architecture=aarch64'* ]]
  [[ "$output" == *'PASS runtime manifest'* ]]
  [[ "$output" == *'PASS rootfs='* ]]
  [[ "$output" == *'PASS x11_socket='* ]]
  [[ "$output" == *'PASS audio'* ]]
  [[ "$output" == *'PASS owned processes='* ]]
}

@test "doctor full mode fails when the X11 socket is missing" {
  _tld_write_manifest

  run bash "$BATS_TEST_DIRNAME/../bin/desktop-doctor"

  [ "$status" -ne 0 ]
  [[ "$output" == *'FAIL Termux:X11 socket is not ready'* ]]
}

@test "doctor full mode exits nonzero when architecture is unsupported" {
  _tld_write_manifest
  TLD_TEST_ARCH=x86_64
  export TLD_TEST_ARCH

  run bash "$BATS_TEST_DIRNAME/../bin/desktop-doctor"

  [ "$status" -ne 0 ]
  [[ "$output" == *'FAIL architecture=x86_64'* ]]
}

@test "doctor --json emits a valid document with the required top-level keys" {
  _tld_write_manifest

  run bash "$BATS_TEST_DIRNAME/../bin/desktop-doctor" --json

  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | python3 -c 'import json, sys; d = json.load(sys.stdin); assert set(d.keys()) == {"toolkit_version", "architecture", "storage", "rootfs", "display", "audio", "gpu", "processes", "profile"}, d.keys()'
  [[ "$output" == *'"toolkit_version": "0.1.0"'* ]]
  [[ "$output" == *'"architecture": "aarch64"'* ]]
  [[ "$output" == *'"profile": "base"'* ]]
}

@test "reset requires an installed toolkit" {
  run bash "$BATS_TEST_DIRNAME/../bin/desktop-reset" --yes

  [ "$status" -ne 0 ]
  [[ "$output" == *'nothing to reset'* ]]
}

@test "reset refuses without --yes" {
  _tld_write_manifest

  run bash "$BATS_TEST_DIRNAME/../bin/desktop-reset"

  [ "$status" -ne 0 ]
  [[ "$output" == *'confirmation required'* ]]
  [ -f "$TLD_INSTANCE_FILE" ]
}

@test "reset --yes backs up and removes toolkit state" {
  _tld_write_manifest
  : > "$TLD_TEST_ROOT/audio-ready"
  printf 'AUDIO_OWNER=external\n' > "$TLD_STATE_DIR/audio-owner.env"

  run bash "$BATS_TEST_DIRNAME/../bin/desktop-reset" --yes

  [ "$status" -eq 0 ]
  [[ "$output" == *'PASS reset backup='* ]]
  [ ! -e "$TLD_INSTANCE_FILE" ]
  [ ! -e "$TLD_STATE_DIR/audio-owner.env" ]
  backup_dir=$(printf '%s\n' "$output" | sed -n 's/^PASS reset backup=//p')
  [ -n "$backup_dir" ]
  [ -f "$backup_dir/instance.env" ]
  grep -F 'proot-distro remove tld-ubuntu' "$TLD_TEST_CALL_LOG"
}

@test "reset --yes removes the toolkit install tree and its symlinks" {
  _tld_write_manifest
  : > "$TLD_TEST_ROOT/audio-ready"
  mkdir -p "$TLD_INSTALL_DIR/bin"
  printf '%s\n' 'OWNER=termux-linux-desktop' 'VERSION=0.1.0' > "$TLD_INSTALL_DIR/.tld-toolkit-owner"
  ln -s -- "$TLD_INSTALL_DIR/bin/desktop-install" "$PREFIX/bin/desktop-install"

  run bash "$BATS_TEST_DIRNAME/../bin/desktop-reset" --yes

  [ "$status" -eq 0 ]
  [ ! -e "$TLD_INSTALL_DIR" ]
  [ ! -L "$PREFIX/bin/desktop-install" ]
}

@test "reset --yes aborts and preserves state when the backup fails" {
  _tld_write_manifest
  printf 'blocked\n' > "$TLD_STATE_DIR/backups"

  run bash "$BATS_TEST_DIRNAME/../bin/desktop-reset" --yes

  [ "$status" -ne 0 ]
  [[ "$output" == *'backup failed'* ]]
  [ -f "$TLD_INSTANCE_FILE" ]
  [ -f "$TLD_STATE_DIR/profile.env" ] || true
}

@test "reset --yes stops and removes an owned process record" {
  _tld_write_manifest
  : > "$TLD_TEST_ROOT/audio-ready"
  export TLD_TEST_KILL_REMOVES=1
  mkdir -p "$TLD_PROC_ROOT/5252"
  printf '5252 (dbus-run-session) R 1 1 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 9999\n' > "$TLD_PROC_ROOT/5252/stat"
  printf '/usr/bin/dbus-run-session\0--flag\0' > "$TLD_PROC_ROOT/5252/cmdline"
  hash=$(tr '\0' '\n' < "$TLD_PROC_ROOT/5252/cmdline" | sha256sum | awk '{print $1}')
  mkdir -p "$TLD_STATE_DIR/processes"
  printf 'ROLE=desktop\nPID=5252\nSTART_TICKS=9999\nCOMMAND_HASH=%s\n' "$hash" > "$TLD_STATE_DIR/processes/desktop.env"

  run bash "$BATS_TEST_DIRNAME/../bin/desktop-reset" --yes

  [ "$status" -eq 0 ]
  [ ! -e "$TLD_STATE_DIR/processes/desktop.env" ]
}
