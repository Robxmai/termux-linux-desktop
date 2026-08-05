#!/usr/bin/env bats

setup() {
  export TLD_TEST_ROOT="$BATS_TEST_TMPDIR/tld"
  export HOME="$TLD_TEST_ROOT/home"
  export PREFIX="$TLD_TEST_ROOT/prefix"
  export TLD_STATE_DIR="$TLD_TEST_ROOT/state"
  export TLD_LOG_DIR="$TLD_TEST_ROOT/log"
  export TLD_CONFIG_DIR="$TLD_TEST_ROOT/config"
  export TLD_LIB_DIR="$BATS_TEST_DIRNAME/../lib"
  export TLD_PROC_ROOT="$TLD_TEST_ROOT/proc"
  export TLD_TEST_BIN="$TLD_TEST_ROOT/bin"
  export TLD_TEST_CALL_LOG="$TLD_TEST_ROOT/calls.log"
  export TLD_TEST_AUDIO_PID=4242
  export TLD_TEST_START_TICKS=12345
  export PULSE_SERVER_DEFAULT='tcp:127.0.0.1:4713'
  export PULSE_SINK_DEFAULT='AAudio_sink'

  export TLD_TEST_MODE=1
  unset TLD_X11_SOCKET TLD_X11_MODE
  unset TLD_AUDIO_OWNER TLD_AUDIO_READY_ENDPOINT

  mkdir -p "$HOME" "$PREFIX/bin" "$TLD_STATE_DIR" "$TLD_LOG_DIR" "$TLD_CONFIG_DIR" "$TLD_TEST_BIN" "$TLD_PROC_ROOT"
  : > "$TLD_TEST_CALL_LOG"

  export TLD_REAL_PATH="$PATH"
  export TLD_REAL_SHA256SUM="$(PATH="$TLD_REAL_PATH" command -v sha256sum)"
  export PATH="$TLD_TEST_BIN:$TLD_REAL_PATH"

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
    'if [[ "${TLD_TEST_AUDIO_NEVER_READY:-0}" != 1 ]]; then' \
    '  : > "${TLD_TEST_ROOT:?}/audio-ready"' \
    'fi' \
    ': > "${TLD_TEST_ROOT:?}/audio-started"' \
    'exit 0' \
    > "$TLD_TEST_BIN/pulseaudio"

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -Eeuo pipefail' \
    'printf "pgrep %s\\n" "$*" >> "${TLD_TEST_CALL_LOG:?}"' \
    'if [[ -f "${TLD_TEST_ROOT:?}/audio-started" ]]; then' \
    '  printf "%s\\n" "${TLD_TEST_AUDIO_PID:?}"' \
    '  exit 0' \
    'fi' \
    'exit 1' \
    > "$TLD_TEST_BIN/pgrep"

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
      rm -f -- "${TLD_TEST_ROOT:?}/audio-started"
    fi
    return 0
  }
  export -f kill

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

_tld_make_audio_proc() {
  mkdir -p "$TLD_PROC_ROOT/$TLD_TEST_AUDIO_PID"
  printf '%s (pulseaudio) R 1 1 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 %s\n' \
    "$TLD_TEST_AUDIO_PID" "$TLD_TEST_START_TICKS" > "$TLD_PROC_ROOT/$TLD_TEST_AUDIO_PID/stat"
  printf '/usr/bin/pulseaudio\0--daemonize\0--exit-idle-time=-1\0' > "$TLD_PROC_ROOT/$TLD_TEST_AUDIO_PID/cmdline"
}

@test "audio start reuses an external ready endpoint without starting a daemon" {
  : > "$TLD_TEST_ROOT/audio-ready"

  run bash -c '
    source "$TLD_LIB_DIR/tld-common.sh"
    source "$TLD_LIB_DIR/tld-process.sh"
    source "$TLD_LIB_DIR/tld-host-audio.sh"
    tld_init_paths
    tld_audio_start
  '

  [ "$status" -eq 0 ]
  [[ "$output" == *"owner=external"* ]]
  grep -q '^pulseaudio ' "$TLD_TEST_CALL_LOG" && return 1 || true
  [ -f "$TLD_STATE_DIR/audio-owner.env" ]
  grep -q '^AUDIO_OWNER=external$' "$TLD_STATE_DIR/audio-owner.env"
}

@test "audio start launches an owned daemon and records it" {
  _tld_make_audio_proc

  run bash -c '
    source "$TLD_LIB_DIR/tld-common.sh"
    source "$TLD_LIB_DIR/tld-process.sh"
    source "$TLD_LIB_DIR/tld-host-audio.sh"
    tld_init_paths
    tld_audio_start
  '

  [ "$status" -eq 0 ]
  [[ "$output" == *"owner=owned"* ]]
  grep -q '^pulseaudio ' "$TLD_TEST_CALL_LOG"
  grep -q '^AUDIO_OWNER=owned$' "$TLD_STATE_DIR/audio-owner.env"
  [ -f "$TLD_STATE_DIR/processes/audio.env" ]
}

@test "audio start cleans up the owned daemon when readiness never arrives" {
  _tld_make_audio_proc
  export TLD_TEST_AUDIO_NEVER_READY=1
  export TLD_TEST_KILL_REMOVES=1

  run bash -c '
    source "$TLD_LIB_DIR/tld-common.sh"
    source "$TLD_LIB_DIR/tld-process.sh"
    source "$TLD_LIB_DIR/tld-host-audio.sh"
    tld_init_paths
    tld_audio_start
  '

  [ "$status" -ne 0 ]
  [[ "$output" == *"did not become ready"* ]]
  if [[ -e "$TLD_PROC_ROOT/$TLD_TEST_AUDIO_PID" ]]; then
    [ ! -f "$TLD_PROC_ROOT/$TLD_TEST_AUDIO_PID/stat" ]
  fi
}

@test "audio stop leaves an external endpoint untouched" {
  : > "$TLD_TEST_ROOT/audio-ready"
  printf 'AUDIO_OWNER=external\n' > "$TLD_STATE_DIR/audio-owner.env"

  run bash -c '
    source "$TLD_LIB_DIR/tld-common.sh"
    source "$TLD_LIB_DIR/tld-process.sh"
    source "$TLD_LIB_DIR/tld-host-audio.sh"
    tld_init_paths
    tld_audio_stop_if_owned
  '

  [ "$status" -eq 0 ]
  [[ "$output" == *"left running"* ]]
  grep -q '^kill ' "$TLD_TEST_CALL_LOG" && return 1 || true
  [ -f "$TLD_STATE_DIR/audio-owner.env" ]
}
