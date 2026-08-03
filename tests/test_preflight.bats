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
  export TLD_TEST_BIN="$BATS_TEST_TMPDIR/bin"
  export PATH="$TLD_TEST_BIN:$BATS_TEST_DIRNAME/helpers/fake-termux/bin:$PATH"

  mkdir -p "$HOME" "$PREFIX" "$TLD_STATE_DIR" "$TLD_LOG_DIR" "$TLD_CONFIG_DIR" "$TLD_TEST_BIN"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "${TLD_TEST_ARCH:-aarch64}"' > "$TLD_TEST_BIN/uname"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "Filesystem 1024-blocks Used Available Capacity Mounted on\nfake 100 50 %s 50%% /\n" "${TLD_TEST_DF_KB:-0}"' > "$TLD_TEST_BIN/df"
  chmod +x "$TLD_TEST_BIN/uname" "$TLD_TEST_BIN/df"

  source "$TLD_LIB_DIR/tld-common.sh"
  source "$TLD_LIB_DIR/tld-preflight.sh"
}

@test "tld_check_architecture passes on aarch64" {
  export TLD_TEST_ARCH=aarch64

  run tld_check_architecture

  [ "$status" -eq 0 ]
  [ "$output" = "PASS architecture=aarch64" ]
}

@test "tld_check_architecture fails on non-aarch64" {
  export TLD_TEST_ARCH=x86_64

  run tld_check_architecture

  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL architecture=x86_64"* ]]
}

@test "tld_check_prerequisite_commands passes with the fake Termux commands" {
  run tld_check_prerequisite_commands

  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS command=bash"* ]]
  [[ "$output" == *"PASS command=pkg"* ]]
  [[ "$output" == *"PASS command=proot-distro"* ]]
  [[ "$output" == *"PASS command=pactl"* ]]
}

@test "tld_require_command reports an actionable missing command" {
  run tld_require_command tld-command-that-is-not-installed

  [ "$status" -ne 0 ]
  [[ "$output" == *"required command not found"* ]]
  [[ "$output" == *"tld-command-that-is-not-installed"* ]]
}

@test "tld_check_storage reports healthy, warning, and failing capacity" {
  export TLD_STORAGE_PATH="$PREFIX"

  export TLD_TEST_DF_KB=40000
  run tld_check_storage 10240000 20480000
  [ "$status" -eq 0 ]
  [[ "$output" == PASS* ]]

  export TLD_TEST_DF_KB=15000
  run tld_check_storage 10240000 20480000
  [ "$status" -eq 0 ]
  [[ "$output" == WARN* ]]

  export TLD_TEST_DF_KB=5000
  run tld_check_storage 10240000 20480000
  [ "$status" -ne 0 ]
  [[ "$output" == FAIL* ]]
}

@test "tld_check_storage rejects invalid arguments and unavailable capacity" {
  export TLD_STORAGE_PATH="$PREFIX"

  run tld_check_storage invalid 20480
  [ "$status" -ne 0 ]
  [[ "$output" == FAIL* ]]

  run tld_check_storage 20480 10240
  [ "$status" -ne 0 ]
  [[ "$output" == FAIL* ]]

  export TLD_TEST_DF_KB=not-a-number
  run tld_check_storage 10240 20480
  [ "$status" -ne 0 ]
  [[ "$output" == FAIL* ]]
}

@test "tld_check_x11_socket passes for an existing Unix socket" {
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import socket, sys; sock = socket.socket(socket.AF_UNIX); sock.bind(sys.argv[1]); sock.close()' "$BATS_TEST_TMPDIR/X0"
  elif command -v python >/dev/null 2>&1; then
    python -c 'import socket, sys; sock = socket.socket(socket.AF_UNIX); sock.bind(sys.argv[1]); sock.close()' "$BATS_TEST_TMPDIR/X0"
  else
    skip "Python is unavailable for creating a Unix socket fixture"
  fi
  export TLD_X11_SOCKET="$BATS_TEST_TMPDIR/X0"

  run tld_check_x11_socket

  [ "$status" -eq 0 ]
  [[ "$output" == PASS* ]]
}

@test "tld_check_x11_socket warns in install mode" {
  export TLD_X11_SOCKET="$BATS_TEST_TMPDIR/missing-X0"
  export TLD_X11_MODE=install

  run tld_check_x11_socket

  [ "$status" -eq 0 ]
  [[ "$output" == WARN* ]]
}

@test "tld_check_x11_socket fails in start mode" {
  export TLD_X11_SOCKET="$BATS_TEST_TMPDIR/missing-X0"
  export TLD_X11_MODE=start

  run tld_check_x11_socket

  [ "$status" -ne 0 ]
  [[ "$output" == FAIL* ]]
}
