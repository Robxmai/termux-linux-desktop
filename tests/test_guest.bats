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
  export TLD_ROOTFS_ENV_FILE="$BATS_TEST_TMPDIR/ubuntu.env"
  export TLD_ROOTFS_DIR="$BATS_TEST_TMPDIR/rootfs/tld-ubuntu"
  export TLD_TEST_BIN="$BATS_TEST_TMPDIR/bin"
  export TLD_TEST_CALL_LOG="$BATS_TEST_TMPDIR/calls.log"
  export TLD_TEST_GUEST_COMMAND="$BATS_TEST_TMPDIR/guest-command"
  export TLD_TEST_ARCH=aarch64
  export TLD_TEST_INSTALL_STATUS=0
  export TLD_TEST_INSTALL_CREATE_ROOTFS=1
  export TLD_TEST_INSTALL_CREATE_MANIFEST=1
  export TLD_TEST_LOGIN_STATUS=0
  export TLD_TEST_MANIFEST_SHA256=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
  export PATH="$TLD_TEST_BIN:$BATS_TEST_DIRNAME/helpers/fake-termux/bin:$PATH"

  mkdir -p "$HOME" "$PREFIX" "$TLD_STATE_DIR" "$TLD_LOG_DIR" "$TLD_CONFIG_DIR" "$TLD_TEST_BIN"
  : > "$TLD_TEST_CALL_LOG"

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -Eeuo pipefail' \
    '{ printf "proot-distro"; printf " %s" "$@"; printf "\n"; } >> "$TLD_TEST_CALL_LOG"' \
    'case "${1-}" in' \
    '  install)' \
    '    if [[ "${TLD_TEST_INSTALL_CREATE_ROOTFS:-1}" == 1 ]]; then' \
    '      mkdir -p "$TLD_ROOTFS_DIR"' \
    '      if [[ "${TLD_TEST_INSTALL_CREATE_MANIFEST:-1}" == 1 ]]; then' \
    '        printf "%s\\n" manifest > "$TLD_ROOTFS_DIR/manifest.json"' \
    '      fi' \
    '    fi' \
    '    exit "${TLD_TEST_INSTALL_STATUS:-0}"' \
    '    ;;' \
    '  login)' \
    '    command="${!#}"' \
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
    'printf "%s  %s\n" "${TLD_TEST_MANIFEST_SHA256:?}" "${1:?}"' > "$TLD_TEST_BIN/sha256sum"

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
  if [[ -f "$TLD_LIB_DIR/tld-guest.sh" ]]; then
    source "$TLD_LIB_DIR/tld-guest.sh"
  fi
}

make_installed_rootfs() {
  mkdir -p "$TLD_ROOTFS_DIR"
  printf '%s\n' manifest > "$TLD_ROOTFS_DIR/manifest.json"
}

@test "tld_guest_install_rootfs validates the pinned rootfs assignments" {
  tld_guest_install_rootfs

  [ "$TLD_ROOTFS_IMAGE" = 'ubuntu:24.04' ]
  [ "$TLD_ROOTFS_CONTAINER" = 'tld-ubuntu' ]
  [ "$TLD_ROOTFS_ARCH" = 'aarch64' ]
  [ "$TLD_ROOTFS_MIN_PROOT_DISTRO" = '5.5.0' ]
  [ "$TLD_GUEST_USER" = 'tld' ]
  [ "$TLD_GUEST_MANIFEST_SHA256" = "$TLD_TEST_MANIFEST_SHA256" ]
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
  [ ! -s "$TLD_TEST_CALL_LOG" ]
}

@test "tld_guest_is_installed requires both the rootfs and manifest" {
  run tld_guest_is_installed
  [ "$status" -ne 0 ]

  mkdir -p "$TLD_ROOTFS_DIR"
  run tld_guest_is_installed
  [ "$status" -ne 0 ]

  printf '%s\n' manifest > "$TLD_ROOTFS_DIR/manifest.json"
  run tld_guest_is_installed
  [ "$status" -eq 0 ]
}

@test "tld_guest_install_rootfs does not reinstall an existing container" {
  make_installed_rootfs

  tld_guest_install_rootfs

  [ ! -s "$TLD_TEST_CALL_LOG" ]
  [ "$TLD_GUEST_MANIFEST_SHA256" = "$TLD_TEST_MANIFEST_SHA256" ]
}

@test "tld_guest_install_rootfs fails when an existing rootfs has no manifest" {
  mkdir -p "$TLD_ROOTFS_DIR"

  run tld_guest_install_rootfs

  [ "$status" -ne 0 ]
  [ ! -s "$TLD_TEST_CALL_LOG" ]
}

@test "tld_guest_install_rootfs fails when install leaves no rootfs" {
  export TLD_TEST_INSTALL_CREATE_ROOTFS=0

  run tld_guest_install_rootfs

  [ "$status" -ne 0 ]
  [ "$(<"$TLD_TEST_CALL_LOG")" = 'proot-distro install ubuntu:24.04 --name tld-ubuntu' ]
}

@test "tld_guest_install_rootfs uses the exact pinned install command" {
  run tld_guest_install_rootfs

  [ "$status" -eq 0 ]
  [ "$(<"$TLD_TEST_CALL_LOG")" = 'proot-distro install ubuntu:24.04 --name tld-ubuntu' ]
  [[ "$output" != *'ubuntu:latest'* ]]
}

@test "tld_guest_provision generates the pinned guest package and user setup" {
  run tld_guest_provision

  [ "$status" -eq 0 ]
  guest_command="$(<"$TLD_TEST_GUEST_COMMAND")"
  [[ "$guest_command" == *'DEBIAN_FRONTEND=noninteractive apt-get update'* ]]
  [[ "$guest_command" == *'apt-get install --no-install-recommends ca-certificates dbus-user-session dbus-x11 file iproute2 procps thunar xfce4-panel xfce4-session xfce4-terminal xfdesktop4 xfwm4 x11-xserver-utils'* ]]
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
  run tld_guest_run 'printf guest-command'

  [ "$status" -eq 0 ]
  [[ "$(<"$TLD_LOG_DIR/guest.log")" == *guest-stdout* ]]
  [[ "$(<"$TLD_LOG_DIR/guest.log")" == *guest-stderr* ]]
}

@test "tld_guest_copy_launcher generates the required guest launcher" {
  run tld_guest_copy_launcher

  [ "$status" -eq 0 ]
  guest_command="$(<"$TLD_TEST_GUEST_COMMAND")"
  [[ "$guest_command" == *'install -D -m 0755 /dev/stdin /usr/local/lib/termux-linux-desktop/start-guest.sh'* ]]
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
