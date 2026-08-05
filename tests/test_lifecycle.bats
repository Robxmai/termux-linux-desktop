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
  export TLD_TEST_CALL_LOG="$TLD_TEST_ROOT/calls.log"
  export TLD_TEST_AUDIO_PID=4242
  export TLD_TEST_GUEST_PID=5252
  export TLD_TEST_AUDIO_TICKS=12345
  export TLD_TEST_GUEST_TICKS=9999
  export TLD_TEST_MODE=1
  export TLD_X11_SOCKET="$TLD_TEST_ROOT/x11.sock"
  export TLD_PROCESS_WAIT_SECONDS=1
  export TLD_PROCESS_KILL_WAIT_SECONDS=1

  unset TLD_X11_MODE TLD_AUDIO_OWNER TLD_START_GUEST_PID
  unset TLD_ROOTFS_DIR TLD_ROOTFS_MANIFEST_FILE TLD_GUEST_LOG_FILE TLD_ROOTFS_ENV_FILE

  mkdir -p "$HOME" "$PREFIX/bin" "$PREFIX/opt" "$TLD_STATE_DIR" "$TLD_LOG_DIR" "$TLD_CONFIG_DIR" "$TLD_TEST_BIN" "$TLD_PROC_ROOT"
  : > "$TLD_TEST_CALL_LOG"

  export TLD_REAL_PATH="$PATH"
  export TLD_REAL_SHA256SUM="$(PATH="$TLD_REAL_PATH" command -v sha256sum)"
  export PATH="$TLD_TEST_BIN:$TLD_REAL_PATH"

  export TLD_TEST_ROOTFS_DIR="$PREFIX/var/lib/proot-distro/containers/tld-ubuntu/rootfs"
  export TLD_TEST_MANIFEST_FILE="$PREFIX/var/lib/proot-distro/containers/tld-ubuntu/manifest.json"
  mkdir -p "$TLD_TEST_ROOTFS_DIR/usr/local/lib/termux-linux-desktop"
  printf '%s\n' '{"architecture":"arm64"}' > "$TLD_TEST_MANIFEST_FILE"
  printf '%s\n' '#!/usr/bin/env bash' > "$TLD_TEST_ROOTFS_DIR/usr/local/lib/termux-linux-desktop/start-guest.sh"
  chmod +x "$TLD_TEST_ROOTFS_DIR/usr/local/lib/termux-linux-desktop/start-guest.sh"

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
    'set -Eeuo pipefail' \
    'printf "pulseaudio %s\\n" "$*" >> "${TLD_TEST_CALL_LOG:?}"' \
    ': > "${TLD_TEST_ROOT:?}/audio-started"' \
    ': > "${TLD_TEST_ROOT:?}/audio-ready"' \
    'exit 0' \
    > "$TLD_TEST_BIN/pulseaudio"

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -Eeuo pipefail' \
    'printf "pgrep %s\\n" "$*" >> "${TLD_TEST_CALL_LOG:?}"' \
    'case "$1" in' \
    '  -x)' \
    '    case "$2" in' \
    '      pulseaudio)' \
    '        if [[ -f "${TLD_TEST_ROOT:?}/audio-started" ]]; then printf "%s\\n" "${TLD_TEST_AUDIO_PID:?}"; exit 0; fi ;;' \
    '      xfce4-session|xfwm4|xfdesktop|xfce4-panel)' \
    '        if [[ -f "${TLD_TEST_ROOT:?}/xfce-ready" ]]; then printf "%s\\n" "${TLD_TEST_GUEST_PID:?}"; exit 0; fi ;;' \
    '    esac' \
    '    ;;' \
    '  -f)' \
    '    if [[ -f "${TLD_TEST_ROOT:?}/guest-started" ]]; then printf "%s\\n" "${TLD_TEST_GUEST_PID:?}"; exit 0; fi' \
    '    ;;' \
    'esac' \
    'exit 1' \
    > "$TLD_TEST_BIN/pgrep"

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -Eeuo pipefail' \
    'printf "proot-distro %s\\n" "$*" >> "${TLD_TEST_CALL_LOG:?}"' \
    ': > "${TLD_TEST_ROOT:?}/guest-started"' \
    'exit 0' \
    > "$TLD_TEST_BIN/proot-distro"

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "sleep %s\\n" "$*" >> "${TLD_TEST_CALL_LOG:?}"' \
    'exit 0' \
    > "$TLD_TEST_BIN/sleep"

  kill() {
    if [[ "${TLD_TEST_MODE:-0}" != 1 ]]; then
      command kill "$@"
      return $?
    fi
    if [[ -n ${TLD_TEST_CALL_LOG:-} ]]; then
      printf 'kill %s\n' "$*" >> "$TLD_TEST_CALL_LOG"
    fi
    if [[ "${TLD_TEST_KILL_FAILS:-0}" == 1 ]]; then
      return 1
    fi
    if [[ "${TLD_TEST_KILL_REMOVES:-0}" == 1 ]]; then
      rm -rf -- "${TLD_PROC_ROOT:?}/${2:?}"
      rm -f -- "${TLD_TEST_ROOT:?}/guest-started" "${TLD_TEST_ROOT:?}/xfce-ready"
    fi
    return 0
  }
  export -f kill

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "uname\\n" >> "${TLD_TEST_CALL_LOG:?}"' \
    'printf "%s\\n" "aarch64"' \
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

  chmod +x "$TLD_TEST_BIN"/*
}

_tld_make_proc_entry() {
  local pid="$1"
  local ticks="$2"
  local comm="$3"

  mkdir -p "$TLD_PROC_ROOT/$pid"
  printf '%s (%s) R 1 1 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 %s\n' "$pid" "$comm" "$ticks" > "$TLD_PROC_ROOT/$pid/stat"
  printf '/usr/bin/%s\0--flag\0' "$comm" > "$TLD_PROC_ROOT/$pid/cmdline"
}

_tld_record_desktop() {
  local hash

  hash=$(tr '\0' '\n' < "$TLD_PROC_ROOT/$TLD_TEST_GUEST_PID/cmdline" | sha256sum | awk '{print $1}')
  mkdir -p "$TLD_STATE_DIR/processes"
  printf 'ROLE=desktop\nPID=%s\nSTART_TICKS=%s\nCOMMAND_HASH=%s\n' \
    "$TLD_TEST_GUEST_PID" "$TLD_TEST_GUEST_TICKS" "$hash" > "$TLD_STATE_DIR/processes/desktop.env"
}

_tld_make_x11_socket() {
  python3 - "$TLD_X11_SOCKET" <<'PY'
import socket, sys
s = socket.socket(socket.AF_UNIX)
s.bind(sys.argv[1])
PY
}

@test "start fails when the toolkit is not installed" {
  run bash "$BATS_TEST_DIRNAME/../bin/desktop-start"

  [ "$status" -ne 0 ]
  [[ "$output" == *"not installed"* ]]
  if [[ -f "$TLD_TEST_CALL_LOG" ]]; then
    grep -q '^proot-distro ' "$TLD_TEST_CALL_LOG" && return 1 || true
  fi
}

@test "start fails when the X11 socket is missing" {
  printf 'manifest=1\n' > "$TLD_INSTANCE_FILE"
  export TLD_X11_SOCKET="$TLD_TEST_ROOT/missing.sock"

  run bash "$BATS_TEST_DIRNAME/../bin/desktop-start"

  [ "$status" -ne 0 ]
  [[ "$output" == *"X11 socket"* ]]
  grep -q '^proot-distro ' "$TLD_TEST_CALL_LOG" && return 1 || true
  [ -f "$TLD_STATE_DIR/start.result" ]
  grep -q '^result=failure$' "$TLD_STATE_DIR/start.result"
}

@test "start launches one guest session and writes a success result" {
  printf 'manifest=1\n' > "$TLD_INSTANCE_FILE"
  _tld_make_x11_socket
  : > "$TLD_TEST_ROOT/audio-ready"
  : > "$TLD_TEST_ROOT/xfce-ready"
  _tld_make_proc_entry "$TLD_TEST_GUEST_PID" "$TLD_TEST_GUEST_TICKS" start-guest.sh

  run bash "$BATS_TEST_DIRNAME/../bin/desktop-start"

  [ "$status" -eq 0 ]
  [[ "$output" == *"XFCE components detected"* ]]
  grep -q '^proot-distro login tld-ubuntu --user tld --shared-tmp --shared-x11 --detach -- /usr/local/lib/termux-linux-desktop/start-guest.sh$' "$TLD_TEST_CALL_LOG"
  [ -f "$TLD_STATE_DIR/processes/desktop.env" ]
  grep -q '^result=success$' "$TLD_STATE_DIR/start.result"
}

@test "a second start reuses the owned session and does not duplicate it" {
  printf 'manifest=1\n' > "$TLD_INSTANCE_FILE"
  _tld_make_x11_socket
  : > "$TLD_TEST_ROOT/audio-ready"
  : > "$TLD_TEST_ROOT/xfce-ready"
  _tld_make_proc_entry "$TLD_TEST_GUEST_PID" "$TLD_TEST_GUEST_TICKS" start-guest.sh
  _tld_record_desktop

  run bash "$BATS_TEST_DIRNAME/../bin/desktop-start"

  [ "$status" -eq 0 ]
  [[ "$output" == *"reused"* ]]
  grep -q '^proot-distro ' "$TLD_TEST_CALL_LOG" && return 1 || true
}

@test "status prints the exact headings and succeeds for a healthy instance" {
  printf 'created_at=2026-08-03T00:00:00Z\n' > "$TLD_INSTANCE_FILE"
  _tld_make_x11_socket
  : > "$TLD_TEST_ROOT/audio-ready"
  _tld_make_proc_entry "$TLD_TEST_GUEST_PID" "$TLD_TEST_GUEST_TICKS" start-guest.sh
  _tld_record_desktop

  run bash "$BATS_TEST_DIRNAME/../bin/desktop-status"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Toolkit: 0.1.0"* ]]
  [[ "$output" == *"Instance: "* ]]
  [[ "$output" == *"Rootfs: PASS"* ]]
  [[ "$output" == *"Display: PASS"* ]]
  [[ "$output" == *"Audio: PASS"* ]]
  [[ "$output" == *"Guest: PASS"* ]]
  [[ "$output" == *"Owned processes: "* ]]
  [[ "$output" == *"Profile: base"* ]]
}

@test "status returns nonzero for a stopped guest" {
  printf 'created_at=2026-08-03T00:00:00Z\n' > "$TLD_INSTANCE_FILE"
  _tld_make_x11_socket
  : > "$TLD_TEST_ROOT/audio-ready"

  run bash "$BATS_TEST_DIRNAME/../bin/desktop-status"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Guest: STOPPED"* ]]
}

@test "stop verifies owned processes, leaves external audio, and writes stop result" {
  printf 'manifest=1\n' > "$TLD_INSTANCE_FILE"
  : > "$TLD_TEST_ROOT/audio-ready"
  printf 'AUDIO_OWNER=external\n' > "$TLD_STATE_DIR/audio-owner.env"
  _tld_make_proc_entry "$TLD_TEST_GUEST_PID" "$TLD_TEST_GUEST_TICKS" start-guest.sh
  _tld_record_desktop
  export TLD_TEST_KILL_REMOVES=1

  run bash "$BATS_TEST_DIRNAME/../bin/desktop-stop"

  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS stop"* ]]
  grep -q '^kill -TERM ' "$TLD_TEST_CALL_LOG"
  [ ! -f "$TLD_STATE_DIR/processes/desktop.env" ]
  grep -q '^result=success$' "$TLD_STATE_DIR/stop.result"
  grep -q '^remaining_owned=0$' "$TLD_STATE_DIR/stop.result"
}

@test "stop succeeds when nothing is owned" {
  printf 'manifest=1\n' > "$TLD_INSTANCE_FILE"
  : > "$TLD_TEST_ROOT/audio-ready"

  run bash "$BATS_TEST_DIRNAME/../bin/desktop-stop"

  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS stop"* ]]
  grep -q '^result=success$' "$TLD_STATE_DIR/stop.result"
  grep -q '^remaining_owned=0$' "$TLD_STATE_DIR/stop.result"
}

@test "stop returns nonzero when an owned process cannot be verified stopped" {
  printf 'manifest=1\n' > "$TLD_INSTANCE_FILE"
  : > "$TLD_TEST_ROOT/audio-ready"
  printf 'AUDIO_OWNER=external\n' > "$TLD_STATE_DIR/audio-owner.env"
  _tld_make_proc_entry "$TLD_TEST_GUEST_PID" "$TLD_TEST_GUEST_TICKS" start-guest.sh
  _tld_record_desktop
  export TLD_TEST_KILL_FAILS=1

  run bash "$BATS_TEST_DIRNAME/../bin/desktop-stop"

  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL stop"* ]]
  grep -q '^result=failure$' "$TLD_STATE_DIR/stop.result"
}
