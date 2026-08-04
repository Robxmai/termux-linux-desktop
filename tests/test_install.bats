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
  export TLD_TEST_BIN="$TLD_TEST_ROOT/bin"
  export TLD_TEST_CALL_LOG="$TLD_TEST_ROOT/calls.log"
  export TLD_TEST_PKG_LOG="$TLD_TEST_ROOT/pkg.log"
  export TLD_TEST_PROOT_STUB="$TLD_TEST_ROOT/proot-distro.stub"
  export TLD_TEST_PACTL_STUB="$TLD_TEST_ROOT/pactl.stub"
  export TLD_TEST_ARCH=aarch64
  export TLD_TEST_PROOT_VERSION=5.5.0
  export TLD_TEST_INSTALL_STATUS=0
  export TLD_TEST_LOGIN_STATUS=0
  export TLD_TEST_MANIFEST_SHA256=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
  export TLD_REPO_ROOT="$BATS_TEST_DIRNAME/.."
  export TLD_INSTALLER="$TLD_REPO_ROOT/bin/install-toolkit"
  export TLD_OTHER_DIR="$TLD_TEST_ROOT/other"

  unset TLD_TEST_MODE TLD_TEST_ROOTFS_DIR TLD_ROOTFS_DIR TLD_ROOTFS_MANIFEST_FILE
  unset TLD_GUEST_LOG_FILE TLD_ROOTFS_ENV_FILE TLD_X11_SOCKET TLD_X11_MODE TLD_STORAGE_PATH
  unset TLD_TEST_STAGE_LOG TLD_TEST_PKG_STATUS TLD_TEST_GUEST_COMMAND_STATUS TLD_TEST_LOCK_HELD

  mkdir -p "$HOME" "$PREFIX/bin" "$PREFIX/opt" "$TLD_STATE_DIR" "$TLD_LOG_DIR" "$TLD_CONFIG_DIR" "$TLD_TEST_BIN" "$TLD_OTHER_DIR"
  : > "$TLD_TEST_CALL_LOG"
  : > "$TLD_TEST_PKG_LOG"

  export TLD_REAL_PATH="$PATH"
  export PATH="$TLD_TEST_BIN:$TLD_REAL_PATH"

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -Eeuo pipefail' \
    'printf "proot-distro" >> "${TLD_TEST_CALL_LOG:?}"' \
    'printf " %s" "$@" >> "${TLD_TEST_CALL_LOG:?}"' \
    'printf "\\n" >> "${TLD_TEST_CALL_LOG:?}"' \
    'case "${1-}" in' \
    '  --version)' \
    '    printf "%s\\n" "${TLD_TEST_PROOT_VERSION:?}"' \
    '    ;;' \
    '  install)' \
    '    mkdir -p "${TLD_TEST_ROOTFS_DIR:?}"' \
    '    printf "%s\\n" manifest > "${TLD_TEST_MANIFEST_FILE:?}"' \
    '    exit "${TLD_TEST_INSTALL_STATUS:-0}"' \
    '    ;;' \
    '  login)' \
    '    exit "${TLD_TEST_LOGIN_STATUS:-0}"' \
    '    ;;' \
    'esac' \
    > "$TLD_TEST_PROOT_STUB"

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -Eeuo pipefail' \
    'printf "pactl %s\\n" "$*" >> "${TLD_TEST_CALL_LOG:?}"' \
    'exit 0' \
    > "$TLD_TEST_PACTL_STUB"

  cp -- "$TLD_TEST_PROOT_STUB" "$TLD_TEST_BIN/proot-distro"
  cp -- "$TLD_TEST_PACTL_STUB" "$TLD_TEST_BIN/pactl"

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -Eeuo pipefail' \
    'printf "pkg %s\\n" "$*" >> "${TLD_TEST_PKG_LOG:?}"' \
    'if [[ "$*" == "install -y proot-distro pulseaudio" ]]; then' \
    '  cp -- "${TLD_TEST_PROOT_STUB:?}" "${TLD_TEST_BIN:?}/proot-distro"' \
    '  cp -- "${TLD_TEST_PACTL_STUB:?}" "${TLD_TEST_BIN:?}/pactl"' \
    '  chmod +x "${TLD_TEST_BIN:?}/proot-distro" "${TLD_TEST_BIN:?}/pactl"' \
    'fi' \
    'exit "${TLD_TEST_PKG_STATUS:-0}"' \
    > "$TLD_TEST_BIN/pkg"

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "%s\\n" "${TLD_TEST_ARCH:?}"' \
    > "$TLD_TEST_BIN/uname"

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "%s  %s\\n" "${TLD_TEST_MANIFEST_SHA256:?}" "${1:?}"' \
    > "$TLD_TEST_BIN/sha256sum"

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'exit 0' \
    > "$TLD_TEST_BIN/flock"

  chmod +x "$TLD_TEST_BIN"/* "$TLD_TEST_PROOT_STUB" "$TLD_TEST_PACTL_STUB"

  export TLD_TEST_ROOTFS_DIR="$PREFIX/var/lib/proot-distro/containers/tld-ubuntu/rootfs"
  export TLD_TEST_MANIFEST_FILE="$PREFIX/var/lib/proot-distro/containers/tld-ubuntu/manifest.json"
  export TLD_TEST_ROOTFS_ENV_FILE="$TLD_TEST_ROOT/ubuntu.env"
  printf '%s\n' \
    "TLD_ROOTFS_IMAGE='ubuntu:24.04'" \
    "TLD_ROOTFS_CONTAINER='tld-ubuntu'" \
    "TLD_ROOTFS_ARCH='aarch64'" \
    "TLD_ROOTFS_MIN_PROOT_DISTRO='5.5.0'" \
    "TLD_GUEST_USER='tld'" \
    > "$TLD_TEST_ROOTFS_ENV_FILE"
}

teardown() {
  rm -f -- \
    "$TLD_REPO_ROOT/rootfs/private.secret" \
    "$TLD_REPO_ROOT/rootfs/example.rootfs" \
    "$TLD_REPO_ROOT/rootfs/example.log"
  rm -r -- \
    "$TLD_REPO_ROOT/rootfs/test-output" \
    "$TLD_REPO_ROOT/rootfs/game-data" \
    2>/dev/null || true
}

run_toolkit_install() {
  run bash -c 'cd "$TLD_OTHER_DIR" && bash "$TLD_INSTALLER"'
}

prepare_desktop_test() {
  export TLD_TEST_MODE=1
  export TLD_TEST_ROOT="$TLD_TEST_ROOT"
  export TLD_ROOTFS_ENV_FILE="$TLD_TEST_ROOTFS_ENV_FILE"
  export TLD_ROOTFS_DIR="$TLD_TEST_ROOTFS_DIR"
  export TLD_ROOTFS_MANIFEST_FILE="$TLD_TEST_MANIFEST_FILE"
  export TLD_GUEST_LOG_FILE="$TLD_LOG_DIR/guest.log"
}

@test "install-toolkit fails for missing pkg before mutating state" {
  rm -f -- "$TLD_TEST_BIN/pkg"

  run_toolkit_install

  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL command=pkg"* ]]
  [ ! -e "$PREFIX/opt/termux-linux-desktop" ]
  [ ! -e "$PREFIX/bin/desktop-install" ]
  [ ! -e "$PREFIX/var" ]
}

@test "install-toolkit rejects a non-aarch64 host before staging" {
  export TLD_TEST_ARCH=x86_64

  run_toolkit_install

  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL architecture=x86_64"* ]]
  [ ! -e "$PREFIX/opt/termux-linux-desktop" ]
}

@test "desktop-install rejects a non-aarch64 host before rootfs installation" {
  run_toolkit_install
  [ "$status" -eq 0 ]
  prepare_desktop_test
  export TLD_TEST_ARCH=x86_64

  run bash "$PREFIX/bin/desktop-install"

  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL architecture=x86_64"* ]]
  ! grep -F 'proot-distro install ubuntu:24.04 --name tld-ubuntu' "$TLD_TEST_CALL_LOG"
  [ ! -e "$TLD_INSTANCE_FILE" ]
}

@test "desktop-install calls guest stages in order" {
  export TLD_TEST_MODE=1
  export TLD_TEST_STAGE_LOG="$TLD_TEST_ROOT/stages.log"
  : > "$TLD_TEST_STAGE_LOG"

  run bash -c '
    source "$TLD_REPO_ROOT/bin/desktop-install"
    tld_guest_install_rootfs() {
      printf "%s\\n" rootfs >> "$TLD_TEST_STAGE_LOG"
      TLD_ROOTFS_IMAGE=ubuntu:24.04
      TLD_ROOTFS_CONTAINER=tld-ubuntu
      TLD_GUEST_ROOTFS_MANIFEST_SHA256="$TLD_TEST_MANIFEST_SHA256"
    }
    tld_guest_provision() {
      printf "%s\\n" guest-provision >> "$TLD_TEST_STAGE_LOG"
    }
    tld_guest_copy_launcher() {
      printf "%s\\n" guest-launcher >> "$TLD_TEST_STAGE_LOG"
    }
    tld_install_main
  '

  [ "$status" -eq 0 ]
  mapfile -t stages < "$TLD_TEST_STAGE_LOG"
  [ "${stages[*]}" = 'rootfs guest-provision guest-launcher' ]
}

@test "desktop-install runs the exact package command once" {
  run_toolkit_install
  [ "$status" -eq 0 ]
  rm -f -- "$TLD_TEST_BIN/proot-distro" "$TLD_TEST_BIN/pactl"
  prepare_desktop_test

  run bash "$PREFIX/bin/desktop-install"

  [ "$status" -eq 0 ]
  [ "$(grep -F -c 'pkg install -y proot-distro pulseaudio' "$TLD_TEST_PKG_LOG")" -eq 1 ]
  [[ "$(<"$TLD_TEST_CALL_LOG")" != *'pkg upgrade'* ]]
  [[ "$(<"$TLD_TEST_CALL_LOG")" != *'x11-repo'* ]]
}

@test "desktop-install does not reinstall an existing rootfs" {
  run_toolkit_install
  [ "$status" -eq 0 ]
  prepare_desktop_test
  mkdir -p "$TLD_TEST_ROOTFS_DIR"
  printf '%s\n' manifest > "$TLD_TEST_MANIFEST_FILE"

  run bash "$PREFIX/bin/desktop-install"

  [ "$status" -eq 0 ]
  ! grep -F 'proot-distro install ubuntu:24.04 --name tld-ubuntu' "$TLD_TEST_CALL_LOG"
}

@test "failed guest provisioning writes failure state without success manifest" {
  run_toolkit_install
  [ "$status" -eq 0 ]
  prepare_desktop_test
  export TLD_TEST_LOGIN_STATUS=23

  run bash "$PREFIX/bin/desktop-install"

  [ "$status" -eq 23 ]
  [ ! -e "$TLD_INSTANCE_FILE" ]
  [ -f "$TLD_STATE_DIR/install.result" ]
  grep -Fx 'result=failure' "$TLD_STATE_DIR/install.result"
  grep -Fx 'stage=guest-provision' "$TLD_STATE_DIR/install.result"
  grep -F 'guest-provision' "$TLD_LOG_DIR/desktop.log"
}

@test "successful install writes the manifest and exact toolkit symlink" {
  run_toolkit_install
  [ "$status" -eq 0 ]
  prepare_desktop_test

  run bash "$PREFIX/bin/desktop-install"

  [ "$status" -eq 0 ]
  [ -f "$TLD_INSTANCE_FILE" ]
  grep -Fx 'toolkit_version=0.1.0' "$TLD_INSTANCE_FILE"
  grep -Fx 'architecture=aarch64' "$TLD_INSTANCE_FILE"
  grep -Fx 'rootfs_image=ubuntu:24.04' "$TLD_INSTANCE_FILE"
  grep -Fx 'rootfs_container=tld-ubuntu' "$TLD_INSTANCE_FILE"
  grep -Fx 'profile=base' "$TLD_INSTANCE_FILE"
  grep -Fx "rootfs_manifest_sha256=$TLD_TEST_MANIFEST_SHA256" "$TLD_INSTANCE_FILE"
  grep -Eq '^created_at=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$TLD_INSTANCE_FILE"
  [ -L "$PREFIX/bin/desktop-install" ]
  [ "$(readlink "$PREFIX/bin/desktop-install")" = "$PREFIX/opt/termux-linux-desktop/bin/desktop-install" ]
  [ ! -e "$PREFIX/bin/install-toolkit" ]
  [[ "$output" == *'Termux:X11'* ]]
  [[ "$output" != *'desktop is ready'* ]]
}

@test "install-toolkit refuses a non-toolkit collision" {
  printf '%s\n' user-file > "$PREFIX/bin/desktop-install"

  run_toolkit_install

  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing to overwrite"* ]]
  [ "$(<"$PREFIX/bin/desktop-install")" = user-file ]
  [ ! -e "$PREFIX/opt/termux-linux-desktop" ]
}

@test "repeated toolkit and desktop installs remain idempotent" {
  run_toolkit_install
  [ "$status" -eq 0 ]
  run_toolkit_install
  [ "$status" -eq 0 ]
  prepare_desktop_test
  rm -f -- "$TLD_TEST_BIN/proot-distro" "$TLD_TEST_BIN/pactl"

  run bash "$PREFIX/bin/desktop-install"
  [ "$status" -eq 0 ]
  run bash "$PREFIX/bin/desktop-install"

  [ "$status" -eq 0 ]
  [ "$(grep -F -c 'pkg install -y proot-distro pulseaudio' "$TLD_TEST_PKG_LOG")" -eq 1 ]
  [ "$(grep -F -c 'proot-distro install ubuntu:24.04 --name tld-ubuntu' "$TLD_TEST_CALL_LOG")" -eq 1 ]
  [ "$(readlink "$PREFIX/bin/desktop-install")" = "$PREFIX/opt/termux-linux-desktop/bin/desktop-install" ]
}

@test "staging is cleaned and private artifacts are not copied" {
  printf '%s\n' secret > "$TLD_REPO_ROOT/rootfs/private.secret"
  printf '%s\n' archive > "$TLD_REPO_ROOT/rootfs/example.rootfs"
  printf '%s\n' log > "$TLD_REPO_ROOT/rootfs/example.log"
  mkdir -p "$TLD_REPO_ROOT/rootfs/test-output" "$TLD_REPO_ROOT/rootfs/game-data"
  printf '%s\n' test-output > "$TLD_REPO_ROOT/rootfs/test-output/result.txt"
  printf '%s\n' game > "$TLD_REPO_ROOT/rootfs/game-data/save.dat"

  run_toolkit_install

  [ "$status" -eq 0 ]
  [ ! -e "$PREFIX/opt/termux-linux-desktop/rootfs/private.secret" ]
  [ ! -e "$PREFIX/opt/termux-linux-desktop/rootfs/example.rootfs" ]
  [ ! -e "$PREFIX/opt/termux-linux-desktop/rootfs/example.log" ]
  [ ! -e "$PREFIX/opt/termux-linux-desktop/rootfs/test-output" ]
  [ ! -e "$PREFIX/opt/termux-linux-desktop/rootfs/game-data" ]
  ! compgen -G "$PREFIX/opt/.termux-linux-desktop.stage.*" >/dev/null
  ! compgen -G "$PREFIX/opt/.termux-linux-desktop.old.*" >/dev/null
  [ ! -e "$PREFIX/opt/termux-linux-desktop/tests" ]
}
