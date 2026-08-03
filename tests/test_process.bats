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
  export TLD_PROCESS_WAIT_SECONDS=0
  export TLD_PROCESS_POLL_SECONDS=0
  export PATH="$BATS_TEST_DIRNAME/helpers/fake-termux/bin:$PATH"

  mkdir -p "$HOME" "$PREFIX" "$TLD_STATE_DIR" "$TLD_LOG_DIR" "$TLD_CONFIG_DIR"
  : > "$TLD_TEST_KILL_LOG"

  kill() {
    printf '%s\n' "$*" >> "$TLD_TEST_KILL_LOG"
    return 0
  }

  source "$TLD_LIB_DIR/tld-common.sh"
  source "$TLD_LIB_DIR/tld-process.sh"
}

write_proc_tree() {
  local start_ticks="${1:-12345}"
  mkdir -p "$TLD_PROC_ROOT/$TLD_TEST_PID"
  printf '4242 (fake-process) S 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 %s 20\n' "$start_ticks" > "$TLD_PROC_ROOT/$TLD_TEST_PID/stat"
  printf '%s\0' bash -c 'echo desktop' > "$TLD_PROC_ROOT/$TLD_TEST_PID/cmdline"
}

process_hash() {
  printf '%s\0' bash -c 'echo desktop' | tr '\0' '\n' | sha256sum | awk '{print $1}'
}

record_process() {
  write_proc_tree
  tld_process_record desktop "$TLD_TEST_PID" "$(process_hash)"
}

@test "tld_process_record stores a valid owned process record" {
  record_process

  [ -f "$TLD_STATE_DIR/processes/desktop.env" ]
  grep -Fx 'ROLE=desktop' "$TLD_STATE_DIR/processes/desktop.env"
  grep -Fx 'PID=4242' "$TLD_STATE_DIR/processes/desktop.env"
  grep -Fx 'START_TICKS=12345' "$TLD_STATE_DIR/processes/desktop.env"
  grep -Fx "COMMAND_HASH=$(process_hash)" "$TLD_STATE_DIR/processes/desktop.env"

  run tld_process_is_owned desktop

  [ "$status" -eq 0 ]
}

@test "tld_process_stop prunes a stale PID without signaling it" {
  record_process
  rm -rf "$TLD_PROC_ROOT/$TLD_TEST_PID"

  run tld_process_stop desktop

  [ "$status" -ne 0 ]
  [ ! -e "$TLD_STATE_DIR/processes/desktop.env" ]
  [ ! -s "$TLD_TEST_KILL_LOG" ]
}

@test "tld_process_stop prunes a record when the start tick changes" {
  record_process
  write_proc_tree 99999

  run tld_process_stop desktop

  [ "$status" -ne 0 ]
  [ ! -e "$TLD_STATE_DIR/processes/desktop.env" ]
  [ ! -s "$TLD_TEST_KILL_LOG" ]
}

@test "tld_process_stop prunes a command hash mismatch without signaling it" {
  write_proc_tree
  tld_process_record desktop "$TLD_TEST_PID" wrong-command-hash

  run tld_process_stop desktop

  [ "$status" -ne 0 ]
  [ ! -e "$TLD_STATE_DIR/processes/desktop.env" ]
  [ ! -s "$TLD_TEST_KILL_LOG" ]
}
