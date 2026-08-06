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
  export TLD_RUNTIME_CACHE_DIR="$BATS_TEST_TMPDIR/runtime-cache"
  export PATH="$BATS_TEST_DIRNAME/helpers/fake-termux/bin:$PATH"

  mkdir -p "$HOME" "$PREFIX" "$TLD_STATE_DIR" "$TLD_LOG_DIR" "$TLD_CONFIG_DIR" "$TLD_RUNTIME_CACHE_DIR"
  source "$TLD_LIB_DIR/tld-common.sh"
  source "$TLD_LIB_DIR/tld-wine-runtime.sh"
}

@test "wine runtime versions reports pinned component versions" {
  run tld_wine_runtime_versions

  [ "$status" -eq 0 ]
  [[ "$output" == *"box64=ba373ab4b3ae2ecbc9aeeece309817cad47ba421"* ]]
  [[ "$output" == *"turnip=24.1.0"* ]]
  [[ "$output" == *"dxvk=2.6.1"* ]]
}

@test "wine runtime cache dir falls back to managed state dir" {
  unset TLD_RUNTIME_CACHE_DIR

  run _tld_wr_cache_dir

  [ "$status" -eq 0 ]
  [ "$output" = "$PREFIX/var/lib/termux-linux-desktop/runtime-cache" ]
  [ -d "$output" ]
}

@test "wine runtime fetch caches an existing wine tarball source" {
  TLD_SKIP_BOX64=1 TLD_SKIP_TURNIP=1 TLD_SKIP_DXVK=1 TLD_SKIP_FIREFOX=1 TLD_SKIP_DIAG=1
  export TLD_SKIP_BOX64 TLD_SKIP_TURNIP TLD_SKIP_DXVK TLD_SKIP_FIREFOX TLD_SKIP_DIAG
  TLD_TEST_MODE=1
  export TLD_TEST_MODE
  wine_src="$BATS_TEST_TMPDIR/wine.tar.gz"
  : > "$wine_src"
  TLD_WINE_RUNTIME_TARBALL="$wine_src"
  export TLD_WINE_RUNTIME_TARBALL

  run tld_wine_runtime_fetch

  [ "$status" -eq 0 ]
  [ -f "$TLD_RUNTIME_CACHE_DIR/wine-11.11-amd64-wow64.tar.gz" ]
}

@test "wine runtime fetch fails on a missing wine source" {
  TLD_SKIP_BOX64=1 TLD_SKIP_TURNIP=1 TLD_SKIP_DXVK=1 TLD_SKIP_FIREFOX=1 TLD_SKIP_DIAG=1
  export TLD_SKIP_BOX64 TLD_SKIP_TURNIP TLD_SKIP_DXVK TLD_SKIP_FIREFOX TLD_SKIP_DIAG
  TLD_TEST_MODE=1
  export TLD_TEST_MODE
  TLD_WINE_RUNTIME_TARBALL="$BATS_TEST_TMPDIR/missing-wine.tar.gz"
  export TLD_WINE_RUNTIME_TARBALL

  run tld_wine_runtime_fetch

  [ "$status" -ne 0 ]
}

@test "wine runtime fetch rejects downloads in test mode" {
  TLD_TEST_MODE=1
  export TLD_TEST_MODE

  run tld_wine_runtime_fetch

  [ "$status" -ne 0 ]
  [[ "$output" == *"download attempted in test mode"* ]]
}

@test "wine runtime install logs the guest provisioning command in test mode" {
  TLD_TEST_MODE=1
  export TLD_TEST_MODE

  run tld_wine_runtime_install

  [ "$status" -eq 0 ]
  [[ "$output" == *"proot-distro login tld-ubuntu --bind"* ]]
  [[ "$output" == *"/bin/bash -lc"* ]]
}

@test "wine runtime install fails when the guest provision script is missing" {
  TLD_TEST_MODE=1
  export TLD_TEST_MODE
  TLD_GUEST_PROVISION_SCRIPT="$BATS_TEST_TMPDIR/missing-provision.sh"
  export TLD_GUEST_PROVISION_SCRIPT

  run tld_wine_runtime_install

  [ "$status" -ne 0 ]
  [[ "$output" == *"guest provisioning script not found"* ]]
}

@test "wine runtime status reports cached components" {
  TLD_TEST_MODE=1
  export TLD_TEST_MODE
  printf 'x' > "$TLD_RUNTIME_CACHE_DIR/box64-ba373ab4b3ae2ecbc9aeeece309817cad47ba421.tar.gz"
  printf 'x' > "$TLD_RUNTIME_CACHE_DIR/dxvk-2.6.1.tar.gz"

  run tld_wine_runtime_status

  [ "$status" -eq 0 ]
  [[ "$output" == *"box64 source: cached"* ]]
  [[ "$output" == *"turnip: missing"* ]]
  [[ "$output" == *"dxvk: cached"* ]]
}

@test "wow-install fails when the runtime is not installed" {
  game_dir="$BATS_TEST_TMPDIR/game"
  mkdir -p "$game_dir"
  : > "$game_dir/Wow.exe"

  run bash "$BATS_TEST_DIRNAME/../bin/wow-install" --game-dir "$game_dir"

  [ "$status" -ne 0 ]
  [[ "$output" == *"wine/GPU runtime is not installed"* ]]
}

@test "wow-install fails without a game directory" {
  mkdir -p "$PREFIX/var/lib/proot-distro/containers/tld-ubuntu/rootfs/usr/local/etc"
  : > "$PREFIX/var/lib/proot-distro/containers/tld-ubuntu/rootfs/usr/local/etc/termux-linux-desktop-runtime.env"

  run bash "$BATS_TEST_DIRNAME/../bin/wow-install" --game-dir "$BATS_TEST_TMPDIR/no-game"

  [ "$status" -ne 0 ]
  [[ "$output" == *"no Wow.exe"* ]]
}

@test "wow-install writes wow state and prepares the guest" {
  mkdir -p "$PREFIX/var/lib/proot-distro/containers/tld-ubuntu/rootfs/usr/local/etc"
  : > "$PREFIX/var/lib/proot-distro/containers/tld-ubuntu/rootfs/usr/local/etc/termux-linux-desktop-runtime.env"
  game_dir="$BATS_TEST_TMPDIR/game"
  mkdir -p "$game_dir"
  : > "$game_dir/Wow.exe"

  run bash "$BATS_TEST_DIRNAME/../bin/wow-install" --game-dir "$game_dir"

  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS wow installed"* ]]
  [ -f "$PREFIX/var/lib/termux-linux-desktop/wow.env" ]
  grep -q "game_dir=$game_dir" "$PREFIX/var/lib/termux-linux-desktop/wow.env"
}

@test "wow-launch fails without a registered wow install" {
  run bash "$BATS_TEST_DIRNAME/../bin/wow-launch"

  [ "$status" -ne 0 ]
  [[ "$output" == *"no wow install registered"* ]]
}

@test "desktop-vnc rejects an unknown action" {
  run bash "$BATS_TEST_DIRNAME/../bin/desktop-vnc" bogus

  [ "$status" -ne 0 ]
  [[ "$output" == *"usage: desktop-vnc"* ]]
}

@test "desktop-gputest fails when diagnostic apps are missing" {
  run bash "$BATS_TEST_DIRNAME/../bin/desktop-gputest"

  [ "$status" -ne 0 ]
  [[ "$output" == *"diagnostic apps are not installed"* ]]
}

@test "desktop-gputest rejects unknown flags" {
  run bash "$BATS_TEST_DIRNAME/../bin/desktop-gputest" --bogus

  [ "$status" -ne 0 ]
  [[ "$output" == *"usage: desktop-gputest"* ]]
}
