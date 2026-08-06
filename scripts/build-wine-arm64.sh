#!/usr/bin/env bash
# Build Wine 11.11 (wow64 mode) for ARM64 Linux hosts.
# Usage: build-wine-arm64.sh [source-dir] [jobs]
# Prints the path to the built runtime tree (bin/wine, lib/wine/...).
set -Eeuo pipefail

TLD_WINE_VERSION="${TLD_WINE_VERSION:-11.11}"
TLD_SRC_DIR="${1:-/opt/wine-src}"
TLD_JOBS="${2:-$(nproc)}"
TLD_SRC_TARBALL="$TLD_SRC_DIR/wine-$TLD_WINE_VERSION.tar.xz"
TLD_BUILD_DIR="$TLD_SRC_DIR/build64"

for command_name in wget tar xz make gcc flex bison; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'missing build dependency: %s\n' "$command_name" >&2
    exit 1
  }
done

mkdir -p "$TLD_SRC_DIR"
if [[ ! -f "$TLD_SRC_TARBALL" ]]; then
  wget -q "https://dl.winehq.org/wine/source/11.x/wine-$TLD_WINE_VERSION.tar.xz" -O "$TLD_SRC_TARBALL"
fi
if [[ ! -d "$TLD_SRC_DIR/wine-$TLD_WINE_VERSION" ]]; then
  tar xf "$TLD_SRC_TARBALL" -C "$TLD_SRC_DIR"
fi

rm -rf "$TLD_BUILD_DIR"
mkdir -p "$TLD_BUILD_DIR"
(
  cd "$TLD_BUILD_DIR"
  "../wine-$TLD_WINE_VERSION/configure" --enable-archs=x86_64
  make -j"$TLD_JOBS"
)

[[ -x "$TLD_BUILD_DIR/bin/wine" ]] || {
  printf 'build did not produce bin/wine\n' >&2
  exit 1
}
printf '%s\n' "$TLD_BUILD_DIR"
