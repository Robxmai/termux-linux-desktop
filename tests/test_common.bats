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
  export TLD_TEST_CALL_LOG="$BATS_TEST_TMPDIR/calls.log"
  export PATH="$BATS_TEST_DIRNAME/helpers/fake-termux/bin:$PATH"

  mkdir -p "$HOME" "$PREFIX" "$TLD_STATE_DIR" "$TLD_LOG_DIR" "$TLD_CONFIG_DIR"
  source "$TLD_LIB_DIR/tld-common.sh"
}

@test "tld_init_paths derives defaults and creates only runtime directories" {
  unset TLD_STATE_DIR TLD_LOG_DIR TLD_CONFIG_DIR TLD_INSTALL_DIR TLD_INSTANCE_FILE

  tld_init_paths

  [ "$TLD_STATE_DIR" = "$PREFIX/var/lib/termux-linux-desktop" ]
  [ "$TLD_LOG_DIR" = "$PREFIX/var/log/termux-linux-desktop" ]
  [ "$TLD_CONFIG_DIR" = "$HOME/.config/termux-linux-desktop" ]
  [ "$TLD_INSTALL_DIR" = "$PREFIX/opt/termux-linux-desktop" ]
  [ "$TLD_INSTANCE_FILE" = "$TLD_STATE_DIR/instance.env" ]
  [ -d "$TLD_STATE_DIR" ]
  [ -d "$TLD_LOG_DIR" ]
  [ -d "$TLD_CONFIG_DIR" ]
  [ ! -d "$TLD_INSTALL_DIR" ]
}

@test "tld_log writes and prints a timestamped line" {
  run tld_log "hello" "world"

  [ "$status" -eq 0 ]
  [[ "$output" =~ ^\[[0-9]{2}:[0-9]{2}:[0-9]{2}\]\ hello\ world$ ]]
  [ "$(<"$TLD_LOG_DIR/desktop.log")" = "$output" ]
}

@test "tld_die returns non-zero and emits an ERROR message" {
  run tld_die "something went wrong"

  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: something went wrong"* ]]
  grep -F "ERROR: something went wrong" "$TLD_LOG_DIR/desktop.log"
}

@test "sourcing tld-common.sh alone creates no directories or command activity" {
  source_only="$BATS_TEST_TMPDIR/source-only"
  source_path="$source_only/bin"
  source_prefix="$source_only/prefix"
  source_home="$source_only/home"
  mkdir -p "$source_path"
  export TLD_SOURCE_PATH="$source_path"
  export TLD_SOURCE_PREFIX="$source_prefix"
  export TLD_SOURCE_HOME="$source_home"

  run bash -c 'set -Eeuo pipefail; export PATH="$TLD_SOURCE_PATH" PREFIX="$TLD_SOURCE_PREFIX" HOME="$TLD_SOURCE_HOME"; unset TLD_STATE_DIR TLD_LOG_DIR TLD_CONFIG_DIR TLD_INSTALL_DIR TLD_INSTANCE_FILE; source "$TLD_LIB_DIR/tld-common.sh"'

  [ "$status" -eq 0 ]
  [ ! -e "$source_prefix" ]
  [ ! -e "$source_home" ]
  [ ! -e "$source_only/state" ]
  [ ! -e "$source_only/log" ]
  [ ! -e "$source_only/config" ]
}

@test "tld_validate_name accepts a safe name" {
  run tld_validate_name "desktop_01-foo.bar"

  [ "$status" -eq 0 ]
}

@test "tld_validate_name rejects paths and shell syntax" {
  for value in "" "." ".." "/tmp/name" "../name" "name/child" "name with space" "name;rm" 'name`id`' 'name$(id)'; do
    run tld_validate_name "$value"
    [ "$status" -ne 0 ]
  done
}

@test "tld_is_true recognizes only supported boolean values" {
  for value in 1 true TRUE yes Yes on ON; do
    run tld_is_true "$value"
    [ "$status" -eq 0 ]
  done

  for value in 0 false no off maybe ""; do
    run tld_is_true "$value"
    [ "$status" -ne 0 ]
  done
}

@test "tld_read_env_file parses safe assignments without sourcing" {
  env_file="$BATS_TEST_TMPDIR/safe.env"
  printf '%s\n' 'ALPHA=one' 'GREETING=hello\ world' "QUOTED=it\'s" > "$env_file"
  unset ALPHA GREETING QUOTED

  tld_read_env_file "$env_file"

  [ "$ALPHA" = "one" ]
  [ "$GREETING" = "hello world" ]
  [ "$QUOTED" = "it's" ]
}

@test "tld_read_env_file rejects command-like and unknown input" {
  marker="$BATS_TEST_TMPDIR/should-not-exist"
  env_file="$BATS_TEST_TMPDIR/unsafe.env"
  printf 'SAFE=one\nBAD=$(touch %s)\n' "$marker" > "$env_file"

  run tld_read_env_file "$env_file"

  [ "$status" -ne 0 ]
  [ ! -e "$marker" ]

  printf '%s\n' 'BAD=`touch marker`' 'echo nope' > "$env_file"
  run tld_read_env_file "$env_file"
  [ "$status" -ne 0 ]
}

@test "tld_read_env_file propagates readonly assignment failures" {
  env_file="$BATS_TEST_TMPDIR/readonly.env"
  printf '%s\n' 'TLD_READONLY=changed' 'SAFE=ok' > "$env_file"
  readonly TLD_READONLY=original

  run tld_read_env_file "$env_file"

  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot assign environment variable"* ]]
}

@test "all public library functions run under strict mode" {
  smoke="$BATS_TEST_TMPDIR/strict-smoke.sh"
  cat > "$smoke" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

export HOME="$BATS_TEST_TMPDIR/smoke-home"
export PREFIX="$BATS_TEST_TMPDIR/smoke-prefix"
export TLD_STATE_DIR="$BATS_TEST_TMPDIR/smoke-state"
export TLD_LOG_DIR="$BATS_TEST_TMPDIR/smoke-log"
export TLD_CONFIG_DIR="$BATS_TEST_TMPDIR/smoke-config"
export TLD_INSTALL_DIR="$BATS_TEST_TMPDIR/smoke-install"
export TLD_INSTANCE_FILE="$TLD_STATE_DIR/instance.env"
mkdir -p "$HOME" "$PREFIX" "$TLD_STATE_DIR" "$TLD_LOG_DIR" "$TLD_CONFIG_DIR"

source "$TLD_LIB_DIR/tld-common.sh"
source "$TLD_LIB_DIR/tld-preflight.sh"
source "$TLD_LIB_DIR/tld-manifest.sh"
source "$TLD_LIB_DIR/tld-process.sh"

tld_init_paths
tld_log smoke
if tld_die smoke; then
  exit 1
fi
tld_require_command bash
tld_validate_name smoke
tld_is_true true
printf '%s\n' 'SAFE=value' > "$BATS_TEST_TMPDIR/smoke.env"
tld_read_env_file "$BATS_TEST_TMPDIR/smoke.env"

tld_check_architecture || true
tld_check_host_prerequisites || true
tld_check_prerequisite_commands
tld_check_storage 0 1
export TLD_X11_SOCKET="$BATS_TEST_TMPDIR/missing-X0" TLD_X11_MODE=install
tld_check_x11_socket
export TLD_X11_MODE=start
if tld_check_x11_socket; then
  exit 1
fi

manifest="$BATS_TEST_TMPDIR/smoke-manifest.env"
tld_manifest_begin install
tld_manifest_set PAYLOAD 'value with spaces $(not-run)'
tld_manifest_commit "$manifest"
tld_manifest_require "$manifest" PAYLOAD 'value with spaces $(not-run)'

export TLD_PROC_ROOT="$BATS_TEST_TMPDIR/smoke-proc"
export TLD_PROCESS_WAIT_SECONDS=0 TLD_PROCESS_KILL_WAIT_SECONDS=0 TLD_PROCESS_POLL_SECONDS=0
pid=4242
mkdir -p "$TLD_PROC_ROOT/$pid"
printf '%s\n' '4242 (fake-process) S 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 12345 20' > "$TLD_PROC_ROOT/$pid/stat"
printf '%s\0' bash -c 'echo desktop' > "$TLD_PROC_ROOT/$pid/cmdline"
process_hash=$(printf '%s\0' bash -c 'echo desktop' | tr '\0' '\n' | sha256sum | awk '{print $1}')
tld_process_record desktop "$pid" "$process_hash"
tld_process_is_owned desktop
kill() {
  if [[ "${1-}" == '-KILL' ]]; then
    rm -rf "$TLD_PROC_ROOT/${2-}"
  fi
  return 0
}
tld_process_stop desktop
tld_process_stop_all
tld_process_prune
EOF
  chmod +x "$smoke"
  run env "BATS_TEST_TMPDIR=$BATS_TEST_TMPDIR" "TLD_LIB_DIR=$TLD_LIB_DIR" "PATH=$PATH" "$smoke"

  [ "$status" -eq 0 ]
}
