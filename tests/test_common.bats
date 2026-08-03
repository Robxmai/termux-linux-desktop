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
