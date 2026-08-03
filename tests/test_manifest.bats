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
  source "$TLD_LIB_DIR/tld-manifest.sh"
}

@test "tld_manifest_commit replaces the active file atomically" {
  manifest="$BATS_TEST_TMPDIR/manifest.env"
  printf '%s\n' 'STATE=old' > "$manifest"

  tld_manifest_begin install
  tld_manifest_set STATE new
  run tld_manifest_commit "$manifest"

  [ "$status" -eq 0 ]
  grep -Fx 'STATE=new' "$manifest"
  ! grep -Fx 'STATE=old' "$manifest"
  [ ! -e "$manifest.tmp" ]
}

@test "tld_manifest_require succeeds for an expected key" {
  manifest="$BATS_TEST_TMPDIR/manifest.env"

  tld_manifest_begin install
  tld_manifest_set STATE ready
  tld_manifest_commit "$manifest"

  run tld_manifest_require "$manifest" STATE ready

  [ "$status" -eq 0 ]
}

@test "tld_manifest_require fails for missing and wrong keys" {
  manifest="$BATS_TEST_TMPDIR/manifest.env"

  tld_manifest_begin install
  tld_manifest_set STATE ready
  tld_manifest_commit "$manifest"

  run tld_manifest_require "$manifest" MISSING ready
  [ "$status" -ne 0 ]

  run tld_manifest_require "$manifest" STATE stopped
  [ "$status" -ne 0 ]
}

@test "tld_manifest preserves spaces quotes and command-like values as data" {
  manifest="$BATS_TEST_TMPDIR/manifest.env"
  marker="$BATS_TEST_TMPDIR/not-created"
  value="text with spaces \"quotes\" \$(touch $marker) \`backtick\`"

  tld_manifest_begin install
  tld_manifest_set PAYLOAD "$value"
  tld_manifest_commit "$manifest"

  run tld_manifest_require "$manifest" PAYLOAD "$value"

  [ "$status" -eq 0 ]
  [ ! -e "$marker" ]
}

@test "tld_manifest_begin records standard metadata" {
  manifest="$BATS_TEST_TMPDIR/manifest.env"

  tld_manifest_begin install
  tld_manifest_set architecture aarch64
  tld_manifest_set rootfs_image debian
  tld_manifest_set rootfs_container debian
  tld_manifest_set profile desktop
  tld_manifest_commit "$manifest"

  tld_manifest_require "$manifest" manifest_version 1
  tld_manifest_require "$manifest" toolkit_version 0.1.0
  tld_manifest_require "$manifest" architecture aarch64
  tld_manifest_require "$manifest" rootfs_image debian
  tld_manifest_require "$manifest" rootfs_container debian
  tld_manifest_require "$manifest" profile desktop
  grep -Eq '^created_at=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$manifest"
}
