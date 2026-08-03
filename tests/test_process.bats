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
  export TLD_PROC_ROOT="$BATS_TEST_TMPDIR/proc"
  export TLD_TEST_PID=4242
  export TLD_TEST_KILL_LOG="$BATS_TEST_TMPDIR/kill.log"
  export TLD_TEST_REMOVE_ON_KILL=1
  export TLD_TEST_TERM_STATUS=0
  export TLD_TEST_KILL_STATUS=0
  export TLD_TEST_REMOVE_ON_TERM_FAILURE=0
  export TLD_PROCESS_WAIT_SECONDS=0
  export TLD_PROCESS_POLL_SECONDS=0
  export PATH="$BATS_TEST_DIRNAME/helpers/fake-termux/bin:$PATH"

  mkdir -p "$HOME" "$PREFIX" "$TLD_STATE_DIR" "$TLD_LOG_DIR" "$TLD_CONFIG_DIR"
  : > "$TLD_TEST_KILL_LOG"

  kill() {
    printf '%s\n' "$*" >> "$TLD_TEST_KILL_LOG"
    if [[ -n ${TLD_TEST_LOCK_HELD:-} && -e "$TLD_TEST_LOCK_HELD" ]]; then
      return 99
    fi
    if [[ "${1-}" == '-TERM' && "${TLD_TEST_REMOVE_ON_TERM_FAILURE:-0}" == 1 ]]; then
      rm -rf "$TLD_PROC_ROOT/${2-}"
    fi
    if [[ "${1-}" == '-KILL' && "${TLD_TEST_REMOVE_ON_KILL:-1}" == 1 ]]; then
      rm -rf "$TLD_PROC_ROOT/${2-}"
    fi
    if [[ "${1-}" == '-TERM' ]]; then
      return "$TLD_TEST_TERM_STATUS"
    fi
    return "$TLD_TEST_KILL_STATUS"
  }

  source "$TLD_LIB_DIR/tld-common.sh"
  source "$TLD_LIB_DIR/tld-process.sh"
}

write_proc_tree() {
  local pid="${1:-$TLD_TEST_PID}"
  local start_ticks="${2:-12345}"
  local comm="${3:-fake-process}"
  mkdir -p "$TLD_PROC_ROOT/$pid"
  printf '%s (%s) S 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 %s 20\n' "$pid" "$comm" "$start_ticks" > "$TLD_PROC_ROOT/$pid/stat"
  printf '%s\0' bash -c 'echo desktop' > "$TLD_PROC_ROOT/$pid/cmdline"
}

process_hash() {
  printf '%s\0' bash -c 'echo desktop' | tr '\0' '\n' | sha256sum | awk '{print $1}'
}

record_process() {
  local role="${1:-desktop}"
  local pid="${2:-$TLD_TEST_PID}"
  write_proc_tree "$pid"
  tld_process_record "$role" "$pid" "$(process_hash)"
}

@test "tld_process_record stores a valid owned process record" {
  record_process

  [ -f "$TLD_STATE_DIR/processes/desktop.env" ]
  grep -Fx 'ROLE=desktop' "$TLD_STATE_DIR/processes/desktop.env"
  grep -Fx 'PID=4242' "$TLD_STATE_DIR/processes/desktop.env"
  grep -Fx 'START_TICKS=12345' "$TLD_STATE_DIR/processes/desktop.env"
  grep -Fx "COMMAND_HASH=$(process_hash)" "$TLD_STATE_DIR/processes/desktop.env"
  [ "$(stat -c '%a' "$TLD_STATE_DIR/processes/desktop.env")" = 600 ]

  run tld_process_is_owned desktop

  [ "$status" -eq 0 ]
}

@test "tld_process_record parses a comm containing a closing delimiter" {
  write_proc_tree "$TLD_TEST_PID" 12345 'fake) process'
  tld_process_record desktop "$TLD_TEST_PID" "$(process_hash)"

  grep -Fx 'START_TICKS=12345' "$TLD_STATE_DIR/processes/desktop.env"
  run tld_process_is_owned desktop
  [ "$status" -eq 0 ]
}

@test "tld_process_stop treats an initially missing PID as already stopped" {
  record_process
  rm -rf "$TLD_PROC_ROOT/$TLD_TEST_PID"

  run tld_process_stop desktop

  [ "$status" -eq 0 ]
  [ ! -e "$TLD_STATE_DIR/processes/desktop.env" ]
  [ ! -s "$TLD_TEST_KILL_LOG" ]
}

@test "tld_process_stop preserves a record when the proc root is missing" {
  record_process
  rm -rf "$TLD_PROC_ROOT"

  run tld_process_stop desktop

  [ "$status" -ne 0 ]
  [ -e "$TLD_STATE_DIR/processes/desktop.env" ]
  [ ! -s "$TLD_TEST_KILL_LOG" ]
}

@test "tld_process_stop preserves a record when the proc root is not a directory" {
  record_process
  rm -rf "$TLD_PROC_ROOT"
  printf '%s\n' 'not a proc root' > "$TLD_PROC_ROOT"

  run tld_process_stop desktop

  [ "$status" -ne 0 ]
  [ -e "$TLD_STATE_DIR/processes/desktop.env" ]
  [ ! -s "$TLD_TEST_KILL_LOG" ]
}

@test "tld_process_stop preserves a record when the proc root lacks search access" {
  record_process
  chmod 0444 "$TLD_PROC_ROOT"

  run tld_process_stop desktop
  chmod 0755 "$TLD_PROC_ROOT"

  [ "$status" -ne 0 ]
  [ -e "$TLD_STATE_DIR/processes/desktop.env" ]
  [ ! -s "$TLD_TEST_KILL_LOG" ]
}

@test "tld_process_stop preserves a record when the PID directory lacks search access" {
  record_process
  chmod 0444 "$TLD_PROC_ROOT/$TLD_TEST_PID"

  run tld_process_stop desktop
  chmod 0755 "$TLD_PROC_ROOT/$TLD_TEST_PID"

  [ "$status" -ne 0 ]
  [ -e "$TLD_STATE_DIR/processes/desktop.env" ]
  [ ! -s "$TLD_TEST_KILL_LOG" ]
}

@test "tld_process_stop prunes a record when the start tick changes" {
  record_process
  write_proc_tree "$TLD_TEST_PID" 99999

  run tld_process_stop desktop

  [ "$status" -ne 0 ]
  [ ! -e "$TLD_STATE_DIR/processes/desktop.env" ]
  [ ! -s "$TLD_TEST_KILL_LOG" ]
}

@test "tld_process_stop preserves a record when proc stat is unreadable" {
  record_process
  rm -f "$TLD_PROC_ROOT/$TLD_TEST_PID/stat"
  mkdir "$TLD_PROC_ROOT/$TLD_TEST_PID/stat"

  run tld_process_stop desktop

  [ "$status" -ne 0 ]
  [ -e "$TLD_STATE_DIR/processes/desktop.env" ]
  [ ! -s "$TLD_TEST_KILL_LOG" ]
}

@test "tld_process_stop preserves a record when proc cmdline is missing" {
  record_process
  rm -f "$TLD_PROC_ROOT/$TLD_TEST_PID/cmdline"

  run tld_process_stop desktop

  [ "$status" -ne 0 ]
  [ -e "$TLD_STATE_DIR/processes/desktop.env" ]
  [ ! -s "$TLD_TEST_KILL_LOG" ]
}

@test "tld_process_record preserves the active record when a write fails" {
  process_hash_value=$(process_hash)
  record_process
  record_file="$TLD_STATE_DIR/processes/desktop.env"
  before_hash=$(sha256sum "$record_file" | awk '{print $1}')

  printf() {
    if [[ "${1-}" == 'PID=%q\n' ]]; then
      return 73
    fi
    builtin printf "$@"
  }

  if tld_process_record desktop "$TLD_TEST_PID" "$process_hash_value"; then
    false
  fi
  unset -f printf

  after_hash=$(sha256sum "$record_file" | awk '{print $1}')
  [ "$after_hash" = "$before_hash" ]
  [ -f "$record_file" ]
  ! compgen -G "$record_file.tmp.*" >/dev/null
}

@test "tld_process_stop sends TERM then KILL only to an owned process" {
  record_process

  run tld_process_stop desktop

  [ "$status" -eq 0 ]
  mapfile -t signals < "$TLD_TEST_KILL_LOG"
  [ "${#signals[@]}" -eq 2 ]
  [ "${signals[0]}" = '-TERM 4242' ]
  [ "${signals[1]}" = '-KILL 4242' ]
  [ ! -e "$TLD_STATE_DIR/processes/desktop.env" ]
}

@test "tld_process_stop_all stops and removes every owned record" {
  record_process desktop 4242
  record_process second 4343

  run tld_process_stop_all

  [ "$status" -eq 0 ]
  mapfile -t signals < "$TLD_TEST_KILL_LOG"
  [ "${#signals[@]}" -eq 4 ]
  [ "${signals[0]}" = '-TERM 4242' ]
  [ "${signals[1]}" = '-KILL 4242' ]
  [ "${signals[2]}" = '-TERM 4343' ]
  [ "${signals[3]}" = '-KILL 4343' ]
  [ ! -e "$TLD_STATE_DIR/processes/desktop.env" ]
  [ ! -e "$TLD_STATE_DIR/processes/second.env" ]
}

@test "tld_process_stop does not signal an unrelated owned PID" {
  record_process desktop 4242
  record_process unrelated 4343

  run tld_process_stop desktop

  [ "$status" -eq 0 ]
  mapfile -t signals < "$TLD_TEST_KILL_LOG"
  [ "${#signals[@]}" -eq 2 ]
  [ "${signals[0]}" = '-TERM 4242' ]
  [ "${signals[1]}" = '-KILL 4242' ]
  ! grep -F '4343' "$TLD_TEST_KILL_LOG"
  [ ! -e "$TLD_STATE_DIR/processes/desktop.env" ]
  [ -e "$TLD_STATE_DIR/processes/unrelated.env" ]
}

@test "tld_process_stop fails when an owned process remains alive after KILL" {
  export TLD_TEST_REMOVE_ON_KILL=0
  record_process

  run tld_process_stop desktop

  [ "$status" -ne 0 ]
  mapfile -t signals < "$TLD_TEST_KILL_LOG"
  [ "${#signals[@]}" -eq 2 ]
  [ "${signals[0]}" = '-TERM 4242' ]
  [ "${signals[1]}" = '-KILL 4242' ]
  [ -e "$TLD_STATE_DIR/processes/desktop.env" ]
}

@test "tld_process_stop returns success for a failed TERM after confirmed exit" {
  export TLD_TEST_TERM_STATUS=1
  export TLD_TEST_REMOVE_ON_TERM_FAILURE=1
  record_process

  run tld_process_stop desktop

  [ "$status" -eq 0 ]
  mapfile -t signals < "$TLD_TEST_KILL_LOG"
  [ "${#signals[@]}" -eq 1 ]
  [ "${signals[0]}" = '-TERM 4242' ]
  [ ! -e "$TLD_STATE_DIR/processes/desktop.env" ]
}

@test "tld_process_stop preserves ownership when KILL fails" {
  export TLD_TEST_KILL_STATUS=1
  export TLD_TEST_REMOVE_ON_KILL=0
  record_process

  run tld_process_stop desktop

  [ "$status" -ne 0 ]
  mapfile -t signals < "$TLD_TEST_KILL_LOG"
  [ "${#signals[@]}" -eq 2 ]
  [ "${signals[0]}" = '-TERM 4242' ]
  [ "${signals[1]}" = '-KILL 4242' ]
  [ -e "$TLD_STATE_DIR/processes/desktop.env" ]
}

@test "tld_process_prune propagates record deletion failure" {
  record_process
  rm -rf "$TLD_PROC_ROOT/$TLD_TEST_PID"
  rm() {
    if [[ "${TLD_TEST_BLOCK_RM:-0}" == 1 && "$*" == *"desktop.env"* ]]; then
      return 1
    fi
    command rm "$@"
  }
  export TLD_TEST_BLOCK_RM=1

  run tld_process_prune

  [ "$status" -ne 0 ]
  [ -e "$TLD_STATE_DIR/processes/desktop.env" ]
}

@test "tld_process_stop propagates record deletion failure" {
  record_process
  rm -rf "$TLD_PROC_ROOT/$TLD_TEST_PID"
  rm() {
    if [[ "$*" == *"desktop.env"* ]]; then
      return 73
    fi
    command rm "$@"
  }

  run tld_process_stop desktop

  [ "$status" -ne 0 ]
  [[ "$output" == *"stale process record"* ]]
  [ -e "$TLD_STATE_DIR/processes/desktop.env" ]
}

@test "tld_process_stop waits for the per-role lock before signaling" {
  record_process
  lock_file="$TLD_STATE_DIR/processes/desktop.lock"
  held="$BATS_TEST_TMPDIR/lock-held"
  export TLD_TEST_LOCK_HELD="$held"
  (
    exec 9>"$lock_file"
    flock -x 9
    : > "$held"
    sleep 0.2
    rm -f "$held"
  ) &
  holder_pid=$!
  while [ ! -e "$held" ]; do
    sleep 0.01
  done

  run tld_process_stop desktop
  wait "$holder_pid"

  [ "$status" -eq 0 ]
  [ ! -e "$TLD_STATE_DIR/processes/desktop.env" ]
}

@test "tld_process_stop prunes a command hash mismatch without signaling it" {
  write_proc_tree
  tld_process_record desktop "$TLD_TEST_PID" wrong-command-hash

  run tld_process_stop desktop

  [ "$status" -ne 0 ]
  [ ! -e "$TLD_STATE_DIR/processes/desktop.env" ]
  [ ! -s "$TLD_TEST_KILL_LOG" ]
}
