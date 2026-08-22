#!/usr/bin/env bash
set -Eeuo pipefail

TLD_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TLD_FAILURES=0

tld_check_fail() {
  printf 'FAIL %s\n' "$*"
  TLD_FAILURES=1
}

for TLD_SCRIPT in "$TLD_REPO_ROOT"/bin/* "$TLD_REPO_ROOT"/lib/*.sh; do
  if [[ -f "$TLD_SCRIPT" && ! -L "$TLD_SCRIPT" ]]; then
    if ! bash -n "$TLD_SCRIPT"; then
      tld_check_fail "syntax check failed for $TLD_SCRIPT"
    fi
  fi
done

for TLD_SCRIPT in "$TLD_REPO_ROOT"/bin/*; do
  if [[ -f "$TLD_SCRIPT" && ! -L "$TLD_SCRIPT" ]]; then
    if ! grep -q 'set -Eeuo pipefail' "$TLD_SCRIPT"; then
      tld_check_fail "missing strict mode in $TLD_SCRIPT"
    fi
  fi
done

for TLD_COMMAND in "$TLD_REPO_ROOT"/bin/*; do
  if [[ -f "$TLD_COMMAND" && ! -L "$TLD_COMMAND" ]]; then
    if [[ ! -x "$TLD_COMMAND" ]]; then
      tld_check_fail "public command is not executable: $TLD_COMMAND"
    fi
    if grep -E -q 'curl[[:space:]]+\|[[:space:]]*(sh|bash)|killall|[[:space:]]pkill[[:space:]]+-f|rm[[:space:]]+-rf[[:space:]]+("\$HOME"|"\$PREFIX")' "$TLD_COMMAND"; then
      tld_check_fail "forbidden runtime pattern in $TLD_COMMAND"
    fi
  fi
done

for TLD_LIBRARY in "$TLD_REPO_ROOT"/lib/*.sh; do
  if [[ -f "$TLD_LIBRARY" && ! -L "$TLD_LIBRARY" ]]; then
    if grep -E -q 'killall|[[:space:]]pkill[[:space:]]+-f' "$TLD_LIBRARY"; then
      tld_check_fail "forbidden process pattern in $TLD_LIBRARY"
    fi
  fi
done

for TLD_PUBLIC in desktop-install desktop-start desktop-stop desktop-status desktop-doctor desktop-profile desktop-reset; do
  if [[ ! -f "$TLD_REPO_ROOT/bin/$TLD_PUBLIC" ]]; then
    tld_check_fail "public command is missing: $TLD_PUBLIC"
  fi
done

for TLD_DOC in INSTALL ARCHITECTURE SUPPORT RECOVERY; do
  if [[ ! -f "$TLD_REPO_ROOT/docs/$TLD_DOC.md" ]]; then
    tld_check_fail "documentation is missing: docs/$TLD_DOC.md"
  fi
done

TLD_GUEST_PROVISION="$TLD_REPO_ROOT/lib/tld-guest.sh"
TLD_GUEST_BLOCK=$(sed -n '/^tld_guest_provision()/,/^}/p' "$TLD_GUEST_PROVISION")
TLD_RUNTIME_PROVISION="$TLD_REPO_ROOT/rootfs/guest-runtime-provision.sh"
TLD_RUNTIME_BLOCK=$(sed -n '/^install_packages()/,/^}/p' "$TLD_RUNTIME_PROVISION")
TLD_RUNTIME_TEXT=$(cat "$TLD_RUNTIME_PROVISION")
TLD_WINE_RUNTIME="$TLD_REPO_ROOT/lib/tld-wine-runtime.sh"
TLD_INSTALLER="$TLD_REPO_ROOT/bin/desktop-install"
TLD_PACKAGE_BLOCK="$TLD_GUEST_BLOCK
$TLD_RUNTIME_BLOCK
$TLD_RUNTIME_TEXT"
if grep -q -- '--no-install-recommends' <<< "$TLD_GUEST_BLOCK" &&
  ! grep -Eq 'apt-get install -y --no-install-recommends winetricks' <<< "$TLD_GUEST_BLOCK"; then
  tld_check_fail 'desktop provisioning must install full package recommendations except targeted winetricks'
fi
for TLD_REQUIRED_PACKAGE in \
  xfce4 xfce4-goodies libreoffice evince \
  mono-complete dotnet-runtime-8.0 aspnetcore-runtime-8.0 \
  python3 nodejs openjdk-17-jre ruby-full php-cli golang-go rustc \
  libpulse0 libasound2t64 libvulkan1 mesa-utils box86-android:armhf \
  cabextract winetricks; do
  if ! grep -Eq "(^|[[:space:]])${TLD_REQUIRED_PACKAGE}(:[[:alnum:]]+)?([[:space:]\\\\]|$)" <<< "$TLD_PACKAGE_BLOCK"; then
    tld_check_fail "desktop provisioning package is missing: $TLD_REQUIRED_PACKAGE"
  fi
done
if ! grep -q 'firefox-esr' <<< "$TLD_RUNTIME_TEXT"; then
  tld_check_fail 'Firefox ESR runtime provisioning is missing'
fi
for TLD_DEB_CHECK in \
  write_deb_package_handler \
  'dpkg-deb --info' \
  'apt-get install -y' \
  'application/vnd.debian.binary-package=deb-install.desktop' \
  'application/x-deb=deb-install.desktop' \
  '/usr/local/bin/gpuinfo' \
  '/usr/local/bin/winecfg' \
  '/usr/local/bin/winereg' \
  'GPUInfo.desktop' \
  'winecfg.desktop' \
  'winereg.desktop' \
  'mscoree=b' \
  'launcher-21'; do
  if ! grep -q -- "$TLD_DEB_CHECK" <<< "$TLD_RUNTIME_TEXT"; then
    tld_check_fail "Debian package installer provisioning is missing: $TLD_DEB_CHECK"
  fi
done
for TLD_WINE_COMPONENT in 'wine-mono-$mono_version-x86.msi' 'wine-gecko-$gecko_version-x86.msi' 'wine-gecko-$gecko_version-x86_64.msi'; do
  if ! grep -q -- "$TLD_WINE_COMPONENT" "$TLD_RUNTIME_PROVISION"; then
    tld_check_fail "Wine component provisioning is missing: $TLD_WINE_COMPONENT"
  fi
done
for TLD_GLADIO_REG_CHECK in \
  'HKCU\\Software\\Wine\\Drivers' \
  'HKCU\\Software\\Wine\\X11 Driver' \
  'HKLM\\System\\CurrentControlSet\\Control\\Video' \
  'GraphicsDriver' \
  'winex11.drv'; do
  if ! grep -Fq -- "$TLD_GLADIO_REG_CHECK" "$TLD_RUNTIME_PROVISION"; then
    tld_check_fail "Wine Gladio registry provisioning is missing: $TLD_GLADIO_REG_CHECK"
  fi
done
if ! grep -q 'WINE_GLADIO_NO_DEVICE_SERVICES' "$TLD_RUNTIME_PROVISION"; then
  tld_check_fail "Wine fast-start overlay flag is missing from provisioning"
fi
for TLD_WINE_FETCH_CHECK in 'wine-mono/$mono_version' 'wine-gecko/$gecko_version' 'TLD_WINE_MONO_VERSION' 'TLD_WINE_GECKO_VERSION'; do
  if ! grep -q -- "$TLD_WINE_FETCH_CHECK" "$TLD_WINE_RUNTIME"; then
    tld_check_fail "Wine runtime fetch is missing: $TLD_WINE_FETCH_CHECK"
  fi
done
if ! grep -q 'tld_wine_runtime_fetch' "$TLD_INSTALLER"; then
  tld_check_fail 'desktop installer does not fetch runtime artifacts'
fi
if [[ ! -f "$TLD_REPO_ROOT/rootfs/box86.list" ]]; then
  tld_check_fail 'Box86 repository definition is missing'
fi

TLD_DOCTOR="$TLD_REPO_ROOT/bin/desktop-doctor"
for TLD_DOCTOR_CHECK in \
  _tld_doctor_full_desktop 'mono --version' 'dotnet --list-runtimes' \
  'TLD_WINE_PREFIX' 'wine-runtime-prefix' 'wine_gecko/VERSION' runtime profile_version \
  libreoffice xfce4-session dbus-run-session dpkg-deb deb-install.desktop; do
  if ! grep -q -- "$TLD_DOCTOR_CHECK" "$TLD_DOCTOR"; then
    tld_check_fail "desktop doctor check is missing: $TLD_DOCTOR_CHECK"
  fi
done

if (( TLD_FAILURES == 0 )); then
  printf '%s\n' 'PASS all script and documentation checks'
  exit 0
fi
exit 1
