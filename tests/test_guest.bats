#!/usr/bin/env bats

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  export PREFIX="$BATS_TEST_TMPDIR/prefix"
  export TLD_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export TLD_LOG_DIR="$BATS_TEST_TMPDIR/log"
  export TLD_CONFIG_DIR="$BATS_TEST_TMPDIR/config"
  export TLD_INSTALL_DIR="$BATS_TEST_TMPDIR/install"
  export TLD_INSTANCE_FILE="$TLD_STATE_DIR/instance.env"
  export TLD_LIB_DIR="$BATS_TEST_DIRNAME/../lib"
  unset TLD_ROOTFS_DIR TLD_ROOTFS_MANIFEST_FILE TLD_GUEST_LOG_FILE TLD_ROOTFS_ENV_FILE TLD_TEST_MODE TLD_TEST_ROOT TLD_TEST_LOCK_HELD TLD_TEST_LOCK_RELEASED
  export TLD_TEST_MODE=1
  export TLD_TEST_ROOT="$BATS_TEST_TMPDIR"
  export TLD_ROOTFS_ENV_FILE="$BATS_TEST_TMPDIR/ubuntu.env"
  export TLD_TEST_ROOTFS_DIR="$PREFIX/var/lib/proot-distro/containers/tld-ubuntu/rootfs"
  export TLD_TEST_MANIFEST_FILE="$PREFIX/var/lib/proot-distro/containers/tld-ubuntu/manifest.json"
  export TLD_TEST_BIN="$BATS_TEST_TMPDIR/bin"
  export TLD_TEST_CALL_LOG="$BATS_TEST_TMPDIR/calls.log"
  export TLD_TEST_GUEST_COMMAND="$BATS_TEST_TMPDIR/guest-command"
  export TLD_TEST_LOGIN_ARGS="$BATS_TEST_TMPDIR/login-args"
  export TLD_TEST_ARCH=aarch64
  export TLD_TEST_PROOT_VERSION=5.5.0
  export TLD_TEST_INSTALL_STATUS=0
  export TLD_TEST_INSTALL_CREATE_ROOTFS=1
  export TLD_TEST_INSTALL_CREATE_MANIFEST=1
  export TLD_TEST_LOGIN_STATUS=0
  export TLD_REAL_PATH="$PATH"
  export TLD_REAL_SHA256SUM="$(PATH="$TLD_REAL_PATH" command -v sha256sum)"
  export PATH="$TLD_TEST_BIN:$BATS_TEST_DIRNAME/helpers/fake-termux/bin:$TLD_REAL_PATH"

  mkdir -p "$HOME" "$PREFIX" "$TLD_STATE_DIR" "$TLD_LOG_DIR" "$TLD_CONFIG_DIR" "$TLD_TEST_BIN"
  : > "$TLD_TEST_CALL_LOG"

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -Eeuo pipefail' \
    '{ printf "proot-distro"; printf " %s" "$@"; printf "\n"; } >> "$TLD_TEST_CALL_LOG"' \
    'case "${1-}" in' \
    '  --version)' \
    '    printf "%s\n" "${TLD_TEST_PROOT_VERSION:?}"' \
    '    exit 0' \
    '    ;;' \
    '  install)' \
    '    if [[ -n "${TLD_TEST_LOCK_HELD:-}" && -e "$TLD_TEST_LOCK_HELD" ]]; then' \
    '      exit 97' \
    '    fi' \
    '    if [[ "${TLD_TEST_INSTALL_CREATE_ROOTFS:-1}" == 1 ]]; then' \
    '      mkdir -p "$TLD_TEST_ROOTFS_DIR"' \
    '      if [[ "${TLD_TEST_INSTALL_CREATE_MANIFEST:-1}" == 1 ]]; then' \
    '        printf "%s\\n" manifest > "$TLD_TEST_MANIFEST_FILE"' \
    '      fi' \
    '    fi' \
    '    exit "${TLD_TEST_INSTALL_STATUS:-0}"' \
    '    ;;' \
    '  login)' \
    '    if [[ -n "${TLD_TEST_LOCK_HELD:-}" && -e "$TLD_TEST_LOCK_HELD" ]]; then' \
    '      printf "%s\n" provision-login-while-locked >> "$TLD_TEST_CALL_LOG"' \
    '      exit 98' \
    '    fi' \
    '    printf "%s\n" provision-login-after-lock >> "$TLD_TEST_CALL_LOG"' \
    '    command="${!#}"' \
    '    printf "%s\\n" "$@" > "$TLD_TEST_LOGIN_ARGS"' \
    '    printf "%s" "$command" > "$TLD_TEST_GUEST_COMMAND"' \
    '    printf "%s\n" guest-stdout' \
    '    printf "%s\n" guest-stderr >&2' \
    '    exit "${TLD_TEST_LOGIN_STATUS:-0}"' \
    '    ;;' \
    'esac' \
    'exit 0' > "$TLD_TEST_BIN/proot-distro"

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "%s\n" "${TLD_TEST_ARCH:-aarch64}"' > "$TLD_TEST_BIN/uname"

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'exec "${TLD_REAL_SHA256SUM:?}" "$@"' > "$TLD_TEST_BIN/sha256sum"

  for command_name in apt-get id useradd install; do
    printf '%s\n' \
      '#!/usr/bin/env bash' \
      'set -Eeuo pipefail' \
      'printf "%s" "${0##*/}" >> "${TLD_TEST_CALL_LOG:?}"' \
      'printf " %s\n" "$@" >> "${TLD_TEST_CALL_LOG:?}"' \
      'exit "${TLD_TEST_GUEST_COMMAND_STATUS:-0}"' > "$TLD_TEST_BIN/$command_name"
  done

  chmod +x "$TLD_TEST_BIN"/*

  printf '%s\n' \
    "TLD_ROOTFS_IMAGE='ubuntu:24.04'" \
    "TLD_ROOTFS_CONTAINER='tld-ubuntu'" \
    "TLD_ROOTFS_ARCH='aarch64'" \
    "TLD_ROOTFS_MIN_PROOT_DISTRO='5.5.0'" \
    "TLD_GUEST_USER='tld'" > "$TLD_ROOTFS_ENV_FILE"

  source "$TLD_LIB_DIR/tld-common.sh"
  source "$TLD_LIB_DIR/tld-guest.sh"
}

make_installed_rootfs() {
  mkdir -p "$TLD_TEST_ROOTFS_DIR"
  printf '%s\n' manifest > "$TLD_TEST_MANIFEST_FILE"
}

test_manifest_sha256() {
  "$TLD_REAL_SHA256SUM" "$TLD_TEST_MANIFEST_FILE" | awk '{print $1}'
}

@test "tld_guest_install_rootfs validates the pinned rootfs assignments" {
  tld_guest_install_rootfs

  [ "$TLD_ROOTFS_IMAGE" = 'ubuntu:24.04' ]
  [ "$TLD_ROOTFS_CONTAINER" = 'tld-ubuntu' ]
  [ "$TLD_ROOTFS_ARCH" = 'aarch64' ]
  [ "$TLD_ROOTFS_MIN_PROOT_DISTRO" = '5.5.0' ]
  [ "$TLD_GUEST_USER" = 'tld' ]
  [ "$TLD_GUEST_PROOT_VERSION" = '5.5.0' ]
  [ "$TLD_GUEST_ROOTFS_DIR" = "$TLD_TEST_ROOTFS_DIR" ]
  [ "$TLD_GUEST_MANIFEST_FILE" = "$TLD_TEST_MANIFEST_FILE" ]
  [ "$TLD_GUEST_MANIFEST_SHA256" = "$(test_manifest_sha256)" ]
}

@test "tld_guest_install_rootfs rejects malicious rootfs env syntax without executing it" {
  marker="$BATS_TEST_TMPDIR/malicious-marker"
  printf '%s\n' \
    "TLD_ROOTFS_IMAGE=\$(touch '$marker')" \
    "TLD_ROOTFS_CONTAINER='tld-ubuntu'" \
    "TLD_ROOTFS_ARCH='aarch64'" \
    "TLD_ROOTFS_MIN_PROOT_DISTRO='5.5.0'" \
    "TLD_GUEST_USER='tld'" > "$TLD_ROOTFS_ENV_FILE"

  run tld_guest_install_rootfs

  [ "$status" -ne 0 ]
  [ ! -e "$marker" ]
}

@test "tld_guest_install_rootfs refuses a non-aarch64 host" {
  export TLD_TEST_ARCH=x86_64

  run tld_guest_install_rootfs

  [ "$status" -ne 0 ]
  ! grep -Fx 'proot-distro install ubuntu:24.04 --name tld-ubuntu' "$TLD_TEST_CALL_LOG"
}

@test "tld_guest_is_installed requires both the rootfs and manifest" {
  run tld_guest_is_installed
  [ "$status" -ne 0 ]

  mkdir -p "$TLD_TEST_ROOTFS_DIR"
  run tld_guest_is_installed
  [ "$status" -ne 0 ]

  printf '%s\n' manifest > "$TLD_TEST_MANIFEST_FILE"
  run tld_guest_is_installed
  [ "$status" -eq 0 ]
}

@test "tld_guest_install_rootfs does not reinstall an existing container" {
  make_installed_rootfs

  tld_guest_install_rootfs

  ! grep -Fx 'proot-distro install ubuntu:24.04 --name tld-ubuntu' "$TLD_TEST_CALL_LOG"
  [ "$TLD_GUEST_MANIFEST_SHA256" = "$(test_manifest_sha256)" ]
}

@test "tld_guest_install_rootfs fails when an existing rootfs has no manifest" {
  mkdir -p "$TLD_TEST_ROOTFS_DIR"

  run tld_guest_install_rootfs

  [ "$status" -ne 0 ]
  ! grep -Fx 'proot-distro install ubuntu:24.04 --name tld-ubuntu' "$TLD_TEST_CALL_LOG"
}

@test "tld_guest_install_rootfs fails when install leaves no rootfs" {
  export TLD_TEST_INSTALL_CREATE_ROOTFS=0

  run tld_guest_install_rootfs

  [ "$status" -ne 0 ]
  grep -Fx 'proot-distro install ubuntu:24.04 --name tld-ubuntu' "$TLD_TEST_CALL_LOG"
}

@test "tld_guest_install_rootfs uses the exact pinned install command" {
  run tld_guest_install_rootfs

  [ "$status" -eq 0 ]
  grep -Fx 'proot-distro install ubuntu:24.04 --name tld-ubuntu' "$TLD_TEST_CALL_LOG"
  [[ "$output" != *'ubuntu:latest'* ]]
}

@test "tld_guest_provision generates the pinned guest package and user setup" {
  run tld_guest_provision

  [ "$status" -eq 0 ]
  guest_command="$(<"$TLD_TEST_GUEST_COMMAND")"
  [[ "$guest_command" == *'DEBIAN_FRONTEND=noninteractive apt-get update'* ]]
  expected_install='DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates dbus-user-session dbus-x11 file iproute2 procps thunar xfce4-panel xfce4-session xfce4-terminal xfdesktop4 xfwm4 x11-xserver-utils'
  grep -Fx -- "$expected_install" "$TLD_TEST_GUEST_COMMAND"
  ! grep -F -- 'apt-get install --no-install-recommends' "$TLD_TEST_GUEST_COMMAND"
  [[ "$guest_command" == *'mkdir -p /home/tld'* ]]
  [[ "$guest_command" == *'id -u tld'* ]]
  [[ "$guest_command" == *'useradd --create-home --home-dir /home/tld --shell /bin/bash tld'* ]]
  [[ "$guest_command" == *'mkdir -p /home/tld/.config'* ]]
  [[ "$guest_command" == *'chown -R tld:tld /home/tld'* ]]
  [[ "$guest_command" != *'apt-get upgrade'* ]]
  [[ "$(<"$TLD_TEST_CALL_LOG")" == *'proot-distro login tld-ubuntu -- /bin/bash -lc'* ]]
}

@test "tld_guest_provision propagates a guest command failure" {
  export TLD_TEST_LOGIN_STATUS=23

  run tld_guest_provision

  [ "$status" -eq 23 ]
}

@test "tld_guest_run captures guest output in a host-owned log" {
  run tld_guest_run /bin/echo guest-command

  [ "$status" -eq 0 ]
  [[ "$(<"$TLD_LOG_DIR/guest.log")" == *guest-stdout* ]]
  [[ "$(<"$TLD_LOG_DIR/guest.log")" == *guest-stderr* ]]
}

@test "tld_guest_copy_launcher generates the required guest launcher" {
  run tld_guest_copy_launcher

  [ "$status" -eq 0 ]
  guest_command="$(<"$TLD_TEST_GUEST_COMMAND")"
  [[ "$guest_command" == *'install -d -m 0755 /usr/local/lib/termux-linux-desktop'* ]]
  [[ "$guest_command" == *'if ! cat > "$temporary"'* ]]
  [[ "$guest_command" == *'[[ ! -s "$temporary" ]]'* ]]
  [[ "$guest_command" == *'install -m 0755 "$temporary" "$copy_target"'* ]]
  [[ "$guest_command" == *'mv -f -- "$copy_target" "$target"'* ]]
  [[ "$guest_command" == *'/usr/local/lib/termux-linux-desktop/start-guest.sh'* ]]
  [[ "$guest_command" == *'#!/usr/bin/env bash'* ]]
  [[ "$guest_command" == *'export DISPLAY=${DISPLAY:-:0}'* ]]
  [[ "$guest_command" == *'export PULSE_SERVER=${PULSE_SERVER:-tcp:127.0.0.1:4713}'* ]]
  [[ "$guest_command" == *'command -v dbus-run-session'* ]]
  [[ "$guest_command" == *'command -v startxfce4'* ]]
  [[ "$guest_command" == *'command -v xfce4-session'* ]]
  [[ "$guest_command" == *'exec dbus-run-session -- startxfce4'* ]]
  [[ "$guest_command" != *'TLD_TEST'* ]]
  [[ "$guest_command" != *"$TLD_TEST_BIN"* ]]
}

@test "tld_guest_install_rootfs rejects a proot-distro version below the floor before install" {
  export TLD_TEST_PROOT_VERSION=5.4.9

  run tld_guest_install_rootfs

  [ "$status" -ne 0 ]
  ! grep -Fx 'proot-distro install ubuntu:24.04 --name tld-ubuntu' "$TLD_TEST_CALL_LOG"
}

@test "tld_guest_provision rejects a proot-distro version below the floor before login" {
  export TLD_TEST_PROOT_VERSION=5.4.9

  run tld_guest_provision

  [ "$status" -ne 0 ]
  ! grep -F 'proot-distro login' "$TLD_TEST_CALL_LOG"
}

@test "tld_guest_run passes shell metacharacters as argv data" {
  marker="$TLD_TEST_ROOT/metacharacter-marker"
  payload="literal; touch $marker"

  run tld_guest_run /bin/echo "$payload"

  [ "$status" -eq 0 ]
  grep -Fx -- "$payload" "$TLD_TEST_LOGIN_ARGS"
  ! grep -Fx -- '-lc' "$TLD_TEST_LOGIN_ARGS"
  [ ! -e "$marker" ]
}

@test "normal mode ignores rootfs, manifest, and log path overrides" {
  make_installed_rootfs
  export TLD_TEST_MODE=0
  export TLD_ROOTFS_DIR="$TLD_TEST_ROOT/outside-rootfs"
  export TLD_ROOTFS_MANIFEST_FILE="$TLD_TEST_ROOT/outside-manifest.json"
  export TLD_GUEST_LOG_FILE="$TLD_TEST_ROOT/outside-guest.log"

  tld_guest_is_installed
  tld_guest_run /bin/echo safe

  [ -s "$TLD_LOG_DIR/guest.log" ]
  [ ! -e "$TLD_GUEST_LOG_FILE" ]
}

@test "test-mode rootfs override rejects traversal" {
  export TLD_ROOTFS_DIR="$TLD_TEST_ROOT/../outside-rootfs"

  run tld_guest_is_installed

  [ "$status" -ne 0 ]
}

@test "test-mode rootfs override rejects out-of-tree paths" {
  outside="$BATS_TEST_TMPDIR-outside"
  mkdir -p "$outside"
  export TLD_ROOTFS_DIR="$outside/rootfs"

  run tld_guest_is_installed
  rm -rf -- "$outside"

  [ "$status" -ne 0 ]
}

@test "test-mode rootfs override rejects symlink components" {
  if ! ln -s "$TLD_TEST_ROOT" "$TLD_TEST_ROOT/symlink-root"; then
    skip 'symlink creation is unavailable'
  fi
  export TLD_ROOTFS_DIR="$TLD_TEST_ROOT/symlink-root/rootfs"

  run tld_guest_is_installed
  rm -f -- "$TLD_TEST_ROOT/symlink-root"

  [ "$status" -ne 0 ]
}

@test "test-mode manifest override rejects traversal and symlinks" {
  make_installed_rootfs
  export TLD_ROOTFS_MANIFEST_FILE="$TLD_TEST_ROOT/../outside-manifest.json"
  run tld_guest_is_installed
  [ "$status" -ne 0 ]

  if ! ln -s "$TLD_TEST_MANIFEST_FILE" "$TLD_TEST_ROOT/manifest-link.json"; then
    skip 'symlink creation is unavailable'
  fi
  export TLD_ROOTFS_MANIFEST_FILE="$TLD_TEST_ROOT/manifest-link.json"
  run tld_guest_is_installed
  rm -f -- "$TLD_TEST_ROOT/manifest-link.json"

  [ "$status" -ne 0 ]
}

@test "test-mode log override rejects traversal and symlinks" {
  export TLD_GUEST_LOG_FILE="$TLD_TEST_ROOT/../outside-guest.log"
  run tld_guest_run /bin/echo unsafe
  [ "$status" -ne 0 ]

  if ! ln -s "$TLD_LOG_DIR" "$TLD_TEST_ROOT/log-link"; then
    skip 'symlink creation is unavailable'
  fi
  export TLD_GUEST_LOG_FILE="$TLD_TEST_ROOT/log-link/guest.log"
  run tld_guest_run /bin/echo unsafe
  rm -f -- "$TLD_TEST_ROOT/log-link"

  [ "$status" -ne 0 ]
}

@test "tld_guest_copy_launcher rejects failed host launcher content reads" {
  printf '%s\n' '#!/usr/bin/env bash' 'exit 41' > "$TLD_TEST_BIN/cat"
  chmod +x "$TLD_TEST_BIN/cat"

  run tld_guest_copy_launcher
  rm -f -- "$TLD_TEST_BIN/cat"

  [ "$status" -eq 41 ]
  ! grep -F 'proot-distro login' "$TLD_TEST_CALL_LOG"
}

@test "tld_guest_copy_launcher rejects an empty generated launcher" {
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$TLD_TEST_BIN/cat"
  chmod +x "$TLD_TEST_BIN/cat"

  run tld_guest_copy_launcher
  rm -f -- "$TLD_TEST_BIN/cat"

  [ "$status" -ne 0 ]
  ! grep -F 'proot-distro login' "$TLD_TEST_CALL_LOG"
}

@test "guest launcher cat failure leaves the active launcher unchanged" {
  launcher_dir="$TLD_TEST_ROOT/launcher-root"
  launcher_path="$launcher_dir/start-guest.sh"
  mkdir -p "$launcher_dir"
  printf '%s\n' old-launcher > "$launcher_path"
  tld_guest_copy_launcher
  guest_command="$(<"$TLD_TEST_GUEST_COMMAND")"
  guest_command=${guest_command//\/usr\/local\/lib\/termux-linux-desktop/$launcher_dir}

  rm -f -- "$TLD_TEST_BIN/install"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 41' > "$TLD_TEST_BIN/cat"
  chmod +x "$TLD_TEST_BIN/cat"
  run bash -c "$guest_command"
  rm -f -- "$TLD_TEST_BIN/cat"

  [ "$status" -ne 0 ]
  [ "$(<"$launcher_path")" = old-launcher ]
}

@test "empty guest launcher cat leaves the active launcher unchanged" {
  launcher_dir="$TLD_TEST_ROOT/launcher-root"
  launcher_path="$launcher_dir/start-guest.sh"
  mkdir -p "$launcher_dir"
  printf '%s\n' old-launcher > "$launcher_path"
  tld_guest_copy_launcher
  guest_command="$(<"$TLD_TEST_GUEST_COMMAND")"
  guest_command=${guest_command//\/usr\/local\/lib\/termux-linux-desktop/$launcher_dir}

  rm -f -- "$TLD_TEST_BIN/install"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$TLD_TEST_BIN/cat"
  chmod +x "$TLD_TEST_BIN/cat"
  run bash -c "$guest_command"
  rm -f -- "$TLD_TEST_BIN/cat"

  [ "$status" -ne 0 ]
  [ "$(<"$launcher_path")" = old-launcher ]
}

@test "tld_guest_copy_launcher propagates guest copy failures" {
  export TLD_TEST_LOGIN_STATUS=19

  run tld_guest_copy_launcher

  [ "$status" -eq 19 ]
}

@test "guest functions run under strict mode" {
  run bash -c 'set -Eeuo pipefail; source "$TLD_LIB_DIR/tld-common.sh"; source "$TLD_LIB_DIR/tld-guest.sh"; tld_guest_install_rootfs; tld_guest_provision; tld_guest_copy_launcher'

  [ "$status" -eq 0 ]
}

@test "guest rootfs operations wait for the state lock" {
  lock_file="$TLD_STATE_DIR/guest.lock"
  held="$TLD_TEST_ROOT/lock-held"
  export TLD_TEST_LOCK_HELD="$held"
  (
    exec 9>"$lock_file"
    flock -x 9
    : > "$held"
    sleep 0.25
    rm -f -- "$held"
  ) &
  holder_pid=$!
  while [ ! -e "$held" ]; do
    sleep 0.01
  done

  run tld_guest_install_rootfs
  wait "$holder_pid"

  [ "$status" -eq 0 ]
  grep -Fx 'proot-distro install ubuntu:24.04 --name tld-ubuntu' "$TLD_TEST_CALL_LOG"
}

@test "guest provisioning waits for the state lock before login" {
  lock_file="$TLD_STATE_DIR/guest.lock"
  held="$TLD_TEST_ROOT/provision-lock-held"
  released="$TLD_TEST_ROOT/provision-lock-released"
  export TLD_TEST_LOCK_HELD="$held"
  export TLD_TEST_LOCK_RELEASED="$released"
  (
    exec 9>"$lock_file"
    flock -x 9
    : > "$held"
    sleep 0.25
    rm -f -- "$held"
    : > "$released"
  ) &
  holder_pid=$!
  while [ ! -e "$held" ]; do
    sleep 0.01
  done

  run tld_guest_provision
  wait "$holder_pid"

  [ "$status" -eq 0 ]
  [ -e "$released" ]
  [ ! -e "$held" ]
  ! grep -Fx 'provision-login-while-locked' "$TLD_TEST_CALL_LOG"
  grep -Fx 'provision-login-after-lock' "$TLD_TEST_CALL_LOG"
  [ "$(grep -F -c 'proot-distro login' "$TLD_TEST_CALL_LOG")" -eq 1 ]
}
